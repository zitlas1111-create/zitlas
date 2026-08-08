import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zitlas_mobile/app/app.dart';
import 'package:zitlas_mobile/app/splash_gate.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.init();
    // The branded splash deliberately holds the route for a short minimum
    // (SplashGate). This test is about the Firebase-unavailable fallback, not
    // splash timing, so release the gate immediately rather than pumping
    // through the hold.
    SplashGate.instance.forceReadyForTest();
  });

  testWidgets('App boots to the login screen when Firebase is unavailable', (tester) async {
    // firebaseReady: false mirrors this repo's current state — no
    // google-services.json yet (docs/MIGRATION_INVENTORY.md §4) — so the
    // app must degrade to the login screen with a clear banner rather than
    // crash or hang on the splash screen forever.
    await tester.pumpWidget(const ZitlasApp(firebaseReady: false));
    await tester.pumpAndSettle();

    // Login screen now mirrors the real website page (login.html/login.css)
    // rather than a plain "ZITLAS" wordmark placeholder.
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.textContaining('Healthier Future.'), findsOneWidget);
    expect(find.textContaining('Firebase is not configured'), findsOneWidget);
  });
}
