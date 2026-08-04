import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'api_exception.dart';

/// Thin wrapper over `package:http` for talking to the existing FastAPI
/// backend (see docs/MIGRATION_INVENTORY.md §1 for the full route table).
///
/// This does not implement retry/caching — those are feature-layer concerns.
/// It only standardizes: base URL, JSON encode/decode, timeouts, and
/// converting non-2xx responses into a single [ApiException] type.
///
/// Every log line carries the COMPLETE method + URL. A log that says only
/// the base URL ("something failed talking to zitlas.com") cannot distinguish
/// "this route is missing" from "the whole server is down", which is exactly
/// the ambiguity that made a missing `/api/coaching/end` look like a network
/// fault for days.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _client = httpClient ?? http.Client(),
      _baseUrl = baseUrl ?? Env.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Optional bearer token supplier, set once auth is wired up (Phase 2).
  /// Kept as a function rather than a stored string so it always reads the
  /// current Firebase ID token rather than a stale one.
  Future<String?> Function()? authTokenProvider;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '$_baseUrl$normalizedPath',
    ).replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final headers = <String, String>{if (json) 'Content-Type': 'application/json'};
    final token = await authTokenProvider?.call();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    final uri = _uri(path, query);
    return _send('GET', uri, () async {
      final headers = await _headers(json: false);
      _logRequest('GET', uri, headers, null);
      return _client.get(uri, headers: headers).timeout(Env.apiTimeout);
    });
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) {
    final uri = _uri(path, query);
    return _send('POST', uri, () async {
      final headers = await _headers();
      _logRequest('POST', uri, headers, body);
      return _client
          .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
          .timeout(timeout ?? Env.apiTimeout);
    });
  }

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) {
    final uri = _uri(path, query);
    return _send('PATCH', uri, () async {
      final headers = await _headers();
      _logRequest('PATCH', uri, headers, body);
      return _client
          .patch(uri, headers: headers, body: body == null ? null : jsonEncode(body))
          .timeout(Env.apiTimeout);
    });
  }

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) {
    final uri = _uri(path, query);
    return _send('DELETE', uri, () async {
      final headers = await _headers(json: false);
      _logRequest('DELETE', uri, headers, null);
      return _client.delete(uri, headers: headers).timeout(Env.apiTimeout);
    });
  }

  /// Multipart upload, for endpoints like `/api/chat/upload`,
  /// `/api/meal/estimate-nutrition`, `/api/certificates/verify`.
  Future<dynamic> uploadFile(
    String path, {
    required File file,
    required String fieldName,
    Map<String, String>? fields,
  }) {
    final uri = _uri(path);
    return _send('POST', uri, () async {
      final request = http.MultipartRequest('POST', uri);
      final token = await authTokenProvider?.call();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      if (fields != null) request.fields.addAll(fields);
      request.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
      _logRequest('POST', uri, request.headers, '<multipart: $fieldName=${file.path}>');
      final streamed = await _client.send(request).timeout(Env.apiTimeout);
      return http.Response.fromStream(streamed);
    });
  }

  /// Multipart upload from IN-MEMORY bytes.
  ///
  /// Distinct from [uploadFile], which needs a path on disk. A recorded voice
  /// clip is transient — writing it to storage just to upload it would add
  /// disk I/O, a cleanup obligation, and a copy of the athlete's speech
  /// sitting in the filesystem.
  Future<dynamic> postMultipartBytes(
    String path, {
    required String fileField,
    required String fileName,
    required Uint8List fileBytes,
    Map<String, String>? fields,
    Duration? timeout,
  }) {
    final uri = _uri(path);
    return _send('POST', uri, () async {
      final request = http.MultipartRequest('POST', uri);
      final token = await authTokenProvider?.call();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      if (fields != null) request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(fileField, fileBytes, filename: fileName),
      );
      _logRequest(
        'POST',
        uri,
        request.headers,
        '<multipart: $fileField=$fileName, ${fileBytes.length} bytes>',
      );
      final streamed = await _client.send(request).timeout(timeout ?? Env.apiTimeout);
      return http.Response.fromStream(streamed);
    });
  }

  /// POSTs JSON and returns the raw response BODY BYTES rather than decoded
  /// JSON — for endpoints that answer with binary (`/api/voice/tts` returns
  /// `audio/mpeg`). Running that through [_send] would try to `jsonDecode` an
  /// MP3 and throw.
  Future<Uint8List> postForBytes(
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    final uri = _uri(path);
    late final http.Response res;
    try {
      final headers = await _headers();
      _logRequest('POST', uri, headers, body);
      res = await _client
          .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
          .timeout(timeout ?? Env.apiTimeout);
    } on Exception catch (e) {
      _logTransportFailure('POST', uri, e);
      throw ApiException(message: e.toString());
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // An error body IS json even though the success body isn't.
      String? detail;
      try {
        final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) detail = decoded['detail']?.toString();
      } on FormatException {
        detail = null;
      }
      _logResponse('POST', uri, res.statusCode, detail);
      throw ApiException(
        message: detail ?? 'Request failed (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    return res.bodyBytes;
  }

  Future<dynamic> _send(
    String method,
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    late final http.Response res;
    try {
      res = await request();
    } on http.ClientException catch (e) {
      _logTransportFailure(method, uri, e);
      throw ApiException(message: e.message);
    } on Exception catch (e) {
      _logTransportFailure(method, uri, e);
      throw ApiException(message: e.toString());
    }

    final dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      // A non-JSON body on a 2xx almost always means we hit something that
      // isn't the API (a proxy/captive-portal/HTML error page) — surfacing
      // that as "malformed response" beats a raw parse crash.
      _log('$method $uri -> ${res.statusCode} NON-JSON body — first 120 chars: '
          '${res.body.length > 120 ? res.body.substring(0, 120) : res.body}');
      throw ApiException(
        message: 'Server returned a non-JSON response',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      _logResponse(method, uri, res.statusCode, detail?.toString());
      throw ApiException(
        message: detail?.toString() ?? 'Request failed (${res.statusCode})',
        statusCode: res.statusCode,
        body: decoded,
      );
    }

    return decoded;
  }

  /// Debug-only. Logs the COMPLETE method + URL, the header names (with the
  /// bearer token redacted — a Firebase ID token in logcat is a working
  /// credential for anyone with `adb`), and the request body.
  void _logRequest(String method, Uri uri, Map<String, String> headers, Object? body) {
    if (!kDebugMode) return;
    final safeHeaders = {
      for (final e in headers.entries)
        e.key: e.key.toLowerCase() == 'authorization'
            ? 'Bearer <redacted, ${e.value.length} chars>'
            : e.value,
    };
    _log('--> $method $uri');
    _log('    headers: $safeHeaders');
    final rendered = body == null
        ? '(none)'
        : (body is String ? body : jsonEncode(body));
    _log('    body: ${rendered.length > 500 ? '${rendered.substring(0, 500)}…' : rendered}');
  }

  void _logResponse(String method, Uri uri, int status, String? detail) {
    _log('<-- $status $method $uri — detail: ${detail ?? '(none)'}');
    // 405 from THIS backend is a special, badly-misleading case. FastAPI
    // serves the whole frontend from `app.mount("/", StaticFiles(...))` as a
    // catch-all, and StaticFiles only implements GET/HEAD. So a POST to a
    // path no API route claims does not 404 — it falls through to the static
    // mount and comes back 405. Verified against production: POST to
    // `/zzz-not-an-api-path` also answers 405. Read it as "route not found
    // on the deployed build", never as "wrong HTTP method".
    if (status == 405) {
      _log('    NOTE: 405 here means NO API ROUTE MATCHED $uri and the request '
          'fell through to the StaticFiles catch-all (GET/HEAD only). The route '
          'is missing from the DEPLOYED build — check the deployment, not the verb.');
    }
  }

  void _logTransportFailure(String method, Uri uri, Object e) {
    _log(
      'TRANSPORT FAILURE on $method $uri (${e.runtimeType}). '
      'If this is a physical device, confirm API_BASE_URL is reachable from '
      'the phone — localhost/127.0.0.1 resolves to the phone itself.',
    );
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ApiClient] $msg');
  }

  void close() => _client.close();
}
