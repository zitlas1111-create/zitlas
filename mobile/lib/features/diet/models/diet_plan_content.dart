import '../../../core/util/json_coerce.dart';
import 'diet_day.dart';

/// The `{days: [...]}` plan content — what `originalDietPlan`/
/// `currentDietPlan` each hold, and the exact shape the backend's
/// `POST /api/assessment/generate-plan` response returns under
/// `diet_plan` (confirmed field-for-field against
/// `backend/routes/assessment.py`'s response, no client-side reshaping).
class DietPlanContent {
  const DietPlanContent({
    this.planName,
    this.dailyCaloriesTarget,
    this.dailyProteinTargetG,
    this.days = const [],
    this.keyRules = const [],
    this.summary,
  });

  final String? planName;
  final num? dailyCaloriesTarget;
  final num? dailyProteinTargetG;
  final List<DietDay> days;
  final List<String> keyRules;
  final String? summary;

  bool get hasDays => days.isNotEmpty;

  factory DietPlanContent.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DietPlanContent();
    final rawDays = m['days'];
    return DietPlanContent(
      planName: asText(m['plan_name']),
      dailyCaloriesTarget: asNum(m['daily_calories_target']),
      dailyProteinTargetG: asNum(m['daily_protein_target_g']),
      days: asMapList(rawDays).map(DietDay.fromMap).toList(),
      keyRules: asStringList(m['key_rules']),
      summary: asText(m['summary']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (planName != null) 'plan_name': planName,
      if (dailyCaloriesTarget != null) 'daily_calories_target': dailyCaloriesTarget,
      if (dailyProteinTargetG != null) 'daily_protein_target_g': dailyProteinTargetG,
      'days': days.map((d) => d.toMap()).toList(),
      if (keyRules.isNotEmpty) 'key_rules': keyRules,
      if (summary != null) 'summary': summary,
    };
  }

  DietPlanContent copyWithDays(List<DietDay> days) {
    return DietPlanContent(
      planName: planName,
      dailyCaloriesTarget: dailyCaloriesTarget,
      dailyProteinTargetG: dailyProteinTargetG,
      days: days,
      keyRules: keyRules,
      summary: summary,
    );
  }
}
