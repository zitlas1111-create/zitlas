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
    return _send(() async {
      final res = await _client
          .get(_uri(path, query), headers: await _headers(json: false))
          .timeout(Env.apiTimeout);
      return res;
    });
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) {
    return _send(() async {
      final res = await _client
          .post(
            _uri(path, query),
            headers: await _headers(),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout ?? Env.apiTimeout);
      return res;
    });
  }

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) {
    return _send(() async {
      final res = await _client
          .patch(
            _uri(path, query),
            headers: await _headers(),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(Env.apiTimeout);
      return res;
    });
  }

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) {
    return _send(() async {
      final res = await _client
          .delete(_uri(path, query), headers: await _headers(json: false))
          .timeout(Env.apiTimeout);
      return res;
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
    return _send(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      final token = await authTokenProvider?.call();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      if (fields != null) request.fields.addAll(fields);
      request.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
      final streamed = await _client.send(request).timeout(Env.apiTimeout);
      return http.Response.fromStream(streamed);
    });
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    late final http.Response res;
    try {
      res = await request();
    } on http.ClientException catch (e) {
      _logTransportFailure(e);
      throw ApiException(message: e.message);
    } on Exception catch (e) {
      _logTransportFailure(e);
      throw ApiException(message: e.toString());
    }

    final dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      // A non-JSON body on a 2xx almost always means we hit something that
      // isn't the API (a proxy/captive-portal/HTML error page) — surfacing
      // that as "malformed response" beats a raw parse crash.
      _log('Non-JSON response (${res.statusCode}) from $_baseUrl — first 120 chars: '
          '${res.body.length > 120 ? res.body.substring(0, 120) : res.body}');
      throw ApiException(
        message: 'Server returned a non-JSON response',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      _log('HTTP ${res.statusCode} from $_baseUrl — detail: ${detail ?? '(none)'}');
      throw ApiException(
        message: detail?.toString() ?? 'Request failed (${res.statusCode})',
        statusCode: res.statusCode,
        body: decoded,
      );
    }

    return decoded;
  }

  /// Debug-only. Logs the base URL and failure class — never the auth
  /// header, request body, or response payload (all of which can carry
  /// tokens or personal data).
  void _logTransportFailure(Object e) {
    _log(
      'Transport failure talking to $_baseUrl (${e.runtimeType}). '
      'If this is a physical device, confirm API_BASE_URL is reachable from '
      'the phone — localhost/127.0.0.1 resolves to the phone itself.',
    );
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ApiClient] $msg');
  }

  void close() => _client.close();
}
