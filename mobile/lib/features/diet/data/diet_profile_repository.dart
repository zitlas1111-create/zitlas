import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/storage/local_storage_service.dart';
import '../models/diet_profile.dart';

/// Persists the athlete's permanent food profile.
///
/// ONE canonical location: `users/{uid}.dietProfile`. Account-level, exactly
/// like `zinoTourCompleted` and `voiceLanguage`, and for the same reason —
/// "who cooks for you" and "what can you afford" are facts about the PERSON,
/// so they must survive logout, reinstall, and a new device, and must never
/// leak to the next account on a shared phone.
///
/// The local copy is a uid-scoped cache so the diet screen can personalise
/// instantly without waiting on a read; Firestore stays the source of truth.
class DietProfileRepository {
  DietProfileRepository({
    required FirebaseFirestore firestore,
    LocalStorageService? storage,
  })  : _db = firestore,
        _storage = storage;

  final FirebaseFirestore _db;
  final LocalStorageService? _storage;

  static const fieldName = 'dietProfile';

  String _cacheKey(String uid) => 'zitlas_diet_profile_$uid';

  LocalStorageService? get _cache {
    if (_storage != null) return _storage;
    try {
      return LocalStorageService.instance;
    } catch (_) {
      // Not initialized (tests / very early startup) — the cache is an
      // optimisation, never a requirement.
      return null;
    }
  }

  /// Loads the profile.
  ///
  /// `known: false` means the read FAILED, which is deliberately distinct
  /// from "no profile yet" — prompting an athlete to re-answer eight
  /// questions because the network blipped would be worse than showing a
  /// slightly less personalised plan.
  Future<({DietProfile profile, bool known})> load(String uid) async {
    final cached = _cache?.getJson(_cacheKey(uid));
    if (cached != null) {
      return (profile: DietProfile.fromMap(cached), known: true);
    }
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final raw = (snap.data()?[fieldName] as Map?)?.cast<String, dynamic>();
      if (raw == null) {
        return (profile: const DietProfile(), known: true);
      }
      final profile = DietProfile.fromMap(raw);
      await _cache?.setJson(_cacheKey(uid), profile.toMap());
      return (profile: profile, known: true);
    } catch (e) {
      if (kDebugMode) debugPrint('[DIET PROFILE] read failed: $e');
      return (profile: const DietProfile(), known: false);
    }
  }

  /// True only when this athlete has verifiably never completed the intake.
  ///
  /// Fails CLOSED — an unreadable profile is not evidence of a new athlete,
  /// so an existing one is never re-asked because of a flaky connection.
  Future<bool> needsIntake(String uid) async {
    final result = await load(uid);
    if (!result.known) return false;
    return !result.profile.isComplete;
  }

  /// Writes the whole block. Local first and unconditionally, so a failed
  /// network write can't cause the intake to reappear on the next launch.
  Future<void> save(String uid, DietProfile profile) async {
    final stamped = profile.completedAt == null
        ? profile.copyWith(completedAt: DateTime.now())
        : profile;
    await _cache?.setJson(_cacheKey(uid), stamped.toMap());
    try {
      await _db.collection('users').doc(uid).set({
        fieldName: stamped.toMap(),
        '${fieldName}UpdatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      if (kDebugMode) debugPrint('[DIET PROFILE] saved for $uid');
    } catch (e) {
      if (kDebugMode) debugPrint('[DIET PROFILE] cloud persist failed: $e');
    }
  }

  /// Permanently records a dislike — the "I don't like this" path from Zino
  /// and from Swap. Additive and idempotent, so saying it twice is harmless.
  Future<DietProfile> addDislike(String uid, String food) async {
    final current = (await load(uid)).profile;
    final name = food.trim();
    if (name.isEmpty) return current;
    final already = current.dislikedFoods
        .any((d) => d.toLowerCase() == name.toLowerCase());
    if (already) return current;
    final updated =
        current.copyWith(dislikedFoods: [...current.dislikedFoods, name]);
    await save(uid, updated);
    return updated;
  }
}
