import 'package:flutter/foundation.dart';

import '../storage/local_storage_service.dart';
import 'step_day.dart';
import 'step_notifications.dart';
import 'step_platform.dart';
import 'step_sensor_baseline.dart';

/// Which source produced a reading — surfaced in debug logs and used by the UI
/// to explain itself honestly.
enum StepSource { healthConnect, sensor, none }

/// Why the counter can't produce a number, so the Activity card can show a
/// real state with a real action instead of a silent, misleading 0.
enum StepUnavailableReason {
  /// Never asked yet.
  notEnabled,

  /// Asked and refused. Never re-prompted automatically.
  permissionDenied,

  /// Health Connect provider needs a Play Store update.
  providerUpdateRequired,

  /// No Health Connect AND no step-counter hardware.
  deviceUnsupported,
}

/// One resolved reading of today's activity.
@immutable
class StepSnapshot {
  const StepSnapshot({
    required this.dayKey,
    required this.steps,
    required this.goal,
    required this.source,
    this.unavailableReason,
  });

  final String dayKey;
  final int steps;
  final int goal;
  final StepSource source;

  /// Non-null only when [source] is [StepSource.none].
  final StepUnavailableReason? unavailableReason;

  bool get isAvailable => source != StepSource.none;
  double get progressFraction => stepProgressFraction(steps: steps, goal: goal);
  int get progressPercent => stepProgressPercent(steps: steps, goal: goal);
  bool get goalReached => stepGoalReached(steps: steps, goal: goal);
}

/// Persisted daily summary — the offline-first record of a day.
@immutable
class StepDaySummary {
  const StepDaySummary({
    required this.date,
    required this.steps,
    required this.goal,
    required this.completed,
    required this.lastUpdated,
  });

  final String date;
  final int steps;
  final int goal;
  final bool completed;
  final DateTime lastUpdated;

  Map<String, dynamic> toMap() => {
        'date': date,
        'steps': steps,
        'goal': goal,
        'completed': completed,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  static StepDaySummary? fromMap(Map<String, dynamic> map) {
    final date = map['date'];
    if (date is! String) return null;
    return StepDaySummary(
      date: date,
      steps: (map['steps'] as num?)?.toInt() ?? 0,
      goal: (map['goal'] as num?)?.toInt() ?? 0,
      completed: map['completed'] == true,
      lastUpdated:
          DateTime.tryParse(map['lastUpdated'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Reads real step data, keeps the daily record, and fires milestone
/// notifications.
///
/// SOURCE SELECTION — Health Connect first, hardware sensor second, NEVER
/// both summed. Health Connect is preferred because its aggregate API
/// deduplicates records across providers (phone + watch + fitness app), which
/// a raw sensor read can't do. The sensor is the fallback because it's the
/// one source guaranteed to exist and to keep counting while this process is
/// dead — many devices have Health Connect installed but nothing writing
/// steps into it, and on those the sensor is the only thing that actually
/// works.
///
/// STORAGE — local first, always. Today's count and the daily history are
/// written to local storage before any network call, so the counter is fully
/// functional offline and a failed sync can never lose steps.
class StepTrackingService {
  StepTrackingService({
    StepPlatform? platform,
    StepNotifications? notifications,
    LocalStorageService? storage,
    DateTime Function()? clock,
  })  : _platform = platform ?? const StepPlatform(),
        _notifications = notifications ?? StepNotifications(),
        _storage = storage ?? LocalStorageService.instance,
        _now = clock ?? DateTime.now;

  final StepPlatform _platform;
  final StepNotifications _notifications;
  final LocalStorageService _storage;
  final DateTime Function() _now;

  static const _kBaseline = 'zitlas_step_baseline';
  static const _kMilestones = 'zitlas_step_milestones';
  static const _kHistory = 'zitlas_step_history';
  static const _kEnabled = 'zitlas_step_tracking_enabled';
  static const _kDenied = 'zitlas_step_permission_denied';
  static const _kLastReadAt = 'zitlas_step_last_read_at';

  /// Where the foreground app caches the effective goal so the background
  /// isolate — which has no Firestore session — can read it.
  static const goalCacheKey = 'zitlas_step_goal_cache';

  /// Days of local history retained. Matches the website's 90-day window.
  static const _historyDays = 90;

  /// True once the athlete has opted in — gates every automatic read so the
  /// app never touches health data before consent.
  bool get isEnabled => _storage.getBool(_kEnabled) ?? false;

  /// True when they were asked and said no. Used to avoid re-prompting.
  bool get wasDenied => _storage.getBool(_kDenied) ?? false;

  Future<StepPlatformStatus> platformStatus() => _platform.getStatus();

  /// Runs the real consent flow. [onNeedsActivityRecognition] is invoked when
  /// the sensor path needs ACTIVITY_RECOGNITION — supplied by the UI layer so
  /// this service stays free of permission_handler and stays unit-testable.
  ///
  /// Returns whether a usable source ended up enabled. Every failure path is
  /// terminal-but-safe: nothing throws, and a denial is recorded so the user
  /// isn't asked again on the next launch.
  Future<bool> enableTracking({
    required Future<bool> Function() onNeedsActivityRecognition,
  }) async {
    final status = await _platform.getStatus();
    if (kDebugMode) {
      debugPrint('[STEPS] enable requested — hc=${status.healthConnect.name} '
          'sensor=${status.sensorAvailable}');
    }

    // Preferred path: Health Connect.
    if (status.healthConnect == HealthConnectAvailability.available) {
      final granted = await _platform.requestHealthConnectPermission();
      if (kDebugMode) debugPrint('[STEPS] permission = ${granted ? 'granted' : 'denied'}');
      if (granted) {
        await _storage.setBool(_kEnabled, true);
        await _storage.setBool(_kDenied, false);
        await _notifications.requestPermission();
        return true;
      }
    }

    // Fallback: hardware sensor (also covers "HC installed but the user
    // declined it" — the sensor is still a legitimate, working source).
    if (status.sensorAvailable) {
      final granted = status.activityRecognitionGranted
          ? true
          : await onNeedsActivityRecognition();
      if (kDebugMode) {
        debugPrint('[STEPS] activity-recognition permission = '
            '${granted ? 'granted' : 'denied'}');
      }
      if (granted) {
        await _storage.setBool(_kEnabled, true);
        await _storage.setBool(_kDenied, false);
        await _notifications.requestPermission();
        return true;
      }
    }

    await _storage.setBool(_kDenied, true);
    return false;
  }

  Future<void> disableTracking() async {
    await _storage.setBool(_kEnabled, false);
  }

  /// The main entry point: read today's real steps, persist, and notify.
  ///
  /// [goal] is the athlete's effective daily goal, passed in by the caller
  /// (the Dashboard already owns goal resolution including Recovery Mode) so
  /// this service never becomes a second source of truth for it.
  Future<StepSnapshot> refresh({required int goal}) async {
    final now = _now();
    final dayKey = localDayKey(now);

    if (!isEnabled) {
      return StepSnapshot(
        dayKey: dayKey,
        steps: 0,
        goal: goal,
        source: StepSource.none,
        unavailableReason: wasDenied
            ? StepUnavailableReason.permissionDenied
            : StepUnavailableReason.notEnabled,
      );
    }

    final status = await _platform.getStatus();
    final start = startOfLocalDay(now);

    if (kDebugMode) {
      debugPrint('[STEPS] date = $dayKey');
      debugPrint('[STEPS] start = ${start.toIso8601String()} (local midnight)');
      debugPrint('[STEPS] now = ${now.toIso8601String()}');
    }

    // ── Source 1: Health Connect (aggregate — dedup handled by the platform)
    if (status.healthConnect == HealthConnectAvailability.available) {
      final hc = await _platform.getStepsBetween(start, now);
      if (hc.usable) {
        final steps = hc.steps!;
        if (kDebugMode) debugPrint('[STEPS] aggregate = $steps (health connect)');
        return _finish(
          dayKey: dayKey,
          steps: steps,
          goal: goal,
          source: StepSource.healthConnect,
          now: now,
        );
      }
      if (kDebugMode) {
        debugPrint('[STEPS] health connect returned no usable answer '
            '(granted=${hc.granted}) — trying sensor');
      }
    }

    // ── Source 2: hardware step counter (baseline math)
    if (status.sensorAvailable && status.activityRecognitionGranted) {
      final reading = await _platform.readStepSensor();
      if (reading != null) {
        final steps = await _applySensorReading(reading, dayKey, now);
        if (kDebugMode) debugPrint('[STEPS] aggregate = $steps (hardware sensor)');
        return _finish(
          dayKey: dayKey,
          steps: steps,
          goal: goal,
          source: StepSource.sensor,
          now: now,
        );
      }
    }

    // Nothing usable — report WHY rather than a misleading 0.
    final reason = switch (status.healthConnect) {
      HealthConnectAvailability.updateRequired =>
        StepUnavailableReason.providerUpdateRequired,
      _ => status.sensorAvailable
          ? StepUnavailableReason.permissionDenied
          : StepUnavailableReason.deviceUnsupported,
    };
    if (kDebugMode) debugPrint('[STEPS] no usable source — reason = ${reason.name}');
    return StepSnapshot(
      dayKey: dayKey,
      steps: 0,
      goal: goal,
      source: StepSource.none,
      unavailableReason: reason,
    );
  }

  /// Persist + evaluate milestones for a resolved step count.
  Future<StepSnapshot> _finish({
    required String dayKey,
    required int steps,
    required int goal,
    required StepSource source,
    required DateTime now,
  }) async {
    final snapshot =
        StepSnapshot(dayKey: dayKey, steps: steps, goal: goal, source: source);

    if (kDebugMode) {
      debugPrint('[STEPS] goal = $goal');
      debugPrint('[STEPS] progress = ${snapshot.progressPercent}%');
    }

    await _writeHistory(snapshot, now);
    await _maybeNotifyMilestone(steps: steps, goal: goal, dayKey: dayKey);
    await _storage.setInt(_kLastReadAt, now.millisecondsSinceEpoch);
    // The background isolate has no Firestore session, so the goal it needs
    // is cached here on every foreground read.
    await _storage.setInt(goalCacheKey, goal);
    return snapshot;
  }

  // ── Sensor baseline ─────────────────────────────────────────────────────

  Future<int> _applySensorReading(
    StepSensorReading reading,
    String dayKey,
    DateTime now,
  ) async {
    final previous = SensorBaseline.fromMap(_storage.getJson(_kBaseline));
    final lastReadMs = _storage.getInt(_kLastReadAt);
    final elapsed = lastReadMs == null
        ? null
        : now.difference(DateTime.fromMillisecondsSinceEpoch(lastReadMs));

    final delta = computeSensorDelta(
      previous: previous,
      cumulative: reading.cumulative,
      bootTimeMillis: reading.bootTimeMillis,
      todayKey: dayKey,
      elapsedSincePreviousRead: elapsed,
    );

    // A day rollover means the stored baseline belonged to yesterday — its
    // final total is already in history (written on the last read of that
    // day), so nothing is lost by re-anchoring here.
    final resolved = SensorBaseline(
      dayKey: dayKey,
      baselineCumulative: delta.baseline.baselineCumulative,
      bootTimeMillis: delta.baseline.bootTimeMillis,
      stepsAtBaseline: delta.stepsToday,
    );
    await _storage.setJson(_kBaseline, resolved.toMap());

    if (kDebugMode && delta.reason != 'ok') {
      debugPrint('[STEPS] sensor baseline: ${delta.reason}');
    }
    return delta.stepsToday;
  }

  // ── Milestones ──────────────────────────────────────────────────────────

  Future<void> _maybeNotifyMilestone({
    required int steps,
    required int goal,
    required String dayKey,
  }) async {
    final stored = _storage.getJson(_kMilestones);
    final state = stored == null
        ? MilestoneState.emptyFor(dayKey)
        : MilestoneState(
            dayKey: stored['dayKey'] as String? ?? dayKey,
            notified: ((stored['notified'] as List?) ?? const [])
                .map((e) => (e as num).toInt())
                .toSet(),
          );

    final decision =
        decideMilestone(steps: steps, goal: goal, state: state, todayKey: dayKey);

    // Persist FIRST, then show. If the process dies between the two, the worst
    // case is one missed notification — strictly better than a duplicate loop
    // that buzzes on every refresh.
    if (decision.state.notified.length != state.forDay(dayKey).notified.length) {
      await _storage.setJson(_kMilestones, {
        'dayKey': decision.state.dayKey,
        'notified': decision.state.notified.toList()..sort(),
      });
    }

    final announce = decision.announce;
    if (announce == null) {
      if (kDebugMode && state.forDay(dayKey).notified.isNotEmpty) {
        debugPrint('[STEPS] milestone = '
            '${state.forDay(dayKey).notified.join(",")} already notified');
      }
      return;
    }
    await _notifications.showMilestone(milestone: announce, goal: goal);
  }

  // ── Daily history (local-first, offline-safe) ───────────────────────────

  Future<void> _writeHistory(StepSnapshot snapshot, DateTime now) async {
    final history = readHistory();
    history[snapshot.dayKey] = StepDaySummary(
      date: snapshot.dayKey,
      steps: snapshot.steps,
      goal: snapshot.goal,
      completed: snapshot.goalReached,
      lastUpdated: now,
    );

    // Trim by local date order so the map can't grow without bound.
    final keys = history.keys.toList()..sort();
    while (keys.length > _historyDays) {
      history.remove(keys.removeAt(0));
    }

    await _storage.setJson(_kHistory, {
      for (final entry in history.entries) entry.key: entry.value.toMap(),
    });
    if (kDebugMode) debugPrint('[STEPS] syncing daily summary (${snapshot.dayKey})');
  }

  /// Locally persisted daily summaries, keyed `YYYY-MM-DD`.
  Map<String, StepDaySummary> readHistory() {
    final raw = _storage.getJson(_kHistory);
    if (raw == null) return {};
    final out = <String, StepDaySummary>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final summary = StepDaySummary.fromMap(value.cast<String, dynamic>());
      if (summary != null) out[entry.key] = summary;
    }
    return out;
  }
}
