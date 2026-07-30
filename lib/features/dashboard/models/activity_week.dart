import 'activity_day_model.dart';

/// One cell of the Mon–Sun strip under the step ring.
enum WeekDayStatus { done, missed, today, future }

class WeekDaySummary {
  const WeekDaySummary({required this.day, required this.date, required this.status});

  /// 'Mon'…'Sun'
  final String day;
  final String date;
  final WeekDayStatus status;

  /// The exact glyphs `renderStepCounterCard()` prints per status.
  String get mark => switch (status) {
    WeekDayStatus.done => '✅',
    WeekDayStatus.missed => '❌',
    WeekDayStatus.today => '·',
    WeekDayStatus.future => '–',
  };
}

/// Direct port of `ZitlasActivity.getWeeklySummary()` (activity-service.js
/// :205-227) — Mon..Sun of the CURRENT week. The website reads its 90-day
/// localStorage history cache; Flutter reads the same records from their
/// authoritative home, `users/{uid}/activity/{date}`, which the website
/// itself syncs every day doc to (`_syncDayToFirestore`).
List<WeekDaySummary> buildWeeklySummary({
  required Map<String, ActivityDayModel> history,
  required ActivityDayModel? today,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final todayStr = _dateStr(n);
  // Back to Monday — `(getDay() + 6) % 7` on the website; Dart's weekday is
  // already 1=Mon..7=Sun, so `weekday - 1` is the same offset.
  final monday = DateTime(n.year, n.month, n.day).subtract(Duration(days: n.weekday - 1));
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final out = <WeekDaySummary>[];
  for (var i = 0; i < 7; i++) {
    final d = monday.add(Duration(days: i));
    final ds = _dateStr(d);
    final rec = ds == todayStr ? today : history[ds];

    final WeekDayStatus status;
    if (ds.compareTo(todayStr) > 0) {
      status = WeekDayStatus.future;
    } else if (ds == todayStr) {
      status = (today?.goalCompleted ?? false) ? WeekDayStatus.done : WeekDayStatus.today;
    } else if (rec != null && rec.goalCompleted) {
      status = WeekDayStatus.done;
    } else {
      status = WeekDayStatus.missed;
    }
    out.add(WeekDaySummary(day: names[i], date: ds, status: status));
  }
  return out;
}

/// Direct port of `getAdaptiveGoalSuggestion()` (activity-service.js
/// :140-157). A SUGGESTION only — never a silent change.
class AdaptiveGoalSuggestion {
  const AdaptiveGoalSuggestion({
    required this.direction,
    required this.currentGoal,
    required this.suggestedGoal,
    required this.avg7day,
    required this.reason,
  });

  /// 'up' | 'down'
  final String direction;
  final int currentGoal;
  final int suggestedGoal;
  final int avg7day;
  final String reason;
}

/// Needs >= 5 archived days so two good days don't whipsaw the goal.
AdaptiveGoalSuggestion? computeAdaptiveGoalSuggestion({
  required Map<String, ActivityDayModel> history,
  required int goal,
}) {
  final dates = history.keys.toList()..sort();
  final recent = dates.length > 7 ? dates.sublist(dates.length - 7) : dates;
  if (recent.length < 5) return null;

  final total = recent.fold<int>(0, (s, d) => s + (history[d]?.steps ?? 0));
  final avg = (total / recent.length).round();

  if (avg >= goal * 1.15) {
    final up = ((goal * 1.1) / 500).round() * 500;
    return AdaptiveGoalSuggestion(
      direction: 'up',
      currentGoal: goal,
      suggestedGoal: up < goal + 2000 ? up : goal + 2000,
      avg7day: avg,
      reason: 'You averaged ${_thousands(avg)} steps this week — above your goal. '
          'Ready to raise it?',
    );
  }
  if (avg > 0 && avg < goal * 0.4) {
    final down = ((goal * 0.7) / 500).round() * 500;
    return AdaptiveGoalSuggestion(
      direction: 'down',
      currentGoal: goal,
      suggestedGoal: down > 3000 ? down : 3000,
      avg7day: avg,
      reason: 'You averaged ${_thousands(avg)} steps this week. A smaller target you '
          'can actually hit builds the habit faster.',
    );
  }
  return null;
}

/// `getStatusMessage()` (activity-service.js:190-200) — all four branches.
String activityStatusMessage(ActivityDayModel? day) {
  final steps = day?.steps ?? 0;
  final goal = day?.effectiveGoal ?? 10000;
  if (day?.isRestDay ?? false) {
    return '🛟 Rest day — step goal paused while you recover.';
  }
  if (steps >= goal) {
    final over = steps - goal;
    return over > 0
        ? "🏆 Amazing! You've exceeded today's goal by ${_thousands(over)} steps."
        : "🎉 Today's target completed!";
  }
  return '🚀 ${_thousands(goal - steps)} steps left today';
}

String _dateStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _thousands(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
