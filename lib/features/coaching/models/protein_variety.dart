import 'package:flutter/foundation.dart';

import 'coach_diet_plan.dart';

/// Protein-source variety across a coach-authored week.
///
/// Why this exists: a week built out of "chicken, chicken, chicken" hits its
/// macro targets and is still a bad plan — it is monotonous, it narrows the
/// micronutrient profile, and in Indian households it is usually the most
/// expensive way to reach the same protein number. The coach gets told, with
/// counts, rather than being left to eyeball a seven-day grid.
///
/// The classifier is deliberately keyword-based over the food NAME rather
/// than a lookup against the dataset: a coach can type any dish, and a plan
/// entry that matched nothing in the dataset would silently vanish from the
/// analysis — which would under-report exactly the repetition this is meant
/// to catch.

/// A protein source ZITLAS recognises, with the words that identify it.
///
/// Ordering matters: the first match wins, so more specific groups are listed
/// before the ones that would otherwise swallow them (paneer before dairy,
/// egg before chicken so "egg curry with chicken stock" isn't miscounted).
enum ProteinSource {
  // NOT 'bhurji' — that is a preparation (a scramble), not an ingredient, and
  // Paneer Bhurji is one of the most common vegetarian breakfasts in India.
  // Claiming it for eggs miscounts a paneer meal AND makes a vegetarian week
  // look like it contains egg.
  egg('Eggs', '🥚', ['egg', 'anda', 'omelet', 'omelette']),
  chicken('Chicken', '🍗', ['chicken', 'murg', 'murgh', 'tandoori']),
  fish('Fish', '🐟', ['fish', 'machli', 'macher', 'tuna', 'salmon', 'prawn', 'shrimp', 'surmai', 'rohu']),
  mutton('Mutton', '🍖', ['mutton', 'lamb', 'keema', 'goat']),
  paneer('Paneer', '🧀', ['paneer', 'cottage cheese']),
  dairy('Dairy', '🥛', ['milk', 'curd', 'dahi', 'yoghurt', 'yogurt', 'lassi', 'buttermilk', 'chaas', 'cheese', 'whey']),
  soy('Soy', '🌱', ['soy', 'soya', 'tofu', 'tempeh', 'edamame']),
  legume('Dal & Legumes', '🫘', [
    'dal', 'daal', 'lentil', 'rajma', 'chana', 'chole', 'chickpea', 'moong',
    'masoor', 'toor', 'urad', 'lobia', 'kidney bean', 'bean', 'sprout', 'usal', 'sambar',
  ]),
  nuts('Nuts & Seeds', '🥜', ['almond', 'badam', 'peanut', 'walnut', 'cashew', 'seed', 'til', 'chia', 'flax', 'pista']),
  grain('Grains', '🌾', ['oats', 'quinoa', 'poha', 'upma', 'roti', 'rice', 'millet', 'ragi', 'bajra', 'jowar', 'daliya']);

  const ProteinSource(this.label, this.icon, this.keywords);

  final String label;
  final String icon;
  final List<String> keywords;

  /// Sources that genuinely carry a meal's protein. Grains contribute some,
  /// but a week whose only "variety" is rice vs roti has not solved anything,
  /// so they are excluded from the variety verdict.
  static const primary = [egg, chicken, fish, mutton, paneer, dairy, soy, legume, nuts];

  /// The source a dish name belongs to, or null when nothing matches.
  static ProteinSource? classify(String foodName) {
    final name = foodName.toLowerCase();
    for (final source in values) {
      for (final keyword in source.keywords) {
        if (name.contains(keyword)) return source;
      }
    }
    return null;
  }
}

/// How often one source appears across the week.
@immutable
class ProteinUsage {
  const ProteinUsage({required this.source, required this.mealCount});

  final ProteinSource source;

  /// Meals — not options. A meal offering three chicken dishes is still one
  /// chicken meal, because the athlete eats one of them.
  final int mealCount;
}

/// The verdict on a week's protein spread.
@immutable
class ProteinVarietyReport {
  const ProteinVarietyReport({
    required this.usage,
    required this.mealsWithProtein,
    required this.mealsWithoutProtein,
  });

  /// Descending by meal count.
  final List<ProteinUsage> usage;

  final int mealsWithProtein;

  /// Meals whose options name no recognisable protein source at all. Worth
  /// showing separately — it is usually a coach who hasn't filled the slot in
  /// yet, not a genuinely protein-free meal.
  final int mealsWithoutProtein;

  int get distinctSources => usage.length;

  /// The single most-repeated source, or null on an empty week.
  ProteinUsage? get dominant => usage.isEmpty ? null : usage.first;

  /// Share of protein-bearing meals taken by the most-used source.
  double get dominantShare {
    final top = dominant;
    if (top == null || mealsWithProtein == 0) return 0;
    return top.mealCount / mealsWithProtein;
  }

  /// True when the week leans too hard on one source.
  ///
  /// Two independent triggers, because they catch different failures: fewer
  /// than three distinct sources is a narrow week however it is balanced, and
  /// one source covering over half the meals is a repetitive week however
  /// many sources are nominally present. Below four protein meals nothing is
  /// flagged — there isn't enough of a week yet to call it repetitive, and
  /// warning a coach mid-build is noise.
  bool get isLowVariety {
    if (mealsWithProtein < 4) return false;
    return distinctSources < 3 || dominantShare > 0.5;
  }

  /// What to tell the coach. Null when the week is fine.
  String? get warning {
    if (!isLowVariety) return null;
    final top = dominant;
    if (top != null && dominantShare > 0.5) {
      final pct = (dominantShare * 100).round();
      return '${top.source.label} covers $pct% of this week\'s protein meals '
          '(${top.mealCount} of $mealsWithProtein). Rotating in another source '
          'widens the nutrient profile and usually costs less.';
    }
    return 'Only $distinctSources protein ${distinctSources == 1 ? "source" : "sources"} '
        'across $mealsWithProtein meals. Aim for at least three across the week.';
  }

  /// Sources NOT used this week, ordered as [ProteinSource.primary] — the
  /// concrete alternatives to offer alongside the warning.
  List<ProteinSource> get unusedSources {
    final used = usage.map((u) => u.source).toSet();
    return [
      for (final s in ProteinSource.primary)
        if (!used.contains(s)) s,
    ];
  }

  static const empty =
      ProteinVarietyReport(usage: [], mealsWithProtein: 0, mealsWithoutProtein: 0);
}

/// Analyses a coach-authored week.
///
/// A meal counts ONCE per source even if several of its options share one —
/// the athlete picks a single option, so three paneer choices at breakfast is
/// one paneer meal, not three. A meal offering genuinely different sources
/// counts towards each, which is the behaviour a coach offering real choice
/// should be credited for.
ProteinVarietyReport analyseProteinVariety(CoachDietPlan plan) {
  final counts = <ProteinSource, int>{};
  var withProtein = 0;
  var withoutProtein = 0;

  for (final day in plan.days) {
    for (final meal in day.meals) {
      if (!meal.hasOptions) continue;
      final sourcesInMeal = <ProteinSource>{};
      for (final option in meal.options) {
        final source = ProteinSource.classify(option.name);
        if (source != null && ProteinSource.primary.contains(source)) {
          sourcesInMeal.add(source);
        }
      }
      if (sourcesInMeal.isEmpty) {
        withoutProtein++;
        continue;
      }
      withProtein++;
      for (final source in sourcesInMeal) {
        counts[source] = (counts[source] ?? 0) + 1;
      }
    }
  }

  final usage = counts.entries
      .map((e) => ProteinUsage(source: e.key, mealCount: e.value))
      .toList()
    ..sort((a, b) {
      final byCount = b.mealCount.compareTo(a.mealCount);
      // Stable tie-break by declaration order, so the same week always
      // produces the same report rather than shuffling between builds.
      return byCount != 0 ? byCount : a.source.index.compareTo(b.source.index);
    });

  return ProteinVarietyReport(
    usage: usage,
    mealsWithProtein: withProtein,
    mealsWithoutProtein: withoutProtein,
  );
}
