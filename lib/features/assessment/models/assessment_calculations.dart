/// `calculations` in the `/api/assessment/generate-plan` response — computed
/// entirely server-side by `assessment_service.run_assessment()`. Every
/// field name and rounding rule matches `backend/services/assessment_service.py`
/// exactly; nothing here is recomputed client-side.
class AssessmentCalculations {
  const AssessmentCalculations({
    required this.bmi,
    required this.bmiCategory,
    required this.bmrKcal,
    required this.tdeeKcal,
    required this.calorieTargetKcal,
    required this.calorieDeficitKcal,
    required this.proteinTargetG,
    required this.waterTargetLiters,
    required this.dailyStepsGoal,
    required this.weightDeltaKg,
    required this.estimatedWeeksToGoal,
    required this.estimatedMonthsToGoal,
  });

  final num bmi;

  /// `bmi_category` — the BACKEND's own categorization (Underweight/Normal
  /// Weight/Overweight/Obese Class I/II/III). NOTE: the Assessment wizard's
  /// own Snapshot screen never displays this field — it recomputes its own
  /// categorization via `bmiInfo()` (see `snapshot_card.dart`), which uses
  /// different category labels (Healthy Weight/Obese Class II+, no
  /// Class III). Both are reproduced faithfully; this field is kept for
  /// completeness/other consumers, not fed into the Snapshot cards.
  final String bmiCategory;
  final num bmrKcal;
  final num tdeeKcal;

  /// `weight_loss_calories_kcal` on the wire — holds a SURPLUS for
  /// muscle_gain, a mild deficit for transformation, maintenance for
  /// general_fitness, and a deficit for weight_loss. Same field name
  /// regardless of goal (not renamed per-goal by the backend).
  final num calorieTargetKcal;
  final num calorieDeficitKcal;
  final num proteinTargetG;
  final num waterTargetLiters;
  final num dailyStepsGoal;

  /// `weight_to_lose_kg` — kg to lose (weight_loss) or gain (muscle_gain);
  /// `0` for general_fitness/transformation (recomposition, scale doesn't move).
  final num weightDeltaKg;

  /// `0` for general_fitness (no timeline — the UI hardcodes "8–12 Weeks").
  final num estimatedWeeksToGoal;
  final num estimatedMonthsToGoal;

  factory AssessmentCalculations.fromMap(Map<String, dynamic> m) {
    return AssessmentCalculations(
      bmi: (m['bmi'] as num?) ?? 0,
      bmiCategory: (m['bmi_category'] as String?) ?? '',
      bmrKcal: (m['bmr_kcal'] as num?) ?? 0,
      tdeeKcal: (m['tdee_kcal'] as num?) ?? 0,
      calorieTargetKcal: (m['weight_loss_calories_kcal'] as num?) ?? 0,
      calorieDeficitKcal: (m['calorie_deficit_kcal'] as num?) ?? 0,
      proteinTargetG: (m['protein_target_g'] as num?) ?? 0,
      waterTargetLiters: (m['water_target_liters'] as num?) ?? 0,
      dailyStepsGoal: (m['daily_steps_goal'] as num?) ?? 0,
      weightDeltaKg: (m['weight_to_lose_kg'] as num?) ?? 0,
      estimatedWeeksToGoal: (m['estimated_weeks_to_goal'] as num?) ?? 0,
      estimatedMonthsToGoal: (m['estimated_months_to_goal'] as num?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bmi': bmi,
      'bmi_category': bmiCategory,
      'bmr_kcal': bmrKcal,
      'tdee_kcal': tdeeKcal,
      'weight_loss_calories_kcal': calorieTargetKcal,
      'calorie_deficit_kcal': calorieDeficitKcal,
      'protein_target_g': proteinTargetG,
      'water_target_liters': waterTargetLiters,
      'daily_steps_goal': dailyStepsGoal,
      'weight_to_lose_kg': weightDeltaKg,
      'estimated_weeks_to_goal': estimatedWeeksToGoal,
      'estimated_months_to_goal': estimatedMonthsToGoal,
    };
  }
}
