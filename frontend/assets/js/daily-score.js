/*!
 * ZITLAS — Daily Score formula (assets/js/daily-score.js)
 *
 * Pure function, no DOM/Firestore access, so it's independently testable
 * via the same Node.js mock-and-require harness pattern used for
 * payment-service.js this session (backend/tests equivalents live in
 * backend/tests; this file's tests are frontend-only, run with plain
 * `node`).
 *
 * Formula (product default — tunable later, not a hard spec):
 *   AI component     = average of (steps%, hydration%) — whichever exist.
 *   Coach component  = average of (meal quality, workout completion,
 *                       sleep%) — whichever exist. Coach-derived because
 *                       meal_checkins.score only exists for a Personal
 *                       Coaching relationship.
 *   Overall = 0.4 * AI + 0.6 * Coach when BOTH exist; otherwise whichever
 *             one exists (never fakes a missing side as 0 — an AI-only
 *             user with no coach still gets a real Overall from steps
 *             and hydration alone, not a score dragged down by an absent
 *             "coach" component).
 *
 * Any individual sub-score with no underlying data is OMITTED from its
 * component's average, not counted as 0 — e.g. no sleep logged today
 * doesn't drag the coach component down, it's just excluded until logged.
 *
 * Usage: ZitlasDailyScore.compute(inputs) -> {
 *   overall, aiScore, coachScore,
 *   subScores: { steps, hydration, mealQuality, workout, sleep }  (each 0-100 or null)
 * }
 *
 * inputs = {
 *   steps, stepsGoal,       // from window.ZitlasActivity
 *   waterMl, waterGoalMl,   // from window.ZitlasActivity.getTodayWellness()
 *   sleepHours,             // from window.ZitlasActivity.getTodayWellness(), normalized against an 8h target
 *   mealScoreAvg,           // 0-10 average of today's REVIEWED meal_checkins, or null
 *   workoutCompleted,       // true/false/null — null means "not tracked today" (no Firestore doc yet), NOT false
 * }
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.ZitlasDailyScore = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var SLEEP_TARGET_HOURS = 8;

  function pct(value, goal) {
    if (!goal || goal <= 0 || value == null) return null;
    return Math.min(100, Math.round((value / goal) * 100));
  }

  function average(values) {
    var present = values.filter(function (v) { return v != null; });
    if (!present.length) return null;
    return Math.round(present.reduce(function (a, b) { return a + b; }, 0) / present.length);
  }

  function compute(inputs) {
    inputs = inputs || {};

    var steps     = pct(inputs.steps, inputs.stepsGoal);
    var hydration = pct(inputs.waterMl, inputs.waterGoalMl);
    var mealQuality = (inputs.mealScoreAvg != null) ? Math.round(inputs.mealScoreAvg * 10) : null;
    var workout    = (inputs.workoutCompleted == null) ? null : (inputs.workoutCompleted ? 100 : 0);
    var sleep      = (inputs.sleepHours != null) ? Math.min(100, Math.round((inputs.sleepHours / SLEEP_TARGET_HOURS) * 100)) : null;

    var aiScore    = average([steps, hydration]);
    var coachScore = average([mealQuality, workout, sleep]);

    var overall;
    if (aiScore != null && coachScore != null) overall = Math.round(0.4 * aiScore + 0.6 * coachScore);
    else if (aiScore != null) overall = aiScore;
    else if (coachScore != null) overall = coachScore;
    else overall = null;

    return {
      overall: overall, aiScore: aiScore, coachScore: coachScore,
      subScores: { steps: steps, hydration: hydration, mealQuality: mealQuality, workout: workout, sleep: sleep },
    };
  }

  return { compute: compute, SLEEP_TARGET_HOURS: SLEEP_TARGET_HOURS };
});
