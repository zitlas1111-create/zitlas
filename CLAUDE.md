# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the App

```bash
cd backend
uvicorn main:app --reload
```

Opens at `http://127.0.0.1:8000`. The FastAPI backend serves the entire frontend as static files (mounted last, catches all non-API routes). Root `/` redirects to the dashboard.

**Environment:** Create `backend/.env` with API keys:
- `GROQ_API_KEY` — primary LLM provider
- `GEMINI_API_KEY` — fallback provider
- `OPENROUTER_API_KEY` — second fallback

**Prebuilding RAG indexes** (run once before first start, or after adding PDFs):
```bash
cd backend
python prebuild_indexes.py
```

## Architecture

### Backend (`backend/`)

FastAPI server in `main.py`. All API prefixes:
- `/api/ai/*` — LLM generation endpoints (training plan, diet plan, SWOT, coach chat, meal swap, etc.)
- `/api/rag/*` — RAG knowledge base queries
- `/api/assessment/*` — three-brain assessment pipeline (mental → physical → nutrition)
- `/api/auth/*`, `/api/user/*`, `/api/diet/*`, `/api/review/*`, `/api/support/*`, `/api/system/*`

**AI provider chain** (`services/groq_service.py`): Groq (`openai/gpt-oss-120b`, intra-Groq fallback to `qwen/qwen3.6-27b` via `_groq_completion()`) → Gemini 2.5 Flash → OpenRouter. Failover is silent — all are tried before raising. Model IDs are env-overridable (`GROQ_PRIMARY_MODEL`/`GROQ_FALLBACK_MODEL`).

**RAG pipeline** (`services/rag_service.py` + `services/kb_manager.py`): 4 goal-specific knowledge bases (`weight_loss`, `muscle_gain`, `general_fitness`, `transformation`). FAISS indexes are lazy-loaded on first request and LRU-evicted (max 2 in RAM simultaneously). Pre-built indexes live in `backend/vector_store/<goal>/`. Source PDFs are NOT in the repo; only the serialized FAISS index and chunk pickle files are.

### Frontend (`frontend/`)

No build step — plain HTML/CSS/JS files served as static assets. No npm, no bundler, no TypeScript. Each page is a self-contained directory with its own `.html`, `.css`, and `.js`.

**Shared components:** `frontend/components/navbar.js`, `frontend/components/wallet.js`, `frontend/assets/js/firebase-config.js`, `frontend/assets/js/i18n.js` (loaded via `<script>` tags in each page's HTML).

**All JS files use an IIFE pattern** (`(function(){ 'use strict'; ... })()`), except `expert-dashboard.js` which is a plain top-level script.

### Key localStorage Keys

All state is localStorage-first. The most important keys:

| Key | Owner | Content |
|-----|-------|---------|
| `zitlas_diet_plan` | `diet.js`, `ai-coach.js`, `cprofile.js` | `{originalDietPlan, currentDietPlan, expertModifications, isExpertPlan, expertName, reviewedAt}` |
| `expert_plan_reviews` | `expert-dashboard.js` | Array of review objects with `status`, `reviewType`, `mealChangeHistory`, `reviewedDietPlan` |
| `zitlas_workout_plan` | `ai-coach.js`, `cprofile.js`, `weekly-plan.js`, `day.js` | Raw AI plan OR new schema `{originalWorkoutPlan, currentWorkoutPlan, workoutModifications, isExpertPlan, expertName, reviewedAt}` |
| `zitlas_roadmap` | `ai-coach.js` | Sport-specific roadmap (alternative workout format) |
| `zitlas_expert_review` | `expert-dashboard.js` (legacy) | Legacy single expert review with `modifiedDietPlan`/`modifiedWorkoutPlan` |
| `zitlas_firebase_user` | `firebase-config.js` | `{uid, email, displayName}` |
| `zitlas_goal` | `ai-coach.js` | `{type, current_value, target_value, end_date}` |
| `zitlas_calculations` | `ai-coach.js` | BMI, calorie targets, protein targets |

### Diet Modification System (the authoritative pattern)

This system is the template for all expert modification features.

**Schema** (`zitlas_diet_plan`):
```js
{
  originalDietPlan:    { days: [...] },   // untouched AI plan
  currentDietPlan:     { days: [...] },   // same as original (athlete swaps modify in-memory only)
  expertModifications: {
    "<dayIndex>": {
      "<mealKey>": { modified, modifiedBy, modifiedAt, oldMeal, newMeal }
    }
  },
  isExpertPlan: bool,
  expertName:   string,
  reviewedAt:   ISO string
}
```

**`_mealKey(name)`** — normalizes `"Breakfast"` → `"breakfast"`, used as the key in `expertModifications`.

**`buildEffectivePlan(storage)`** — deep-clones `currentDietPlan`, applies `expertModifications` on top. Sets `meal._expertModified = true`, `meal._modifiedBy`, `meal._modifiedAt` on modified meals. Runs before `normalizePlan()`.

**`normalizePlan(plan)`** — mutates in place: fills in missing `meal_name`, `color`, `emoji`, ensures `foods` is always an array of strings. Does NOT strip `_*` properties.

**`isNewDietSchema(obj)`** — `!!(obj && obj.originalDietPlan && obj.currentDietPlan)`.

**`loadDietStorage()`** — reads `zitlas_diet_plan`; if it's in old flat format (`{days:[...]}`), migrates and **persists** the migration immediately. Always returns the new schema or null.

**Expert review status values** that `getCompletedPlanReview()` accepts: `'review_completed'` OR `'completed'` (both are valid).

**`planIdMismatch` guard** — only rejects a review when BOTH `activePlanId` and `r.planId` are present and differ. A missing `r.planId` means the review predates the planId feature and is still valid.

**`showExpertReviewBanner(review)`** — calls `initExpertReviewBannerInteractions()` internally at the end. Do not call `initExpertReviewBannerInteractions()` separately after `showExpertReviewBanner()`.

**`init()` in `diet.js`** — new-schema path early-returns after rendering but ALSO checks `getCompletedPlanReview()` and shows the banner before returning, so the accept button is always wired on load.

### Expert Dashboard (`expert-dashboard.js`)

Top-level script (not IIFE). `EXPERT_DB` mirrors `COACH_DB` in `cprofile.js` — keep both in sync when adding experts.

- `buildEditableDietPlanEl(review, card)` — renders editable meal rows; sets `meal._edited = true` when expert saves a form
- `buildMealChangeHistory(origPlan, newPlan, expertName)` — diffs the original plan against the expert-edited plan by scanning for `meal._edited`, returns `mealChangeHistory[]`
- `savePlanEdits(reviewId, card, expert)` — sets `status = 'review_completed'`, saves `reviewedDietPlan` and `mealChangeHistory` to `expert_plan_reviews`
- When reading `review.planData` that may be in new schema format, always unwrap: `if (planData.originalDietPlan || planData.currentDietPlan) { planData = planData.currentDietPlan || planData.originalDietPlan; }`

### Athlete Accept Flow (cprofile.js)

`_buildDietStorageFromReview(review)` — builds the full new schema from a review object. Tries `mealChangeHistory` first; always also scans `reviewedDietPlan._edited` as a supplement/override (to handle cases where `newFoods` in history is empty). `_cpSaveDietStorage()` writes to `zitlas_diet_plan`.

### Workout Modification System (mirrors diet)

**Schema** (`zitlas_workout_modifications`):
```js
{
  originalWorkoutPlan:  { weekly_plan: [...] },  // untouched AI plan
  currentWorkoutPlan:   { weekly_plan: [...] },  // same as original
  workoutModifications: {
    "<dayIndex>": { modified, modifiedBy, modifiedAt, oldWorkout, newWorkout }
  },
  isExpertPlan: bool,
  expertName:   string,
  reviewedAt:   ISO string
}
```

`newWorkout` / `oldWorkout` shape: `{ focus, duration_minutes, exercises: [{name, sets, reps_or_duration}] }`

**`buildEffectiveWorkoutPlan(storage)`** — deep-clones `currentWorkoutPlan`, applies `workoutModifications` on top. Sets `day._modified`, `day._modifiedBy`, `day._modifiedAt`. In both `weekly-plan.js` and `day.js`.

**`buildWorkoutChangeHistory(origPlan, newPlan, expertName)`** — diffs by scanning `day._edited` flags. Returns `workoutChangeHistory[]`.

**`buildEditableWorkoutPlanEl(review, card)`** in `expert-dashboard.js` — sets `card._editedWorkoutPlan`. Edits are in-place mutations (same as diet).

**`_buildWorkoutStorageFromReview(review)`** in `cprofile.js` — mirrors `_buildDietStorageFromReview`. Saves to `zitlas_workout_plan` (same key as raw AI plan, new schema) via `_cpSaveWorkoutStorage()`.

### Workout Plan Sources (priority order)

Both `weekly-plan.js` and `day.js` try keys in this order:
1. `zitlas_expert_review` (legacy, `status === 'APPROVED'`, has `modifiedWorkoutPlan`)
2. `zitlas_roadmap` (sport/roadmap format, has `.days`)
3. `zitlas_workout_plan` — detects schema: if `originalWorkoutPlan || currentWorkoutPlan` → new expert-modified schema; otherwise → raw AI plan

New schema detection happens inside the `zitlas_workout_plan` read (step 3). If the new schema is detected and `workoutModifications` is non-empty, `buildEffectiveWorkoutPlan()` is applied before rendering.

`normalizeWeeklyPlan(wp)` handles schema variants: `wp.weekly_plan || wp.days || wp.weekly_schedule || wp.workout_days`.

**Day-level modification badge** — `renderFitnessDay` in `day.js` shows `✏️ Modified by Expert` only on days where `day._modified === true` when `expertReview.isNewModificationSystem === true` (new system). Legacy system shows banner on all days.

**Weekly plan badge** — per-day `wp-expert-badge` rendered automatically via existing `_expertModified` + `_expertMeta` mechanism in `renderDayList`.

## Deployment

Deployed on Render (see `render.yaml`). `rootDir: backend`, start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`. Frontend is served as static files by the same FastAPI process — no separate static host needed.
