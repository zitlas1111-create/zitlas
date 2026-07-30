import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'auth_state.dart';

/// Single logout entry point shared by every authenticated role (athlete
/// Profile screen, Expert Dashboard account menu, ...) so there is exactly
/// one place that decides what "signing out" means in this app.
///
/// [AuthState.signOut] already does the correct, complete thing: Firebase
/// Auth sign-out (covers email/password and Google, both funnel through the
/// same `FirebaseAuth.instance.signOut()`), Google session sign-out, and
/// [AccountGuard.clearUserCache] — which only purges the local
/// SharedPreferences cache (device-scoped keys survive), never touches
/// Firestore. No user/expert/plan data is ever deleted by logging out.
///
/// `context.go('/login')` after that is a deliberate explicit replace (not
/// `push`) on top of the reactive GoRouter redirect that already fires from
/// `refreshListenable` — it guarantees the authenticated route is gone from
/// the stack so Android Back can't reopen it, rather than relying solely on
/// the redirect's timing.
Future<void> performSignOut(BuildContext context) async {
  await context.read<AuthState>().signOut();
  if (context.mounted) context.go('/login');
}
