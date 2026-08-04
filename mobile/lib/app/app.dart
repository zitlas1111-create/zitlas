import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifications/fcm_service.dart';
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
abstract final class _FcmBootstrap {
  static String? _initializedForUid;

  static void maybeInit(AuthState authState) {
    if (authState.status != AuthStatus.authenticated) return;
    final uid = authState.profile?.uid;
    if (uid == null || uid == _initializedForUid) return;
    _initializedForUid = uid;
    FcmService(firestore: FirebaseFirestore.instance).initForUser(uid).catchError((Object e) {
      if (kDebugMode) debugPrint('[FCM] init failed: $e');
    });
  }
}
