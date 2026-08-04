import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/profile_repository.dart';
import 'models/personal_info.dart';

/// Aggregates the Profile hub's live state. Mirrors `profile.js`'s
/// `loadAthleteProfile()` + cloud-sync realtime re-render (`attachRealtime`)
/// — one `users/{uid}` listener drives the avatar/name/AI-label/membership
/// badge instead of profile.js's four separate localStorage reads, because
/// Flutter has no localStorage-first cache to read from.
class ProfileController extends ChangeNotifier {
  ProfileController({required this.uid, required ProfileRepository repository}) : _repository = repository {
    _sub = _repository.watchUserDoc(uid).listen(_onUserDoc, onError: (e) {
      error = e;
      loading = false;
      _safeNotify();
    });
  }

  final String uid;
  final ProfileRepository _repository;
  ProfileRepository get repository => _repository;
  StreamSubscription<Map<String, dynamic>?>? _sub;
  bool _disposed = false;

  bool loading = true;
  Object? error;

  PersonalInfo personalInfo = const PersonalInfo();
  Membership membership = const Membership();

  /// Fallback identity fields from the base `users/{uid}` doc (written by
  /// login), used whenever `personalInfo` hasn't been filled in yet —
  /// mirrors `info.fullName || zUser.name || fbUser.displayName` exactly.
  String? _accountName;
  String? _accountPhoto;

  /// `zitlas_expert_applied` on web — this app's equivalent lives on the
  /// same doc as `expert_status == 'pending'` (see `UserModel.isExpert`);
  /// surfaced here only for the banner, not for role routing.
  bool expertApplicationPending = false;

  String? _goalType;

  void _onUserDoc(Map<String, dynamic>? data) {
    loading = false;
    error = null;
    if (data == null) {
      _safeNotify();
      return;
    }
    personalInfo = PersonalInfo.fromMap((data['personalInfo'] as Map?)?.cast<String, dynamic>());
    membership = Membership.fromMap((data['membership'] as Map?)?.cast<String, dynamic>());
    _accountName = data['name'] as String?;
    _accountPhoto = data['photo'] as String?;
    expertApplicationPending = data['expert_status'] == 'pending';

    final goal = (data['goal'] as Map?)?.cast<String, dynamic>();
    final survey = (data['survey'] as Map?)?.cast<String, dynamic>();
    _goalType = (goal?['type'] as String?) ?? (survey?['fitness_goal'] as String?);
    _safeNotify();
  }

  /// `var name = (info.fullName || zUser.name || fbUser.displayName || fbUser.name || '').trim()`
  String displayName(String authFallbackName) {
    final n = personalInfo.fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (_accountName != null && _accountName!.trim().isNotEmpty) return _accountName!.trim();
    return authFallbackName.trim();
  }

  /// `var photo = info.photo || zUser.photo || fbUser.photoURL || fbUser.photo || null`
  String? displayPhoto(String? authFallbackPhoto) {
    if (personalInfo.photo != null && personalInfo.photo!.isNotEmpty) return personalInfo.photo;
    if (_accountPhoto != null && _accountPhoto!.isNotEmpty) return _accountPhoto;
    return authFallbackPhoto;
  }

  /// `'AI ' + goalType + ' Member'`, title-cased per word — `loadAthleteProfile()`.
  String aiLabel() {
    final type = _goalType?.replaceAll('_', ' ').trim();
    if (type == null || type.isEmpty) return 'AI Weight-Loss Member';
    final titled = type.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    return 'AI $titled Member';
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
