import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether Health Connect can serve step data on this device.
enum HealthConnectAvailability {
  /// Installed, up to date, usable.
  available,

  /// Present but the provider app needs a Play Store update before its API
  /// can be called.
  updateRequired,

  /// Not installed / not supported (common on Android 13 and below, where
  /// Health Connect is an optional app rather than part of the system).
  unavailable,
}

/// What the device can actually do, as reported by the platform — never
/// assumed. Drives both source selection and the Activity card's UI state.
@immutable
class StepPlatformStatus {
  const StepPlatformStatus({
    required this.healthConnect,
    required this.sensorAvailable,
    required this.activityRecognitionGranted,
  });

  final HealthConnectAvailability healthConnect;

  /// A hardware TYPE_STEP_COUNTER exists. Practically every modern phone has
  /// one; when it doesn't, there is no background-capable fallback at all.
  final bool sensorAvailable;

  /// ACTIVITY_RECOGNITION — required from Android 10 to read the sensor.
  final bool activityRecognitionGranted;

  /// True when *some* real source could work, so the UI can distinguish
  /// "needs permission" from "this device can't do it at all".
  bool get anySourcePossible =>
      healthConnect == HealthConnectAvailability.available || sensorAvailable;

  static const unsupported = StepPlatformStatus(
    healthConnect: HealthConnectAvailability.unavailable,
    sensorAvailable: false,
    activityRecognitionGranted: false,
  );
}

/// One Health Connect aggregate answer.
///
/// [steps] `null` means "no usable answer" (not installed / not granted /
/// threw) — deliberately distinct from `0`, which is a real "hasn't walked
/// yet". Collapsing the two is how a broken integration masquerades as a lazy
/// morning, so nothing in this file is allowed to default a null to zero.
@immutable
class HealthConnectSteps {
  const HealthConnectSteps({required this.granted, required this.steps});

  final bool granted;
  final int? steps;

  bool get usable => granted && steps != null;

  static const unavailable = HealthConnectSteps(granted: false, steps: null);
}

/// A raw TYPE_STEP_COUNTER reading: steps accumulated since the device booted.
///
/// [bootTimeMillis] is the wall-clock time of that boot. It travels with the
/// reading so a reboot (which silently resets [cumulative] to 0) can be told
/// apart from a genuine decrease — see `StepSensorSource.computeDelta`.
@immutable
class StepSensorReading {
  const StepSensorReading({required this.cumulative, required this.bootTimeMillis});

  final int cumulative;
  final int bootTimeMillis;
}

/// The step counter's value at the moment a local day ended, captured by the
/// native midnight receiver while ZITLAS was closed.
///
/// [dayKey] is the day that ENDED. The same [cumulative] is simultaneously
/// that day's closing total and the next day's opening origin, which is what
/// lets the two days be split exactly instead of guessed at.
@immutable
class StepDayBoundaryReading {
  const StepDayBoundaryReading({
    required this.dayKey,
    required this.cumulative,
    required this.bootTimeMillis,
  });

  final String dayKey;
  final int cumulative;
  final int bootTimeMillis;
}

/// Thin, honest wrapper over the `com.zitlas.app/steps` MethodChannel
/// (android/app/src/main/kotlin/com/zitlas/app/StepTrackerPlugin.kt).
///
/// Every method degrades to "unavailable" rather than throwing: a missing
/// plugin (iOS, tests, a desktop debug run) must never take down the
/// Dashboard, and the caller already has a truthful "no source" path to fall
/// into.
class StepPlatform {
  const StepPlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.zitlas.app/steps');

  final MethodChannel _channel;

  Future<StepPlatformStatus> getStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getStatus');
      if (raw == null) return StepPlatformStatus.unsupported;
      return StepPlatformStatus(
        healthConnect: switch (raw['healthConnect']) {
          'available' => HealthConnectAvailability.available,
          'updateRequired' => HealthConnectAvailability.updateRequired,
          _ => HealthConnectAvailability.unavailable,
        },
        sensorAvailable: raw['sensorAvailable'] == true,
        activityRecognitionGranted: raw['activityRecognitionGranted'] == true,
      );
    } on MissingPluginException {
      return StepPlatformStatus.unsupported;
    } catch (_) {
      return StepPlatformStatus.unsupported;
    }
  }

  /// Opens the real Health Connect permission sheet. Returns whether READ
  /// steps ended up granted. Already-granted short-circuits to `true` without
  /// showing anything.
  Future<bool> requestHealthConnectPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestHealthConnectPermission') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Health Connect's own aggregate total for `[start, end)`.
  ///
  /// The window is always passed in explicitly (never computed natively) so
  /// there is exactly ONE definition of "today" in the codebase — the local
  /// midnight boundary in `StepDay`.
  Future<HealthConnectSteps> getStepsBetween(DateTime start, DateTime end) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getStepsBetween', {
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
      });
      if (raw == null) return HealthConnectSteps.unavailable;
      final steps = raw['steps'];
      return HealthConnectSteps(
        granted: raw['granted'] == true,
        steps: steps is num ? steps.toInt() : null,
      );
    } on MissingPluginException {
      return HealthConnectSteps.unavailable;
    } catch (_) {
      return HealthConnectSteps.unavailable;
    }
  }

  /// One-shot hardware step-counter read; `null` when unreadable (no
  /// permission, no sensor, or the sensor never reported).
  Future<StepSensorReading?> readStepSensor() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('readStepSensor');
      if (raw == null) return null;
      final cumulative = raw['cumulative'];
      final bootTime = raw['bootTimeMillis'];
      if (cumulative is! num || bootTime is! num) return null;
      return StepSensorReading(
        cumulative: cumulative.toInt(),
        bootTimeMillis: bootTime.toInt(),
      );
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Arms the native local-midnight capture (StepDayBoundary.kt).
  ///
  /// Called on every launch: an app force-stop clears its alarms, so the
  /// schedule has to be repairable, and re-arming is idempotent.
  Future<void> scheduleDayBoundary() async {
    try {
      await _channel.invokeMethod<bool>('scheduleDayBoundary');
    } on MissingPluginException {
      // Non-Android / tests — the Dart-side rollover still covers the
      // app-was-open case.
    } catch (_) {}
  }

  /// Takes the midnight reading the native receiver captured, if any.
  ///
  /// Consume-once by design: the native side deletes it as it hands it over,
  /// because folding the same boundary in twice would credit a day's closing
  /// steps to two different days.
  Future<StepDayBoundaryReading?> consumeDayBoundary() async {
    try {
      final raw = await _channel.invokeMethod<String>('consumeDayBoundary');
      if (raw == null) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final dayKey = map['dayKey'];
      final cumulative = map['cumulative'];
      final bootTime = map['bootTimeMillis'];
      if (dayKey is! String || cumulative is! num || bootTime is! num) return null;
      return StepDayBoundaryReading(
        dayKey: dayKey,
        cumulative: cumulative.toInt(),
        bootTimeMillis: bootTime.toInt(),
      );
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Deep-links to Health Connect's settings (or its Play Store page when the
  /// provider isn't installed) — used by the "denied" and "update required"
  /// UI states so the athlete has a real way forward.
  Future<bool> openHealthConnectSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openHealthConnectSettings') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
