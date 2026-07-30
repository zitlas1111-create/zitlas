import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/workout/models/workout_day.dart';
import 'package:zitlas_mobile/features/workout/models/workout_exercise.dart';
import 'package:zitlas_mobile/features/workout/models/workout_plan_content.dart';

/// Regression tests for the physical-device crash:
///
///   type 'String' is not a subtype of type 'num?' in type cast
///   at WorkoutExercise.fromMap (workout_exercise.dart:35)
///
/// `sets` was typed `num?` from the backend's *prompt* schema
/// (`"sets": number` in assessment.py), but that schema is only an
/// instruction to the LLM — not an enforced contract. Production genuinely
/// contains BOTH shapes:
///   • `sets: 3`   — the expert editor writes ints (modify-workout.js:139
///                   `sets: sets ? parseInt(sets) : 0`), and the LLM often
///                   obeys the prompt.
///   • `sets: "3"` / `"3-4"` / `"AMRAP"` — raw LLM output that doesn't.
///
/// Every website render site treats it as an opaque display value
/// (`String(ex.sets)` at day.js:472/549/1023, `String(ex.sets || '')` at
/// weekly-plan.js:538, `ex.sets + ' sets · '` at ai-coach.js:2064) and never
/// does arithmetic on it — so JS's dynamic typing absorbed the variance and
/// the website never broke.
void main() {
  group('WorkoutExercise.fromMap — the exact crashing shape', () {
    test('sets as a String no longer throws (the reported crash)', () {
      // This is the shape that crashed on-device.
      expect(
        () => WorkoutExercise.fromMap(const {
          'name': 'Barbell Squat',
          'sets': '3',
          'reps_or_duration': '12 reps',
          'rest_seconds': 60,
          'tip': 'Keep your chest up.',
        }),
        returnsNormally,
      );
    });

    test('sets as a String is preserved verbatim for display', () {
      final ex = WorkoutExercise.fromMap(const {'name': 'Squat', 'sets': '3'});
      expect(ex.sets, '3');
    });

    test('sets as an int renders identically to the string form', () {
      final asInt = WorkoutExercise.fromMap(const {'name': 'Squat', 'sets': 3});
      final asStr = WorkoutExercise.fromMap(const {'name': 'Squat', 'sets': '3'});
      expect(asInt.sets, asStr.sets);
      expect(asInt.sets, '3');
    });

    test('semantic set values survive intact — never coerced to a number', () {
      for (final raw in ['3-4', 'AMRAP', 'To failure', '3 x 12']) {
        final ex = WorkoutExercise.fromMap({'name': 'X', 'sets': raw});
        expect(ex.sets, raw, reason: 'semantic value "$raw" must not be destroyed');
      }
    });

    test('rest_seconds tolerates both number and string forms', () {
      expect(WorkoutExercise.fromMap(const {'name': 'X', 'rest_seconds': 60}).restSeconds, '60');
      expect(WorkoutExercise.fromMap(const {'name': 'X', 'rest_seconds': '60'}).restSeconds, '60');
      expect(WorkoutExercise.fromMap(const {'name': 'X', 'rest_seconds': '60 sec'}).restSeconds, '60 sec');
    });

    test('a double set count does not render a trailing .0', () {
      // Some LLM responses emit 3.0 rather than 3.
      expect(WorkoutExercise.fromMap(const {'name': 'X', 'sets': 3.0}).sets, '3');
    });

    test('null and missing optional fields stay null', () {
      final missing = WorkoutExercise.fromMap(const {'name': 'X'});
      expect(missing.sets, isNull);
      expect(missing.restSeconds, isNull);
      expect(missing.repsOrDuration, isNull);
      expect(missing.tip, isNull);
      expect(missing.progression, isNull);

      final explicitNulls = WorkoutExercise.fromMap(const {
        'name': 'X',
        'sets': null,
        'rest_seconds': null,
        'reps_or_duration': null,
      });
      expect(explicitNulls.sets, isNull);
      expect(explicitNulls.restSeconds, isNull);
      expect(explicitNulls.repsOrDuration, isNull);
    });

    test('reps_or_duration tolerates a bare number (LLM sometimes emits 12)', () {
      expect(WorkoutExercise.fromMap(const {'name': 'X', 'reps_or_duration': 12}).repsOrDuration, '12');
    });

    test('tip falls back to notes (expert-editor field name)', () {
      expect(WorkoutExercise.fromMap(const {'name': 'X', 'notes': 'from expert'}).tip, 'from expert');
      expect(
        WorkoutExercise.fromMap(const {'name': 'X', 'tip': 'ai', 'notes': 'expert'}).tip,
        'ai',
        reason: 'tip wins when both present, matching the website',
      );
    });

    test('toMap round-trips numeric sets back as a number, not a string', () {
      // modify-workout.js stores ints; writing "3" back where 3 was read
      // would drift the stored type for the expert dashboard.
      final fromInt = WorkoutExercise.fromMap(const {'name': 'X', 'sets': 3, 'rest_seconds': 60});
      expect(fromInt.toMap()['sets'], 3);
      expect(fromInt.toMap()['rest_seconds'], 60);

      // ...but a semantic string must be written back unchanged.
      final fromSemantic = WorkoutExercise.fromMap(const {'name': 'X', 'sets': '3-4'});
      expect(fromSemantic.toMap()['sets'], '3-4');
    });
  });

  group('WorkoutDay.fromMap — tolerant of the same variance', () {
    test('parses a full day whose exercises use mixed sets types', () {
      final day = WorkoutDay.fromMap(const {
        'day': 'Monday',
        'type': 'Workout',
        'focus': 'Upper Body + Core',
        'duration_minutes': 45,
        'calories_burned_est': 320,
        'daily_tip': 'Warm up first.',
        'exercises': [
          {'name': 'Push-ups', 'sets': 3, 'reps_or_duration': '12 reps', 'rest_seconds': 45},
          {'name': 'Plank', 'sets': '3', 'reps_or_duration': '30 sec', 'rest_seconds': '30'},
          {'name': 'Burpees', 'sets': 'AMRAP', 'reps_or_duration': '60 sec'},
        ],
      });

      expect(day.exercises, hasLength(3));
      expect(day.exercises[0].sets, '3');
      expect(day.exercises[1].sets, '3');
      expect(day.exercises[2].sets, 'AMRAP');
      expect(day.durationMinutes, 45);
      expect(day.isRest, isFalse);
    });

    test('duration_minutes tolerates string forms (used in arithmetic)', () {
      expect(WorkoutDay.fromMap(const {'day': 'Mon', 'duration_minutes': '45'}).durationMinutes, 45);
      // The website coerces via parseInt(String(x).replace(/[^0-9]/g,'')) —
      // see weekly-plan.js:717-721 totalMin reduce.
      expect(WorkoutDay.fromMap(const {'day': 'Mon', 'duration_minutes': '45 min'}).durationMinutes, 45);
      expect(WorkoutDay.fromMap(const {'day': 'Mon', 'duration_minutes': 'unknown'}).durationMinutes, isNull);
    });

    test('missing / null / non-list exercises degrade to empty, not a crash', () {
      expect(WorkoutDay.fromMap(const {'day': 'Mon'}).exercises, isEmpty);
      expect(WorkoutDay.fromMap(const {'day': 'Mon', 'exercises': null}).exercises, isEmpty);
      expect(WorkoutDay.fromMap(const {'day': 'Mon', 'exercises': 'none'}).exercises, isEmpty);
    });

    test('non-map entries inside exercises are skipped, not fatal', () {
      final day = WorkoutDay.fromMap(const {
        'day': 'Mon',
        'exercises': [
          {'name': 'Valid'},
          'garbage',
          null,
        ],
      });
      expect(day.exercises, hasLength(1));
      expect(day.exercises.single.name, 'Valid');
    });

    test('rest day detection still works across type/focus', () {
      expect(WorkoutDay.fromMap(const {'day': 'Sun', 'type': 'Rest'}).isRest, isTrue);
      expect(WorkoutDay.fromMap(const {'day': 'Sun', 'type': 'Active Recovery'}).isRest, isTrue);
    });
  });

  group('WorkoutPlanContent.fromMap — full generate-plan response shape', () {
    test('parses a realistic 7-day response with mixed numeric types', () {
      final plan = WorkoutPlanContent.fromMap(const {
        'plan_name': '7-Day Fat Loss Plan',
        'fitness_level': 'Beginner',
        'weekly_frequency': '5 days/week',
        'weekly_calorie_burn_est': '1600',
        'summary': 'Built for your schedule.',
        'weekly_plan': [
          {
            'day': 'Monday',
            'type': 'Workout',
            'focus': 'Cardio + Lower Body',
            'duration_minutes': 30,
            'calories_burned_est': 250,
            'exercises': [
              {'name': 'Squats', 'sets': '3', 'reps_or_duration': '15 reps', 'rest_seconds': 45},
            ],
            'daily_tip': 'Hydrate.',
          },
          {'day': 'Tuesday', 'type': 'Rest', 'focus': 'Recovery', 'exercises': []},
        ],
      });

      expect(plan.planName, '7-Day Fat Loss Plan');
      expect(plan.days, hasLength(2));
      expect(plan.weeklyCalorieBurnEst, 1600); // string coerced for arithmetic
      expect(plan.days[0].exercises.single.sets, '3');
      expect(plan.days[1].isRest, isTrue);
    });

    test('muscle-gain/transformation-only fields tolerate string forms', () {
      final plan = WorkoutPlanContent.fromMap(const {
        'weekly_training_volume_sets': '84',
        'training_split': 'Push / Pull / Legs',
        'weekly_plan': [
          {'day': 'Mon', 'sets_volume_est': '12', 'exercises': []},
        ],
      });
      expect(plan.weeklyTrainingVolumeSets, 84);
      expect(plan.trainingSplit, 'Push / Pull / Legs');
      expect(plan.days.single.setsVolumeEst, 12);
    });

    test('all four array-key aliases are still honoured', () {
      for (final key in ['weekly_plan', 'days', 'weekly_schedule', 'workout_days']) {
        final plan = WorkoutPlanContent.fromMap({
          key: [
            {'day': 'Mon', 'exercises': []},
          ],
        });
        expect(plan.days, hasLength(1), reason: 'alias "$key" must still parse');
      }
    });
  });
}
