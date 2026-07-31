import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/steps/step_background_worker.dart';
import 'core/storage/local_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // True edge-to-edge on Android: Flutter draws full-bleed behind the
  // status/navigation bars instead of the OS reserving opaque space for
  // them. Without this (and the transparent bar colors below), the system
  // bars render as an opaque black strip on top of whatever Flutter draws —
  // that's the actual root cause of the black framing around the auth
  // screen, not a Scaffold/background/SafeArea issue.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // App-wide DEFAULT system bar style — transparent + light icons, matching
  // the dark app theme every screen except the auth flow uses. The auth
  // screens override this locally via `AnnotatedRegion<SystemUiOverlayStyle>`
  // (see login_screen.dart / expert_application_review_screen.dart) — this
  // is per-screen, not global, so it doesn't turn Dashboard/Diet/etc. cream.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );

  await LocalStorageService.init();

  // Firebase isn't registered for com.zitlas.app yet — no
  // android/app/google-services.json exists (see
  // docs/MIGRATION_INVENTORY.md §4). Guarded so a missing/invalid config
  // degrades to a "Firebase not configured" auth screen instead of
  // crashing the app on startup; nothing here applies the Gradle
  // google-services plugin, so the build itself is unaffected either way.
  var firebaseReady = true;
  try {
    await bootstrapFirebase();
  } catch (e) {
    debugPrint('[ZITLAS] Firebase unavailable, continuing without it: $e');
    firebaseReady = false;
  }

  // Best-effort periodic step-milestone check so a goal can be announced
  // while ZITLAS is closed. Registration is idempotent and never blocks
  // startup — see StepBackgroundWorker for the Android delivery limits this
  // is explicitly subject to.
  unawaited(StepBackgroundWorker.register());

  runApp(ZitlasApp(firebaseReady: firebaseReady));
}
