import 'package:flutter/foundation.dart';

import '../storage/local_storage_service.dart';
import 'step_day.dart';
import 'step_notifications.dart';
import 'step_platform.dart';
import 'step_sensor_baseline.dart';

/// Which source produced a reading — surfaced in debug logs and used by the UI
/// to explain itself honestly.
enum StepSource {
  healthConnect,
  sensor,

  /// Today's last successfully stored total, replayed because this particular
  /// read couldn't get a fresh answer.
  ///
  /// TYPE_STEP_COUNTER is an on-change sensor: on many devices it reports only
  /// when a step is actually taken, so reading it on a phone sitting on a desk
  /// legitimately returns nothing. That is not a permission problem and must
  /// never be presented as one.
  cached,

  none,
}

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

  /// Everything is granted and enabled; the source just hasn't produced a
  /// first reading for today yet. A waiting state, NOT an error — the UI must
  /// not offer to "enable" something that is already on.
  noReadingYet,
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

  /// Arms the native local-midnight capture. Idempotent; safe on every launch.
  Future<void> scheduleDayBoundary() => _platform.scheduleDayBoundary();

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

  /// Silently resumes tracking when the OS grant is already in place.
  ///
  /// Permissions live in Android, not in ZITLAS. A grant survives a sign-out,
  /// a cleared cache and a reinstall, so any local flag that says "not enabled"
  /// while the OS says "granted" is stale bookkeeping — and acting on it means
  /// showing an Enable button to someone who already pressed it. This is called
  /// on every launch: if a real source is readable, tracking turns itself back
  /// on without a dialog.
  ///
  /// Returns whether tracking is active afterwards. Never prompts, never
  /// launches a permission sheet — the UI owns that decision.
  Future<bool> ensureTrackingActive() async {
    if (isEnabled) return true;

    final status = await _platform.getStatus();

    if (status.healthConnect == HealthConnectAvailability.available) {
      // Probing the real aggregate is how we learn whether the grant is still
      // held — Health Connect can revoke it for an app that hasn't read in a
      // long while, and only the API knows that.
      final now = _now();
      final probe = await _platform.getStepsBetween(startOfLocalDay(now), now);
      if (probe.granted) {
        if (kDebugMode) debugPrint('[STEPS] resuming — Health Connect already granted');
        await _storage.setBool(_kEnabled, true);
        await _storage.setBool(_kDenied, false);
        return true;
      }
    }

    if (status.sensorAvailable && status.activityRecognitionGranted) {
      if (kDebugMode) debugPrint('[STEPS] resuming — activity recognition already granted');
      await _storage.setBool(_kEnabled, true);
      await _storage.setBool(_kDenied, false);
      return true;
    }

    return false;
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

    // Close out any day the native midnight receiver captured while ZITLAS was
    // shut. Must run BEFORE today's reading is taken, so the sensor path
    // measures today from the real midnight origin rather than from wherever
    // the app last happened to be open.
    await _settleCapturedBoundary(now);

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

    // No fresh reading this time. Before declaring anything wrong, replay
    // today's last stored total — a stationary phone whose on-change sensor
    // stayed quiet is the single most common way to get here, and showing an
    // "Enable step tracking" prompt to someone whose tracking is enabled and
    // working is what makes the feature look broken and gets it re-enabled
    // over and over.
    final today = readHistory()[dayKey];
    if (today != null) {
      if (kDebugMode) {
        debugPrint('[STEPS] no fresh reading — replaying stored ${today.steps}');
      }
      return StepSnapshot(
        dayKey: dayKey,
        steps: today.steps,
        goal: goal,
        source: StepSource.cached,
      );
    }

    // Genuinely nothing to show — report WHY rather than a misleading 0, and
    // only blame permissions when a permission is actually missing.
    final permissionMissing = status.sensorAvailable && !status.activityRecognitionGranted;
    final reason = switch (status.healthConnect) {
      HealthConnectAvailability.updateRequired =>
        StepUnavailableReason.providerUpdateRequired,
      _ => status.anySourcePossible
          ? (permissionMissing
              ? StepUnavailableReason.permissionDenied
              : StepUnavailableReason.noReadingYet)
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

  // ── Midnight rollover ───────────────────────────────────────────────────

  /// Applies a midnight reading captured natively while the app was closed.
  ///
  /// Two things happen with one number: the day that ended gets its exact
  /// closing total (last stored total + whatever was walked between the final
  /// app read and 00:00), and the new day gets an origin anchored to the true
  /// boundary. Without this the in-between steps are simply lost — the sensor
  /// only reports a since-boot running total, so they cannot be recovered
  /// after the fact by any amount of arithmetic.
  Future<void> _settleCapturedBoundary(DateTime now) async {
    final boundary = await _platform.consumeDayBoundary();
    if (boundary == null) return;

    final baseline = SensorBaseline.fromMap(_storage.getJson(_kBaseline));
    final history = readHistory();
    final goal = _storage.getInt(goalCacheKey) ?? 0;

    // Finalise the closed day, but only from a baseline that actually belongs
    // to it and to the same boot. A reboot between the last read and midnight
    // makes the subtraction meaningless, and a stale baseline from an earlier
    // day would credit the wrong date.
    if (baseline != null &&
        baseline.dayKey == boundary.dayKey &&
        (boundary.bootTimeMillis - baseline.bootTimeMillis).abs() <= 90 * 1000) {
      final closing = baseline.stepsAtBaseline +
          (boundary.cumulative - baseline.baselineCumulative);
      final existing = history[boundary.dayKey];
      // Never let a boundary reduce a day that was already recorded higher —
      // Health Connect may have contributed a larger, deduplicated total.
      if (closing >= 0 && (existing == null || closing > existing.steps)) {
        history[boundary.dayKey] = StepDaySummary(
          date: boundary.dayKey,
          steps: closing,
          goal: existing?.goal ?? goal,
          completed: stepGoalReached(steps: closing, goal: existing?.goal ?? goal),
          lastUpdated: now,
        );
        await _persistHistory(history);
        if (kDebugMode) {
          debugPrint('[STEPS] midnight rollover: ${boundary.dayKey} closed at $closing');
        }
      }
    }

    // Anchor the NEW day at the boundary reading, with a zeroed total. This is
    // the "reset today's counter" half of the rollover, and it happens without
    // the athlete touching anything.
    final newDayKey = localDayKey(now);
    if (newDayKey != boundary.dayKey) {
      await _storage.setJson(
        _kBaseline,
        SensorBaseline(
          dayKey: newDayKey,
          baselineCumulative: boundary.cumulative,
          bootTimeMillis: boundary.bootTimeMillis,
          stepsAtBaseline: 0,
        ).toMap(),
      );
    }
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

    // Persist EXACTLY what the math produced. Rebuilding the baseline here
    // with a different `stepsAtBaseline` than the origin it was computed
    // against is what made the two disagree — the origin said "start of day"
    // while the total said "everything so far", so every read added the day
    // to itself. computeSensorDelta owns this pairing; nothing else may
    // rewrite half of it.
    await _storage.setJson(_kBaseline, delta.baseline.toMap());

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

    await _persistHistory(history);
    if (kDebugMode) debugPrint('[STEPS] syncing daily summary (${snapshot.dayKey})');
  }

  Future<void> _persistHistory(Map<String, StepDaySummary> history) async {
    // Trim by local date order so the map can't grow without bound.
    final keys = history.keys.toList()..sort();
    while (keys.length > _historyDays) {
      history.remove(keys.removeAt(0));
    }
    await _storage.setJson(_kHistory, {
      for (final entry in history.entries) entry.key: entry.value.toMap(),
    });
  }

  /// Rebuilds past days from Health Connect's own records.
  ///
  /// This is what makes yesterday viewable at all. Health Connect stores
  /// TIMESTAMPED records, so a completed day can be totalled correctly hours
  /// or days after the fact — ZITLAS does not have to have been awake at
  /// midnight, or even installed, to report it. The hardware counter can make
  /// no such claim: it only knows a since-boot running total, so a day that
  /// ended while the app was closed can never be reconstructed from it, and
  /// this method leaves those days exactly as they were recorded rather than
  /// inventing them.
  ///
  /// Reads through the same aggregate API as the live path, so a day totalled
  /// here is deduplicated across every provider (phone, watch, fitness app) —
  /// backfilling cannot introduce double counting.
  ///
  /// Returns how many days were (re)written.
  Future<int> backfillFromHealthConnect({int days = 30}) async {
    if (!isEnabled) return 0;
    final status = await _platform.getStatus();
    if (status.healthConnect != HealthConnectAvailability.available) return 0;

    final now = _now();
    final history = readHistory();
    final goalFallback = _storage.getInt(goalCacheKey) ?? 0;
    var written = 0;

    // Skip index 0 (today) — the live path owns it and is fresher.
    for (var i = 1; i <= days; i++) {
      final dayStart = DateTime(now.year, now.month, now.day - i);
      final dayEnd = DateTime(now.year, now.month, now.day - i + 1);
      final key = localDayKey(dayStart);

      final result = await _platform.getStepsBetween(dayStart, dayEnd);
      if (!result.usable) continue;

      final steps = result.steps!;
      final existing = history[key];
      // A day with no records in Health Connect and no local record is a day
      // nothing was measured — leave it absent rather than writing a 0 that
      // would drag the weekly average down and break a streak retroactively.
      if (steps == 0 && existing == null) continue;
      // Never overwrite a locally recorded day with a smaller HC total: the
      // sensor path may legitimately have caught steps that no provider ever
      // wrote to Health Connect.
      if (existing != null && existing.steps >= steps) continue;

      final goal = existing?.goal ?? goalFallback;
      history[key] = StepDaySummary(
        date: key,
        steps: steps,
        goal: goal,
        completed: stepGoalReached(steps: steps, goal: goal),
        lastUpdated: now,
      );
      written++;
    }

    if (written > 0) {
      await _persistHistory(history);
      if (kDebugMode) debugPrint('[STEPS] backfilled $written day(s) from Health Connect');
    }
    return written;
  }

  /// Seeds the local record from days already synced to Firestore.
  ///
  /// Local storage disappears on reinstall and never existed on a second
  /// device, so a synced day is the only surviving copy of it. Merged rather
  /// than assigned, and only where the synced day is HIGHER: a device that
  /// recorded more steps locally than it managed to sync must not have its own
  /// record reduced by a stale server copy.
  ///
  /// Returns how many days were added or corrected.
  Future<int> hydrateHistory(Map<String, ({int steps, int goal})> synced) async {
    if (synced.isEmpty) return 0;
    final history = readHistory();
    final now = _now();
    var changed = 0;

    for (final entry in synced.entries) {
      final incoming = entry.value;
      if (incoming.steps <= 0) continue;
      final existing = history[entry.key];
      if (existing != null && existing.steps >= incoming.steps) continue;
      history[entry.key] = StepDaySummary(
        date: entry.key,
        steps: incoming.steps,
        goal: incoming.goal,
        completed: stepGoalReached(steps: incoming.steps, goal: incoming.goal),
        lastUpdated: now,
      );
      changed++;
    }

    if (changed > 0) {
      await _persistHistory(history);
      if (kDebugMode) debugPrint('[STEPS] hydrated $changed day(s) from sync');
    }
    return changed;
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
