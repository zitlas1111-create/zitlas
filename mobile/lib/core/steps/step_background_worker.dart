import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../storage/local_storage_service.dart';
import 'step_notifications.dart';
import 'step_platform.dart';
import 'step_tracking_service.dart';

/// Periodic background step check, so a milestone can fire while ZITLAS isn't
/// open.
///
/// HONEST ANDROID LIMITATIONS — this is best-effort by design, not a
/// guarantee, and the UI never claims otherwise:
///
///  * **15 minutes is Android's hard floor** for periodic WorkManager work.
///    Requesting less is silently rounded up. So a milestone can be announced
///    up to ~15 minutes after it was actually crossed.
///  * **Doze and App Standby stretch that further.** With the screen off and
///    the device stationary, Android batches deferrable work into maintenance
///    windows; the real gap can be hours. This is the OS working as intended
///    and cannot be overridden without a persistent foreground service, which
///    would be a battery/notification-shade cost far out of proportion to a
///    step milestone.
///  * **Aggressive OEM battery management** (OnePlus/Oppo/Realme, Xiaomi,
///    Samsung, Huawei) may stop background work entirely for an app the user
///    hasn't "unrestricted". Nothing an app can do in code overrides this.
///  * **Force-stop halts everything** until the app is next opened. That's an
///    OS-level guarantee, not a bug to route around.
///
/// What is NOT compromised by any of the above: the step COUNT itself. Both
/// sources accumulate independently of this app running — Health Connect
/// records are written by their own providers, and the TYPE_STEP_COUNTER chip
/// counts in hardware. So a delayed or skipped background run delays a
/// *notification*; the steps are still there and appear in full the moment
/// ZITLAS is reopened. That's the trade this design deliberately makes.
class StepBackgroundWorker {
  static const taskName = 'zitlas_step_milestone_check';
  static const _uniqueName = 'zitlas_step_milestone_periodic';

  /// Registers the periodic check. Safe to call on every launch — the unique
  /// name keeps it a single task rather than stacking duplicates.
  static Future<void> register() async {
    if (!_isAndroid) return;
    try {
      await Workmanager().initialize(stepCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
        ),
      );
      if (kDebugMode) debugPrint('[STEPS] background milestone check registered');
    } catch (e) {
      // A device that refuses to schedule work must not break app startup —
      // foreground refresh still covers every milestone on next open.
      if (kDebugMode) debugPrint('[STEPS] background registration failed: $e');
    }
  }

  static Future<void> cancel() async {
    if (!_isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
    } catch (_) {
      // Nothing to clean up if it was never scheduled.
    }
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

/// Entry point for the background isolate.
///
/// Runs in a FRESH isolate with no access to the app's memory, so every
/// dependency is constructed from scratch here and all state is read back from
/// local storage.
@pragma('vm:entry-point')
void stepCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != StepBackgroundWorker.taskName) return true;
    try {
      await LocalStorageService.init();
      final service = StepTrackingService(
        platform: const StepPlatform(),
        notifications: StepNotifications(),
        storage: LocalStorageService.instance,
      );
      if (!service.isEnabled) return true;

      // The goal is read from the value the foreground app last persisted.
      // The background isolate has no Firestore session, and waking one just
      // to re-read a number that changes rarely would be wasteful — a goal
      // edited seconds ago is picked up on the next foreground refresh.
      final goal =
          LocalStorageService.instance.getInt(StepTrackingService.goalCacheKey) ?? 0;
      if (goal <= 0) return true;

      await service.refresh(goal: goal);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[STEPS] background task failed: $e');
      // Returning true prevents WorkManager from retry-storming a task that
      // fails for a persistent reason (e.g. permission revoked).
      return true;
    }
  });
}

