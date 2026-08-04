import 'package:flutter/foundation.dart';

import '../../../core/util/json_coerce.dart';

/// `coaching_plans/{athleteUid}.diet` — the coach-authored diet.
///
/// SHAPE IS FIXED BY THE WEBSITE (`components/coaching-workspace.js`), which
/// reads and writes the same document:
///
/// ```
/// { planId, days: [ { day, meals: [ { id, name, time,
///     options: [ { name, calories, protein, notes } ] } ] } ] }
/// ```
///
/// It is deliberately NOT the AI plan's shape. A coach offers OPTIONS per meal
/// and the athlete picks one (`dietSelections`), which is why this lives in its
/// own document rather than overwriting `users/{uid}.dietPlan`. That separation
/// is the whole of "AI never overwrites coach modifications": the two plans are
/// different documents with different owners, so neither can clobber the other.
const kCoachPlanDays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const kCoachDefaultMeals = <String>['Breakfast', 'Lunch', 'Snacks', 'Dinner'];

/// One food the coach offers for a meal.
@immutable
class CoachMealOption {
  const CoachMealOption({
    required this.name,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.notes,
  });

  final String name;

  /// Kept nullable rather than defaulted to 0 — a coach who hasn't filled in
  /// the calories has not said "zero calories", and an athlete adding up a
  /// day's total must not silently count a blank as nothing.
  final num? calories;
  final num? protein;

  /// Carbs and fat EXTEND the website's shape rather than replace it. The
  /// workspace writes with `set(merge)` and ignores fields it doesn't know, so
  /// adding these is additive — a plan edited on the phone still opens on the
  /// web, it simply shows the two macros the web editor doesn't collect.
  final num? carbs;
  final num? fat;

  final String? notes;

  CoachMealOption copyWith({
    String? name,
    Object? calories = _unset,
    Object? protein = _unset,
    Object? carbs = _unset,
    Object? fat = _unset,
    Object? notes = _unset,
  }) {
    return CoachMealOption(
      name: name ?? this.name,
      calories: calories == _unset ? this.calories : calories as num?,
      protein: protein == _unset ? this.protein : protein as num?,
      carbs: carbs == _unset ? this.carbs : carbs as num?,
      fat: fat == _unset ? this.fat : fat as num?,
      notes: notes == _unset ? this.notes : notes as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'notes': notes,
      };

  static CoachMealOption? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final name = (m['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    return CoachMealOption(
      name: name,
      calories: asNum(m['calories']),
      protein: asNum(m['protein']),
      carbs: asNum(m['carbs']),
      fat: asNum(m['fat']),
      notes: (m['notes'] as String?)?.trim().isEmpty == true ? null : m['notes'] as String?,
    );
  }
}

const _unset = Object();

/// One meal slot in the coach's day.
@immutable
class CoachMeal {
  const CoachMeal({
    required this.id,
    required this.name,
    this.time,
    this.options = const [],
  });

  /// Stable within the day — `dietSelections` is keyed `'<day>:<mealId>'`, so
  /// changing this orphans the athlete's choice.
  final String id;

  final String name;
  final String? time;
  final List<CoachMealOption> options;

  bool get hasOptions => options.isNotEmpty;

  CoachMeal copyWith({
    String? name,
    Object? time = _unset,
    List<CoachMealOption>? options,
  }) {
    return CoachMeal(
      id: id,
      name: name ?? this.name,
      time: time == _unset ? this.time : time as String?,
      options: options ?? this.options,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'time': time,
        'options': [for (final o in options) o.toMap()],
      };

  static CoachMeal? fromMap(Object? raw, {required int index}) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final name = (m['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final rawOptions = m['options'];
    return CoachMeal(
      id: (m['id'] as String?)?.trim().isNotEmpty == true
          ? m['id'] as String
          : 'meal_$index',
      name: name,
      time: (m['time'] as String?)?.trim().isEmpty == true ? null : m['time'] as String?,
      options: [
        if (rawOptions is List)
          for (final o in rawOptions) ?CoachMealOption.fromMap(o),
      ],
    );
  }
}

/// One day of the coach's week.
@immutable
class CoachDietDay {
  const CoachDietDay({required this.day, this.meals = const []});

  final String day;
  final List<CoachMeal> meals;

  /// Total calories across ONE option per meal (the first), which is what a
  /// day actually costs the athlete — summing every option would count
  /// alternatives the athlete will never all eat.
  num get representativeCalories => meals.fold<num>(
        0,
        (sum, meal) => sum + (meal.options.isEmpty ? 0 : (meal.options.first.calories ?? 0)),
      );

  num get representativeProtein => meals.fold<num>(
        0,
        (sum, meal) => sum + (meal.options.isEmpty ? 0 : (meal.options.first.protein ?? 0)),
      );

  CoachDietDay copyWith({List<CoachMeal>? meals}) =>
      CoachDietDay(day: day, meals: meals ?? this.meals);

  Map<String, dynamic> toMap() => {
        'day': day,
        'meals': [for (final m in meals) m.toMap()],
      };

  static CoachDietDay? fromMap(Object? raw, {required int index}) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final rawMeals = m['meals'];
    return CoachDietDay(
      day: (m['day'] as String?)?.trim().isNotEmpty == true
          ? m['day'] as String
          : kCoachPlanDays[index % kCoachPlanDays.length],
      meals: [
        if (rawMeals is List)
          for (var i = 0; i < rawMeals.length; i++) ?CoachMeal.fromMap(rawMeals[i], index: i),
      ],
    );
  }
}

/// The whole coach-authored diet.
@immutable
class CoachDietPlan {
  const CoachDietPlan({this.days = const [], this.planId});

  final List<CoachDietDay> days;

  /// The athlete plan GENERATION this was authored against.
  ///
  /// Consumers fail closed on a mismatch — if the athlete resets their goal,
  /// `users/{uid}.planId` changes and this coach plan silently retires rather
  /// than continuing to prescribe against a goal nobody has any more.
  final String? planId;

  bool get hasDays => days.any((d) => d.meals.any((m) => m.hasOptions));

  /// A blank week the coach can fill in.
  static CoachDietPlan emptyWeek() => CoachDietPlan(
        days: [
          for (final day in kCoachPlanDays)
            CoachDietDay(
              day: day,
              meals: [
                for (var i = 0; i < kCoachDefaultMeals.length; i++)
                  CoachMeal(id: 'meal_$i', name: kCoachDefaultMeals[i]),
              ],
            ),
        ],
      );

  CoachDietPlan copyWith({List<CoachDietDay>? days, Object? planId = _unset}) {
    return CoachDietPlan(
      days: days ?? this.days,
      planId: planId == _unset ? this.planId : planId as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'planId': planId,
        'days': [for (final d in days) d.toMap()],
      };

  static CoachDietPlan fromMap(Object? raw) {
    if (raw is! Map) return const CoachDietPlan();
    final m = raw.cast<String, dynamic>();
    final rawDays = m['days'];
    return CoachDietPlan(
      planId: m['planId'] as String?,
      days: [
        if (rawDays is List)
          for (var i = 0; i < rawDays.length; i++) ?CoachDietDay.fromMap(rawDays[i], index: i),
      ],
    );
  }
}
