/// Derived figures for a day of steps: distance, calories, active time.
///
/// All three are ESTIMATES computed from the step count, and the app says so.
/// A pedometer knows how many times you stepped — not how long your legs are,
/// how much you weigh, or how fast you were going. Where ZITLAS holds the
/// athlete's real height and weight (from the profile survey) those are used;
/// where it doesn't, a population average stands in and the figure is still
/// worth showing, but it must never be presented as measured.
library;

/// Fraction of standing height that a walking stride covers.
///
/// The widely used walking-stride approximation. Running stride is longer, but
/// a daily step total is overwhelmingly walking, and assuming otherwise would
/// inflate every distance shown.
const _strideToHeightRatio = 0.415;

/// Stand-ins when the profile has no height/weight yet. Chosen as adult
/// averages rather than anything flattering — an unknown body should not
/// produce a bigger number than a known one.
const _defaultHeightCm = 168.0;
const _defaultWeightKg = 70.0;

/// Typical walking cadence, steps per minute, used to estimate active time.
///
/// Only a fallback: Health Connect can report real exercise minutes, and when
/// it does that value wins. 100 spm is the standard moderate-intensity walking
/// cadence.
const _stepsPerActiveMinute = 100.0;

/// Metres covered per step for someone [heightCm] tall.
double strideLengthMetres({double? heightCm}) {
  final h = (heightCm != null && heightCm > 50 && heightCm < 260)
      ? heightCm
      : _defaultHeightCm;
  return (h / 100) * _strideToHeightRatio;
}

/// Estimated distance in kilometres.
double distanceKm({required int steps, double? heightCm}) {
  if (steps <= 0) return 0;
  return steps * strideLengthMetres(heightCm: heightCm) / 1000;
}

/// Estimated energy burned WALKING that distance, in kilocalories.
///
/// Uses the standard net walking cost of ~0.53 kcal per kg per kilometre,
/// which scales with both body mass and distance — the two things that
/// actually drive it. A flat "0.04 kcal per step" ignores both and is wrong by
/// a factor of two at the edges of a normal weight range.
///
/// This is NET of resting metabolism: it counts the cost of the walk, not the
/// calories the body would have burned sitting still over the same period.
/// Adding those in is how step apps end up crediting a sedentary day with
/// hundreds of "burned" calories.
int estimatedCalories({required int steps, double? weightKg, double? heightCm}) {
  if (steps <= 0) return 0;
  final kg = (weightKg != null && weightKg > 20 && weightKg < 400)
      ? weightKg
      : _defaultWeightKg;
  return (0.53 * kg * distanceKm(steps: steps, heightCm: heightCm)).round();
}

/// Estimated minutes spent moving, when nothing better is available.
///
/// Returns null for a step count too small to represent deliberate activity —
/// showing "1 min active" for 60 steps taken walking to the kitchen reads as
/// noise, and an absent figure is more honest than a meaningless one.
int? estimatedActiveMinutes({required int steps}) {
  if (steps < 500) return null;
  return (steps / _stepsPerActiveMinute).round();
}

/// Completion against a goal, capped at 100 — for progress BARS, which cannot
/// draw past full. Safe for a paused (0) goal.
int completionPercent({required int steps, required int goal}) {
  if (goal <= 0) return 100;
  return ((steps / goal) * 100).clamp(0, 100).round();
}

/// Completion against a goal, UNCAPPED — for the figure shown as text.
///
/// Someone who walked 12,500 against an 8,000 goal did 156%, and rounding that
/// down to "100%" erases the best thing about their day.
int completionPercentUncapped({required int steps, required int goal}) {
  if (goal <= 0) return 100;
  if (steps <= 0) return 0;
  return ((steps / goal) * 100).round();
}
