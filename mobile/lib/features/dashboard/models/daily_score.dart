/// Pure-function port of `frontend/assets/js/daily-score.js`'s
/// `ZitlasDailyScore.compute()` — no DOM/Firestore access there, so this is
/// a direct, formula-for-formula translation, not a reinterpretation.
class DailyScoreInputs {
  const DailyScoreInputs({
    this.steps,
    this.stepsGoal,
    this.waterMl,
    this.waterGoalMl,
    this.sleepHours,
    this.mealScoreAvg,
    this.workoutCompleted,
  });

  final int? steps;
  final int? stepsGoal;
  final int? waterMl;
  final int? waterGoalMl;
  final double? sleepHours;

  /// 0-10 average of today's *reviewed* meal_checkins, or null.
  final double? mealScoreAvg;

  /// null = "not tracked today".
  final bool? workoutCompleted;
}

class DailyScoreResult {
  const DailyScoreResult({
    required this.overall,
    required this.aiScore,
    required this.coachScore,
    required this.stepsPct,
    required this.hydrationPct,
    required this.mealQualityPct,
    required this.workoutPct,
    required this.sleepPct,
  });

  final int? overall;
  final int? aiScore;
  final int? coachScore;
  final int? stepsPct;
  final int? hydrationPct;
  final int? mealQualityPct;
  final int? workoutPct;
  final int? sleepPct;

  static const sleepTargetHours = 8;

  static int? _pct(num? value, num? goal) {
    if (value == null || goal == null || goal <= 0) return null;
    final pct = (value / goal * 100).round();
    return pct > 100 ? 100 : pct;
  }

  static int? _average(List<int?> values) {
    final present = values.whereType<int>().toList();
    if (present.isEmpty) return null;
    return (present.reduce((a, b) => a + b) / present.length).round();
  }

  factory DailyScoreResult.compute(DailyScoreInputs inputs) {
    final stepsPct = _pct(inputs.steps, inputs.stepsGoal);
    final hydrationPct = _pct(inputs.waterMl, inputs.waterGoalMl);
    final mealQualityPct = inputs.mealScoreAvg != null
        ? (inputs.mealScoreAvg! * 10).round()
        : null;
    final workoutPct = inputs.workoutCompleted == null
        ? null
        : (inputs.workoutCompleted! ? 100 : 0);
    int? sleepPct;
    if (inputs.sleepHours != null) {
      final raw = ((inputs.sleepHours! / sleepTargetHours) * 100).round();
      sleepPct = raw > 100 ? 100 : raw;
    }

    final aiScore = _average([stepsPct, hydrationPct]);
    final coachScore = _average([mealQualityPct, workoutPct, sleepPct]);

    int? overall;
    if (aiScore != null && coachScore != null) {
      overall = (0.4 * aiScore + 0.6 * coachScore).round();
    } else if (aiScore != null) {
      overall = aiScore;
    } else if (coachScore != null) {
      overall = coachScore;
    }

    return DailyScoreResult(
      overall: overall,
      aiScore: aiScore,
      coachScore: coachScore,
      stepsPct: stepsPct,
      hydrationPct: hydrationPct,
      mealQualityPct: mealQualityPct,
      workoutPct: workoutPct,
      sleepPct: sleepPct,
    );
  }
}
