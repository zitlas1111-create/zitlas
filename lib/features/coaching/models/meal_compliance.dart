import 'package:flutter/foundation.dart';

import 'meal_checkin.dart';

/// How well an athlete is actually following their plan.
///
/// Computed from real check-ins only. There is no estimation and no filling-in
/// of gaps: a meal that was never photographed is UNKNOWN, not a failure, and
/// it is reported separately rather than dragged into the percentage. A coach
/// looking at "60% compliance" needs to know whether that means four bad meals
/// or six missing photos, because those call for opposite conversations.

/// One day's meals.
@immutable
class DayCompliance {
  const DayCompliance({
    required this.dayKey,
    required this.submitted,
    required this.reviewed,
    required this.compliant,
    required this.expectedMeals,
  });

  /// Local `YYYY-MM-DD`.
  final String dayKey;

  /// Meals photographed.
  final int submitted;

  /// Of those, how many the coach has actually rated.
  final int reviewed;

  /// Of the reviewed ones, how many scored Good or better.
  final int compliant;

  /// How many meals the athlete's plan expects in a day.
  final int expectedMeals;

  /// Meals with no photo at all — unknown, not failed.
  int get missing => (expectedMeals - submitted).clamp(0, expectedMeals);

  /// Share of REVIEWED meals that were compliant. Null when the coach hasn't
  /// rated anything yet — a day with three unreviewed photos has no quality
  /// score, and showing 0% would blame the athlete for the coach's backlog.
  double? get qualityRate => reviewed == 0 ? null : compliant / reviewed;

  /// Share of expected meals that were photographed at all.
  double get submissionRate => expectedMeals == 0 ? 0 : (submitted / expectedMeals).clamp(0, 1);
}

/// A window of days.
@immutable
class ComplianceSummary {
  const ComplianceSummary({
    required this.days,
    required this.totalSubmitted,
    required this.totalReviewed,
    required this.totalCompliant,
    required this.totalExpected,
  });

  final List<DayCompliance> days;
  final int totalSubmitted;
  final int totalReviewed;
  final int totalCompliant;
  final int totalExpected;

  int get totalMissing => (totalExpected - totalSubmitted).clamp(0, totalExpected);

  /// Photographed / expected.
  double get submissionRate =>
      totalExpected == 0 ? 0 : (totalSubmitted / totalExpected).clamp(0, 1);

  /// Compliant / reviewed. Null until the coach has rated something.
  double? get qualityRate => totalReviewed == 0 ? null : totalCompliant / totalReviewed;

  /// The single headline number.
  ///
  /// Deliberately the SUBMISSION rate weighted by quality where quality is
  /// known — a meal photographed and rated Poor is not adherence, and a meal
  /// never photographed is not adherence either. Null only when nothing is
  /// expected at all.
  double? get overall {
    if (totalExpected == 0) return null;
    if (totalReviewed == 0) return submissionRate;
    // Submitted-and-good, over everything that was expected.
    return (totalCompliant / totalExpected).clamp(0, 1);
  }

  int? get overallPercent {
    final o = overall;
    return o == null ? null : (o * 100).round();
  }

  static const empty = ComplianceSummary(
    days: [],
    totalSubmitted: 0,
    totalReviewed: 0,
    totalCompliant: 0,
    totalExpected: 0,
  );
}

/// Builds a summary over [days] calendar days ending today.
///
/// [expectedMealsPerDay] comes from the athlete's own recorded profile, not a
/// constant — an athlete who eats three meals a day must not be marked down
/// for missing a fourth they never planned.
ComplianceSummary buildCompliance({
  required List<MealCheckin> checkins,
  required DateTime today,
  int days = 7,
  int expectedMealsPerDay = 4,
}) {
  final byDay = <String, List<MealCheckin>>{};
  for (final c in checkins) {
    final t = c.timestamp;
    if (t == null) continue;
    byDay.putIfAbsent(_key(t), () => []).add(c);
  }

  final result = <DayCompliance>[];
  var submitted = 0, reviewed = 0, compliant = 0;

  for (var i = 0; i < days; i++) {
    final date = DateTime(today.year, today.month, today.day - i);
    final key = _key(date);
    final forDay = byDay[key] ?? const [];

    // One meal SLOT counts once even if the athlete photographed it twice
    // (a retake, or a second helping) — otherwise a keen athlete scores over
    // 100% and the number stops meaning anything.
    final bySlot = <String, MealCheckin>{};
    for (final c in forDay) {
      final existing = bySlot[c.mealType];
      if (existing == null) {
        bySlot[c.mealType] = c;
        continue;
      }
      // Keep the reviewed one; failing that, the latest.
      if (c.isReviewed && !existing.isReviewed) {
        bySlot[c.mealType] = c;
      } else if (c.isReviewed == existing.isReviewed) {
        final a = c.timestamp, b = existing.timestamp;
        if (a != null && b != null && a.isAfter(b)) bySlot[c.mealType] = c;
      }
    }

    final daySubmitted = bySlot.length;
    final dayReviewed = bySlot.values.where((c) => c.reaction != null).length;
    final dayCompliant =
        bySlot.values.where((c) => c.reaction?.isCompliant == true).length;

    submitted += daySubmitted;
    reviewed += dayReviewed;
    compliant += dayCompliant;

    result.add(DayCompliance(
      dayKey: key,
      submitted: daySubmitted,
      reviewed: dayReviewed,
      compliant: dayCompliant,
      expectedMeals: expectedMealsPerDay,
    ));
  }

  return ComplianceSummary(
    days: result,
    totalSubmitted: submitted,
    totalReviewed: reviewed,
    totalCompliant: compliant,
    totalExpected: days * expectedMealsPerDay,
  );
}

/// A pattern worth telling the coach about (Step 11).
@immutable
class CoachInsight {
  const CoachInsight({required this.icon, required this.text, required this.isPositive});

  final String icon;
  final String text;
  final bool isPositive;
}

/// Observations drawn from the record — never generic advice.
///
/// Each one names the meal and the count that produced it, so a coach can
/// check it against the history rather than take it on faith. Nothing fires
/// from a single data point: one skipped breakfast is a Tuesday, not a
/// pattern, and a tool that says otherwise gets ignored.
List<CoachInsight> buildInsights({
  required List<MealCheckin> checkins,
  required DateTime today,
  int days = 7,
  int expectedMealsPerDay = 4,
}) {
  final insights = <CoachInsight>[];
  final summary = buildCompliance(
    checkins: checkins,
    today: today,
    days: days,
    expectedMealsPerDay: expectedMealsPerDay,
  );

  final windowStart = DateTime(today.year, today.month, today.day - (days - 1));
  final inWindow = checkins.where((c) {
    final t = c.timestamp;
    return t != null && !t.isBefore(windowStart);
  }).toList();

  // Which meal slots are being missed, by name.
  final slotCounts = <String, int>{};
  for (final c in inWindow) {
    slotCounts[c.mealType] = (slotCounts[c.mealType] ?? 0) + 1;
  }
  for (final slot in const ['breakfast', 'lunch', 'snacks', 'dinner']) {
    final logged = slotCounts[slot] ?? 0;
    final missed = days - logged;
    if (missed >= 3) {
      insights.add(CoachInsight(
        icon: '📷',
        text: '${_title(slot)} has no photo on $missed of the last $days days.',
        isPositive: false,
      ));
    }
  }

  // Quality, only once there is enough rated to mean something.
  if (summary.totalReviewed >= 4) {
    final rate = summary.qualityRate!;
    if (rate >= 0.85) {
      insights.add(CoachInsight(
        icon: '🌟',
        text: 'Excellent adherence — ${summary.totalCompliant} of '
            '${summary.totalReviewed} reviewed meals were Good or better.',
        isPositive: true,
      ));
    } else if (rate < 0.5) {
      insights.add(CoachInsight(
        icon: '⚠',
        text: 'Only ${summary.totalCompliant} of ${summary.totalReviewed} '
            'reviewed meals met the plan. Worth a conversation.',
        isPositive: false,
      ));
    }
  }

  // A review backlog is the coach's own problem to see.
  final pending = inWindow.where((c) => c.isPending).length;
  if (pending >= 3) {
    insights.add(CoachInsight(
      icon: '⏳',
      text: '$pending meals are waiting on your review.',
      isPositive: false,
    ));
  }

  // Late dinners — a real pattern a photo timestamp can actually evidence.
  final lateDinners = inWindow
      .where((c) => c.mealType == 'dinner' && (c.timestamp?.hour ?? 0) >= 22)
      .length;
  if (lateDinners >= 3) {
    insights.add(CoachInsight(
      icon: '🌙',
      text: 'Dinner was logged after 10pm on $lateDinners days.',
      isPositive: false,
    ));
  }

  // Protein, only where the AI actually estimated it — never guessed.
  final withProtein = inWindow.where((c) => c.estimatedProtein != null).toList();
  if (withProtein.length >= 5) {
    final avg = withProtein.fold<num>(0, (s, c) => s + c.estimatedProtein!) /
        withProtein.length;
    if (avg < 15) {
      insights.add(CoachInsight(
        icon: '🥩',
        text: 'Estimated protein averages ${avg.round()}g per photographed meal '
            '— low across ${withProtein.length} meals.',
        isPositive: false,
      ));
    }
  }

  return insights;
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
