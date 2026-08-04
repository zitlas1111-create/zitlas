import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/assessment/data/assessment_repository.dart';

/// Orchestration regression tests.
///
/// The reported bug surfaced as `[ASSESSMENT] generate-plan FAILED`, implying
/// the whole assessment had failed — but the backend had actually succeeded:
/// only one field inside the workout tree was the wrong JSON type. Because
/// all four response sections were parsed in a single expression, that one
/// bad field discarded the completed assessment, the calculations and the
/// SWOT along with it.
///
/// `AssessmentResult.fromMap` now mirrors the backend's own isolation
/// (`routes/assessment.py` wraps the diet and workout LLM steps in separate
/// `try/except` and can legitimately return either as `null`).
void main() {
  // The minimum viable 200 response: run_assessment() always produces these.
  const calculations = {
    'bmi': 29.4,
    'bmi_category': 'Overweight',
    'bmr_kcal': 1859,
    'tdee_kcal': 2231,
    'weight_loss_calories_kcal': 1731,
    'calorie_deficit_kcal': 500,
    'protein_target_g': 150,
    'water_target_liters': 3.2,
    'daily_steps_goal': 7000,
    'weight_to_lose_kg': 15.0,
    'estimated_weeks_to_goal': 30,
    'estimated_months_to_goal': 6.9,
  };

  const swot = {
    'user_archetype': 'The Busy Professional',
    'summary': 'Solid foundation, inconsistent execution.',
    'priority_action': 'Lock in a fixed dinner time.',
    'scores': {
      'nutrition': 55,
      'activity': 40,
      'sleep': 60,
      'habits': 45,
      'mindset': 70,
      'consistency': 50,
    },
    'swot': {
      'strengths': [
        {'title': 'Strong motivation', 'detail': 'You committed to a 90-day goal.'},
      ],
      'weaknesses': [
        {'title': 'Sedentary job'},
      ],
      'opportunities': [],
      'threads': [],
    },
  };

  group('AssessmentResult.fromMap — section fault isolation', () {
    test('the reported crash shape: a bad workout tree no longer kills the assessment', () {
      // `sets: "3"` is the exact value that threw
      // `type 'String' is not a subtype of type 'num?'` on-device.
      final result = AssessmentResult.fromMap({
        'assessment': const {'age': 28, 'gender': 'male'},
        'calculations': calculations,
        'swot': swot,
        'diet_plan': const {
          'plan_name': 'Diet',
          'days': [
            {'day': 'Monday', 'meals': []},
          ],
        },
        'workout_plan': const {
          'plan_name': 'Workout',
          'weekly_plan': [
            {
              'day': 'Monday',
              'exercises': [
                {'name': 'Squat', 'sets': '3', 'reps_or_duration': '12 reps'},
              ],
            },
          ],
        },
        'precautions': const [],
      });

      // Everything survives, and the workout now parses rather than throwing.
      expect(result.calculations.bmi, 29.4);
      expect(result.swot.userArchetype, 'The Busy Professional');
      expect(result.dietPlan, isNotNull);
      expect(result.workoutPlan, isNotNull);
      expect(result.workoutPlan!.days.single.exercises.single.sets, '3');
    });

    test('a genuinely unparseable workout section keeps assessment/calc/swot/diet', () {
      // `weekly_plan` as a bare string is not recoverable into days, but it
      // must not cost the athlete the rest of the result.
      final result = AssessmentResult.fromMap({
        'assessment': const {'age': 28},
        'calculations': calculations,
        'swot': swot,
        'diet_plan': const {'plan_name': 'Diet', 'days': [{'day': 'Mon', 'meals': []}]},
        'workout_plan': 'totally not an object',
      });

      expect(result.calculations.calorieTargetKcal, 1731);
      expect(result.swot.summary, isNotEmpty);
      expect(result.dietPlan, isNotNull);
      expect(result.workoutPlan, isNull, reason: 'unparseable section degrades to absent');
    });

    test('backend-side null plans (LLM step failed server-side) are normal', () {
      final result = AssessmentResult.fromMap({
        'assessment': const {},
        'calculations': calculations,
        'swot': swot,
        'diet_plan': null,
        'workout_plan': null,
      });
      expect(result.dietPlan, isNull);
      expect(result.workoutPlan, isNull);
      expect(result.calculations.bmi, 29.4);
    });

    test('a missing calculations/swot IS a hard failure, reported clearly', () {
      // These come from pure Python arithmetic — absent in a 200 means the
      // response is genuinely malformed, so it must not be silently defaulted.
      expect(
        () => AssessmentResult.fromMap({'swot': swot}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AssessmentResult.fromMap({'calculations': calculations}),
        throwsA(isA<FormatException>()),
      );
    });

    test('precautions/medical labels tolerate absent or non-list values', () {
      final result = AssessmentResult.fromMap({
        'calculations': calculations,
        'swot': swot,
        'precautions': 'not a list',
      });
      expect(result.precautions, isEmpty);
      expect(result.medicalConditionsDetected, isEmpty);
    });
  });
}
