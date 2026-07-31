import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/steps/step_day.dart';
import 'package:zitlas_mobile/core/steps/step_sensor_baseline.dart';

/// Step counter — the correctness surface that must hold without a device.
///
/// Covers every rule the feature depends on being right: where a day starts
/// and ends (LOCAL midnight, never UTC, never "24h since launch"), how
/// progress reads at each tier, when a milestone is allowed to fire, and every
/// way the hardware step counter can lie (reboot, rollover, garbage spikes).
void main() {
  group('local day boundaries', () {
    test('a day starts at LOCAL 00:00:00.000, not at the current time', () {
      final start = startOfLocalDay(DateTime(2026, 7, 30, 14, 37, 12, 500));
      expect(start, DateTime(2026, 7, 30));
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.millisecond, 0);
    });

    test('the boundary is the local calendar date even just after midnight', () {
      // 00:00:30 IST is still *yesterday* in UTC. Deriving the key from a UTC
      // date here would file this walk under the wrong day and make "today"
      // appear to reset at 05:30 local instead of midnight.
      final justAfterMidnight = DateTime(2026, 7, 31, 0, 0, 30);
      expect(localDayKey(justAfterMidnight), '2026-07-31');
      expect(startOfLocalDay(justAfterMidnight), DateTime(2026, 7, 31));
    });

    test('the boundary is still today at 23:59:59', () {
      final endOfDay = DateTime(2026, 7, 30, 23, 59, 59);
      expect(localDayKey(endOfDay), '2026-07-30');
      expect(startOfLocalDay(endOfDay), DateTime(2026, 7, 30));
    });

    test('next-day boundary rolls the month over correctly', () {
      expect(startOfNextLocalDay(DateTime(2026, 7, 31, 22)), DateTime(2026, 8, 1));
    });

    test('next-day boundary rolls the year over correctly', () {
      expect(startOfNextLocalDay(DateTime(2026, 12, 31, 9)), DateTime(2027, 1, 1));
    });

    test('leap-day boundaries are handled by real date arithmetic', () {
      expect(startOfNextLocalDay(DateTime(2028, 2, 28, 12)), DateTime(2028, 2, 29));
      expect(localDayKey(DateTime(2028, 2, 29, 12)), '2028-02-29');
    });

    test('day keys are zero-padded so they sort chronologically as strings', () {
      final keys = [
        localDayKey(DateTime(2026, 12, 9)),
        localDayKey(DateTime(2026, 1, 5)),
        localDayKey(DateTime(2026, 10, 20)),
      ]..sort();
      expect(keys, ['2026-01-05', '2026-10-20', '2026-12-09']);
    });
  });

  group('progress tiers', () {
    test('0 steps is 0%, not a division error', () {
      expect(stepProgressFraction(steps: 0, goal: 8000), 0);
      expect(stepProgressPercent(steps: 0, goal: 8000), 0);
      expect(stepGoalReached(steps: 0, goal: 8000), isFalse);
    });

    test('25 / 50 / 75 / 100 percent read exactly', () {
      expect(stepProgressPercent(steps: 2000, goal: 8000), 25);
      expect(stepProgressPercent(steps: 4000, goal: 8000), 50);
      expect(stepProgressPercent(steps: 6000, goal: 8000), 75);
      expect(stepProgressPercent(steps: 8000, goal: 8000), 100);
      expect(stepGoalReached(steps: 8000, goal: 8000), isTrue);
    });

    test('over 100%: the RING caps at 1.0 but the percentage stays truthful', () {
      // 10,532 / 8,000 must still display as 10,532 steps and 132% — only the
      // ring geometry is clamped, never the reported achievement.
      expect(stepProgressFraction(steps: 10532, goal: 8000), 1.0);
      expect(stepProgressPercent(steps: 10532, goal: 8000), 132);
      expect(stepGoalReached(steps: 10532, goal: 8000), isTrue);
    });

    test('a paused (0) goal shows a calm full ring and is not an achievement', () {
      // Recovery Mode "Rest": the website's calculateStepProgress() returns
      // 100% for a 0 goal, but a paused goal isn't something you *completed*.
      expect(stepProgressFraction(steps: 0, goal: 0), 1);
      expect(stepProgressPercent(steps: 0, goal: 0), 100);
      expect(stepGoalReached(steps: 5000, goal: 0), isFalse);
    });
  });

  group('milestone notifications', () {
    const today = '2026-07-30';

    MilestoneState empty() => MilestoneState.emptyFor(today);

    test('crossing 25% announces 25 and records it', () {
      final d = decideMilestone(
        steps: 2000,
        goal: 8000,
        state: empty(),
        todayKey: today,
      );
      expect(d.announce, 25);
      expect(d.state.notified, {25});
    });

    test('the SAME milestone never fires twice in one day', () {
      var state = empty();
      final first = decideMilestone(steps: 2000, goal: 8000, state: state, todayKey: today);
      expect(first.announce, 25);
      state = first.state;

      // More steps, still below 50% — nothing new to say.
      final second = decideMilestone(steps: 3200, goal: 8000, state: state, todayKey: today);
      expect(second.announce, isNull, reason: '25% was already announced today');
    });

    test('a big jump announces ONE notification, not a burst', () {
      // 20% -> 55% in a single sync (phone was in a pocket). Firing 25 and 50
      // back to back would be spam; only the highest is announced.
      final d = decideMilestone(
        steps: 4400, // 55%
        goal: 8000,
        state: empty(),
        todayKey: today,
      );
      expect(d.announce, 50);
      expect(d.state.notified, {25, 50},
          reason: 'the leapfrogged 25% must be suppressed, never fired later');
    });

    test('leapfrogged milestones can never fire retroactively', () {
      final jump = decideMilestone(steps: 4400, goal: 8000, state: empty(), todayKey: today);
      final later = decideMilestone(
        steps: 4500,
        goal: 8000,
        state: jump.state,
        todayKey: today,
      );
      expect(later.announce, isNull);
    });

    test('goal completion outranks everything when several cross at once', () {
      final d = decideMilestone(steps: 9000, goal: 8000, state: empty(), todayKey: today);
      expect(d.announce, 100, reason: 'goal-complete is the message that matters');
      expect(d.state.notified, {25, 50, 75, 100});
    });

    test('milestone eligibility RESETS on the next local calendar day', () {
      final yesterday = decideMilestone(
        steps: 9000,
        goal: 8000,
        state: empty(),
        todayKey: today,
      );
      expect(yesterday.state.notified, {25, 50, 75, 100});

      // Same stored state, new day: a fresh 25% must be announceable again.
      final newDay = decideMilestone(
        steps: 2000,
        goal: 8000,
        state: yesterday.state,
        todayKey: '2026-07-31',
      );
      expect(newDay.announce, 25);
      expect(newDay.state.dayKey, '2026-07-31');
      expect(newDay.state.notified, {25});
    });

    test('a paused (0) goal never notifies', () {
      final d = decideMilestone(steps: 5000, goal: 0, state: empty(), todayKey: today);
      expect(d.announce, isNull);
    });

    test('lowering the goal mid-day completes it once, and only once', () {
      // Spec case: 6,000 steps against an 8,000 goal (75%), then the athlete
      // drops the goal to 5,000 — that's now complete and should say so.
      var state = empty();
      final before = decideMilestone(steps: 6000, goal: 8000, state: state, todayKey: today);
      expect(before.announce, 75);
      state = before.state;

      final afterGoalDrop =
          decideMilestone(steps: 6000, goal: 5000, state: state, todayKey: today);
      expect(afterGoalDrop.announce, 100);
      state = afterGoalDrop.state;

      // Every later refresh that day must stay silent.
      final refreshed =
          decideMilestone(steps: 6200, goal: 5000, state: state, todayKey: today);
      expect(refreshed.announce, isNull,
          reason: 'no duplicate completion notification on subsequent reads');
    });

    test('raising the goal after completing does not un-notify or re-notify', () {
      var state = empty();
      state = decideMilestone(steps: 8000, goal: 8000, state: state, todayKey: today).state;
      final raised =
          decideMilestone(steps: 8000, goal: 12000, state: state, todayKey: today);
      expect(raised.announce, isNull);
      expect(raised.state.notified, contains(100));
    });

    test('messages name the real goal and match the required copy', () {
      expect(milestoneMessage(milestone: 25, goal: 8000),
          "Great start! You've completed 25% of today's step goal.");
      expect(milestoneMessage(milestone: 50, goal: 8000),
          "Halfway there! You've completed 50% of today's step goal.");
      expect(milestoneMessage(milestone: 75, goal: 8000),
          "Almost there! 75% of today's step goal is complete.");
      expect(milestoneMessage(milestone: 100, goal: 8000),
          "Daily goal completed 🎉 You've reached 8,000 steps today.");
    });
  });

  group('hardware sensor baseline', () {
    const today = '2026-07-30';

    test('the first ever read credits 0, never the whole since-boot total', () {
      // The chip may have been counting for days. Crediting 40,000 steps to
      // "today" because the app was just installed is the single worst thing
      // this math can do.
      final d = computeSensorDelta(
        previous: null,
        cumulative: 40000,
        bootTimeMillis: 1000,
        todayKey: today,
      );
      expect(d.stepsToday, 0);
      expect(d.baseline.baselineCumulative, 40000);
      expect(d.reason, 'first-read');
    });

    test('a normal walk is the difference from the baseline', () {
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: today,
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 0,
        ),
        cumulative: 40120,
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 5),
      );
      expect(d.stepsToday, 120);
      expect(d.reason, 'ok');
    });

    test('steps accumulate across reads within the same day', () {
      var baseline = const SensorBaseline(
        dayKey: today,
        baselineCumulative: 40000,
        bootTimeMillis: 1000,
        stepsAtBaseline: 0,
      );
      final first = computeSensorDelta(
        previous: baseline,
        cumulative: 40120,
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 5),
      );
      expect(first.stepsToday, 120);

      baseline = first.baseline;
      final second = computeSensorDelta(
        previous: baseline,
        cumulative: 40300,
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 10),
      );
      expect(second.stepsToday, 300, reason: 'measured from the same origin');
    });

    test('a REBOOT re-anchors and keeps the steps already earned today', () {
      // The counter restarts at 0 after a reboot. A naive subtraction would
      // report a huge negative; erasing the morning would be just as wrong.
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: today,
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 3500,
        ),
        cumulative: 12,
        bootTimeMillis: 999999999,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 30),
      );
      expect(d.stepsToday, 3500, reason: "the morning's steps survive the reboot");
      expect(d.baseline.baselineCumulative, 12);
      expect(d.reason, 'reboot-reanchor');
    });

    test('small boot-time drift is NOT mistaken for a reboot', () {
      // bootTime = wallClock - elapsedRealtime drifts a few ms per read and
      // jumps on NTP correction. Exact equality would report a phantom reboot
      // on literally every read and freeze the count.
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: today,
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 100,
        ),
        cumulative: 40200,
        bootTimeMillis: 1000 + 4200, // 4.2s of drift
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 5),
      );
      expect(d.reason, 'ok');
      expect(d.stepsToday, 300);
    });

    test('a NEW local day restarts the count from zero', () {
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: '2026-07-29',
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 8421,
        ),
        cumulative: 48421,
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(hours: 9),
      );
      expect(d.stepsToday, 0, reason: 'a new day starts at zero');
      expect(d.baseline.dayKey, today);
      expect(d.baseline.baselineCumulative, 48421);
      expect(d.reason, 'new-day');
    });

    test('a counter that goes backwards without a reboot re-anchors safely', () {
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: today,
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 250,
        ),
        cumulative: 900, // OEM firmware reset the counter
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 5),
      );
      expect(d.stepsToday, 250);
      expect(d.stepsToday, isNonNegative);
      expect(d.reason, 'counter-reset-reanchor');
    });

    test('an implausible spike is rejected rather than trusted', () {
      // 50,000 steps in five minutes is not a person.
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: today,
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 1200,
        ),
        cumulative: 90000,
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 5),
      );
      expect(d.stepsToday, 1200);
      expect(d.reason, 'implausible-jump-rejected');
    });

    test('a fast but human pace is accepted', () {
      // ~3 steps/second sustained for five minutes — a real run.
      final d = computeSensorDelta(
        previous: const SensorBaseline(
          dayKey: today,
          baselineCumulative: 40000,
          bootTimeMillis: 1000,
          stepsAtBaseline: 0,
        ),
        cumulative: 40900,
        bootTimeMillis: 1000,
        todayKey: today,
        elapsedSincePreviousRead: const Duration(minutes: 5),
      );
      expect(d.stepsToday, 900);
      expect(d.reason, 'ok');
    });

    test('baselines survive a serialize/deserialize round trip', () {
      const original = SensorBaseline(
        dayKey: today,
        baselineCumulative: 40000,
        bootTimeMillis: 1234567,
        stepsAtBaseline: 321,
      );
      final restored = SensorBaseline.fromMap(original.toMap())!;
      expect(restored.dayKey, original.dayKey);
      expect(restored.baselineCumulative, original.baselineCumulative);
      expect(restored.bootTimeMillis, original.bootTimeMillis);
      expect(restored.stepsAtBaseline, original.stepsAtBaseline);
    });

    test('corrupt stored state is rejected instead of crashing', () {
      expect(SensorBaseline.fromMap(null), isNull);
      expect(SensorBaseline.fromMap({'dayKey': 5}), isNull);
      expect(SensorBaseline.fromMap({'dayKey': '2026-07-30'}), isNull);
    });
  });
}
