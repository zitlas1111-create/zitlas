import '../../../core/util/json_coerce.dart';
import 'workout_day.dart';

/// The `{weekly_plan: [...]}` shape — what `originalWorkoutPlan`/
/// `currentWorkoutPlan` each hold, and the exact shape the backend's
/// `POST /api/assessment/generate-plan` response returns under
/// `workout_plan` (confirmed field-for-field against
/// `backend/routes/assessment.py`'s JSON schema, no client-side reshaping).
class WorkoutPlanContent {
  const WorkoutPlanContent({
    this.planName,
    this.weeklyFrequency,
    this.days = const [],
    this.weeklyCalorieBurnEst,
    this.summary,
    this.weeklyTrainingVolumeSets,
    this.trainingSplit,
  });

  final String? planName;
  final String? weeklyFrequency;
  final List<WorkoutDay> days;
  final num? weeklyCalorieBurnEst;
  final String? summary;

  /// Muscle-gain/transformation-only fields — the backend includes these in
  /// the `workout_plan` response for those two goals, but neither
  /// `weekly-plan.js` nor `training/day.js` (the persisted Training pages)
  /// ever reads them; only the Assessment wizard's own plan-preview screen
  /// (`renderWorkout()` in `ai-coach.js`) does. Kept here (not on a
  /// duplicate model) so both surfaces share one schema; harmless `null` for
  /// every other goal type.
  final num? weeklyTrainingVolumeSets;
  final String? trainingSplit;

  bool get hasDays => days.isNotEmpty;

  /// `normalizeWeeklyPlan(wp)` on the website tolerates `weekly_plan`,
  /// `days`, `weekly_schedule`, or `workout_days` as the array key — all
  /// four are checked here for the same tolerance.
  /// Tolerant against LLM type drift throughout — see `WorkoutExercise`'s
  /// class doc for why the documented JSON schema isn't an enforced contract.
  factory WorkoutPlanContent.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const WorkoutPlanContent();
    final rawDays =
        m['weekly_plan'] ?? m['days'] ?? m['weekly_schedule'] ?? m['workout_days'];
    return WorkoutPlanContent(
      planName: asText(m['plan_name']),
      weeklyFrequency: asText(m['weekly_frequency']),
      days: asMapList(rawDays).map(WorkoutDay.fromMap).toList(),
      weeklyCalorieBurnEst: asNum(m['weekly_calorie_burn_est']),
      summary: asText(m['summary']),
      weeklyTrainingVolumeSets: asNum(m['weekly_training_volume_sets']),
      trainingSplit: asText(m['training_split']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (planName != null) 'plan_name': planName,
      if (weeklyFrequency != null) 'weekly_frequency': weeklyFrequency,
      'weekly_plan': days.map((d) => d.toMap()).toList(),
      if (weeklyCalorieBurnEst != null) 'weekly_calorie_burn_est': weeklyCalorieBurnEst,
      if (summary != null) 'summary': summary,
      if (weeklyTrainingVolumeSets != null) 'weekly_training_volume_sets': weeklyTrainingVolumeSets,
      if (trainingSplit != null) 'training_split': trainingSplit,
    };
  }

  WorkoutPlanContent copyWithDays(List<WorkoutDay> days) {
    return WorkoutPlanContent(
      planName: planName,
      weeklyFrequency: weeklyFrequency,
      days: days,
      weeklyCalorieBurnEst: weeklyCalorieBurnEst,
      summary: summary,
      weeklyTrainingVolumeSets: weeklyTrainingVolumeSets,
      trainingSplit: trainingSplit,
    );
  }
}
