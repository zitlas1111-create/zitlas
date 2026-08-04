import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../storage/local_storage_service.dart';

/// Native FCM token management — the mobile counterpart to
/// `assets/js/push-notifications.js`'s `registerAndStoreToken()`. Writes to
/// the SAME `users/{uid}.pushTokens` array (arrayUnion — multi-device safe,
/// logging in on a second device never overwrites the first token) the
/// website already writes to, so the two clients are indistinguishable to
/// any future FCM sender.
///
/// Honest limitation: the backend (`services/push_service.py`) can deliver
/// to a stored token, but nothing server-side calls it for a real ZITLAS
/// event yet — `notification-center.js`'s own header comment confirms this
/// ("FCM-READY... No Cloud Function exists yet"). Registering the token here
/// is real, correct, forward-compatible infrastructure, not a promise that
/// push-per-event already fires — see docs/MIGRATION_INVENTORY.md Phase 8.
class FcmService {
  FcmService({required FirebaseFirestore firestore}) : _db = firestore;

  final FirebaseFirestore _db;
  static const _stateKey = 'zitlas_push_state'; // mirrors web's STATE_KEY
  static const _snoozeDays = 7;

  /// `route()`'s `perm === 'default'` snooze gate (push-notifications.js:236),
  /// ported so the OS permission dialog isn't re-shown every app open.
  bool get _isSnoozed {
    final raw = LocalStorageService.instance.getString(_stateKey);
    if (raw == null) return false;
    try {
      final parts = raw.split('|'); // "status|epochMillis"
      if (parts.length != 2 || parts[0] != 'snoozed') return false;
      final ts = int.tryParse(parts[1]) ?? 0;
      return (DateTime.now().millisecondsSinceEpoch - ts) / 86400000 < _snoozeDays;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setState(String status) {
    return LocalStorageService.instance.setString(_stateKey, '$status|${DateTime.now().millisecondsSinceEpoch}');
  }

  /// Called once per app session after authentication resolves — NOT at
  /// splash, matching the task's "contextual, not at launch" requirement.
  /// Silently no-ops if already snoozed this week; never re-prompts once
  /// permanently denied (`authorizationStatus == denied` after a real ask).
  Future<void> initForUser(String uid) async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.denied && !kIsWeb) {
      // Already explicitly denied by the user previously — Android won't
      // re-show its own dialog either way; nothing to do but stay usable.
      return;
    }
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      if (_isSnoozed) return;
      final result = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (result.authorizationStatus != AuthorizationStatus.authorized &&
          result.authorizationStatus != AuthorizationStatus.provisional) {
        await _setState('snoozed');
        return;
      }
    }
    await _setState('granted');
    await _registerToken(uid);
    FirebaseMessaging.instance.onTokenRefresh.listen((token) => _storeToken(uid, token));
  }

  Future<void> _registerToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _storeToken(uid, token);
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] token registration failed: $e');
    }
  }

  Future<void> _storeToken(String uid, String token) async {
    if (kDebugMode) debugPrint('[FCM] token for $uid: ${token.substring(0, token.length.clamp(0, 24))}…');
    await _db.collection('users').doc(uid).set({
      'pushTokens': FieldValue.arrayUnion([token]),
      'pushTokensUpdatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}
