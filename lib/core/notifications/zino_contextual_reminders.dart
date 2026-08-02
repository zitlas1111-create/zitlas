import 'package:flutter/foundation.dart';

import '../steps/step_day.dart';
import '../steps/step_tracking_service.dart';
import '../storage/local_storage_service.dart';
import 'notification_preferences.dart';
import 'zino_messages.dart';
import 'zino_notification_scheduler.dart';

/// The two reminders that must read live data before they are allowed to speak.
///
/// A notification scheduled at 09:00 for 18:00 cannot know whether the goal was
/// met in between. Sending "only 1,800 steps left" to someone who finished at
/// lunch, or "your workout is waiting" to someone who already trained, is the
/// fastest way to get an app permanently muted — so these two slots are
/// evaluated at fire time instead of baked into the schedule.
class ZinoContextualReminders {
  ZinoContextualReminders({
    ZinoNotificationScheduler? scheduler,
    StepTrackingService? steps,
    LocalStorageService? storage,
    DateTime Function()? clock,
  })  : _scheduler = scheduler ?? ZinoNotificationScheduler(),
        _steps = steps,
        _storage = storage,
        _now = clock ?? DateTime.now;

  final ZinoNotificationScheduler _scheduler;
  final StepTrackingService? _steps;
  final LocalStorageService? _storage;
  final DateTime Function() _now;

  /// Set by the Diet/Workout flows when a session is marked done, so the
  /// evening reminder can be suppressed without a network round trip from a
  /// background isolate.
  static const workoutDoneKeyPrefix = 'zitlas_workout_done_';

  static String workoutDoneKey(DateTime day) =>
      '$workoutDoneKeyPrefix${localDayKey(day)}';

  LocalStorageService? get _store {
    if (_storage != null) return _storage;
    try {
      return LocalStorageService.instance;
    } catch (_) {
      return null;
    }
  }

  /// 18:00 — step progress, using the athlete's REAL count.
  ///
  /// Returns what it decided, so this is testable without a notification
  /// channel and so the decision is visible in logs.
  Future<StepReminderOutcome> runStepReminder() async {
    final prefs = NotificationPreferences.load(_store);
    if (!prefs.isEnabled(NotificationCategory.steps)) {
      return StepReminderOutcome.suppressedByPreference;
    }

    final service = _steps;
    if (service == null || !service.isEnabled) {
      // Step tracking off — a progress reminder would be meaningless.
      return StepReminderOutcome.noData;
    }

    final goal = _store?.getInt(StepTrackingService.goalCacheKey) ?? 0;
    if (goal <= 0) return StepReminderOutcome.noData;

    final snapshot = await service.refresh(goal: goal);
    if (!snapshot.isAvailable) return StepReminderOutcome.noData;

    if (snapshot.goalReached) {
      // Celebrate — and crucially, never ask for more walking.
      if (!prefs.isEnabled(NotificationCategory.achievements)) {
        return StepReminderOutcome.suppressedByPreference;
      }
      await _scheduler.showContextual(
        slot: ZinoSlot.steps,
        body: kStepGoalCompleteMessage,
      );
      return StepReminderOutcome.celebrated;
    }

    await _scheduler.showContextual(
      slot: ZinoSlot.steps,
      body: stepProgressMessage(steps: snapshot.steps, goal: snapshot.goal),
    );
    return StepReminderOutcome.encouraged;
  }

  /// 19:00 — workout nudge, skipped entirely if today's session is done.
  Future<WorkoutReminderOutcome> runWorkoutReminder() async {
    final prefs = NotificationPreferences.load(_store);
    if (!prefs.isEnabled(NotificationCategory.workout)) {
      return WorkoutReminderOutcome.suppressedByPreference;
    }
    if (isWorkoutDone(_now())) {
      // Spec is explicit: if the workout is complete, send NOTHING. Not a
      // congratulation, not a softer nudge — silence is the reward.
      return WorkoutReminderOutcome.alreadyDone;
    }
    await _scheduler.showContextual(
      slot: ZinoSlot.workout,
      body: pickForDay(kWorkoutMessages, _now()),
    );
    return WorkoutReminderOutcome.reminded;
  }

  bool isWorkoutDone(DateTime day) =>
      _store?.getBool(workoutDoneKey(day)) ?? false;

  /// Called by the Training flow when a session is completed.
  Future<void> markWorkoutDone(DateTime day) async {
    await _store?.setBool(workoutDoneKey(day), true);
    if (kDebugMode) debugPrint('[NOTIF] workout marked done for ${localDayKey(day)}');
  }
}

enum StepReminderOutcome {
  /// Goal not met — progress message with real numbers sent.
  encouraged,

  /// Goal met — congratulation sent, no request to walk more.
  celebrated,

  /// Tracking off, no goal, or no readable step data.
  noData,

  suppressedByPreference,
}

enum WorkoutReminderOutcome {
  reminded,

  /// Session already completed today — deliberately silent.
  alreadyDone,

  suppressedByPreference,
}
