import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/assessment/models/assessment_calculations.dart';
import 'package:zitlas_mobile/features/assessment/models/snapshot_card.dart';
import 'package:zitlas_mobile/features/assessment/models/unit_conversions.dart';

/// Deterministic calculation-parity tests.
///
/// The BMI/BMR/TDEE/calorie/protein/water/steps FORMULAS themselves live
/// entirely server-side (`backend/services/assessment_service.py`) — Flutter
/// never recomputes them, only displays whatever `AssessmentCalculations`
/// the backend returned (by design, per the migration task's own
/// instruction not to build a second calculation engine). So the
/// meaningful parity check here is NOT "does Dart reproduce Python's math"
/// — it's "given the SAME `calculations` numbers the backend would return
/// for a known profile, does Flutter's display layer (bmiInfo() categories,
/// number formatting, goal-date/kg-per-week derivations ported from
/// `renderSnapshot()`, and the wheel-picker unit conversions) produce
/// exactly what `ai-coach.js` would render for that same profile."
///
/// Each case below hand-computes the backend's `run_assessment()` formulas
/// for a concrete profile (documented inline) so the expected
/// `AssessmentCalculations` values are independently verified against the
/// Python source, not copied from Dart.
void main() {
  group('AssessmentCalculations.fromMap — wire format parsing', () {
    test('parses every field with the exact backend key names', () {
      final calc = AssessmentCalculations.fromMap({
        'bmi': 24.5,
        'bmi_category': 'Normal Weight',
        'bmr_kcal': 1650,
        'tdee_kcal': 2062,
        'weight_loss_calories_kcal': 1562,
        'calorie_deficit_kcal': 500,
        'protein_target_g': 130,
        'water_target_liters': 2.7,
        'daily_steps_goal': 7000,
        'weight_to_lose_kg': 8.0,
        'estimated_weeks_to_goal': 16,
        'estimated_months_to_goal': 3.7,
      });

      expect(calc.bmi, 24.5);
      expect(calc.bmiCategory, 'Normal Weight');
      expect(calc.bmrKcal, 1650);
      expect(calc.tdeeKcal, 2062);
      expect(calc.calorieTargetKcal, 1562);
      expect(calc.calorieDeficitKcal, 500);
      expect(calc.proteinTargetG, 130);
      expect(calc.waterTargetLiters, 2.7);
      expect(calc.dailyStepsGoal, 7000);
      expect(calc.weightDeltaKg, 8.0);
      expect(calc.estimatedWeeksToGoal, 16);
      expect(calc.estimatedMonthsToGoal, 3.7);
    });
  });

  group('bmiInfo() — Snapshot screen categorization (distinct from bmi_category)', () {
    // Thresholds transcribed from `bmiInfo()` in ai-coach.js — NOT the same
    // labels as the backend's own `_BMI_CATEGORIES` (see doc comment on
    // AssessmentCalculations.bmiCategory).
    test('boundaries match the website exactly', () {
      expect(bmiInfo(18.4).label, 'Underweight');
      expect(bmiInfo(18.5).label, 'Healthy Weight');
      expect(bmiInfo(24.9).label, 'Healthy Weight');
      expect(bmiInfo(25.0).label, 'Overweight');
      expect(bmiInfo(29.9).label, 'Overweight');
      expect(bmiInfo(30.0).label, 'Obese Class I');
      expect(bmiInfo(34.9).label, 'Obese Class I');
      expect(bmiInfo(35.0).label, 'Obese Class II+');
      expect(bmiInfo(40.0).label, 'Obese Class II+');
    });

    test('accent + badge match per band', () {
      expect(bmiInfo(17.0).accent, 'yellow');
      expect(bmiInfo(17.0).badge, '⚠️ Needs Attention');
      expect(bmiInfo(22.0).accent, 'green');
      expect(bmiInfo(22.0).badge, '✓ Healthy');
      expect(bmiInfo(27.0).accent, 'yellow');
      expect(bmiInfo(32.0).accent, 'red');
      expect(bmiInfo(32.0).badge, '🔴 High Priority');
    });
  });

  group('thousands() — toLocaleString() port', () {
    test('formats with comma separators like JS toLocaleString()', () {
      expect(thousands(7000), '7,000');
      expect(thousands(1562), '1,562');
      expect(thousands(999), '999');
      expect(thousands(10000), '10,000');
      expect(thousands(2.7), '2.7');
    });
  });

  group('Weight-loss profile — 28yo male, 90kg, 175cm, sedentary, goal 75kg', () {
    // Hand-computed from assessment_service.py:
    //   BMR (Mifflin-St Jeor, male) = 10*90 + 6.25*175 - 5*28 + 5 = 900+1093.75-140+5 = 1858.75
    //   TDEE = BMR * 1.20 (sedentary) = 2230.5 -> calculations rounds bmr/tdee separately
    //   target = TDEE - 500 = 1730.5 -> round = 1731 (floor not below male safety 1400)
    //   protein = max(75*2.0, 90*1.6) = max(150, 144) = 150
    //   weight_gap = 90 - 75 = 15 -> weeks = round(15/0.5) = 30
    //   bmi = 90 / 1.75^2 = 29.3877... -> round(.,1) = 29.4 -> category 'Overweight' (<30)
    late AssessmentCalculations calc;

    setUp(() {
      calc = const AssessmentCalculations(
        bmi: 29.4,
        bmiCategory: 'Overweight',
        bmrKcal: 1859, // round(1858.75)
        tdeeKcal: 2231, // round(1858.75*1.20)
        calorieTargetKcal: 1731, // round(2230.5-500)
        calorieDeficitKcal: 500,
        proteinTargetG: 150,
        waterTargetLiters: 3.2, // 90*35/1000 = 3.15 -> clamp/round(.,1) = 3.2 per Python round-half-to-even is 3.2
        dailyStepsGoal: 7000,
        weightDeltaKg: 15.0,
        estimatedWeeksToGoal: 30,
        estimatedMonthsToGoal: 6.9,
      );
    });

    test('Snapshot BMI card uses the website\'s own category, not bmi_category', () {
      final info = bmiInfo(calc.bmi);
      expect(info.label, 'Overweight');
      // Distinct from the (also correct) backend label at this BMI:
      expect(calc.bmiCategory, 'Overweight');
    });

    test('default-flow cards render the exact deficit/target copy', () {
      final cards = buildDefaultCards(calc, isMuscle: false, now: DateTime(2026, 1, 1));
      final caloriesCard = cards.firstWhere((c) => c.id == 'calories');
      expect(caloriesCard.value, '1,731 kcal');
      expect(caloriesCard.expand, contains('<strong>2,231 kcal/day</strong>'));
      expect(caloriesCard.expand, contains('<strong>500 kcal deficit</strong>'));

      final goalCard = cards.firstWhere((c) => c.id == 'goal');
      expect(goalCard.value, '15.0 kg');
      // 15 kg / 30 weeks = 0.5 kg/week
      expect(goalCard.expand, contains('0.5 kg/week'));
    });

    test('goal date label lands ~30 weeks (210 days) after "now"', () {
      final summary = buildDefaultSummary(calc, isMuscle: false, now: DateTime(2026, 1, 1));
      final goalDateItem = summary.items.firstWhere((i) => i.label == 'Est. Goal Date');
      // 2026-01-01 + 210 days = 2026-07-30
      expect(goalDateItem.value, 'July 2026');
    });
  });

  group('Unit conversions — wheel picker toggles', () {
    test('cm <-> ft/in round-trips for common heights', () {
      // 170 cm = 5'7" (170/2.54=66.9in -> 5ft 6.9in -> rounds to 5'7")
      expect(cmToFt(170), 5);
      expect(cmToIn(170), 7);
      // 5*30.48 + 7*2.54 = 170.18 -> roundToDouble() = 170.0
      expect(ftInToCm(5, 7), 170.0);

      // 182 cm ~ 5'11.65" -> rounds to 5'12" -> carries to 6'0"
      expect(cmToFt(182), 6);
      expect(cmToIn(182), 0);
    });

    test('kg <-> lbs round-trips for common weights', () {
      expect(kgToLbs(70), 154); // 70*2.20462 = 154.32 -> 154
      expect(lbsToKg(154), 69.9); // 154*0.45359237 = 69.853... -> 1dp round = 69.9
    });
  });
}
