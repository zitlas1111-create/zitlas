import '../../../core/util/json_coerce.dart';

/// A single exercise inside a `WorkoutDay.exercises` array.
///
/// **On field types:** `backend/routes/assessment.py` documents
/// `"sets": number` and `"rest_seconds": number`, but that JSON schema is a
/// *prompt instruction to the LLM*, not an enforced contract — nothing
/// validates the model's reply. Production therefore contains a genuine mix:
///
/// | source | `sets` |
/// |---|---|
/// | expert editor (`modify-workout.js:139` `sets: parseInt(sets)`) | `3` (int) |
/// | LLM obeying the prompt | `3` (int) |
/// | LLM not obeying | `"3"`, `"3-4"`, `"AMRAP"`, `"To failure"` |
///
/// Every website render site treats these as opaque display values and never
/// computes with them — `String(ex.sets)` (day.js:472/549/1023),
/// `String(ex.sets || '')` (weekly-plan.js:538), `ex.sets + ' sets · '`
/// (ai-coach.js:2064) — so JS absorbed the variance silently.
///
/// They are modelled as [String] here for exactly that reason: coercing to
/// `num` would crash on (or destroy) legitimate values like `"3-4"`. Numeric
/// round-tripping is preserved on write — see [toMap].
class WorkoutExercise {
  const WorkoutExercise({
    required this.name,
    this.sets,
    this.repsOrDuration,
    this.restSeconds,
    this.weight,
    this.tip,
    this.progression,
  });

  final String name;

  /// Display-only. `"3"`, `"3-4"`, `"AMRAP"` — see the class doc.
  final String? sets;

  /// e.g. "12 reps" | "30 sec" | "25 min" — a free-form caption, not two
  /// separate fields, exactly as the backend generates it.
  final String? repsOrDuration;

  /// Display-only, same mixed-type reality as [sets]: `60` or `"60"` or
  /// `"60 sec"`. Rendered as `Rest ${x}s` on the website (day.js:1025), which
  /// is why the raw text is kept rather than a parsed count of seconds.
  final String? restSeconds;

  /// Load for this exercise (`"40 kg"`, `"bodyweight"`). ADDITIVE — the
  /// generator never sets it, and both the athlete app and the website ignore
  /// keys they don't know, so an expert filling this in cannot break an
  /// existing plan on either client.
  final String? weight;

  /// `ex.tip` on the website, falling back to `ex.notes` for expert-edited
  /// entries (`modify-workout.js` writes `notes`, not `tip`).
  final String? tip;

  /// Muscle-gain/transformation-only progressive-overload cue — see
  /// `WorkoutPlanContent`'s doc comment on `weeklyTrainingVolumeSets`. Only
  /// the Assessment preview screen reads this.
  final String? progression;

  WorkoutExercise copyWith({
    String? name,
    String? sets,
    String? repsOrDuration,
    String? restSeconds,
    String? weight,
    String? tip,
    String? progression,
  }) {
    return WorkoutExercise(
      name: name ?? this.name,
      sets: sets ?? this.sets,
      repsOrDuration: repsOrDuration ?? this.repsOrDuration,
      restSeconds: restSeconds ?? this.restSeconds,
      weight: weight ?? this.weight,
      tip: tip ?? this.tip,
      progression: progression ?? this.progression,
    );
  }

  factory WorkoutExercise.fromMap(Map<String, dynamic> m) {
    return WorkoutExercise(
      name: asText(m['name']) ?? 'Exercise',
      sets: asDisplayString(m['sets']),
      repsOrDuration: asText(m['reps_or_duration']),
      restSeconds: asDisplayString(m['rest_seconds']),
      weight: asText(m['weight']),
      tip: asText(m['tip']) ?? asText(m['notes']),
      progression: asText(m['progression']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      // Numeric-looking values are written back as numbers so reading a plan
      // and re-saving it never drifts `sets: 3` into `sets: "3"` for the
      // expert dashboard; semantic strings are preserved verbatim.
      if (sets != null) 'sets': displayStringToJson(sets),
      if (repsOrDuration != null) 'reps_or_duration': repsOrDuration,
      if (restSeconds != null) 'rest_seconds': displayStringToJson(restSeconds),
      if (weight != null) 'weight': weight,
      if (tip != null) 'tip': tip,
      if (progression != null) 'progression': progression,
    };
  }
}
