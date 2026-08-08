import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'notification_payload.dart';

/// Global navigator key, handed to GoRouter in `buildRouter`.
///
/// A notification tap arrives from outside the widget tree (an FCM callback or
/// a local-notification response), so there is no `BuildContext` to navigate
/// with. This key provides one. It is also what lets a COLD START navigate
/// after the first frame, once the router actually exists.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'zitlasRootNavigator');

/// THE one place that turns a notification into a destination.
///
/// Every entry point routes through [route]: a tap while backgrounded
/// (`onMessageOpenedApp`), a cold start (`getInitialMessage`), a foreground
/// local-notification tap, and the in-app Notification Centre. Keeping the
/// mapping here — rather than scattered across screens — is what stops the
/// four paths from drifting apart.
///
/// COACHING LIVES ON THE WEBSITE. Personal Coaching (chat, meal reviews, plan
/// editing, End Coaching) is intentionally served by the Website inside
/// `CoachingWebViewScreen`, so coaching notifications deep-link to
/// `/coach-profile/:id` (athlete) or `/expert-dashboard` (coach) — NOT to the
/// dormant native coaching screens. Diet/Training/Dashboard remain native.
abstract final class NotificationRouter {
  /// A notification that arrived before the app was ready to navigate (cold
  /// start, or before authentication resolved). Consumed by
  /// [consumePending] once the router and session exist.
  static NotificationPayload? _pending;

  static void remember(NotificationPayload payload) {
    _pending = payload;
    if (kDebugMode) debugPrint('[NOTIF ROUTER] pending: ${payload.type}');
  }

  static bool get hasPending => _pending != null;

  /// Navigates to the remembered notification's destination, if any. Called
  /// after the first frame AND after auth resolves — whichever is later — so a
  /// cold start from a notification lands on the right screen instead of the
  /// dashboard.
  static void consumePending() {
    final payload = _pending;
    if (payload == null) return;
    _pending = null;
    route(payload);
  }

  /// Resolves [payload] to a route and navigates. No-op (with a log) when the
  /// navigator is not mounted yet — the caller should [remember] instead in
  /// that case.
  static void route(NotificationPayload payload) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      if (kDebugMode) {
        debugPrint('[NOTIF ROUTER] navigator not ready — remembering ${payload.type}');
      }
      remember(payload);
      return;
    }
    final destination = destinationFor(payload);
    if (destination == null) {
      if (kDebugMode) debugPrint('[NOTIF ROUTER] no destination for ${payload.type}');
      return;
    }
    if (kDebugMode) {
      debugPrint('[NOTIF ROUTER] ${payload.type} -> $destination');
    }
    try {
      GoRouter.of(context).push(destination);
    } catch (e) {
      if (kDebugMode) debugPrint('[NOTIF ROUTER] navigation failed: $e');
    }
  }

  /// The route for a payload, or null when it should not navigate anywhere.
  ///
  /// Pure and side-effect free, so it is directly unit-testable without a
  /// widget tree — see test/notification_router_test.dart.
  static String? destinationFor(NotificationPayload p) {
    final isCoach = p.recipientRole == 'coach';

    switch (p.type) {
      // ── Chat ────────────────────────────────────────────────────────────
      // Same message, two destinations: the coach works out of their
      // dashboard, the athlete out of their coach's profile workspace.
      // `recipientRole` is derived server-side precisely so this is not a guess.
      case 'chat_message':
        if (isCoach) return '/expert-dashboard';
        final coach = p.counterpartId ?? p.senderId ?? p.coachId;
        return coach != null ? '/coach-profile/$coach?action=ask' : '/experts';

      // ── Meal reviews ────────────────────────────────────────────────────
      case 'meal_review_pending': // coach: an athlete sent a meal
      case 'meal_checkin':
        return '/expert-dashboard';
      case 'meal_review_completed': // athlete: the coach rated it
      case 'meal_reviewed':
        return '/diet';

      // ── Plans ───────────────────────────────────────────────────────────
      case 'diet_updated':
        return '/diet';
      case 'workout_updated':
        return '/training';

      // ── Zino / AI ───────────────────────────────────────────────────────
      case 'zino_message':
        return '/zino';

      default:
        return _coachingOrActionFallback(p, isCoach);
    }
  }

  /// Coaching lifecycle types (`coaching_requested`, `coaching_accepted`,
  /// `coaching_started`, `coaching_ended`, `payment_*` …) plus the
  /// notification-centre `action` keys the backend has always written.
  ///
  /// Honouring `action` here is deliberate: those values predate push, and
  /// mapping them the same way `navigateForAction()` does on the website keeps
  /// a pushed notification and an in-app tap landing on the SAME screen.
  static String? _coachingOrActionFallback(NotificationPayload p, bool isCoach) {
    final type = p.type;
    if (type.startsWith('coaching') || type.startsWith('payment')) {
      if (isCoach) return '/expert-dashboard';
      final coach = p.coachId ?? p.counterpartId ?? p.actionId ?? p.coachingId;
      return coach != null ? '/coach-profile/$coach' : '/experts';
    }

    switch (p.action) {
      case 'diet':
        return '/diet';
      case 'training':
        return '/training';
      case 'dashboard':
        return '/dashboard';
      case 'coaches':
        return '/experts';
      case 'expert_dashboard':
        return '/expert-dashboard';
      case 'profile':
        return '/profile';
      case 'expert_profile':
      case 'coaching_workspace':
      case 'chat':
        final id = p.actionId ?? p.coachId ?? p.counterpartId;
        if (id == null) return '/experts';
        return p.action == 'chat'
            ? '/coach-profile/$id?action=ask'
            : '/coach-profile/$id';
      default:
        // Unknown/general — the Notification Centre is the honest destination:
        // the notification is definitely there, whatever it was about.
        return '/notifications';
    }
  }
}
