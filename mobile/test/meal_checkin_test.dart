import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/coaching/models/meal_checkin.dart';
import 'package:zitlas_mobile/features/coaching/models/meal_compliance.dart';

/// Meal Snap, coach review and compliance.
///
/// The thing worth protecting here is honesty about gaps: a meal nobody
/// photographed is UNKNOWN, not a failure, and a photo the coach hasn't opened
/// yet is the coach's backlog, not the athlete's non-compliance. Numbers that
/// blur those two are worse than no numbers.
void main() {
  final today = DateTime(2026, 8, 4, 20);

  MealCheckin checkin({
    required String mealType,
    required int daysAgo,
    MealReaction? reaction,
    int hour = 13,
    num? protein,
  }) {
    final t = DateTime(today.year, today.month, today.day - daysAgo, hour);
    return MealCheckin(
      checkinId: 'MCI_${mealType}_$daysAgo',
      athleteId: 'athlete_1',
      coachId: 'coach_1',
      mealType: mealType,
      mealName: mealType[0].toUpperCase() + mealType.substring(1),
      status: reaction == null ? 'pending' : 'reviewed',
      timestamp: t,
      reaction: reaction,
      score: reaction?.score,
      estimatedProtein: protein,
    );
  }

  group('the coach verdict', () {
    test('reaction ids match the website exactly', () {
      // A meal rated on the phone must read correctly on the web.
      expect(MealReaction.perfect.id, 'perfect');
      expect(MealReaction.great.id, 'great');
      expect(MealReaction.good.id, 'good');
      expect(MealReaction.needsImprovement.id, 'needs_improvement');
      expect(MealReaction.notRecommended.id, 'not_recommended');
    });

    test('scores run 5 down to 1', () {
      expect(MealReaction.perfect.score, 5);
      expect(MealReaction.notRecommended.score, 1);
    });

    test('Good and above counts as following the plan', () {
      expect(MealReaction.perfect.isCompliant, isTrue);
      expect(MealReaction.great.isCompliant, isTrue);
      expect(MealReaction.good.isCompliant, isTrue);
    });

    test('"needs improvement" does NOT count as adherence', () {
      // Counting it would flatter the number and hide the thing the coach is
      // trying to fix.
      expect(MealReaction.needsImprovement.isCompliant, isFalse);
      expect(MealReaction.notRecommended.isCompliant, isFalse);
    });

    test('an unknown reaction from a newer client is ignored, not guessed', () {
      expect(MealReaction.fromId('spectacular'), isNull);
      expect(MealReaction.fromId(null), isNull);
    });
  });

  group('the stored document', () {
    test('round-trips through the website shape', () {
      final original = MealCheckin(
        checkinId: 'MCI_1',
        athleteId: 'athlete_1',
        athleteName: 'Rohit',
        coachId: 'coach_1',
        day: 'Tuesday',
        mealType: 'breakfast',
        mealName: 'Breakfast',
        imageUrl: 'https://example.com/a.jpg',
        timestamp: DateTime(2026, 8, 4, 9),
        status: 'reviewed',
        reaction: MealReaction.great,
        score: 4,
        comment: 'Excellent protein. Add one fruit tomorrow.',
        estimatedCalories: 420,
        estimatedProtein: 28,
        foodRecognition: ['Poha', 'Boiled eggs'],
        confidenceScore: 82,
      );

      final parsed = MealCheckin.fromMap(original.toMap())!;
      expect(parsed.checkinId, 'MCI_1');
      expect(parsed.reaction, MealReaction.great);
      expect(parsed.score, 4);
      expect(parsed.comment, contains('Add one fruit'));
      expect(parsed.foodRecognition, ['Poha', 'Boiled eggs']);
      expect(parsed.estimatedProtein, 28);
      expect(parsed.isReviewed, isTrue);
    });

    test('a failed nutrition estimate stays null, never zero', () {
      final parsed = MealCheckin.fromMap({
        'checkinId': 'MCI_2',
        'athleteId': 'a',
        'coachId': 'c',
        'mealType': 'lunch',
        'mealName': 'Lunch',
        'status': 'pending',
        'estimatedCalories': null,
      })!;
      expect(parsed.estimatedCalories, isNull, reason: 'null means not estimated');
      expect(parsed.hasEstimate, isFalse);
    });

    test('numbers stored as strings by the website still parse', () {
      final parsed = MealCheckin.fromMap({
        'checkinId': 'MCI_3',
        'athleteId': 'a',
        'coachId': 'c',
        'mealType': 'dinner',
        'mealName': 'Dinner',
        'status': 'reviewed',
        'score': '4',
        'estimatedProtein': '31',
      })!;
      expect(parsed.score, 4);
      expect(parsed.estimatedProtein, 31);
    });

    test('a document with no coach is not a check-in', () {
      expect(MealCheckin.fromMap({'athleteId': 'a', 'mealType': 'lunch'}), isNull);
    });
  });

  group('compliance counts only what is known', () {
    test('a fully followed day scores 100%', () {
      final summary = buildCompliance(
        checkins: [
          checkin(mealType: 'breakfast', daysAgo: 0, reaction: MealReaction.perfect),
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.great),
          checkin(mealType: 'snacks', daysAgo: 0, reaction: MealReaction.good),
          checkin(mealType: 'dinner', daysAgo: 0, reaction: MealReaction.good),
        ],
        today: today,
        days: 1,
        expectedMealsPerDay: 4,
      );
      expect(summary.overallPercent, 100);
      expect(summary.totalMissing, 0);
    });

    test('a meal nobody photographed is MISSING, not failed', () {
      final summary = buildCompliance(
        checkins: [
          checkin(mealType: 'breakfast', daysAgo: 0, reaction: MealReaction.perfect),
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.perfect),
        ],
        today: today,
        days: 1,
        expectedMealsPerDay: 4,
      );
      expect(summary.totalMissing, 2);
      expect(summary.qualityRate, 1.0, reason: 'both photographed meals were good');
      expect(summary.overallPercent, 50, reason: 'half the day is unaccounted for');
    });

    test('an unreviewed photo is the coach backlog, not athlete failure', () {
      final summary = buildCompliance(
        checkins: [
          checkin(mealType: 'breakfast', daysAgo: 0),
          checkin(mealType: 'lunch', daysAgo: 0),
        ],
        today: today,
        days: 1,
        expectedMealsPerDay: 2,
      );
      expect(summary.totalReviewed, 0);
      expect(summary.qualityRate, isNull, reason: 'nothing rated yet — no quality score');
      expect(summary.overallPercent, 100,
          reason: 'the athlete did their part; the review is outstanding');
    });

    test('a poorly rated meal does not count towards adherence', () {
      final summary = buildCompliance(
        checkins: [
          checkin(mealType: 'breakfast', daysAgo: 0, reaction: MealReaction.perfect),
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.notRecommended),
        ],
        today: today,
        days: 1,
        expectedMealsPerDay: 2,
      );
      expect(summary.totalCompliant, 1);
      expect(summary.qualityRate, 0.5);
      expect(summary.overallPercent, 50);
    });

    test('photographing one meal twice counts once', () {
      // A retake, or a second helping. Otherwise a keen athlete scores over
      // 100% and the number stops meaning anything.
      final summary = buildCompliance(
        checkins: [
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.good, hour: 13),
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.good, hour: 14),
        ],
        today: today,
        days: 1,
        expectedMealsPerDay: 4,
      );
      expect(summary.totalSubmitted, 1);
      expect(summary.overallPercent, 25);
    });

    test('a reviewed retake wins over an unreviewed one', () {
      final summary = buildCompliance(
        checkins: [
          checkin(mealType: 'lunch', daysAgo: 0, hour: 14),
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.good, hour: 13),
        ],
        today: today,
        days: 1,
        expectedMealsPerDay: 1,
      );
      expect(summary.totalReviewed, 1);
      expect(summary.totalCompliant, 1);
    });

    test('expected meals come from the athlete profile, not a constant', () {
      // Someone who eats three meals must not be marked down for a fourth
      // they never planned.
      final meals = [
        checkin(mealType: 'breakfast', daysAgo: 0, reaction: MealReaction.good),
        checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.good),
        checkin(mealType: 'dinner', daysAgo: 0, reaction: MealReaction.good),
      ];
      expect(
        buildCompliance(checkins: meals, today: today, days: 1, expectedMealsPerDay: 3)
            .overallPercent,
        100,
      );
      expect(
        buildCompliance(checkins: meals, today: today, days: 1, expectedMealsPerDay: 4)
            .overallPercent,
        75,
      );
    });

    test('a week returns one row per day, gaps included', () {
      final summary = buildCompliance(
        checkins: [checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.good)],
        today: today,
        days: 7,
      );
      expect(summary.days.length, 7);
      expect(summary.days.first.dayKey, '2026-08-04');
      expect(summary.days.last.dayKey, '2026-07-29');
      expect(summary.days[1].submitted, 0);
    });

    test('an empty record produces zero, never a divide-by-zero', () {
      final summary = buildCompliance(checkins: [], today: today, days: 7);
      expect(summary.overallPercent, 0);
      expect(summary.qualityRate, isNull);
      expect(summary.submissionRate, 0);
    });
  });

  group('insights are drawn from the record, never generic', () {
    test('a repeatedly skipped meal is named with its count', () {
      final insights = buildInsights(
        checkins: [
          for (var d = 0; d < 7; d++)
            checkin(mealType: 'lunch', daysAgo: d, reaction: MealReaction.good),
        ],
        today: today,
        days: 7,
      );
      final breakfast = insights.firstWhere((i) => i.text.contains('Breakfast'));
      expect(breakfast.text, contains('7 of the last 7 days'));
      expect(breakfast.isPositive, isFalse);
    });

    test('one missed meal is a Tuesday, not a pattern', () {
      final insights = buildInsights(
        checkins: [
          for (var d = 0; d < 7; d++)
            if (d != 3)
              checkin(mealType: 'breakfast', daysAgo: d, reaction: MealReaction.good),
        ],
        today: today,
        days: 7,
      );
      expect(insights.where((i) => i.text.contains('Breakfast')), isEmpty);
    });

    test('strong adherence is called out with the real numbers', () {
      final insights = buildInsights(
        checkins: [
          for (var d = 0; d < 6; d++)
            checkin(mealType: 'lunch', daysAgo: d, reaction: MealReaction.great),
        ],
        today: today,
        days: 7,
      );
      final good = insights.firstWhere((i) => i.isPositive);
      expect(good.text, contains('6 of 6'));
    });

    test('quality is not judged from one or two meals', () {
      final insights = buildInsights(
        checkins: [
          checkin(mealType: 'lunch', daysAgo: 0, reaction: MealReaction.notRecommended),
        ],
        today: today,
        days: 7,
      );
      expect(insights.where((i) => i.text.contains('met the plan')), isEmpty);
    });

    test('a review backlog is surfaced to the coach', () {
      final insights = buildInsights(
        checkins: [
          for (var d = 0; d < 4; d++) checkin(mealType: 'lunch', daysAgo: d),
        ],
        today: today,
        days: 7,
      );
      expect(insights.any((i) => i.text.contains('waiting on your review')), isTrue);
    });

    test('late dinners are evidenced by real timestamps', () {
      final insights = buildInsights(
        checkins: [
          for (var d = 0; d < 4; d++)
            checkin(mealType: 'dinner', daysAgo: d, hour: 23, reaction: MealReaction.good),
        ],
        today: today,
        days: 7,
      );
      expect(insights.any((i) => i.text.contains('after 10pm')), isTrue);
    });

    test('protein is only judged where it was actually estimated', () {
      // No estimate means no claim — never a guess.
      final noEstimates = buildInsights(
        checkins: [
          for (var d = 0; d < 6; d++)
            checkin(mealType: 'lunch', daysAgo: d, reaction: MealReaction.good),
        ],
        today: today,
        days: 7,
      );
      expect(noEstimates.where((i) => i.text.contains('protein')), isEmpty);

      final withEstimates = buildInsights(
        checkins: [
          for (var d = 0; d < 6; d++)
            checkin(mealType: 'lunch', daysAgo: d, reaction: MealReaction.good, protein: 8),
        ],
        today: today,
        days: 7,
      );
      expect(withEstimates.any((i) => i.text.contains('protein averages 8g')), isTrue);
    });

    test('a clean record produces no noise', () {
      final insights = buildInsights(
        checkins: [
          for (var d = 0; d < 7; d++) ...[
            checkin(mealType: 'breakfast', daysAgo: d, reaction: MealReaction.great),
            checkin(mealType: 'lunch', daysAgo: d, reaction: MealReaction.great),
            checkin(mealType: 'snacks', daysAgo: d, reaction: MealReaction.good),
            checkin(mealType: 'dinner', daysAgo: d, hour: 20, reaction: MealReaction.great),
          ],
        ],
        today: today,
        days: 7,
      );
      expect(insights.every((i) => i.isPositive), isTrue);
    });
  });
}
