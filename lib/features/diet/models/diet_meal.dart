import '../../../core/util/json_coerce.dart';

/// A single meal inside a `DietDay`. Field names match the real production
/// schema traced from `frontend/pages/diet/diet.js` (`renderDay`,
/// `normalizePlan`, `applySwappedMeal`, `acceptExpertPlan`) — there is no
/// `quantity`/`portion` or `alternatives` field anywhere on the website;
/// foods are plain strings in an array.
class DietMeal {
  const DietMeal({
    required this.mealName,
    this.time,
    this.foods = const [],
    this.purpose,
    this.color,
    this.emoji,
    this.calories,
    this.proteinG,
    this.notes,
    this.expertModified = false,
    this.modifiedBy,
    this.modifiedAt,
    this.recovery = false,
    this.edited = false,
  });

  final String mealName;
  final String? time;
  final List<String> foods;

  /// `purpose` falls back to the legacy `tip` field on the website — both
  /// read here, normalized to one field.
  final String? purpose;
  final String? color;
  final String? emoji;
  final num? calories;

  /// Exact field name on the website is `protein_g`, not `protein`.
  final num? proteinG;
  final String? notes;

  /// Set by `buildEffectivePlan()` when an `expertModifications` entry
  /// applies to this meal — not persisted, computed at render time.
  final bool expertModified;
  final String? modifiedBy;
  final String? modifiedAt;

  /// Health-status/recovery override lock (`meal._recovery`) — disables
  /// the swap button when true. Recovery-mode itself (health-status.js)
  /// is deferred, but the flag is honored if present on stored data.
  final bool recovery;

  /// `meal._edited` — set by the expert's editor when this meal differs
  /// from the original. Scanned as a supplement/override to
  /// `mealChangeHistory` when the athlete accepts a review
  /// (`_buildDietStorageFromReview()`/`acceptExpertPlan()`), to catch
  /// entries missed by history or with an empty `newFoods`.
  final bool edited;

  /// `_mealKey()` on the website — lowercase, trim, non-alphanumeric → `_`.
  /// This is the dictionary key used inside `expertModifications`.
  String get mealKey => mealName.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  DietMeal copyWith({
    List<String>? foods,
    num? calories,
    num? proteinG,
    String? purpose,
    bool? expertModified,
    String? modifiedBy,
    String? modifiedAt,
    bool? edited,
  }) {
    return DietMeal(
      mealName: mealName,
      time: time,
      foods: foods ?? this.foods,
      purpose: purpose ?? this.purpose,
      color: color,
      emoji: emoji,
      calories: calories ?? this.calories,
      proteinG: proteinG ?? this.proteinG,
      notes: notes,
      expertModified: expertModified ?? this.expertModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      recovery: recovery,
      edited: edited ?? this.edited,
    );
  }

  /// Tolerant coercion throughout: `diet_plan` is raw LLM output, so a field
  /// the prompt schema documents as a number can arrive as `"350"` or
  /// `"350 kcal"`. The website absorbed this via JS concatenation
  /// (`(meal.calories || 0) + ' kcal'`); Dart's `as num?` did not — the same
  /// defect class that crashed `WorkoutExercise.sets` on-device.
  /// Unlike `sets`, calories/protein ARE genuine quantities (they feed
  /// `toModificationSnapshot()` and day totals), so they stay numeric and are
  /// coerced rather than kept as display strings.
  factory DietMeal.fromMap(Map<String, dynamic> m) {
    return DietMeal(
      mealName: asText(m['meal_name']) ?? asText(m['name']) ?? 'Meal',
      time: asText(m['time']),
      foods: _foodsOf(m['foods']),
      purpose: asText(m['purpose']) ?? asText(m['tip']),
      color: asText(m['color']),
      emoji: asText(m['emoji']),
      calories: asNum(m['calories']),
      proteinG: asNum(m['protein_g']),
      notes: asText(m['notes']),
      expertModified: m['_expertModified'] == true,
      modifiedBy: m['_modifiedBy'] as String?,
      modifiedAt: m['_modifiedAt'] as String?,
      recovery: m['_recovery'] == true,
      edited: m['_edited'] == true,
    );
  }

  /// The website tolerates `foods` arriving as non-string entries or even
  /// absent; `normalizePlan()` always coerces to a string array.
  static List<String> _foodsOf(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'meal_name': mealName,
      if (time != null) 'time': time,
      'foods': foods,
      if (purpose != null) 'purpose': purpose,
      if (color != null) 'color': color,
      if (emoji != null) 'emoji': emoji,
      if (calories != null) 'calories': calories,
      if (proteinG != null) 'protein_g': proteinG,
      if (notes != null) 'notes': notes,
      // Only written when the expert's editor produced this meal — mirrors
      // modify-diet.js leaving `_edited`/`_modifiedBy` on the saved doc so
      // `_buildDietStorageFromReview()`'s fallback scan can find it.
      if (edited) '_edited': true,
      if (edited && modifiedBy != null) '_modifiedBy': modifiedBy,
      if (edited && modifiedAt != null) '_modifiedAt': modifiedAt,
    };
  }

  /// The `{foods, calories, protein_g}` shape used for `oldMeal`/`newMeal`
  /// inside an `expertModifications` entry.
  Map<String, dynamic> toModificationSnapshot() {
    return {
      'foods': foods,
      'calories': calories,
      'protein_g': proteinG,
    };
  }
}
