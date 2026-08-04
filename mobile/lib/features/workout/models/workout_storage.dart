import '../../../core/util/json_coerce.dart';
import 'expert_workout_modification.dart';
import 'workout_day.dart';
import 'workout_exercise.dart';
import 'workout_plan_content.dart';

/// The `zitlas_workout_modifications` / `users/{uid}.workoutPlan` wrapper —
/// traced field-for-field from `weekly-plan.js` (`buildEffectiveWorkoutPlan`,
/// the goal-identity gate in `loadPlan()`) and `training/day.js`'s identical
/// gate in `loadPlanWithSource()`. Mirrors the Diet feature's `DietStorage`
/// exactly — same wrapper shape, same `planId` fail-closed semantics,
/// applied to workouts instead of meals. Documented in CLAUDE.md's "Workout
/// Modification System" section.
///
/// `workoutModifications` keys are STRING day indices (`"0"`, `"1"`, ...).
class WorkoutStorage {
  const WorkoutStorage({
    required this.originalWorkoutPlan,
    required this.currentWorkoutPlan,
    this.workoutModifications = const {},
    this.isExpertPlan = false,
    this.expertName,
    this.reviewedAt,
    this.planId,
  });

  final WorkoutPlanContent originalWorkoutPlan;
  final WorkoutPlanContent currentWorkoutPlan;
  final Map<String, ExpertWorkoutModification> workoutModifications;
  final bool isExpertPlan;
  final String? expertName;
  final String? reviewedAt;

  /// Goal-identity stamp. `TrainingController` fail-closed-validates this
  /// against the athlete's live `users/{uid}.planId` before ever rendering
  /// this wrapper — a stale plan (from before a goal reset/regeneration)
  /// must never be shown or silently kept. Exact port of `weekly-plan.js`'s
  /// (and `day.js`'s identical copy of) the goal-identity gate in `loadPlan()`.
  final String? planId;

  static bool isNewSchema(Map<String, dynamic>? m) =>
      m != null && m['originalWorkoutPlan'] != null && m['currentWorkoutPlan'] != null;

  factory WorkoutStorage.fromMap(Map<String, dynamic> m) {
    final rawMods = (m['workoutModifications'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mods = <String, ExpertWorkoutModification>{};
    rawMods.forEach((dayIdx, modRaw) {
      if (modRaw is Map) {
        mods[dayIdx] = ExpertWorkoutModification.fromMap(modRaw.cast<String, dynamic>());
      }
    });

    return WorkoutStorage(
      originalWorkoutPlan:
          WorkoutPlanContent.fromMap((m['originalWorkoutPlan'] as Map?)?.cast<String, dynamic>()),
      currentWorkoutPlan:
          WorkoutPlanContent.fromMap((m['currentWorkoutPlan'] as Map?)?.cast<String, dynamic>()),
      workoutModifications: mods,
      isExpertPlan: m['isExpertPlan'] == true,
      expertName: m['expertName'] as String?,
      reviewedAt: m['reviewedAt'] as String?,
      planId: m['planId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'originalWorkoutPlan': originalWorkoutPlan.toMap(),
      'currentWorkoutPlan': currentWorkoutPlan.toMap(),
      'workoutModifications': workoutModifications.map((k, v) => MapEntry(k, v.toMap())),
      'isExpertPlan': isExpertPlan,
      'expertName': expertName,
      'reviewedAt': reviewedAt,
      'planId': planId,
    };
  }

  /// `buildEffectiveWorkoutPlan()` (identical copy in weekly-plan.js and
  /// day.js) — deep-clones `currentWorkoutPlan` (falling back to
  /// `originalWorkoutPlan`), applies `workoutModifications` on top per day,
  /// stamping the `modified`/`modifiedBy`/`modifiedAt` render flags. This is
  /// what the Training screens actually render — never `currentWorkoutPlan`
  /// raw.
  WorkoutPlanContent buildEffectivePlan() {
    final base = currentWorkoutPlan.hasDays ? currentWorkoutPlan : originalWorkoutPlan;
    if (!base.hasDays) return base;
    if (workoutModifications.isEmpty) return base;

    final newDays = <WorkoutDay>[];
    for (var i = 0; i < base.days.length; i++) {
      final day = base.days[i];
      final mod = workoutModifications[i.toString()];
      if (mod == null || !mod.modified) {
        newDays.add(day);
        continue;
      }
      final nw = mod.newWorkout;
      // `newWorkout` is written by the expert editor (modify-workout.js) from
      // free-text form inputs, so it carries the same string/number variance
      // as the LLM tree — see WorkoutExercise's class doc.
      newDays.add(
        day.copyWith(
          focus: asText(nw?['focus']),
          type: asText(nw?['focus']),
          durationMinutes: asNum(nw?['duration_minutes']),
          exercises: nw?['exercises'] == null
              ? null
              : asMapList(nw!['exercises']).map(WorkoutExercise.fromMap).toList(),
          modified: true,
          modifiedBy: mod.modifiedBy,
          modifiedAt: mod.modifiedAt,
        ),
      );
    }
    return base.copyWithDays(newDays);
  }

  /// `_migrated`/flat-plan construction — wraps a legacy flat
  /// `{weekly_plan:[...]}` plan (pre-dating the expert modification schema)
  /// into the current wrapper shape.
  factory WorkoutStorage.fromLegacyFlatPlan(WorkoutPlanContent plan, {String? planId}) {
    return WorkoutStorage(
      originalWorkoutPlan: plan,
      currentWorkoutPlan: plan,
      planId: planId,
    );
  }

  factory WorkoutStorage.fromAiPlan(WorkoutPlanContent plan, {String? planId}) {
    return WorkoutStorage(
      originalWorkoutPlan: plan,
      currentWorkoutPlan: plan,
      isExpertPlan: false,
      planId: planId,
    );
  }

  WorkoutStorage copyWith({
    WorkoutPlanContent? currentWorkoutPlan,
    Map<String, ExpertWorkoutModification>? workoutModifications,
    bool? isExpertPlan,
    String? expertName,
    String? reviewedAt,
    String? planId,
  }) {
    return WorkoutStorage(
      originalWorkoutPlan: originalWorkoutPlan,
      currentWorkoutPlan: currentWorkoutPlan ?? this.currentWorkoutPlan,
      workoutModifications: workoutModifications ?? this.workoutModifications,
      isExpertPlan: isExpertPlan ?? this.isExpertPlan,
      expertName: expertName ?? this.expertName,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      planId: planId ?? this.planId,
    );
  }
}
