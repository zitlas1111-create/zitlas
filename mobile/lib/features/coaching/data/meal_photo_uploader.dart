import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';

/// Uploads a meal photo, mirroring `assets/js/chat-attachments.js` exactly.
///
/// THE SAME THREE STEPS THE WEBSITE USES, in the same order:
///   1. compress,
///   2. Firebase Storage — the primary path, into the same bucket certificate
///      uploads already use, at `meal_checkins/{uid}/{ts}_{rand}.jpg`,
///   3. `POST /api/chat/upload` — the fallback, used whenever Storage is
///      unavailable, denied by bucket rules, or times out.
///
/// The fallback is the whole point: an athlete photographing their lunch must
/// not lose it because a bucket rule changed. A failed Storage upload is a
/// logged warning, never a failed check-in.
class MealPhotoUploader {
  MealPhotoUploader({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    ApiClient? api,
  })  : _storage = storage,
        _auth = auth ?? FirebaseAuth.instance,
        _api = api ?? ApiClient();

  final FirebaseStorage? _storage;
  final FirebaseAuth _auth;
  final ApiClient _api;

  /// Matches the website's own limits (`chat-attachments.js`).
  static const maxBytes = 10 * 1024 * 1024;
  static const _storageTimeout = Duration(seconds: 30);
  static const _backendTimeout = Duration(seconds: 60);

  /// Longest edge after compression. A meal photo is looked at on a phone by
  /// one coach; anything larger is bandwidth the athlete pays for on mobile
  /// data for no gain.
  static const _maxDimension = 1600;
  static const _quality = 80;

  /// Returns the URL to store on the check-in.
  ///
  /// Throws only when BOTH paths fail — at which point there genuinely is no
  /// image to attach and the caller must not write a check-in pointing at
  /// nothing.
  Future<String> upload(File file, {String pathPrefix = 'meal_checkins'}) async {
    final original = await file.length();
    if (original > maxBytes) {
      throw Exception('That image is larger than 10 MB. Try another photo.');
    }

    final bytes = await _compress(file);
    if (kDebugMode) {
      debugPrint('[MEAL UPLOAD] compressed ${original ~/ 1024}KB -> ${bytes.length ~/ 1024}KB');
    }

    try {
      final url = await _toFirebaseStorage(bytes, pathPrefix).timeout(_storageTimeout);
      if (kDebugMode) debugPrint('[MEAL UPLOAD] Firebase Storage OK');
      return url;
    } catch (e) {
      // Exactly the website's behaviour: warn and fall through. Storage being
      // unreachable is not a reason to lose the athlete's photo.
      if (kDebugMode) {
        debugPrint('[MEAL UPLOAD] Firebase Storage failed ($e) — falling back to backend');
      }
    }

    final url = await _toBackend(bytes).timeout(_backendTimeout);
    if (kDebugMode) debugPrint('[MEAL UPLOAD] backend fallback OK -> $url');
    return url;
  }

  Future<Uint8List> _compress(File file) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        quality: _quality,
        format: CompressFormat.jpeg,
      );
      if (result != null && result.isNotEmpty) return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[MEAL UPLOAD] compression failed ($e) — sending original');
    }
    // Compression is an optimisation, not a gate. A device whose codec refuses
    // still gets to submit its meal.
    return file.readAsBytes();
  }

  Future<String> _toFirebaseStorage(Uint8List bytes, String pathPrefix) async {
    final storage = _storage ?? FirebaseStorage.instance;
    final uid = _auth.currentUser?.uid ?? 'anon';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rand = (stamp % 100000).toRadixString(36);
    final path = '$pathPrefix/$uid/${stamp}_$rand.jpg';

    final ref = storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<String> _toBackend(Uint8List bytes) async {
    final res = await _api.postMultipartBytes(
      '/api/chat/upload',
      fileField: 'file',
      fileName: 'meal.jpg',
      fileBytes: bytes,
    );
    if (res is Map && res['success'] == true && res['url'] is String) {
      final url = res['url'] as String;
      // The backend returns a site-relative path (`/uploads/chat/x.jpg`);
      // absolute-ise it so the coach's app can load it from anywhere.
      return url.startsWith('http') ? url : '${Env.apiBaseUrl}$url';
    }
    throw Exception('Could not upload the photo. Please try again.');
  }
}
