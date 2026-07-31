import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zitlas_mobile/core/steps/step_notifications.dart';
import 'package:zitlas_mobile/core/steps/step_platform.dart';
import 'package:zitlas_mobile/core/steps/step_tracking_service.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';

/// Service-level behaviour: source selection, permission states, offline
/// operation, and daily history — all against a fake platform so no device,
/// clock, or network is involved.

/// Stands in for the native plugin. Every field is settable so a test can
/// describe an exact device situation (HC present but ungranted, sensor only,
/// nothing at all, ...).
class _FakePlatform implements StepPlatform {
  _FakePlatform({
    this.healthConnect = HealthConnectAvailability.unavailable,
    this.sensorAvailable = false,
    this.activityRecognitionGranted = false,
    this.hcSteps = HealthConnectSteps.unavailable,
    this.sensorReading,
    this.grantOnRequest = false,
  });

  HealthConnectAvailability healthConnect;
  bool sensorAvailable;
  bool activityRecognitionGranted;
  HealthConnectSteps hcSteps;
  StepSensorReading? sensorReading;
  bool grantOnRequest;

  int hcCallCount = 0;
  int sensorCallCount = 0;

  @override
  Future<StepPlatformStatus> getStatus() async => StepPlatformStatus(
        healthConnect: healthConnect,
        sensorAvailable: sensorAvailable,
        activityRecognitionGranted: activityRecognitionGranted,
      );

  @override
  Future<bool> requestHealthConnectPermission() async {
    if (grantOnRequest) hcSteps = const HealthConnectSteps(granted: true, steps: 0);
    return grantOnRequest;
  }

  @override
  Future<HealthConnectSteps> getStepsBetween(DateTime start, DateTime end) async {
    hcCallCount++;
    return hcSteps;
  }

  @override
  Future<StepSensorReading?> readStepSensor() async {
    sensorCallCount++;
    return sensorReading;
  }

  @override
  Future<bool> openHealthConnectSettings() async => true;
}

/// Records milestones instead of showing them, so notification behaviour is
/// assertable without a platform channel.
class _FakeNotifications implements StepNotifications {
  final shown = <int>[];
  bool permissionGranted = true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<bool> areNotificationsEnabled() async => permissionGranted;

  @override
  Future<void> showMilestone({required int milestone, required int goal}) async {
    shown.add(milestone);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.init();
  });

  StepTrackingService build(
    _FakePlatform platform, {
    _FakeNotifications? notifications,
    DateTime Function()? clock,
  }) =>
      StepTrackingService(
        platform: platform,
        notifications: notifications ?? _FakeNotifications(),
        storage: storage,
        clock: clock ?? () => DateTime(2026, 7, 30, 10),
      );

  group('permission states', () {
    test('before opting in, nothing is read and the reason is notEnabled', () async {
      final platform = _FakePlatform(sensorAvailable: true);
      final service = build(platform);

      final snap = await service.refresh(goal: 8000);

      expect(snap.isAvailable, isFalse);
      expect(snap.unavailableReason, StepUnavailableReason.notEnabled);
      expect(snap.steps, 0);
      expect(platform.hcCallCount, 0, reason: 'no health data touched before consent');
      expect(platform.sensorCallCount, 0);
    });

    test('a denial is remembered so the user is not re-prompted', () async {
      final platform = _FakePlatform(); // nothing available at all
      final service = build(platform);

      final enabled = await service.enableTracking(
        onNeedsActivityRecognition: () async => false,
      );

      expect(enabled, isFalse);
      expect(service.wasDenied, isTrue);
      expect(service.isEnabled, isFalse);

      final snap = await service.refresh(goal: 8000);
      expect(snap.unavailableReason, StepUnavailableReason.permissionDenied);
    });

    test('a device with no source at all reports deviceUnsupported', () async {
      final platform = _FakePlatform();
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      final snap = await service.refresh(goal: 8000);

      expect(snap.unavailableReason, StepUnavailableReason.deviceUnsupported);
    });

    test('an outdated Health Connect provider is reported as such', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.updateRequired,
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      final snap = await service.refresh(goal: 8000);

      expect(snap.unavailableReason, StepUnavailableReason.providerUpdateRequired);
    });

    test('declining Health Connect still enables the sensor path', () async {
      // Real and common: the athlete refuses the HC sheet, but the hardware
      // counter is a perfectly good source and shouldn't be abandoned.
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        grantOnRequest: false,
        sensorAvailable: true,
        activityRecognitionGranted: false,
      );
      final service = build(platform);

      final enabled = await service.enableTracking(
        onNeedsActivityRecognition: () async => true,
      );

      expect(enabled, isTrue);
      expect(service.isEnabled, isTrue);
      expect(service.wasDenied, isFalse);
    });

    test('denying notifications does NOT stop step counting', () async {
      final notifications = _FakeNotifications()..permissionGranted = false;
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        grantOnRequest: true,
      );
      final service = build(platform, notifications: notifications);

      final enabled = await service.enableTracking(
        onNeedsActivityRecognition: () async => false,
      );

      expect(enabled, isTrue, reason: 'notifications are additive, never a gate');
      expect(service.isEnabled, isTrue);
    });
  });

  group('source selection', () {
    test('Health Connect is preferred and the sensor is not also read', () async {
      // Reading both and summing them would double-count the same walk.
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 3482),
        sensorAvailable: true,
        activityRecognitionGranted: true,
        sensorReading: const StepSensorReading(cumulative: 99999, bootTimeMillis: 1),
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      final snap = await service.refresh(goal: 8000);

      expect(snap.source, StepSource.healthConnect);
      expect(snap.steps, 3482);
      expect(platform.sensorCallCount, 0, reason: 'sources are never summed');
    });

    test('a real Health Connect zero is trusted, not treated as broken', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 0),
        sensorAvailable: true,
        activityRecognitionGranted: true,
        sensorReading: const StepSensorReading(cumulative: 500, bootTimeMillis: 1),
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      final snap = await service.refresh(goal: 8000);

      expect(snap.source, StepSource.healthConnect);
      expect(snap.steps, 0, reason: "granted + 0 records is a real 'not walked yet'");
      expect(platform.sensorCallCount, 0);
    });

    test('an ungranted Health Connect falls through to the sensor', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: HealthConnectSteps.unavailable,
        sensorAvailable: true,
        activityRecognitionGranted: true,
        sensorReading: const StepSensorReading(cumulative: 1000, bootTimeMillis: 5000),
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      final snap = await service.refresh(goal: 8000);

      expect(snap.source, StepSource.sensor);
      expect(platform.sensorCallCount, 1);
    });
  });

  group('offline operation and daily history', () {
    test('a reading is persisted locally with no network involved', () async {
      // Nothing in this test can reach a server; the count and the history
      // entry must exist regardless.
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 8421),
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      final snap = await service.refresh(goal: 8000);
      expect(snap.steps, 8421);

      final history = service.readHistory();
      expect(history['2026-07-30']!.steps, 8421);
      expect(history['2026-07-30']!.goal, 8000);
      expect(history['2026-07-30']!.completed, isTrue);
    });

    test('an incomplete day is recorded as not completed', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 7132),
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      await service.refresh(goal: 8000);

      expect(service.readHistory()['2026-07-30']!.completed, isFalse);
    });

    test('crossing midnight keeps the previous day in history', () async {
      // Day 1
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 8421),
      );
      final day1 = build(platform, clock: () => DateTime(2026, 7, 30, 23, 55));
      await storage.setBool('zitlas_step_tracking_enabled', true);
      await day1.refresh(goal: 8000);

      // Day 2 — a fresh local date, and Health Connect's aggregate for the new
      // window is naturally small again.
      platform.hcSteps = const HealthConnectSteps(granted: true, steps: 120);
      final day2 = build(platform, clock: () => DateTime(2026, 7, 31, 0, 5));
      final snap = await day2.refresh(goal: 8000);

      expect(snap.dayKey, '2026-07-31');
      expect(snap.steps, 120, reason: 'the new day shows only the new day');

      final history = day2.readHistory();
      expect(history['2026-07-30']!.steps, 8421,
          reason: "yesterday's total is retained, never deleted");
      expect(history['2026-07-31']!.steps, 120);
    });

    test('the goal is cached for the background isolate to read', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 100),
      );
      final service = build(platform);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      await service.refresh(goal: 8000);

      expect(storage.getInt(StepTrackingService.goalCacheKey), 8000);
    });
  });

  group('milestone delivery through the service', () {
    test('crossing a milestone notifies exactly once across refreshes', () async {
      final notifications = _FakeNotifications();
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 2000),
      );
      final service = build(platform, notifications: notifications);
      await storage.setBool('zitlas_step_tracking_enabled', true);

      await service.refresh(goal: 8000);
      expect(notifications.shown, [25]);

      // A second refresh with a few more steps must stay silent.
      platform.hcSteps = const HealthConnectSteps(granted: true, steps: 2100);
      await service.refresh(goal: 8000);
      expect(notifications.shown, [25], reason: 'no duplicate on re-read');
    });

    test('goal completion fires once and survives a service restart', () async {
      final notifications = _FakeNotifications();
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 8000),
      );
      await storage.setBool('zitlas_step_tracking_enabled', true);

      await build(platform, notifications: notifications).refresh(goal: 8000);
      expect(notifications.shown, [100]);

      // A brand-new service instance (app relaunch) reads the persisted
      // milestone state and must not re-announce.
      platform.hcSteps = const HealthConnectSteps(granted: true, steps: 8600);
      await build(platform, notifications: notifications).refresh(goal: 8000);
      expect(notifications.shown, [100], reason: 'persisted across restart');
    });
  });
}
