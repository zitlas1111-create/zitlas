import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/notifications/fcm_service.dart';
import '../core/notifications/notification_payload.dart';
import '../core/notifications/notification_router.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/data/auth_repository.dart';
import 'router.dart';
import 'theme.dart';

class ZitlasApp extends StatelessWidget {
  const ZitlasApp({super.key, required this.firebaseReady});

  /// Whether `Firebase.initializeApp()` succeeded in `main.dart`. False
  /// until the Android/iOS Firebase apps are registered and
  /// google-services.json/GoogleService-Info.plist are in place — see
  /// docs/MIGRATION_INVENTORY.md §4. [AuthRepository] degrades gracefully
  /// when this is false rather than crashing.
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    final repository = AuthRepository(
      auth: firebaseReady ? FirebaseAuth.instance : null,
      firestore: firebaseReady ? FirebaseFirestore.instance : null,
    );

    return ChangeNotifierProvider(
      create: (_) => AuthState(repository),
      child: Consumer<AuthState>(
        builder: (context, authState, _) {
          if (firebaseReady) _FcmBootstrap.maybeInit(authState);
          return MaterialApp.router(
            title: 'ZITLAS',
            debugShowCheckedModeBanner: false,
            theme: ZitlasTheme.dark,
            darkTheme: ZitlasTheme.dark,
            themeMode: ThemeMode.dark,
            routerConfig: buildRouter(authState),
          );
        },
      ),
    );
  }
}

/// Fires `FcmService.initForUser()` exactly once per newly-authenticated
/// uid — NOT at splash, only once [AuthState] actually resolves to
/// `authenticated` — mirroring `push-notifications.js`'s "only after login"
/// gate. A static latch (not per-widget state) survives the `Consumer`
/// rebuilding on every [AuthState] change without re-triggering.
///
/// Also wires the three message lifecycles exactly once per process:
///   * `onMessage`          — app FOREGROUND: the OS draws nothing, so
///     [FcmService.showForeground] republishes it locally.
///   * `onMessageOpenedApp`  — app was BACKGROUNDED and the user tapped the
///     OS notification.
///   * `getInitialMessage()` — app was TERMINATED and launched BY the tap.
///     Cannot navigate yet (no router), so it is remembered and consumed once
///     authentication resolves.
abstract final class _FcmBootstrap {
  static String? _initializedForUid;
  static bool _listenersAttached = false;
  static final FcmService _service = FcmService(firestore: FirebaseFirestore.instance);

  static void maybeInit(AuthState authState) {
    _attachListeners();
    if (authState.status != AuthStatus.authenticated) return;
    final uid = authState.profile?.uid;
    if (uid == null || uid == _initializedForUid) return;
    _initializedForUid = uid;
    _service.initForUser(uid).catchError((Object e) {
      if (kDebugMode) debugPrint('[FCM] init failed: $e');
    });
    // A cold start FROM a notification can only navigate once the session is
    // real and the first frame exists — both are true here.
    if (NotificationRouter.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => NotificationRouter.consumePending());
    }
  }

  static void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    // Local-notification taps (a foreground notification we drew ourselves)
    // route through the SAME NotificationRouter as OS notification taps.
    _service.initLocalNotifications(onTap: NotificationRouter.route);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) debugPrint('[FCM] foreground ${message.data['type']}');
      _service.showForeground(message, suppress: _isViewingChat(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      NotificationRouter.route(
        NotificationPayload.fromData(message.data.cast<String, dynamic>()),
      );
    });

    // Terminated-state launch. Remembered rather than routed: the router does
    // not exist yet at this point in startup.
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message == null) return;
      NotificationRouter.remember(
        NotificationPayload.fromData(message.data.cast<String, dynamic>()),
      );
    });
  }

  /// True when the user is already looking at exactly the conversation this
  /// message belongs to — a tray entry for the screen you are reading is the
  /// noise real messaging apps deliberately avoid.
  static bool _isViewingChat(RemoteMessage message) {
    if (message.data['type'] != 'chat_message') return false;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return false;
    try {
      final location = GoRouterState.of(context).uri.toString();
      final counterpart = message.data['counterpartId']?.toString();
      final chatId = message.data['chatId']?.toString();
      // The coaching chat lives in the Website WebView, reached via
      // /coach-profile/<coachId>; the native chat route is /chat/<roomId>.
      if (counterpart != null && location.contains('/coach-profile/$counterpart')) return true;
      if (chatId != null && location.contains('/chat/$chatId')) return true;
      return false;
    } catch (_) {
      return false;
    }
  }
}
