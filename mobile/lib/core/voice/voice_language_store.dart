import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../storage/local_storage_service.dart';
import 'voice_language.dart';

/// Stores the athlete's preferred voice language.
///
/// ACCOUNT-LEVEL, like the Zino tour flag and for the same reason: "which
/// language do you want Zino to speak" is a fact about the PERSON, not about
/// the phone. Persisting it only in SharedPreferences would re-ask on every
/// reinstall and on every new device, and would leak one athlete's choice to
/// the next account on a shared handset.
///
/// ONE canonical field: `users/{uid}.voiceLanguage`. The local copy is a
/// uid-scoped cache so the call screen can open instantly without waiting on a
/// network read; Firestore stays authoritative.
class VoiceLanguageStore {
  VoiceLanguageStore({required FirebaseFirestore firestore, LocalStorageService? storage})
      : _db = firestore,
        _storage = storage ?? LocalStorageService.instance;

  final FirebaseFirestore _db;
  final LocalStorageService _storage;

  static const fieldName = 'voiceLanguage';

  String _cacheKey(String uid) => 'zitlas_voice_language_$uid';

  /// The stored language, or null when the athlete has never chosen one —
  /// which is precisely the signal to show the first-run picker.
  ///
  /// Returns the cached value immediately when present. On a cache miss it
  /// reads Firestore; a FAILED read returns null-with-`known: false` so the
  /// caller can tell "never chose" apart from "couldn't check", and avoid
  /// overwriting a real remote choice with a fresh prompt.
  Future<({VoiceLanguage? language, bool known})> load(String uid) async {
    final cached = _storage.getString(_cacheKey(uid));
    if (cached != null && cached.isNotEmpty) {
      return (language: VoiceLanguage.fromId(cached), known: true);
    }
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final raw = snap.data()?[fieldName];
      if (raw is String && raw.trim().isNotEmpty) {
        final lang = VoiceLanguage.fromId(raw);
        await _storage.setString(_cacheKey(uid), lang.id);
        return (language: lang, known: true);
      }
      // Read succeeded, field genuinely absent -> a real first-time athlete.
      return (language: null, known: true);
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] language read failed: $e');
      return (language: null, known: false);
    }
  }

  /// Persists the choice. Local first and unconditionally, so a failed network
  /// write can't cause the picker to reappear on the next launch; the cloud
  /// write then makes it durable across devices.
  Future<void> save(String uid, VoiceLanguage language) async {
    await _storage.setString(_cacheKey(uid), language.id);
    try {
      await _db.collection('users').doc(uid).set({
        fieldName: language.id,
        '${fieldName}UpdatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      if (kDebugMode) debugPrint('[VOICE] language saved: ${language.id}');
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] language cloud persist failed: $e');
    }
  }
}
