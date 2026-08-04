import '../../../core/util/json_coerce.dart';
import 'workout_exercise.dart';

/// A single day inside `WorkoutPlanContent.days` — mirrors one entry of
/// `weekly_plan[]`. `day.js`'s `renderFitnessDay()` reads both `type` and
/// `focus`; an expert modification (`newWorkout.focus`) sets both fields
/// together (`buildEffectiveWorkoutPlan()`: `day.focus = nw.focus; day.type
/// = nw.focus;`), so both are kept here rather than collapsed to one.
class WorkoutDay {
  const WorkoutDay({
    required this.day,
    this.type,
    this.focus,
    this.durationMinutes,
    this.caloriesBurnedEst,
    this.dailyTip,
    this.exercises = const [],
    this.modified = false,
    this.modifiedBy,
    this.modifiedAt,
    this.edited = false,
    this.setsVolumeEst,
  });

  /// e.g. "Monday".
  final String day;
  final String? type;
  final String? focus;
  final num? durationMinutes;
  final num? caloriesBurnedEst;
  final String? dailyTip;
  final List<WorkoutExercise> exercises;

  /// Muscle-gain/transformation-only — see `WorkoutPlanContent`'s doc
  /// comment on `weeklyTrainingVolumeSets`. Only the Assessment preview
  /// screen reads this.
  final num? setsVolumeEst;

  /// Set by `buildEffectiveWorkoutPlan()` when an `workoutModifications`
  /// entry applies to this day — not persisted, computed at render time.
  final bool modified;
  final String? modifiedBy;
  final String? modifiedAt;

  /// `day._edited` — set by the expert's editor when this day differs from
  /// the original. Scanned as a supplement/override to `workoutChangeHistory`
  /// when the athlete accepts a review, mirroring the Diet feature's
  /// identical `meal._edited` mechanism.
  final bool edited;

  /// `renderFitnessDay()`'s `isRest` check — both `type` and `focus` are
  /// tested since either can carry "Rest"/"Active Recovery".
  bool get isRest {
    final t = (type ?? '').toLowerCase();
    final f = (focus ?? '').toLowerCase();
    return t.contains('rest') || t.contains('recovery') || f.contains('rest');
  }

  /// The heading shown for this day — `focus || type`.
  String get theme => focus ?? type ?? 'Training';

  WorkoutDay copyWith({
    String? type,
    String? focus,
    num? durationMinutes,
    List<WorkoutExercise>? exercises,
    bool? modified,
    String? modifiedBy,
    String? modifiedAt,
  }) {
    return WorkoutDay(
      day: day,
      type: type ?? this.type,
      focus: focus ?? this.focus,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      caloriesBurnedEst: caloriesBurnedEst,
      dailyTip: dailyTip,
      exercises: exercises ?? this.exercises,
      modified: modified ?? this.modified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      setsVolumeEst: setsVolumeEst,
    );
  }

  /// Every field goes through the tolerant coercion helpers — this tree is
  /// raw LLM output, so a documented `number` can arrive as a string and vice
  /// versa (see `WorkoutExercise`'s class doc for the full explanation).
  /// `duration_minutes` in particular is summed into total training hours by
  /// `WorkoutHero`, mirroring the website's own tolerant
  /// `parseInt(String(x).replace(/[^0-9]/g,''))` in `weekly-plan.js`.
  factory WorkoutDay.fromMap(Map<String, dynamic> m) {
    return WorkoutDay(
      day: asText(m['day']) ?? '',
      type: asText(m['type']),
      focus: asText(m['focus']),
      durationMinutes: asNum(m['duration_minutes']),
      caloriesBurnedEst: asNum(m['calories_burned_est']),
      dailyTip: asText(m['daily_tip']),
      // asMapList tolerates a missing/null/non-list value and skips junk
      // entries, so one malformed exercise can't discard a good 7-day plan.
      exercises: asMapList(m['exercises']).map(WorkoutExercise.fromMap).toList(),
      modified: m['_modified'] == true,
      modifiedBy: asText(m['_modifiedBy']),
      modifiedAt: asText(m['_modifiedAt']),
      edited: m['_edited'] == true,
      setsVolumeEst: asNum(m['sets_volume_est']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'day': day,
      if (type != null) 'type': type,
      if (focus != null) 'focus': focus,
      if (durationMinutes != null) 'duration_minutes': durationMinutes,
      if (caloriesBurnedEst != null) 'calories_burned_est': caloriesBurnedEst,
      if (dailyTip != null) 'daily_tip': dailyTip,
      'exercises': exercises.map((e) => e.toMap()).toList(),
      if (setsVolumeEst != null) 'sets_volume_est': setsVolumeEst,
    };
  }

  /// `{focus, duration_minutes, exercises}` shape used for `oldWorkout`/
  /// `newWorkout` inside a `workoutModifications` entry.
  Map<String, dynamic> toModificationSnapshot() {
    return {
      'focus': theme,
      'duration_minutes': durationMinutes,
      'exercises': exercises.map((e) => e.toMap()).toList(),
    };
  }
}
