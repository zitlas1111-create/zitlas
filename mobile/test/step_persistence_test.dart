import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zitlas_mobile/core/steps/step_history.dart';
import 'package:zitlas_mobile/core/steps/step_metrics.dart';
import 'package:zitlas_mobile/core/steps/step_notifications.dart';
import 'package:zitlas_mobile/core/steps/step_platform.dart';
import 'package:zitlas_mobile/core/steps/step_tracking_service.dart';
import 'package:zitlas_mobile/core/storage/account_guard.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';

/// Step-tracking PERSISTENCE.
///
/// Every test here corresponds to a real reported failure: the counter
/// inflating or freezing during the day, the Enable prompt reappearing on a
/// phone that was already granted, and yesterday being unviewable. They are
/// written to fail against the previous implementation, not just to pass
/// against the new one.
class _FakePlatform implements StepPlatform {
  _FakePlatform({
    this.healthConnect = HealthConnectAvailability.unavailable,
    this.sensorAvailable = true,
    this.activityRecognitionGranted = true,
    this.hcSteps = HealthConnectSteps.unavailable,
    this.sensorReading,
  });

  HealthConnectAvailability healthConnect;
  bool sensorAvailable;
  bool activityRecognitionGranted;
  HealthConnectSteps hcSteps;
  StepSensorReading? sensorReading;
  StepDayBoundaryReading? dayBoundary;
  final hcByDay = <String, int>{};
  int boundaryScheduleCount = 0;

  @override
  Future<StepPlatformStatus> getStatus() async => StepPlatformStatus(
        healthConnect: healthConnect,
        sensorAvailable: sensorAvailable,
        activityRecognitionGranted: activityRecognitionGranted,
      );

  @override
  Future<bool> requestHealthConnectPermission() async => false;

  @override
  Future<HealthConnectSteps> getStepsBetween(DateTime start, DateTime end) async {
    final key = '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    final perDay = hcByDay[key];
    if (perDay != null) return HealthConnectSteps(granted: true, steps: perDay);
    return hcSteps;
  }

  @override
  Future<StepSensorReading?> readStepSensor() async => sensorReading;

  @override
  Future<void> scheduleDayBoundary() async => boundaryScheduleCount++;

  @override
  Future<StepDayBoundaryReading?> consumeDayBoundary() async {
    final b = dayBoundary;
    dayBoundary = null;
    return b;
  }

  @override
  Future<bool> openHealthConnectSettings() async => true;
}

class _FakeNotifications implements StepNotifications {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<void> showMilestone({required int milestone, required int goal}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.init();
  });

  StepTrackingService build(_FakePlatform platform, DateTime Function() clock) =>
      StepTrackingService(
        platform: platform,
        notifications: _FakeNotifications(),
        storage: storage,
        clock: clock,
      );

  Future<void> enable() => storage.setBool('zitlas_step_tracking_enabled', true);

  group('the daily total never inflates', () {
    test('four reads through one day report the walk once, not four times', () async {
      // The reported bug: a 4,000-step day displayed as 9,000 because each
      // read re-measured the whole day and added it to a total that already
      // contained it.
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 9);
      final service = build(platform, () => now);
      await enable();

      const boot = 1000000;
      Future<int> readAt(DateTime at, int cumulative) async {
        now = at;
        platform.sensorReading =
            StepSensorReading(cumulative: cumulative, bootTimeMillis: boot);
        return (await service.refresh(goal: 8000)).steps;
      }

      expect(await readAt(DateTime(2026, 7, 30, 9), 1000), 0);
      expect(await readAt(DateTime(2026, 7, 30, 10), 3000), 2000);
      expect(await readAt(DateTime(2026, 7, 30, 11), 4000), 3000);
      expect(await readAt(DateTime(2026, 7, 30, 12), 5000), 4000);
    });

    test('reading twice without moving does not change the total', () async {
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 9);
      final service = build(platform, () => now);
      await enable();

      platform.sensorReading =
          const StepSensorReading(cumulative: 1000, bootTimeMillis: 1000000);
      await service.refresh(goal: 8000);

      now = DateTime(2026, 7, 30, 10);
      platform.sensorReading =
          const StepSensorReading(cumulative: 4000, bootTimeMillis: 1000000);
      expect((await service.refresh(goal: 8000)).steps, 3000);

      // Same reading again a minute later — the athlete has not moved.
      now = DateTime(2026, 7, 30, 10, 1);
      expect((await service.refresh(goal: 8000)).steps, 3000);
    });
  });

  group('the counter does not freeze', () {
    test('a resume seconds after a long walk still counts the new steps', () async {
      // The reported bug: after a few hours of walking, the day's delta was
      // compared against a cap sized for the seconds since the last refresh,
      // was always rejected as "implausible", and the count stuck.
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 9);
      final service = build(platform, () => now);
      await enable();

      const boot = 1000000;
      platform.sensorReading = const StepSensorReading(cumulative: 1000, bootTimeMillis: boot);
      await service.refresh(goal: 8000);

      now = DateTime(2026, 7, 30, 11);
      platform.sensorReading = const StepSensorReading(cumulative: 5000, bootTimeMillis: boot);
      expect((await service.refresh(goal: 8000)).steps, 4000);

      now = DateTime(2026, 7, 30, 11, 0, 10);
      platform.sensorReading = const StepSensorReading(cumulative: 5020, bootTimeMillis: boot);
      expect((await service.refresh(goal: 8000)).steps, 4020,
          reason: '20 steps in 10 seconds is a walk, not a firmware glitch');
    });

    test('a genuinely impossible jump is still rejected', () async {
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 9);
      final service = build(platform, () => now);
      await enable();

      const boot = 1000000;
      platform.sensorReading = const StepSensorReading(cumulative: 1000, bootTimeMillis: boot);
      await service.refresh(goal: 8000);

      // 50,000 steps in ten seconds. Nobody walked that.
      now = DateTime(2026, 7, 30, 9, 0, 10);
      platform.sensorReading = const StepSensorReading(cumulative: 51000, bootTimeMillis: boot);
      expect((await service.refresh(goal: 8000)).steps, 0);
    });
  });

  group('a working tracker is never asked to be enabled again', () {
    test('a silent sensor replays the stored total instead of a prompt', () async {
      // TYPE_STEP_COUNTER only reports when a step is taken, so an idle phone
      // legitimately returns nothing. That used to be reported as
      // permissionDenied, which put an "Enable" button over a working card.
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 9);
      final service = build(platform, () => now);
      await enable();

      platform.sensorReading =
          const StepSensorReading(cumulative: 1000, bootTimeMillis: 1000000);
      await service.refresh(goal: 8000);
      now = DateTime(2026, 7, 30, 10);
      platform.sensorReading =
          const StepSensorReading(cumulative: 4200, bootTimeMillis: 1000000);
      await service.refresh(goal: 8000);

      // Now the sensor goes quiet.
      platform.sensorReading = null;
      final snapshot = await service.refresh(goal: 8000);

      expect(snapshot.steps, 3200, reason: 'the day so far is still known');
      expect(snapshot.source, StepSource.cached);
      expect(snapshot.unavailableReason, isNull);
      expect(snapshot.isAvailable, isTrue, reason: 'no Enable prompt');
    });

    test('an unreadable source with permission granted is not a denial', () async {
      final platform = _FakePlatform(sensorReading: null);
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();

      final snapshot = await service.refresh(goal: 8000);
      expect(snapshot.unavailableReason, StepUnavailableReason.noReadingYet);
      expect(snapshot.unavailableReason, isNot(StepUnavailableReason.permissionDenied));
    });

    test('a device with no step hardware at all says so, and offers nothing', () async {
      final platform = _FakePlatform(sensorAvailable: false, activityRecognitionGranted: false);
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();

      final snapshot = await service.refresh(goal: 8000);
      expect(snapshot.unavailableReason, StepUnavailableReason.deviceUnsupported);
    });

    test('a genuinely missing permission IS still reported as denied', () async {
      final platform = _FakePlatform(activityRecognitionGranted: false);
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();

      final snapshot = await service.refresh(goal: 8000);
      expect(snapshot.unavailableReason, StepUnavailableReason.permissionDenied);
    });

    test('tracking resumes silently when the OS grant is already held', () async {
      // Reinstall / cleared cache / signed out and back in: Android still has
      // the grant, so there is nothing to ask for.
      final platform = _FakePlatform();
      final service = build(platform, () => DateTime(2026, 7, 30, 9));

      expect(service.isEnabled, isFalse);
      expect(await service.ensureTrackingActive(), isTrue);
      expect(service.isEnabled, isTrue);
    });

    test('nothing is resumed when no permission is actually held', () async {
      final platform = _FakePlatform(activityRecognitionGranted: false);
      final service = build(platform, () => DateTime(2026, 7, 30, 9));

      expect(await service.ensureTrackingActive(), isFalse);
      expect(service.isEnabled, isFalse);
    });
  });

  group('signing out does not switch step tracking off', () {
    test('the enabled flag and sensor baseline survive a cache purge', () async {
      // The purge exists to stop account B inheriting account A's cached
      // plans. It was also deleting the flags that record what THIS PHONE has
      // been granted, so every sign-out looked like tracking had been
      // switched off.
      await storage.setBool('zitlas_step_tracking_enabled', true);
      await storage.setJson('zitlas_step_baseline', {
        'dayKey': '2026-07-30',
        'baselineCumulative': 4200,
        'bootTimeMillis': 1000000,
        'stepsAtBaseline': 3200,
      });
      await storage.setString('zitlas_diet_plan', 'account-scoped');

      await AccountGuard.instance.clearUserCache();

      expect(storage.getBool('zitlas_step_tracking_enabled'), isTrue);
      expect(storage.getJson('zitlas_step_baseline'), isNotNull);
      expect(storage.getString('zitlas_diet_plan'), isNull,
          reason: 'account-scoped data must still be purged');
    });
  });

  group('midnight rollover', () {
    test('a captured boundary closes yesterday and zeroes today', () async {
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 22);
      final service = build(platform, () => now);
      await enable();

      const boot = 1000000;
      platform.sensorReading = const StepSensorReading(cumulative: 1000, bootTimeMillis: boot);
      await service.refresh(goal: 8000);
      now = DateTime(2026, 7, 30, 23);
      platform.sensorReading = const StepSensorReading(cumulative: 7000, bootTimeMillis: boot);
      expect((await service.refresh(goal: 8000)).steps, 6000);

      // The phone was closed at midnight; the native receiver captured 7,500 —
      // 500 more steps were walked after the last time the app was open.
      platform.dayBoundary = const StepDayBoundaryReading(
        dayKey: '2026-07-30',
        cumulative: 7500,
        bootTimeMillis: boot,
      );

      now = DateTime(2026, 7, 31, 8);
      platform.sensorReading = const StepSensorReading(cumulative: 7900, bootTimeMillis: boot);
      final today = await service.refresh(goal: 8000);

      expect(today.steps, 400, reason: 'the new day starts from the midnight reading');
      expect(service.readHistory()['2026-07-30']?.steps, 6500,
          reason: 'the closing 500 steps belong to yesterday, not today');
    });

    test('the boundary is consumed once, never applied twice', () async {
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 23);
      final service = build(platform, () => now);
      await enable();

      const boot = 1000000;
      platform.sensorReading = const StepSensorReading(cumulative: 5000, bootTimeMillis: boot);
      await service.refresh(goal: 8000);

      platform.dayBoundary = const StepDayBoundaryReading(
        dayKey: '2026-07-30',
        cumulative: 5200,
        bootTimeMillis: boot,
      );
      now = DateTime(2026, 7, 31, 8);
      platform.sensorReading = const StepSensorReading(cumulative: 5600, bootTimeMillis: boot);
      final first = await service.refresh(goal: 8000);
      final second = await service.refresh(goal: 8000);

      expect(first.steps, 400);
      expect(second.steps, 400, reason: 'a replayed boundary would re-anchor and lose steps');
    });

    test('a reboot between the last read and midnight is not subtracted', () async {
      final platform = _FakePlatform();
      var now = DateTime(2026, 7, 30, 23);
      final service = build(platform, () => now);
      await enable();

      platform.sensorReading =
          const StepSensorReading(cumulative: 9000, bootTimeMillis: 1000000);
      await service.refresh(goal: 8000);
      final before = service.readHistory()['2026-07-30']?.steps;

      // Device rebooted: the counter restarted, so 200 is NOT 8,800 fewer steps.
      platform.dayBoundary = const StepDayBoundaryReading(
        dayKey: '2026-07-30',
        cumulative: 200,
        bootTimeMillis: 9000000,
      );
      now = DateTime(2026, 7, 31, 8);
      platform.sensorReading =
          const StepSensorReading(cumulative: 500, bootTimeMillis: 9000000);
      await service.refresh(goal: 8000);

      expect(service.readHistory()['2026-07-30']?.steps, before,
          reason: 'yesterday must not be rewritten from an incomparable counter');
    });
  });

  group('yesterday is viewable', () {
    test('Health Connect backfills days the app was never open for', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 0),
      );
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();
      await storage.setInt(StepTrackingService.goalCacheKey, 8000);

      platform.hcByDay['2026-07-29'] = 9100;
      platform.hcByDay['2026-07-28'] = 4300;

      expect(await service.backfillFromHealthConnect(days: 7), 2);

      final history = StepHistory(service.readHistory());
      expect(history.forDay('2026-07-29')?.steps, 9100);
      expect(history.forDay('2026-07-29')?.completed, isTrue);
      expect(history.forDay('2026-07-28')?.completed, isFalse);
    });

    test('backfill never overwrites a larger locally recorded day', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 0),
        sensorReading: const StepSensorReading(cumulative: 100, bootTimeMillis: 1),
      );
      var now = DateTime(2026, 7, 29, 20);
      final service = build(platform, () => now);
      await enable();
      await storage.setInt(StepTrackingService.goalCacheKey, 8000);

      // A real sensor-recorded day of 6,000 steps.
      platform.hcByDay['2026-07-29'] = 6000;
      await service.refresh(goal: 8000);
      platform.hcByDay['2026-07-29'] = 6000;

      // Health Connect only knows about 2,000 of them (no provider wrote the rest).
      now = DateTime(2026, 7, 30, 9);
      platform.hcByDay['2026-07-29'] = 2000;
      await service.backfillFromHealthConnect(days: 7);

      expect(service.readHistory()['2026-07-29']!.steps, 6000);
    });

    test('a reinstall recovers its history from the synced day docs', () async {
      // Local storage is gone; Firestore still has every day.
      final platform = _FakePlatform();
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();
      expect(service.readHistory(), isEmpty);

      expect(
        await service.hydrateHistory({
          '2026-07-29': (steps: 9500, goal: 8000),
          '2026-07-28': (steps: 4000, goal: 8000),
        }),
        2,
      );

      final history = StepHistory(service.readHistory());
      expect(history.forDay('2026-07-29')?.steps, 9500);
      expect(history.forDay('2026-07-29')?.completed, isTrue);
      expect(history.currentStreak(today: DateTime(2026, 7, 30)), 1);
    });

    test('hydration never reduces a day this device recorded higher', () async {
      final platform = _FakePlatform();
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();

      await service.hydrateHistory({'2026-07-29': (steps: 9000, goal: 8000)});
      // A stale server copy from before the last sync.
      await service.hydrateHistory({'2026-07-29': (steps: 3000, goal: 8000)});

      expect(service.readHistory()['2026-07-29']!.steps, 9000);
    });

    test('an unmeasured day stays absent rather than becoming a zero', () async {
      final platform = _FakePlatform(
        healthConnect: HealthConnectAvailability.available,
        hcSteps: const HealthConnectSteps(granted: true, steps: 0),
      );
      final service = build(platform, () => DateTime(2026, 7, 30, 9));
      await enable();

      expect(await service.backfillFromHealthConnect(days: 7), 0);
      expect(service.readHistory(), isEmpty);
    });
  });

  group('history views', () {
    StepHistory historyOf(Map<String, (int steps, int goal)> days) => StepHistory({
          for (final e in days.entries)
            e.key: StepDaySummary(
              date: e.key,
              steps: e.value.$1,
              goal: e.value.$2,
              completed: e.value.$1 >= e.value.$2,
              lastUpdated: DateTime(2026, 7, 30),
            ),
        });

    test('the 7-day average ignores days that were never recorded', () async {
      final history = historyOf({
        '2026-07-30': (10000, 8000),
        '2026-07-29': (6000, 8000),
        // 28th, 27th, ... never recorded.
      });
      expect(history.averageSteps(today: DateTime(2026, 7, 30), count: 7), 8000);
    });

    test('an unfinished today does not break yesterday\'s streak', () async {
      // At 00:01 today's goal is obviously not met yet. Resetting the streak
      // to 0 until the athlete walks would show a broken streak every morning.
      final history = historyOf({
        '2026-07-30': (120, 8000),
        '2026-07-29': (9000, 8000),
        '2026-07-28': (8500, 8000),
        '2026-07-27': (8200, 8000),
      });
      expect(history.currentStreak(today: DateTime(2026, 7, 30)), 3);
    });

    test('completing today extends the streak', () async {
      final history = historyOf({
        '2026-07-30': (9000, 8000),
        '2026-07-29': (9000, 8000),
      });
      expect(history.currentStreak(today: DateTime(2026, 7, 30)), 2);
    });

    test('a missed day ends the streak', () async {
      final history = historyOf({
        '2026-07-30': (9000, 8000),
        '2026-07-29': (1000, 8000),
        '2026-07-28': (9000, 8000),
      });
      expect(history.currentStreak(today: DateTime(2026, 7, 30)), 1);
    });

    test('the longest streak is found anywhere in the record', () async {
      final history = historyOf({
        '2026-07-30': (9000, 8000),
        '2026-07-27': (9000, 8000),
        '2026-07-26': (9000, 8000),
        '2026-07-25': (9000, 8000),
        '2026-07-24': (9000, 8000),
      });
      expect(history.longestStreak(), 4);
      expect(history.currentStreak(today: DateTime(2026, 7, 30)), 1);
    });

    test('a 30-day window returns every date, gaps included', () async {
      final history = historyOf({'2026-07-30': (9000, 8000)});
      final window = history.window(today: DateTime(2026, 7, 30), count: 30);
      expect(window.length, 30);
      expect(window.first.hasData, isTrue);
      expect(window[1].hasData, isFalse, reason: 'a gap is shown, not closed up');
      expect(window.last.dayKey, '2026-07-01');
    });
  });

  group('derived figures', () {
    test('distance scales with real height when it is known', () {
      final tall = distanceKm(steps: 10000, heightCm: 190);
      final short = distanceKm(steps: 10000, heightCm: 150);
      expect(tall, greaterThan(short));
      // ~0.79m stride for a 190cm athlete.
      expect(tall, closeTo(7.885, 0.01));
    });

    test('calories scale with body weight', () {
      final heavier = estimatedCalories(steps: 10000, weightKg: 95, heightCm: 175);
      final lighter = estimatedCalories(steps: 10000, weightKg: 55, heightCm: 175);
      expect(heavier, greaterThan(lighter));
    });

    test('an unknown body still produces a usable estimate', () {
      expect(estimatedCalories(steps: 10000), greaterThan(0));
      expect(distanceKm(steps: 10000), greaterThan(0));
    });

    test('zero steps produce zero, never a phantom burn', () {
      expect(estimatedCalories(steps: 0, weightKg: 80), 0);
      expect(distanceKm(steps: 0), 0);
      expect(estimatedActiveMinutes(steps: 0), isNull);
    });

    test('a paused goal reads as complete rather than dividing by zero', () {
      expect(completionPercent(steps: 0, goal: 0), 100);
    });
  });
}
