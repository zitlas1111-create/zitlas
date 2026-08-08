import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/app/splash_gate.dart';

/// The splash gate is what stops a fast startup flashing the logo for two
/// frames, and it is also what a cold-start notification has to wait for
/// before it can navigate. Both properties are worth pinning down.
void main() {
  setUp(() => SplashGate.instance.resetForTest());
  tearDown(() => SplashGate.instance.resetForTest());

  test('is NOT ready immediately after start() — the splash is held', () {
    SplashGate.instance.start();
    expect(SplashGate.instance.isReady, isFalse);
  });

  test('becomes ready once the minimum duration elapses, and notifies', () {
    fakeAsync((elapse) {
      var notified = 0;
      SplashGate.instance.addListener(() => notified++);
      SplashGate.instance.start();

      elapse(SplashGate.minimumDuration - const Duration(milliseconds: 50));
      expect(SplashGate.instance.isReady, isFalse, reason: 'still inside the hold');
      expect(notified, 0);

      elapse(const Duration(milliseconds: 100));
      expect(SplashGate.instance.isReady, isTrue);
      // Exactly one notification — the router must not be re-triggered
      // repeatedly by the gate.
      expect(notified, 1);
    });
  });

  test('start() is idempotent — a second call cannot re-hold or stack timers', () {
    fakeAsync((elapse) {
      SplashGate.instance.start();
      elapse(const Duration(milliseconds: 600));
      SplashGate.instance.start(); // e.g. a hot restart
      elapse(SplashGate.minimumDuration);
      expect(SplashGate.instance.isReady, isTrue);
    });
  });

  test('reading isReady self-starts the clock, so the app can never be stranded '
      'on the splash when start() was never called', () {
    fakeAsync((elapse) {
      // Deliberately do NOT call start() — mimics an entry path that skips main().
      expect(SplashGate.instance.isReady, isFalse);
      elapse(SplashGate.minimumDuration + const Duration(milliseconds: 50));
      expect(SplashGate.instance.isReady, isTrue);
    });
  });

  test('forceReadyForTest releases immediately', () {
    SplashGate.instance.forceReadyForTest();
    expect(SplashGate.instance.isReady, isTrue);
  });
}

/// Minimal fake-async helper so these tests don't wait in real time.
void fakeAsync(void Function(void Function(Duration) elapse) body) {
  FakeAsync().run((async) {
    body(async.elapse);
  });
}
