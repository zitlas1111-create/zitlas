import 'diet_meal.dart';

/// A single day inside a `DietPlanContent.days` array. Field names traced
/// from `frontend/pages/diet/diet.js` (`renderDay`, `normalizePlan`).
class DietDay {
  const DietDay({
    required this.day,
    this.dayType,
    this.theme,
    this.nutritionTip,
    this.meals = const [],
  });

  /// e.g. "Monday" — matched case-insensitively against the weekday name
  /// for "today" detection, same as the website's day-pill auto-select.
  final String day;
  final String? dayType;
  final String? theme;
  final String? nutritionTip;
  final List<DietMeal> meals;

  DietDay copyWithMeals(List<DietMeal> meals) {
    return DietDay(day: day, dayType: dayType, theme: theme, nutritionTip: nutritionTip, meals: meals);
  }

  factory DietDay.fromMap(Map<String, dynamic> m) {
    return DietDay(
      day: (m['day'] as String?) ?? '',
      dayType: m['day_type'] as String?,
      theme: m['theme'] as String?,
      nutritionTip: m['nutrition_tip'] as String?,
      meals: _mealsOf(m['meals']),
    );
  }

  /// The website tolerates `meals` arriving as an object keyed by meal name
  /// (Personal Coaching mode) as well as the normal array — `_mealsToArray`
  /// equivalent, kept here defensively even though coaching mode itself is
  /// deferred, since some legacy stored plans may already be in this shape.
  static List<DietMeal> _mealsOf(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => DietMeal.fromMap(e.cast<String, dynamic>())).toList();
    }
    if (raw is Map) {
      return raw.values
          .whereType<Map>()
          .map((e) => DietMeal.fromMap(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> toMap() {
    return {
      'day': day,
      if (dayType != null) 'day_type': dayType,
      if (theme != null) 'theme': theme,
      if (nutritionTip != null) 'nutrition_tip': nutritionTip,
      'meals': meals.map((m) => m.toMap()).toList(),
    };
  }
}
