import 'package:flutter/foundation.dart';

/// Baseline math for the hardware TYPE_STEP_COUNTER fallback.
///
/// The sensor reports steps SINCE BOOT, not since midnight, so a daily figure
/// is `currentCumulative - baselineAtStartOfDay`. That subtraction is the
/// classic source of absurd step counts, so every failure mode it has is
/// handled explicitly here and covered by tests:
///
///  * **Reboot** — the counter restarts at 0, so a stale baseline yields a
///    large negative delta. Detected via the boot timestamp, not by guessing
///    from the numbers.
///  * **New local day** — the baseline must re-anchor to the current reading
///    at the first read after midnight.
///  * **Counter decrease without a reboot** — some OEM firmware resets or
///    rolls the counter; treated as a re-anchor rather than trusted.
///  * **Implausible jumps** — a device that was off/asleep for a long stretch,
///    or firmware reporting garbage, can produce a spike no human walked.
///
/// This is used ONLY when Health Connect can't answer. The two sources are
/// never added together.
@immutable
class SensorBaseline {
  const SensorBaseline({
    required this.dayKey,
    required this.baselineCumulative,
    required this.bootTimeMillis,
    required this.stepsAtBaseline,
  });

  /// Local `YYYY-MM-DD` this baseline anchors.
  final String dayKey;

  /// The sensor's since-boot total at the moment the baseline was taken.
  final int baselineCumulative;

  /// Wall-clock boot time when the baseline was taken. A different value means
  /// the device rebooted since, so [baselineCumulative] is meaningless.
  final int bootTimeMillis;

  /// Steps already credited to [dayKey] before this baseline was (re-)anchored.
  ///
  /// Without this, a reboot mid-day would silently erase the morning's steps:
  /// re-anchoring resets the subtraction origin, so the total accumulated
  /// before the reboot has to be carried forward explicitly.
  final int stepsAtBaseline;

  Map<String, dynamic> toMap() => {
        'dayKey': dayKey,
        'baselineCumulative': baselineCumulative,
        'bootTimeMillis': bootTimeMillis,
        'stepsAtBaseline': stepsAtBaseline,
      };

  static SensorBaseline? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final dayKey = map['dayKey'];
    final baseline = map['baselineCumulative'];
    final boot = map['bootTimeMillis'];
    if (dayKey is! String || baseline is! num || boot is! num) return null;
    return SensorBaseline(
      dayKey: dayKey,
      baselineCumulative: baseline.toInt(),
      bootTimeMillis: boot.toInt(),
      stepsAtBaseline: (map['stepsAtBaseline'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Outcome of folding a fresh sensor reading into a stored baseline.
@immutable
class SensorDelta {
  const SensorDelta({
    required this.stepsToday,
    required this.baseline,
    required this.reason,
  });

  /// Steps attributable to the current local day.
  final int stepsToday;

  /// The baseline to persist for the next read.
  final SensorBaseline baseline;

  /// Why this outcome happened — surfaced only in debug logs.
  final String reason;
}

/// Two boot timestamps refer to the same boot if they're within this much.
///
/// `bootTime = wallClock - elapsedRealtime` drifts by a few ms between reads
/// (and jumps when the clock is NTP-corrected), so exact equality would report
/// a phantom reboot on every single read. A real reboot moves this by at least
/// the length of the downtime.
const _bootDriftToleranceMs = 90 * 1000;

/// Steps beyond this in one interval are treated as not-a-walk.
///
/// Anchored to elapsed time at ~5 steps/second — comfortably above sprinting,
/// so it only rejects firmware garbage and counter rollovers, never a real
/// human. Falls back to a flat cap when the interval is unknown.
const _maxStepsPerSecond = 5;
const _absoluteJumpCap = 30000;

/// Folds a new reading into the stored baseline.
///
/// [previous] is the persisted baseline (null on first ever read).
/// [todayKey] / [elapsedSincePreviousRead] come from the caller so this stays
/// pure and testable — no clock access here.
SensorDelta computeSensorDelta({
  required SensorBaseline? previous,
  required int cumulative,
  required int bootTimeMillis,
  required String todayKey,
  Duration? elapsedSincePreviousRead,
}) {
  // First ever read: today starts now. Steps taken earlier today (before
  // ZITLAS was ever opened) are unknowable from a since-boot counter — we
  // credit 0 rather than inventing them.
  if (previous == null) {
    return SensorDelta(
      stepsToday: 0,
      baseline: SensorBaseline(
        dayKey: todayKey,
        baselineCumulative: cumulative,
        bootTimeMillis: bootTimeMillis,
        stepsAtBaseline: 0,
      ),
      reason: 'first-read',
    );
  }

  final rebooted =
      (bootTimeMillis - previous.bootTimeMillis).abs() > _bootDriftToleranceMs;
  final newDay = previous.dayKey != todayKey;

  // New local day: whatever the counter reads now is this day's origin. The
  // previous day's total was already archived by the caller.
  if (newDay) {
    return SensorDelta(
      stepsToday: 0,
      baseline: SensorBaseline(
        dayKey: todayKey,
        baselineCumulative: cumulative,
        bootTimeMillis: bootTimeMillis,
        stepsAtBaseline: 0,
      ),
      reason: 'new-day',
    );
  }

  // Reboot mid-day: the counter restarted from 0, so re-anchor here but KEEP
  // the steps already credited today. Steps taken during the reboot itself are
  // genuinely lost — the sensor wasn't counting while the device was off.
  if (rebooted) {
    return SensorDelta(
      stepsToday: previous.stepsAtBaseline,
      baseline: SensorBaseline(
        dayKey: todayKey,
        baselineCumulative: cumulative,
        bootTimeMillis: bootTimeMillis,
        stepsAtBaseline: previous.stepsAtBaseline,
      ),
      reason: 'reboot-reanchor',
    );
  }

  final rawDelta = cumulative - previous.baselineCumulative;

  // Counter went backwards without a reboot — OEM firmware reset or rollover.
  // Re-anchor rather than emit a negative number.
  if (rawDelta < 0) {
    return SensorDelta(
      stepsToday: previous.stepsAtBaseline,
      baseline: SensorBaseline(
        dayKey: todayKey,
        baselineCumulative: cumulative,
        bootTimeMillis: bootTimeMillis,
        stepsAtBaseline: previous.stepsAtBaseline,
      ),
      reason: 'counter-reset-reanchor',
    );
  }

  // The cap is per-INTERVAL, so it is only meaningful against a delta measured
  // since the previous read — which is exactly what [rawDelta] is, because
  // every successful read below re-anchors the origin to the current reading.
  final cap = elapsedSincePreviousRead == null
      ? _absoluteJumpCap
      : (elapsedSincePreviousRead.inSeconds * _maxStepsPerSecond)
          .clamp(0, _absoluteJumpCap);

  // Implausible spike: keep what we had and re-anchor, so one bad reading
  // can't permanently inflate the day.
  if (rawDelta > cap) {
    return SensorDelta(
      stepsToday: previous.stepsAtBaseline,
      baseline: SensorBaseline(
        dayKey: todayKey,
        baselineCumulative: cumulative,
        bootTimeMillis: bootTimeMillis,
        stepsAtBaseline: previous.stepsAtBaseline,
      ),
      reason: 'implausible-jump-rejected',
    );
  }

  // Normal accumulation. The origin MOVES to the current reading and the
  // running total moves with it — the two always describe the same instant.
  //
  // Leaving the origin at the start of the day instead (what this used to do)
  // silently double-counts: the next read measures the whole day again and
  // adds it to a total that already contained it, so a 4,000-step day is
  // reported as 9,000 after four refreshes. It also breaks the interval cap
  // above, because a whole day of walking always looks implausible when
  // compared against the seconds since the last refresh — which is how the
  // counter ends up frozen for the rest of the day.
  final total = previous.stepsAtBaseline + rawDelta;
  return SensorDelta(
    stepsToday: total,
    baseline: SensorBaseline(
      dayKey: todayKey,
      baselineCumulative: cumulative,
      bootTimeMillis: bootTimeMillis,
      stepsAtBaseline: total,
    ),
    reason: 'ok',
  );
}
