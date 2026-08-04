/// One entry inside `WorkoutStorage.workoutModifications["<dayIndex>"]`.
/// Field names match `buildEffectiveWorkoutPlan()` in
/// `frontend/pages/dashboard/weekly-plan/weekly-plan.js` /
/// `training/day.js` exactly — this is the same shape documented in
/// CLAUDE.md's "Workout Modification System" section.
class ExpertWorkoutModification {
  const ExpertWorkoutModification({
    this.modified = true,
    this.modifiedBy,
    this.modifiedAt,
    this.oldWorkout,
    this.newWorkout,
  });

  final bool modified;
  final String? modifiedBy;
  final String? modifiedAt;

  /// `{focus, duration_minutes, exercises}` snapshots — not full
  /// `WorkoutDay` objects.
  final Map<String, dynamic>? oldWorkout;
  final Map<String, dynamic>? newWorkout;

  factory ExpertWorkoutModification.fromMap(Map<String, dynamic> m) {
    return ExpertWorkoutModification(
      modified: m['modified'] != false,
      modifiedBy: m['modifiedBy'] as String?,
      modifiedAt: m['modifiedAt'] as String?,
      oldWorkout: (m['oldWorkout'] as Map?)?.cast<String, dynamic>(),
      newWorkout: (m['newWorkout'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'modified': modified,
      if (modifiedBy != null) 'modifiedBy': modifiedBy,
      if (modifiedAt != null) 'modifiedAt': modifiedAt,
      if (oldWorkout != null) 'oldWorkout': oldWorkout,
      if (newWorkout != null) 'newWorkout': newWorkout,
    };
  }
}
