import 'package:go_router/go_router.dart';

import '../core/widgets/app_shell.dart';
import '../features/ai_coach/presentation/screens/ai_coach_screen.dart';
import '../features/assessment/presentation/screens/assessment_screen.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/presentation/screens/expert_application_review_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/coaching/presentation/screens/coaching_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/diet/presentation/screens/diet_screen.dart';
import '../features/expert_dashboard/presentation/screens/expert_dashboard_screen.dart';
import '../features/experts/presentation/screens/expert_profile_screen.dart';
import '../features/experts/presentation/screens/experts_screen.dart';
import '../features/health/presentation/screens/health_screen.dart';
import '../features/membership/presentation/screens/membership_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/payments/presentation/screens/payments_screen.dart';
import '../features/profile/presentation/screens/help_support_screen.dart';
import '../features/profile/presentation/screens/personal_info_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/reviews/presentation/screens/reviews_screen.dart';
import '../features/workout/presentation/screens/workout_screen.dart';
import '../features/zino/data/zino_context_builder.dart';
import '../features/zino/presentation/screens/zino_screen.dart';

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
      GoRoute(
        path: '/expert-dashboard',
        builder: (context, state) => const ExpertDashboardScreen(),
      ),
      GoRoute(path: '/coaching', builder: (context, state) => const CoachingScreen()),
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
      GoRoute(path: '/membership', builder: (context, state) => const MembershipScreen()),
      GoRoute(path: '/profile/personal-info', builder: (context, state) => const PersonalInfoScreen()),
      GoRoute(path: '/profile/help-support', builder: (context, state) => const HelpSupportScreen()),
      GoRoute(path: '/wallet', builder: (context, state) => const PaymentsScreen()),
      GoRoute(path: '/activity', builder: (context, state) => const HealthScreen()),
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
