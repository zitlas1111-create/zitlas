import 'package:google_sign_in/google_sign_in.dart';

/// User-facing auth failure. [message] is already resolved to display text
/// by the time it leaves [AuthRepository] — see [mapFirebaseAuthErrorCode].
class AuthException implements Exception {
  const AuthException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AuthException($code): $message';
}

/// Thrown when the user backs out of the native Google account picker.
/// Handled silently by the UI (no error shown), same intent as `login.js`'s
/// `auth/popup-closed-by-user` no-op on web.
class AuthCancelledException implements Exception {
  const AuthCancelledException();
}

/// Exact copy of `getAuthErrorMsg()` in `frontend/pages/login/login.js`.
/// FirebaseAuthException.code on Flutter is the bare code (no `auth/`
/// prefix), so the keys here are bare too.
String mapFirebaseAuthErrorCode(String? code) {
  const messages = {
    'user-not-found': 'No account found with this email.',
    'wrong-password': 'Incorrect password. Please try again.',
    'invalid-credential': 'Invalid email or password.',
    'email-already-in-use': 'An account with this email already exists.',
    'weak-password': 'Password must be at least 6 characters.',
    'invalid-email': 'Please enter a valid email address.',
    'too-many-requests': 'Too many attempts. Please try again later.',
    'network-request-failed': 'Network error. Check your connection.',
  };
  return messages[code] ?? 'Authentication failed. Please try again.';
}

/// User-facing message for a native `GoogleSignInException` (thrown by the
/// `google_sign_in` package's Credential Manager-backed `authenticate()`).
/// Cancel/interrupt codes are handled separately via [AuthCancelledException]
/// before this is reached — see the package's own README on
/// `clientConfigurationError`/`uiUnavailable` for what these mean in practice.
String mapGoogleSignInErrorCode(GoogleSignInExceptionCode code) {
  switch (code) {
    case GoogleSignInExceptionCode.clientConfigurationError:
    case GoogleSignInExceptionCode.providerConfigurationError:
      return 'Google sign-in is not configured correctly for this app. Please try again later.';
    case GoogleSignInExceptionCode.uiUnavailable:
      return 'Google sign-in is unavailable right now. Please try again.';
    case GoogleSignInExceptionCode.userMismatch:
      return 'Please sign out of the other account first, then try again.';
    case GoogleSignInExceptionCode.canceled:
    case GoogleSignInExceptionCode.interrupted:
    case GoogleSignInExceptionCode.unknownError:
      return 'Google sign-in failed. Please try again.';
  }
}
