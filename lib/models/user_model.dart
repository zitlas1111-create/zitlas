/// Mirrors the `users/{uid}` Firestore document — the single most-shared
/// collection in the app (see docs/MIGRATION_INVENTORY.md §3). Only the
/// identity/role fields are modeled here; the large cloud-synced app-state
/// blob (goal/assessment/diet/workout/personalInfo/...) belongs to each
/// owning feature's own model once that feature is built, not here.
class UserModel {
  const UserModel({
    required this.uid,
    required this.email,
    this.name,
    this.photoUrl,
    this.role = 'athlete',
    this.roles = const [],
    this.expertStatus = 'none',
  });

  final String uid;
  final String email;
  final String? name;
  final String? photoUrl;

  /// Legacy single-value role (`'athlete' | 'expert'`) — kept alongside
  /// [roles] because both are still read on web; see the Firebase audit.
  final String role;
  final List<String> roles;

  /// `'none' | 'pending' | 'approved'`
  final String expertStatus;

  /// Exact role-resolution algorithm from `frontend/pages/login/login.js`
  /// (both the `onAuthStateChanged` listener and the Google existing-user
  /// path use this identical check) — do not simplify this, it's the
  /// production source of truth for who lands in the expert dashboard.
  bool get isExpert =>
      roles.contains('expert') ||
      roles.contains('expert_pending') ||
      expertStatus == 'approved' ||
      expertStatus == 'pending' ||
      role == 'expert';

  /// `'expert' | 'athlete'` — what `login.js` calls `resolvedRole`.
  String get resolvedRole => isExpert ? 'expert' : 'athlete';

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String,
      email: map['email'] as String? ?? '',
      name: map['name'] as String?,
      photoUrl: map['photo'] as String?,
      role: map['role'] as String? ?? 'athlete',
      roles: (map['roles'] as List?)?.cast<String>() ?? const [],
      expertStatus: map['expert_status'] as String? ?? 'none',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      if (name != null) 'name': name,
      if (photoUrl != null) 'photo': photoUrl,
      'role': role,
      'roles': roles,
      'expert_status': expertStatus,
    };
  }
}
