/// Mirrors `users/{uid}.calculations` (`zitlas_calculations` on web) —
/// computed entirely server-side by `assessment_service.run_assessment()`,
/// never recalculated client-side. Field names are exact (note
/// `weight_loss_calories_kcal` holds the calorie TARGET regardless of goal
/// type — deficit for weight loss, surplus for muscle gain, maintenance
/// TDEE for general fitness — and `water_target_liters` is liters, not ml).
class DietCalculations {
  const DietCalculations({
    this.bmi,
    this.bmiCategory,
    this.bmrKcal,
    this.tdeeKcal,
    this.calorieTargetKcal,
    this.calorieDeficitKcal,
    this.proteinTargetG,
    this.waterTargetLiters,
    this.dailyStepsGoal,
  });

  final num? bmi;
  final String? bmiCategory;
  final num? bmrKcal;
  final num? tdeeKcal;

  /// `weight_loss_calories_kcal` on the wire — the actual daily calorie
  /// target regardless of goal type.
  final num? calorieTargetKcal;
  final num? calorieDeficitKcal;
  final num? proteinTargetG;
  final num? waterTargetLiters;
  final num? dailyStepsGoal;

  factory DietCalculations.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DietCalculations();
    return DietCalculations(
      bmi: m['bmi'] as num?,
      bmiCategory: m['bmi_category'] as String?,
      bmrKcal: m['bmr_kcal'] as num?,
      tdeeKcal: m['tdee_kcal'] as num?,
      calorieTargetKcal: m['weight_loss_calories_kcal'] as num?,
      calorieDeficitKcal: m['calorie_deficit_kcal'] as num?,
      proteinTargetG: m['protein_target_g'] as num?,
      waterTargetLiters: m['water_target_liters'] as num?,
      dailyStepsGoal: m['daily_steps_goal'] as num?,
    );
  }
}
