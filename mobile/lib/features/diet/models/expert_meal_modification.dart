/// One entry inside `DietStorage.expertModifications["<dayIndex>"]["<mealKey>"]`.
/// Field names match `buildEffectivePlan()`/`acceptExpertPlan()` in
/// `frontend/pages/diet/diet.js` exactly.
class ExpertMealModification {
  const ExpertMealModification({
    this.modified = true,
    this.modifiedBy,
    this.modifiedAt,
    this.oldMeal,
    this.newMeal,
  });

  final bool modified;
  final String? modifiedBy;
  final String? modifiedAt;

  /// `{foods, calories, protein_g}` snapshots — not full `DietMeal` objects.
  final Map<String, dynamic>? oldMeal;
  final Map<String, dynamic>? newMeal;

  factory ExpertMealModification.fromMap(Map<String, dynamic> m) {
    return ExpertMealModification(
      modified: m['modified'] != false,
      modifiedBy: m['modifiedBy'] as String?,
      modifiedAt: m['modifiedAt'] as String?,
      oldMeal: (m['oldMeal'] as Map?)?.cast<String, dynamic>(),
      newMeal: (m['newMeal'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'modified': modified,
      if (modifiedBy != null) 'modifiedBy': modifiedBy,
      if (modifiedAt != null) 'modifiedAt': modifiedAt,
      if (oldMeal != null) 'oldMeal': oldMeal,
      if (newMeal != null) 'newMeal': newMeal,
    };
  }
}
