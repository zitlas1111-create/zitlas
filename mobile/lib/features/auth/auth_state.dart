import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/notifications/fcm_service.dart';
import '../../core/storage/account_guard.dart';
import '../../models/user_model.dart';
import 'data/auth_repository.dart';

enum AuthStatus {
  /// First frame, before Firebase's persisted session has been checked.
  unknown,
  unauthenticated,
  authenticated,

  /// Firebase isn't registered for `com.zitlas.app` yet (no
  /// google-services.json) — see docs/MIGRATION_INVENTORY.md §4. Routes
  /// like `unauthenticated` but the login screen shows why sign-in can't
  /// work yet instead of silently failing.
  firebaseUnavailable,
}

/// Drives auth/session state for the whole app: session restore on cold
/// start, sign-in/sign-up/Google/logout, and the role resolution GoRouter's
/// redirect logic depends on. See docs/MIGRATION_INVENTORY.md §2/§3 for the
/// production behavior this ports.
class AuthState extends ChangeNotifier {
  AuthState(this._repository) {
    if (!_repository.isAvailable) {
      _status = AuthStatus.firebaseUnavailable;
      return;
    }
    _sub = _repository.authStateChanges().listen(_handleFirebaseUser);
  }

  final AuthRepository _repository;
  AuthRepository get repository => _repository;

  StreamSubscription<User?>? _sub;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _profile;

  AuthStatus get status => _status;
  UserModel? get profile => _profile;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Cold-start session restore (Firebase persists sessions natively on
  /// Android/iOS) and the fallback path if an interactive flow's own
  /// resolution hasn't completed yet. Guarded against redoing work an
  /// interactive method already did for the same uid.
  Future<void> _handleFirebaseUser(User? user) async {
    if (user == null) {
      _profile = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    if (_profile?.uid == user.uid) return;

    try {
      final profile = await _repository.fetchProfile(user);
      await _applyAuthenticated(profile);
    } catch (_) {
      // Doc not created yet (e.g. mid Google role-selection, or signup's
      // Firestore write hasn't landed) — only downgrade on the very first
      // cold-start resolution; don't clobber an interactive flow in flight.
      if (_status == AuthStatus.unknown) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    }
  }

  Future<void> _applyAuthenticated(UserModel profile) async {
    await AccountGuard.instance.beginSession(profile.uid);
    _profile = profile;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    final profile = await _repository.signInWithEmail(email, password);
    await _applyAuthenticated(profile);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final profile = await _repository.signUpWithEmail(
      email: email,
      password: password,
      name: name,
      role: role,
    );
    await _applyAuthenticated(profile);
  }

  /// Returns the raw outcome so the login screen can show the role-picker
  /// modal when needed; already-resolved outcomes are applied here.
  Future<GoogleSignInOutcome> signInWithGoogle() async {
    final outcome = await _repository.signInWithGoogle();
    if (outcome is GoogleSignInResolved) {
      await _applyAuthenticated(outcome.profile);
    }
    return outcome;
  }

  Future<void> completeGoogleRoleSelection(User user, String role) async {
    final profile = await _repository.completeGoogleRoleSelection(user, role);
    await _applyAuthenticated(profile);
  }

  Future<void> sendPasswordReset(String email) => _repository.sendPasswordReset(email);

  Future<void> signOut() async {
    // Detach THIS device from the outgoing account BEFORE Firebase sign-out,
    // while its uid and a valid auth context still exist (the Firestore write
    // needs both). Without this the previous account keeps a live token for a
    // phone somebody else may now be signing into, and the backend would keep
    // delivering their notifications here — the cross-account leak.
    //
    // Best-effort: a failure must never block logout, and it self-corrects
    // anyway because the next login re-owns the same token document.
    final outgoingUid = _profile?.uid;
    if (outgoingUid != null) {
      try {
        await FcmService().unregisterDevice(outgoingUid);
      } catch (e) {
        if (kDebugMode) debugPrint('[AUTH] FCM unregister failed (non-fatal): $e');
      }
    }
    await _repository.signOut();
    await AccountGuard.instance.clearUserCache();
    _profile = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  bool _disposed = false;

  // Guards "A ChangeNotifier was used after being disposed" / dispose-during-
  // notify: an async Firebase auth callback can fire after this provider is
  // torn down (navigation). A disposed notifier simply stops notifying.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
