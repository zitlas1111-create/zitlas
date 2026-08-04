/// Mirrors the `goal` field on `users/{uid}` (see `cloud-sync.js`'s
/// `FIELD_MAP.goal -> zitlas_goal`) — the source of truth for the Current
/// Goal card on `dashboard.html`. Field names match `dashboard.js`'s
/// `saveGoal()` call shape exactly: `{type, currentVal, targetVal,
/// startDate, endDate}` — note there is NO `goalName` field; the website's
/// `saveGoal()` never sets one, and `renderGoalCard()`'s display name always
/// falls through to [goalNames] below.
class GoalModel {
  const GoalModel({
    required this.type,
    required this.currentVal,
    required this.targetVal,
    required this.startDate,
    required this.endDate,
  });

  final String type;
  final double currentVal;
  final double targetVal;
  final DateTime startDate;
  final DateTime endDate;

  /// `GOAL_NAMES` in dashboard.js.
  static const goalNames = {
    'Weight Loss': 'Lose Weight',
    'Eat Healthier': 'Eat Healthier',
    'Nutrition': 'Improve Nutrition',
    'Fitness': 'Improve Fitness',
    'Habits': 'Build Better Habits',
    'Custom': 'Personal Goal',
  };

  /// `GOAL_UNITS` in dashboard.js.
  static const goalUnits = {
    'Weight Loss': 'kg',
    'Eat Healthier': 'Score',
    'Nutrition': 'Score',
    'Fitness': 'Score',
    'Habits': 'Streak',
    'Custom': 'Value',
  };

  String get displayName => goalNames[type] ?? type;
  String get unit => goalUnits[type] ?? 'Value';

  /// `renderGoalCard()`: `Math.min(100, Math.round(current/target*100))`.
  int get progressPercent {
    if (targetVal == 0) return 0;
    final pct = (currentVal / targetVal * 100).round();
    return pct > 100 ? 100 : pct;
  }

  /// `calcDaysLeft()`: whole days between today and end date, floor at 0,
  /// null if no end date.
  int get daysLeft {
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = end.difference(today).inDays;
    return diff < 0 ? 0 : diff;
  }

  static GoalModel? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    try {
      return GoalModel(
        type: map['type'] as String? ?? 'Custom',
        currentVal: (map['currentVal'] as num?)?.toDouble() ?? 0,
        targetVal: (map['targetVal'] as num?)?.toDouble() ?? 0,
        startDate: DateTime.parse(map['startDate'] as String),
        endDate: DateTime.parse(map['endDate'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'currentVal': currentVal,
      'targetVal': targetVal,
      'startDate': startDate.toIso8601String().split('T').first,
      'endDate': endDate.toIso8601String().split('T').first,
    };
  }
}
