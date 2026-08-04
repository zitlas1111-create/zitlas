/*!
 * ZITLAS — Canonical Personal Coaching active/expiry gate (assets/js/coaching-gate.js)
 *
 * Single source of truth for "is this athlete's Personal Coaching relationship
 * currently usable." Before this file existed, the same status+expiry check
 * was duplicated three times and had drifted out of sync:
 *   - cprofile.js's _coachingIsActive (status + endDate) — correct.
 *   - cprofile.js's _coachingWorkspaceFor (status only) — missing the endDate
 *     check, meaning an athlete could open the paid Coaching Workspace via
 *     chat after their subscription expired but before the backend sweep
 *     (services/coaching_sweep.py) or a page refresh caught up.
 *   - diet.js's buildCoachMealRow gate for "Send Meal to Coach" (status only)
 *     — same gap.
 *   - expert-dashboard.js's listenForMyAthletes active-roster filter (status
 *     + endDate) — correct, kept here as the reference implementation.
 *
 * This is UI-side defense in depth, not the source of truth for security —
 * the backend sweep (30-day expiry) and Firestore Security Rules (gating
 * meal_checkins/coaching_plans/chat_rooms on the same status+endDateTs check,
 * documented separately for the Firebase Console) are what actually prevent
 * data access after expiry. This file exists so the UI reacts instantly
 * instead of waiting on either of those.
 *
 * Usage: ZitlasCoachingGate.evaluate(rel) -> {active, expired, daysRemaining, relationship}
 *   rel = a personal_coaching/{athleteUid} doc (or null/undefined).
 */
(function (win) {
  'use strict';

  function evaluate(rel) {
    if (!rel) return { active: false, expired: false, daysRemaining: null, relationship: null };

    var endDate = rel.endDate ? new Date(rel.endDate) : null;
    var pastEndDate = !!(endDate && endDate <= new Date());
    var active = rel.status === 'active' && !pastEndDate;
    var expired = rel.status === 'expired' || (rel.status === 'active' && pastEndDate);
    var daysRemaining = endDate ? Math.max(0, Math.ceil((endDate - new Date()) / 86400000)) : null;

    return { active: active, expired: expired, daysRemaining: daysRemaining, relationship: rel };
  }

  win.ZitlasCoachingGate = { evaluate: evaluate };
})(window);
