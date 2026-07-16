# ZITLAS — Goal Lifecycle & Coaching Data Architecture

**Status:** implemented 2026-07-16. This document is the audit + dependency map for the
fitness-journey data flow (goal → assessment → AI plans → nutritionist review →
personal coaching → goal reset), and the architectural contract every future
feature must follow.

---

## 1. The two architectural rules

### Rule 1 — Single source of truth: `users/{uid}`

`users/{uid}` (written by `assets/js/cloud-sync.js`) is the **only** canonical store
for goal-scoped athlete data:

| Field on `users/{uid}` | localStorage mirror | Meaning |
|---|---|---|
| `goal` | `zitlas_goal` | Current goal (type, current/target value, dates) |
| `assessment` | `zitlas_assessment` | Latest assessment (incl. `medical_conditions` free text) |
| `survey` | `zitlas_survey` | Raw assessment answers |
| `calculations` | `zitlas_calculations` | BMI / BMR / TDEE / targets |
| `swot` | `zitlas_swot` | AI SWOT |
| `dietPlan` | `zitlas_diet_plan` | AI diet plan (or expert-modification wrapper schema) |
| `workoutPlan` | `zitlas_workout_plan` | AI workout plan (or wrapper schema) |
| `roadmap` | `zitlas_roadmap` | Sport roadmap variant |
| `precautions` | `zitlas_precautions` | Medical rules-engine output |
| `planGeneratedAt` | `zitlas_plan_generated_at` | Generation timestamp |
| `planId` | `zitlas_plan_id` | **The goal epoch — see Rule 2** |

- The athlete's device reads/writes localStorage; cloud-sync mirrors both ways
  (`hydrateOnLoad`, `attachRealtime`, `save/saveBulk`).
- **Consumers on other devices (the coach's workspace) subscribe to `users/{uid}`
  directly.** Nothing may keep its own copy of this data. The old
  `coaching_plans/{uid}.athleteContext` copy is retired: it is no longer written or
  read anywhere (Goal Reset actively deletes it from existing docs).
- A cloud value of `null` means **cleared** — cloud-sync translates it to
  `localStorage.removeItem` on every device, which is how a reset propagates.

### Rule 2 — Goal epoch (`planId`): stamp at write, fail-closed at read

Every plan generation mints a fresh `planId` (`ai-coach.js saveToLocalStorage()`,
`'plan_' + Date.now()`). Every goal-scoped **artifact** records the `planId` it was
created under, and every **consumer** renders it only when
`artifact.planId === current planId` — *both present and equal*, otherwise the
artifact is treated as nonexistent.

Stamped artifacts:
- `review_requests/{id}.planId` — nutritionist/expert review requests (both the
  free flow in `cprofile.js` and the paid flow).
- `zitlas_expert_review.planId` — accepted legacy review object.
- `coaching_plans/{uid}.diet.planId` / `.training.planId` — coach-authored plans
  (stamped at save in `coaching-workspace.js`).
- **The plan wrapper schemas themselves** — `zitlas_diet_plan`
  (`{originalDietPlan, currentDietPlan, expertModifications, isExpertPlan, planId}`)
  and `zitlas_workout_plan` (`{originalWorkoutPlan, …, workoutModifications, planId}`),
  stamped at every creation site: accept flows (diet.js `acceptExpertPlan`,
  cprofile.js `_buildDietStorageFromReview`/`_buildWorkoutStorageFromReview` and
  the inline workout-accept), flat→wrapper migrations, and the swap-flow rewrap.

**Wrapper read policy** (`validateDietStorage()` in diet.js; mirrored inline in
weekly-plan.js and day.js for the workout wrapper):
- stamped + matching current `planId` → **valid**, render.
- stamped + mismatched (or no active goal) → **stale** — the whole wrapper
  belongs to a dead goal: it is DELETED locally *and* nulled on the `users/{uid}`
  mirror, then the page falls through to the no-plan/AI path.
- unstamped + expert layer (`isExpertPlan` or non-empty modifications) →
  **stale** — an expert claim that cannot prove which goal it was accepted
  under never renders. This was the final leak: nutritionist modifications
  baked into the wrapper survived resets with no identity to validate.
- unstamped + pure AI content → **adopted** — first-party content is stamped
  with the current planId in place (it is always written in the same
  lifecycle as `zitlas_plan_id`), so existing users' plans are undisturbed.

Fail-closed readers:
- `diet.js getCompletedPlanReview()` (nutritionist banner)
- `diet.js renderVerifyNutriSection()` ("Request Sent / Pending" card + verified badge)
- `diet.js` legacy `zitlas_expert_review` guard, `day.js`, `weekly-plan.js` (expert-modified plans)
- `diet.js applyCoachDiet()` / `weekly-plan.js applyCoachTraining()` (coach plans on athlete pages)
- `coaching-workspace.js` `coachPlanIsCurrent()` (editor drafts, viewers, header chips)
- `review-sync.js reconcileAnchor()` (may only *adopt* a live review whose `planId`
  matches the device's current one; with no current `planId` it adopts nothing)

**Why fail-closed:** cleanup-at-reset is a blacklist — every missed key or
collection leaks forever (this is exactly what happened). Validation-at-read is a
whitelist — even an artifact that cleanup missed can never render, because its
`planId` belongs to a dead epoch.

---

## 2. Goal Reset — exact contract

Trigger points: Dashboard **Reset Goal** modal (`dashboard.js`) and Diet page
**Reset Goal** button (`diet.js`). Both do, in order, and **await completion before
navigating**:

1. **localStorage purge** — all goal/assessment/plan/review/nutritionist keys
   (`clearAllGoalData()` in dashboard.js; the equivalent list in diet.js).
2. **`ZitlasCoachingReset.clearAll({ relationshipStatus: 'reset' })`**, which runs
   four parallel operations:
   - **Query-based review dismissal** — `review_requests where userId == uid` with a
     live status (`pending / in_progress / expert_reviewing / completed /
     review_completed`) → `status: 'dismissed'`. Query-based, so it works even when
     localStorage was already empty (the old ids-from-cache approach was the
     resurrection hole). Locally-cached ids are still dismissed as a supplement for
     legacy docs without `userId`.
   - **Relationship retirement** — `personal_coaching/{uid}.status = 'reset'`
     (never deleted: history, chat, ratings, wallet records survive; but no page
     treats `'reset'` as show-worthy).
   - **Published-context deletion** — removes the legacy
     `coaching_plans/{uid}.athleteContext` blob so old assessments/medical data
     can't be read from stale docs.
   - **`ZitlasCloudSync.clearGoalData()`** — nulls every goal-scoped field on
     `users/{uid}` (and removes the local mirrors). **This was the #1 root cause:**
     before this existed, `hydrateOnLoad()` restored every cleared localStorage key
     from the cloud on the next page load, undoing the reset.

After reset: no goal, no planId → every fail-closed reader renders the
brand-new-user state ("No Goal Set Yet" / AI-only pages / no banners / no snap
meal / no coach plans). What survives (by design): account identity,
`personalInfo`, wallet + transactions, chat history, notifications, activity/steps
history, coaching *history* (retired relationships, versioned coach plans).

Plan **regeneration** (new assessment via ai-coach.js) is a *replace*, not a reset:
it mints a new `planId`, overwrites all users/{uid} fields via `saveBulk`, clears
review caches, and calls `ZitlasCoachingReset.clearAll({})` (review dismissal only —
an active coaching relationship deliberately survives regeneration; the coach's
old plan silently retires via the planId mismatch and the workspace auto-seeds
from the new AI plan).

---

## 3. Personal Coaching data flow (after this fix)

```
ATHLETE DEVICE                         FIRESTORE                    COACH DEVICE
──────────────                         ─────────                    ────────────
ai-coach.js generates plan
  └─ saveBulk() ────────────────────▶ users/{uid}  ◀──────────────── coaching-workspace.js
     (goal, assessment, plans,          (SINGLE SOURCE OF TRUTH)      onSnapshot: Overview,
      calculations, planId…)                                          medical profile, AI-plan
                                                                      auto-seed — always LIVE
diet.js / weekly-plan.js               coaching_plans/{uid}
  render coach plan ONLY when   ◀───── diet{planId}, training{planId} ◀─ coach Save (stamps
  planId matches current                dietSelections, versions/        athlete's current planId)
                                        (coach-authored ONLY —
                                         athleteContext retired)
cprofile.js request ─────────────────▶ personal_coach_requests
                                       personal_coaching/{uid}
                                        status: pending→active→
                                        ended | expired | reset
```

The coach can never see stale data because there is nothing stale to read: the
workspace has **no copy** — it renders whatever `users/{uid}` says *right now*.
If the athlete resets, the coach's open workspace live-updates to "no active goal
yet"; when the athlete finishes a new assessment, it live-updates to the new data.

Medical conditions come **only** from `users/{uid}.assessment.medical_conditions`
(athlete-typed free text) + `precautions` (deterministic rules engine). No
conditions → the exact copy **"No medical conditions reported."** Never read from
coaching plans, review docs, or any cache.

---

## 4. Firestore collection audit

| Collection | Created by | Updated by | Read by | Goal Reset behavior | Should survive reset? | Duplication verdict |
|---|---|---|---|---|---|---|
| `users/{uid}` | login.js, cloud-sync.js | cloud-sync (`save/saveBulk/clearGoalData`), streak/activity services | every athlete page (hydrate), **coaching workspace (live)** | goal-scoped fields **nulled** by `clearGoalData()`; identity/wallet fields survive | Identity yes; goal fields no (cleared) | ✅ canonical — the one true copy |
| `review_requests/{id}` | cprofile.js (free + paid review flows) | expert flows (status), coaching-reset (**query-dismissal**) | review-sync.js, pending-requests-bar.js, cprofile.js | all live docs for uid → `status:'dismissed'` | As dismissed history only | carries a `context` snapshot for the expert to review — acceptable: it's an immutable *submission*, stamped with planId |
| `expert_plan_reviews` (localStorage) | review-sync.js merge | review-sync.js | diet.js banner/accept | cleared locally + can't re-adopt (fail-closed planId) | No | cache of review_requests — validated at read |
| `personal_coach_requests` | backend `/api/coaching/request` | backend accept/reject/sweeps | cprofile.js, expert-dashboard.js, wallet | untouched (escrow/money flow — backend owns lifecycle) | Yes (financial record) | ✅ no duplication |
| `personal_coaching/{uid}` | backend accept | backend sweeps, coaching-reset (`status:'reset'`), End Coaching | diet.js, weekly-plan.js, cprofile.js, expert-dashboard.js, workspace | `status → 'reset'` (retired, never deleted) | Yes, as retired history | ✅ relationship only — no athlete data |
| `coaching_plans/{uid}` | coach Save in workspace | coach Save; athlete `dietSelections`; coaching-reset deletes legacy `athleteContext` | workspace, diet.js, weekly-plan.js | plans retire via planId mismatch; legacy `athleteContext` deleted | Yes (coach IP / history via `versions/`) | was duplicating athlete data via `athleteContext` — **retired** |
| `coaching_plans/{uid}/versions` | coach Save | — | History sheet | untouched | Yes | ✅ audit trail |
| `meal_checkins`, `workout_checkins`, `coaching_meal_requests` | athlete actions | coach review | workspace, diet.js/day.js | untouched (gated by relationship status = post-reset invisible) | Yes (history) | ✅ |
| `chat_rooms/*` | either side | either side | chat UIs | untouched | Yes | ✅ |
| `meal_snap_logs/{uid}/{date}` | diet.js Snap Meal | — | diet.js (today only) | untouched (date-scoped, harmless) | Yes (personal log) | ✅ |
| `coaching_notifications`, `notifications` | both sides + backend | read/clear flows | toast + notification center | untouched | Yes | ✅ |

## 5. localStorage audit (goal-scoped keys)

Cleared by BOTH reset paths and (except plan keys being replaced) by regeneration:
`zitlas_goal, zitlas_survey, zitlas_assessment, zitlas_calculations, zitlas_swot,
zitlas_diet_plan, zitlas_workout_plan, zitlas_roadmap, zitlas_precautions,
zitlas_plan_id, zitlas_plan_generated_at, zitlas_current_diet,
zitlas_generated_diet, zitlas_meal_plan, zitlas_meal_swap_history, zitlas_sources,
zitlas_nutritionists, zitlas_workout_modifications, nutrition_* , mental_*,
physical_*, athlete_profile, athlete_summary, overall_score, athlete_tier,
development_priority, lifestyle_data, diet_rejected_foods` + every review key
(`zitlas_expert_review, zitlas_plan_versions, zitlas_review_request,
expert_plan_reviews, expert_review, expert_diet_override, reviewed_diet_plan,
modifiedBy, expertApproval, review_request, expertDiet, expertOverride,
dietOverride, reviewStatus, expertReviewedPlan, approvedPlan,
expertWorkoutOverride`).

Deliberately NOT cleared: `zitlas_firebase_user`, `zitlas_user`, `zitlas_token`,
`zitlas_wallet`, `zitlas_personal_info`, `zitlas_location`, theme/i18n/tutorial
flags, streaks, `zitlas_activity_*` (steps), `zitlas_health_today`,
`zitlas_step_perm_state`.

**Any new goal-scoped key or collection MUST (a) be added to the reset lists, and
(b) carry + validate `planId`. (b) is what saves you when (a) is forgotten.**

## 6. Known accepted trade-offs

- A coach plan authored before this deploy (no `planId` stamp) stops rendering
  until the coach re-saves — one click, the editor auto-seeds/preserves content,
  and old versions remain in History. Chosen deliberately over grandfathering,
  which would have kept exactly the stale-data class this fix eliminates.
- `review_requests.context` intentionally snapshots the plan the athlete asked to
  have reviewed (an immutable submission document, like an email attachment) —
  this is not "live data duplication".
- Pending `personal_coach_requests` (reserved money) are not auto-cancelled by a
  goal reset — money flows belong to the backend escrow lifecycle. A coach who
  accepts afterwards sees the athlete's *new* goal data (or the empty state) via
  the live `users/{uid}` subscription.
