import 'package:go_router/go_router.dart';

import '../core/widgets/app_shell.dart';
import '../features/admin/presentation/screens/admin_screen.dart';
import '../features/ai_coach/presentation/screens/ai_coach_screen.dart';
import '../features/assessment/presentation/screens/assessment_screen.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/presentation/screens/expert_application_review_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/coaching_webview/coaching_webview_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/diet/presentation/screens/diet_screen.dart';
// NOTE: ExpertDashboardScreen (native coach dashboard) is intentionally NOT
// imported — /expert-dashboard now renders CoachingWebViewScreen. The native
// screen stays in the tree, dormant, for the eventual return to native parity.
import '../features/experts/presentation/screens/expert_profile_screen.dart';
import '../features/experts/presentation/screens/experts_screen.dart';
import '../features/health/presentation/screens/step_history_route.dart';
import '../features/membership/presentation/screens/membership_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/payments/presentation/screens/wallet_screen.dart';
import '../features/profile/presentation/screens/help_support_screen.dart';
import '../features/profile/presentation/screens/notification_settings_screen.dart';
import '../features/profile/presentation/screens/personal_info_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/reviews/presentation/screens/reviews_screen.dart';
import '../features/workout/presentation/screens/workout_screen.dart';
import '../features/zino/data/zino_context_builder.dart';
import '../features/zino/presentation/screens/zino_screen.dart';
import '../features/zino/voice/presentation/zino_call_screen.dart';

/// Routing foundation. The 5 bottom-nav tabs (matching `components/navbar.js`
/// on web) live under a [StatefulShellRoute] so each tab keeps its own back
/// stack; everything else is a flat top-level route for now — see
/// docs/MIGRATION_INVENTORY.md §2 for which web page maps to which route,
/// and §6 for what's deliberately not wired up yet (real screens, nested
/// feature navigation, role-gating).
GoRouter buildRouter(AuthState authState) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authState,
    redirect: (context, state) {
      final status = authState.status;
      final loc = state.matchedLocation;
      final onSplash = loc == '/splash';
      final onLogin = loc == '/login';

      // Before Firebase's persisted-session check resolves, stay on the
      // splash screen — never flash /login or a dashboard first.
      if (status == AuthStatus.unknown) {
        return onSplash ? null : '/splash';
      }

      final signedIn = status == AuthStatus.authenticated;
      if (!signedIn) {
        // Covers both unauthenticated and firebaseUnavailable — both route
        // to the login screen (which shows why sign-in is disabled for the
        // latter, see docs/MIGRATION_INVENTORY.md §4).
        return onLogin ? null : '/login';
      }

      // Signed in: leave the splash/login screens for the correct
      // dashboard by role. Every other route (including /under-review,
      // which an authenticated pending-expert lands on deliberately) is
      // left alone — this is what prevents redirect loops.
      if (onSplash || onLogin) {
        return authState.profile?.resolvedRole == 'expert' ? '/expert-dashboard' : '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/under-review',
        builder: (context, state) => const ExpertApplicationReviewScreen(),
      ),

      // Full-screen flows outside the bottom-nav shell.
      GoRoute(path: '/assessment', builder: (context, state) => const AssessmentScreen()),
      GoRoute(path: '/ai-coach', builder: (context, state) => const AiCoachScreen()),
      // Personal Coaching (coach side) is served by the Website inside a
      // secure WebView until native Flutter reaches parity. The native
      // ExpertDashboardScreen is kept in the tree (dormant) so this can be
      // flipped back with a one-line change.
      GoRoute(
        path: '/expert-dashboard',
        builder: (context, state) => CoachingWebViewScreen.expertDashboard(),
      ),
      // The COMPLETE coach journey — profile, Request Review, Personal Coach,
      // payment, and (once active) the full coaching workspace: diet,
      // training, meal snap/review, chat, calls, progress, End Coaching.
      // INTENTIONALLY the Website's own cprofile.html in a WebView, kept as
      // ONE continuous Website session for all of it — never the native
      // ExpertProfileScreen (that screen stays in the tree, dormant, and is
      // no longer reached by anything in the normal flow).
      // `action` (optional) deep-links straight into the website's own
      // Request-Review / Personal-Coach / Chat flow on load, reusing
      // cprofile.js's existing `?action=` handling.
      GoRoute(
        path: '/coach-profile/:id',
        builder: (context, state) => CoachingWebViewScreen.coachProfile(
          expertId: state.pathParameters['id']!,
          action: state.uri.queryParameters['action'],
        ),
      ),
      GoRoute(path: '/reviews/:id', builder: (context, state) => const ReviewsScreen()),
      GoRoute(
        path: '/chat/:roomId',
        builder: (context, state) => ChatScreen(
          roomId: state.pathParameters['roomId']!,
          expertId: state.uri.queryParameters['expertId'],
          expertName: state.uri.queryParameters['expertName'],
        ),
      ),
      GoRoute(
        path: '/experts/:id',
        builder: (context, state) => ExpertProfileScreen(
          expertId: state.pathParameters['id']!,
          action: state.uri.queryParameters['action'],
        ),
      ),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
      // Admin certificate console — parity with the website's cert-audit /
      // admin-review pages. The screen itself claim-gates (backend `admin`
      // custom claim); a non-admin who reaches it sees an access-denied view.
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      GoRoute(path: '/membership', builder: (context, state) => const MembershipScreen()),
      GoRoute(path: '/profile/personal-info', builder: (context, state) => const PersonalInfoScreen()),
      GoRoute(path: '/profile/help-support', builder: (context, state) => const HelpSupportScreen()),
      GoRoute(path: '/profile/notifications', builder: (context, state) => const NotificationSettingsScreen()),
      GoRoute(path: '/wallet', builder: (context, state) => const WalletScreen()),
      GoRoute(path: '/activity', builder: (context, state) => const StepHistoryRoute()),
      // Full-screen voice call. A top-level route (not nested in the shell)
      // so the bottom nav and the Zino FAB don't sit on top of a call.
      // Declared BEFORE '/zino' so the more specific path matches first.
      GoRoute(path: '/zino/call', builder: (context, state) => const ZinoCallScreen()),
      // `?from=diet` tells Zino which screen the athlete opened it from, so
      // an ambiguous question ("replace this") anchors to what they were just
      // looking at — the mobile equivalent of zino.js's `current_page`.
      GoRoute(
        path: '/zino',
        builder: (context, state) => ZinoScreen(
          screenContext: zinoScreenContextFromName(state.uri.queryParameters['from']),
          viewingExpertId: state.uri.queryParameters['expertId'],
        ),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/diet', builder: (context, state) => const DietScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/training', builder: (context, state) => const WorkoutScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/experts', builder: (context, state) => const ExpertsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
