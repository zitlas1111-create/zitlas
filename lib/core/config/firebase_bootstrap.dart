import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Initializes the shared `zitlas-b8677` Firebase project.
///
/// Deliberately calls `Firebase.initializeApp()` with NO explicit
/// `FirebaseOptions` — on Android this reads the native config the
/// `com.google.gms.google-services` Gradle plugin generates from
/// `android/app/google-services.json` at build time (see
/// `android/app/build.gradle.kts`); iOS would read
/// `ios/Runner/GoogleService-Info.plist` the same way once that's added.
/// No Firebase credentials are hardcoded in Dart anywhere in this app.
///
/// Called from `main.dart`, guarded by a try/catch there so a missing/
/// misconfigured native file degrades to `AuthStatus.firebaseUnavailable`
/// instead of crashing startup — see docs/MIGRATION_INVENTORY.md §4.
Future<void> bootstrapFirebase() async {
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase bootstrap failed: $e\n$st');
    rethrow;
  }
}
