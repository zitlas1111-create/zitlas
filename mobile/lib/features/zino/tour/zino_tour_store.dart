import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/storage/local_storage_service.dart';

/// Decides whether the Zino tour may auto-start, and records completion.
///
/// THE CANONICAL FIELD is `users/{uid}.zinoTourCompleted` — the SAME field
/// `zino.js`'s `markDone()` writes (`ZitlasCloudSync.save('zinoTourCompleted',
/// 'true')`). No new field is introduced, so an athlete who completed the tour
/// on the website is never re-toured in the app, and vice versa. It is written
/// as the STRING `'true'` for exactly that cross-client compatibility; reads
/// accept either form, matching the website's own
/// `String(snap.data().zinoTourCompleted) === 'true'` coercion.
///
/// ACCOUNT-LEVEL, NOT INSTALL-LEVEL. This is the difference between "new to
/// this phone" and "new to ZITLAS". SharedPreferences alone would re-tour
/// every existing athlete the moment they installed the Flutter app, and
/// would re-tour anyone who reinstalled — so the local flag is only ever a
/// fast-path CACHE of the authoritative Firestore value, never the decision.
///
/// FAIL-CLOSED. If the Firestore check can't be completed (offline, permission
/// error, timeout), [shouldAutoStart] returns **false** — do not tour. Ported
/// deliberately from the website's `_confirmNeverToured()`, whose comment
/// spells out the reasoning: a returning athlete must never be re-toured,
/// whereas a genuinely new one simply gets the tour on the next launch when
/// the read succeeds. That single choice is also what prevents the endless
/// onboarding loop a fail-open design would cause on a flaky connection.
class ZinoTourStore {
  ZinoTourStore({required FirebaseFirestore firestore, LocalStorageService? storage})
      : _db = firestore,
        _storage = storage ?? LocalStorageService.instance;

  final FirebaseFirestore _db;
  final LocalStorageService _storage;

  /// Field name shared with the website — do not rename.
  static const fieldName = 'zinoTourCompleted';

  /// Local mirror, uid-scoped so two accounts on one phone can't read each
  /// other's status. Purely an optimisation; Firestore is authoritative.
  String _cacheKey(String uid) => 'zitlas_zino_tour_completed_$uid';

  bool _cachedCompleted(String uid) => _storage.getBool(_cacheKey(uid)) ?? false;

  /// True only when this ACCOUNT has verifiably never finished or skipped the
  /// tour. Anything uncertain returns false.
  Future<bool> shouldAutoStart(String uid) async {
    if (_cachedCompleted(uid)) {
      if (kDebugMode) debugPrint('[ZINO TOUR] cached completed -> no auto-start');
      return false;
    }
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final done = _isCompleted(snap.data());
      if (done) {
        // Heal the local mirror so later launches short-circuit without a read.
        await _storage.setBool(_cacheKey(uid), true);
        if (kDebugMode) debugPrint('[ZINO TOUR] account already toured -> no auto-start');
        return false;
      }
      if (kDebugMode) debugPrint('[ZINO TOUR] new account -> auto-start');
      return true;
    } catch (e) {
      // Fail closed: an unreadable profile is NOT evidence of a new user.
      if (kDebugMode) {
        debugPrint('[ZINO TOUR] completion check failed — not auto-starting: $e');
      }
      return false;
    }
  }

  /// Accepts the website's string form and a plain bool, so either client's
  /// write is understood.
  static bool _isCompleted(Map<String, dynamic>? data) {
    final v = data?[fieldName];
    if (v is bool) return v;
    return v?.toString().toLowerCase() == 'true';
  }

  /// Records completion. Called when the athlete finishes OR skips — the
  /// website treats both identically (`skip()` funnels into `finish()`), and
  /// re-showing a tour someone deliberately dismissed would be worse than not
  /// showing it at all.
  ///
  /// The local mirror is written FIRST and unconditionally, so a failed
  /// network write can never resurrect the tour on the next launch. The
  /// Firestore write then makes it durable across devices; if it fails, the
  /// athlete simply isn't re-toured on this device, and the next successful
  /// write (or a completion elsewhere) settles it.
  Future<void> markCompleted(String uid) async {
    await _storage.setBool(_cacheKey(uid), true);
    try {
      await _db.collection('users').doc(uid).set({
        fieldName: 'true',
        '${fieldName}UpdatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      if (kDebugMode) debugPrint('[ZINO TOUR] completion persisted for $uid');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ZINO TOUR] cloud persist failed (local flag kept): $e');
      }
    }
  }
}
