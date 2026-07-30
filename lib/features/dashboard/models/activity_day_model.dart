/// Mirrors a single-day doc at `users/{uid}/activity/{date}` (see
/// `activity-service.js`) — steps/goal fields plus the additive wellness
/// fields (`waterMl`, `waterGoalMl`, `sleepHours`) the same doc carries.
/// `date` is `YYYY-MM-DD`.
class ActivityDayModel {
  const ActivityDayModel({
    required this.date,
    this.steps = 0,
    this.distance = 0,
    this.calories = 0,
    this.activeMinutes = 0,
    this.goal = 10000,
    this.goalEffective,
    this.recoveryMode = false,
    this.goalCompleted = false,
    this.waterMl,
    this.waterGoalMl = 2500,
    this.sleepHours,
    this.workoutCompleted,
  });

  final String date;
  final int steps;
  final double distance;
  final int calories;
  final int activeMinutes;

  /// The athlete's BASE step goal (`getEffectiveGoal().base` on the website).
  final int goal;

  /// Today's goal after any Recovery-Mode reduction — `getEffectiveGoal().goal`.
  /// `0` means a paused ("Rest") goal. Null on day docs written before this
  /// field existed, in which case [goal] is the effective goal.
  final int? goalEffective;

  /// `getEffectiveGoal().recovery` — health-status.js reduced/paused today.
  final bool recoveryMode;
  final bool goalCompleted;
  final int? waterMl;
  final int waterGoalMl;
  final double? sleepHours;

  /// The goal actually in force today (falls back to [goal] pre-field docs).
  int get effectiveGoal => goalEffective ?? goal;

  /// `getEffectiveGoal().rest` — a paused goal, i.e. a recovery rest day.
  bool get isRestDay => recoveryMode && effectiveGoal == 0;

  /// null = "not tracked today" (matches `daily-score.js`'s `workout: null`
  /// semantics — distinct from `false`, which would count as a miss).
  final bool? workoutCompleted;

  double get stepProgress =>
      effectiveGoal <= 0 ? 1 : (steps / effectiveGoal).clamp(0, 1);

  static ActivityDayModel empty(String date) => ActivityDayModel(date: date);

  factory ActivityDayModel.fromMap(String date, Map<String, dynamic> map) {
    return ActivityDayModel(
      date: date,
      steps: (map['steps'] as num?)?.toInt() ?? 0,
      distance: (map['distance'] as num?)?.toDouble() ?? 0,
      calories: (map['calories'] as num?)?.toInt() ?? 0,
      activeMinutes: (map['activeMinutes'] as num?)?.toInt() ?? 0,
      goal: (map['goal'] as num?)?.toInt() ?? 10000,
      goalEffective: (map['goalEffective'] as num?)?.toInt(),
      recoveryMode: map['recoveryMode'] as bool? ?? false,
      goalCompleted: map['goalCompleted'] as bool? ?? false,
      waterMl: (map['waterMl'] as num?)?.toInt(),
      waterGoalMl: (map['waterGoalMl'] as num?)?.toInt() ?? 2500,
      sleepHours: (map['sleepHours'] as num?)?.toDouble(),
      workoutCompleted: map['workoutCompleted'] as bool?,
    );
  }
}
