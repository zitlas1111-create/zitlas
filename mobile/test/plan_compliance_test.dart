import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/coaching/models/coach_diet_plan.dart';
import 'package:zitlas_mobile/features/coaching/models/plan_compliance.dart';
import 'package:zitlas_mobile/features/diet/models/diet_profile.dart';

/// Does the coach's plan respect what the athlete told us?
///
/// The rule throughout: WARN, never block. A coach can have a clinical reason
/// to prescribe something the athlete dislikes, and an editor that refuses to
/// save is one that gets worked around.
void main() {
  const vegetarian = DietProfile(
    dietPreference: DietPreference.vegetarian,
    allergies: ['Peanut'],
    neverEaten: ['Mushroom'],
    dislikedFoods: ['Bitter Gourd'],
    budget: FoodBudget.economy,
    lovedFoods: ['Paneer'],
  );

  group('allergies — the most serious check', () {
    test('a dataset-tagged allergen is caught', () {
      final flags = checkFood(
        foodName: 'Groundnut Chikki',
        profile: vegetarian,
        allergens: ['peanut'],
      );
      expect(flags.single.issue, ComplianceIssue.allergen);
      expect(flags.single.detail, 'Allergic to Peanut');
      expect(flags.single.issue.isSevere, isTrue);
    });

    test('an allergen in the NAME is caught even when the dataset never tagged it', () {
      // The athlete types free text; the dataset's tagging is not exhaustive.
      // Missing this because a tag was absent would be the dangerous failure.
      final flags = checkFood(foodName: 'Peanut Butter Toast', profile: vegetarian);
      expect(flags.single.issue, ComplianceIssue.allergen);
    });

    test('an unrelated food raises nothing', () {
      expect(checkFood(foodName: 'Poha', profile: vegetarian), isEmpty);
    });
  });

  group('diet type', () {
    test('chicken is flagged in a vegetarian plan', () {
      final flags = checkFood(
        foodName: 'Chicken Curry',
        profile: vegetarian,
        dietSuitable: ['non-vegetarian'],
      );
      expect(flags.single.issue, ComplianceIssue.dietType);
      expect(flags.single.detail, contains('Vegetarian'));
    });

    test('paneer is fine for a vegetarian', () {
      expect(
        checkFood(foodName: 'Paneer Tikka', profile: vegetarian, dietSuitable: ['vegetarian']),
        isEmpty,
      );
    });

    test('egg is flagged for a vegetarian but not an eggetarian', () {
      const egg = ['eggetarian'];
      expect(
        checkFood(foodName: 'Egg Bhurji', profile: vegetarian, dietSuitable: egg).single.issue,
        ComplianceIssue.dietType,
      );
      expect(
        checkFood(
          foodName: 'Egg Bhurji',
          profile: const DietProfile(dietPreference: DietPreference.eggetarian),
          dietSuitable: egg,
        ),
        isEmpty,
      );
    });

    test('dairy is flagged for a vegan but not a vegetarian', () {
      const dairy = ['vegetarian'];
      expect(
        checkFood(
          foodName: 'Paneer Tikka',
          profile: const DietProfile(dietPreference: DietPreference.vegan),
          dietSuitable: dairy,
        ).single.issue,
        ComplianceIssue.dietType,
      );
      expect(
        checkFood(foodName: 'Paneer Tikka', profile: vegetarian, dietSuitable: dairy),
        isEmpty,
      );
    });

    test('a non-vegetarian athlete is never flagged on diet type', () {
      expect(
        checkFood(
          foodName: 'Chicken Curry',
          profile: const DietProfile(dietPreference: DietPreference.nonVegetarian),
          dietSuitable: ['non-vegetarian'],
        ),
        isEmpty,
      );
    });

    test('an athlete who never stated a diet type is not second-guessed', () {
      expect(
        checkFood(
          foodName: 'Chicken Curry',
          profile: const DietProfile(),
          dietSuitable: ['non-vegetarian'],
        ),
        isEmpty,
      );
    });
  });

  group('foods the athlete told us about', () {
    test('a never-eaten food is flagged', () {
      final flags = checkFood(foodName: 'Mushroom Masala', profile: vegetarian);
      expect(flags.single.issue, ComplianceIssue.neverEaten);
      expect(flags.single.detail, 'Never eats Mushroom');
    });

    test('a disliked food is flagged, but not as severe', () {
      final flags = checkFood(foodName: 'Bitter Gourd Sabzi', profile: vegetarian);
      expect(flags.single.issue, ComplianceIssue.disliked);
      expect(flags.single.issue.isSevere, isFalse,
          reason: 'a coach may have a real reason to prescribe it');
    });
  });

  group('budget — tiers, because no rupee cost exists', () {
    test('a High-cost food is flagged for an Economy athlete', () {
      final flags = checkFood(
        foodName: 'Almond Milk Smoothie',
        profile: vegetarian,
        budgetCategory: 'High',
      );
      expect(flags.single.issue, ComplianceIssue.overBudget);
      expect(flags.single.detail, contains('Economy'));
    });

    test('a Low-cost food is fine for an Economy athlete', () {
      expect(
        checkFood(foodName: 'Poha', profile: vegetarian, budgetCategory: 'Low'),
        isEmpty,
      );
    });

    test('a Premium athlete is never over budget', () {
      expect(
        checkFood(
          foodName: 'Almond Milk Smoothie',
          profile: const DietProfile(budget: FoodBudget.premium),
          budgetCategory: 'High',
        ),
        isEmpty,
      );
    });

    test('an athlete with no stated budget is not flagged', () {
      expect(
        checkFood(
          foodName: 'Almond Milk Smoothie',
          profile: const DietProfile(),
          budgetCategory: 'High',
        ),
        isEmpty,
      );
    });
  });

  group('the whole week', () {
    CoachDietPlan weekOf(List<String> foods) => CoachDietPlan(days: [
          CoachDietDay(
            day: 'Monday',
            meals: [
              CoachMeal(
                id: 'm0',
                name: 'Breakfast',
                options: [for (final f in foods) CoachMealOption(name: f)],
              ),
            ],
          ),
        ]);

    test('EVERY option is checked, not just the first', () {
      // An athlete allergic to peanuts is not safe because option 1 avoids them.
      final report = checkPlan(
        plan: weekOf(['Poha', 'Peanut Chikki']),
        profile: vegetarian,
      );
      expect(report.hasSevere, isTrue);
      expect(report.severe.single.foodName, 'Peanut Chikki');
    });

    test('a compliant week is clean', () {
      final report = checkPlan(plan: weekOf(['Poha', 'Idli']), profile: vegetarian);
      expect(report.isClean, isTrue);
      expect(report.budgetWarning, isNull);
    });

    test('the budget warning counts foods and says saving is still allowed', () {
      final report = checkPlan(
        plan: weekOf(['Poha', 'Almonds', 'Cashew Curry', 'Idli']),
        profile: vegetarian,
        budgetByFood: {
          'almonds': 'High',
          'cashew curry': 'High',
          'poha': 'Low',
          'idli': 'Low',
        },
      );
      expect(report.overBudgetFoods, 2);
      expect(report.totalFoods, 4);
      expect(report.overBudgetShare, 0.5);
      expect(report.budgetWarning, contains('2 of 4'));
      expect(report.budgetWarning, contains('50%'));
      expect(report.budgetWarning, contains('still save'),
          reason: 'the coach is warned, never blocked');
    });

    test('flags carry the day and meal so the coach can find them', () {
      final report = checkPlan(plan: weekOf(['Mushroom Masala']), profile: vegetarian);
      expect(report.flags.single.day, 'Monday');
      expect(report.flags.single.mealName, 'Breakfast');
    });

    test('foods the athlete loves are counted', () {
      final report = checkPlan(
        plan: weekOf(['Paneer Bhurji', 'Poha']),
        profile: vegetarian,
      );
      expect(report.lovedFoodsUsed, 1);
    });

    test('an empty plan reports nothing rather than dividing by zero', () {
      final report = checkPlan(plan: const CoachDietPlan(), profile: vegetarian);
      expect(report.totalFoods, 0);
      expect(report.overBudgetShare, 0);
      expect(report.isClean, isTrue);
    });
  });
}
