import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';

/// One food from the ZITLAS database, as returned by
/// `GET /api/diet/foods/search`.
@immutable
class FoodSearchResult {
  const FoodSearchResult({
    required this.id,
    required this.name,
    required this.display,
    this.servingSize,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.category,
    this.region,
    this.type,
    this.budgetCategory,
    this.dietSuitable = const [],
    this.allergens = const [],
  });

  final int id;
  final String name;

  /// `"Poha (1 plate (200 g))"` — the EXACT string shape plans store, so an
  /// expert's swap lands in the same format the generator produces and the
  /// athlete's app already knows how to render.
  final String display;

  final String? servingSize;
  final num? calories;
  final num? protein;
  final num? carbs;
  final num? fat;
  final String? category;
  final String? region;
  final String? type;

  /// `Low` | `Medium` | `High` — the dataset's own tier. There is NO rupee
  /// cost anywhere in the 4,520-food database, so this is the only real cost
  /// signal that exists; anything in ₹ would be invented.
  final String? budgetCategory;

  /// Diet types this food is suitable for (`vegetarian`, `eggetarian`, ...) —
  /// straight from the dataset's `dietSuitable`.
  final List<String> dietSuitable;

  /// Dataset allergen tags, for checking against the athlete's allergies.
  final List<String> allergens;

  static FoodSearchResult? fromMap(Map<String, dynamic> m) {
    final id = m['id'];
    final name = m['name'];
    if (id is! num || name is! String) return null;
    return FoodSearchResult(
      id: id.toInt(),
      name: name,
      display: m['display'] as String? ?? name,
      servingSize: m['serving_size'] as String?,
      calories: m['calories'] as num?,
      protein: m['protein'] as num?,
      carbs: m['carbs'] as num?,
      fat: m['fat'] as num?,
      category: m['category'] as String?,
      region: m['region'] as String?,
      type: m['type'] as String?,
      budgetCategory: m['budgetCategory'] as String?,
      dietSuitable: _strings(m['dietSuitable']),
      allergens: _strings(m['allergens']),
    );
  }

  static List<String> _strings(Object? raw) => [
        if (raw is List)
          for (final v in raw)
            if (v is String && v.trim().isNotEmpty) v.trim(),
      ];
}

/// Reads the real food database for the expert's Swap Food action.
///
/// Deliberately server-side: the dataset is ~4,500 foods and is already the
/// single source of truth for every generation and swap path. Shipping a copy
/// into the app would guarantee it drifts from what the engine actually scores
/// against.
class FoodSearchRepository {
  FoodSearchRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<List<FoodSearchResult>> search({
    String query = '',
    String? category,
    String? region,
    String? goal,
    String? diet,
    double? minProtein,
    double? maxCalories,
    int limit = 30,
  }) async {
    final res = await _api.get('/api/diet/foods/search', query: {
      'q': query,
      'category': ?category,
      'region': ?region,
      'goal': ?goal,
      'diet': ?diet,
      'min_protein': ?minProtein,
      'max_calories': ?maxCalories,
      'limit': limit,
    });
    if (res is! Map) return const [];
    final foods = res['foods'];
    if (foods is! List) return const [];
    return [
      for (final f in foods)
        if (f is Map<String, dynamic>) ?FoodSearchResult.fromMap(f),
    ];
  }
}
