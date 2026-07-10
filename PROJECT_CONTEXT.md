# ZITLAS Project Context

## Folder Structure

```text
zitlas/
+-- backend/
|   +-- main.py
|   +-- requirements.txt
|   +-- routes/
|   |   +-- ai.py
|   |   +-- assessment.py
|   |   +-- auth.py
|   |   +-- chat.py
|   |   +-- diet.py
|   |   +-- player.py
|   |   +-- rag.py
|   |   +-- review.py
|   |   +-- support.py
|   |   +-- system.py
|   +-- services/
|   |   +-- assessment_service.py
|   |   +-- gemini_service.py
|   |   +-- groq_service.py
|   |   +-- kb_manager.py
|   |   +-- offline_fallback.py
|   |   +-- openrouter_service.py
|   |   +-- rag_service.py
|   +-- data/
|   |   +-- fitness_drills.json
|   |   +-- nutrition_guidelines.json
|   |   +-- nutri_foods.json
|   |   +-- nutri_index.json
|   +-- vector_store/
|   |   +-- weight_loss/
|   |   +-- muscle_gain/
|   |   +-- general_fitness/
|   |   +-- transformation/
|   +-- uploads/
|   |   +-- chat/
|   +-- weight_loss/
|   +-- Muscle_Gain/
|   +-- general fitness/
|   +-- transformation/
+-- frontend/
|   +-- index.html
|   +-- assets/
|   |   +-- js/
|   +-- components/
|   |   +-- navbar.js
|   |   +-- wallet.js
|   +-- pages/
|       +-- coaches/
|       +-- dashboard/
|       |   +-- ai-coach/
|       |   +-- training/
|       |   +-- weekly-plan/
|       +-- diet/
|       +-- dietitian/
|       +-- experts/
|       +-- login/
|       +-- profile/
+-- android/
+-- package.json
+-- capacitor.config.json
+-- render.yaml
```

## Architecture

ZITLAS is a static HTML/CSS/JS frontend served by a FastAPI backend.

`backend/main.py`:
- Loads environment variables from `backend/.env`.
- Initializes FastAPI.
- Registers all API routers under `/api/*`.
- Mounts `/uploads` for uploaded chat images.
- Mounts `frontend/` as the final catch-all static app.

The backend has three main responsibilities:
- Assessment calculations and plan generation.
- AI calls through Groq, with Gemini and OpenRouter fallback paths.
- RAG retrieval over FAISS indexes built from fitness/nutrition PDFs.

The frontend is localStorage-first. Most user, plan, review, expert, and chat state is stored in the browser rather than a persistent backend database.

## Important APIs

### Assessment

- `GET /api/assessment/health`
  - Health check.

- `POST /api/assessment/analyze`
  - Pure Python assessment.
  - No LLM call.
  - Returns `assessment`, `calculations`, and `swot`.

- `POST /api/assessment/generate-plan`
  - Main plan generation endpoint.
  - Flow: assessment calculations -> RAG retrieval -> AI diet plan -> AI workout plan.
  - Returns:
    - `assessment`
    - `calculations`
    - `swot`
    - `diet_plan`
    - `workout_plan`
    - `sources`
    - `meta`

### AI

- `GET /api/ai/health`
  - AI module health check.

- `POST /api/ai/chat`
  - General Zino assistant chat.
  - Uses RAG context based on `user_context.fitness_goal`.

- `POST /api/ai/nutrition-weekly-plan`
  - Generates a 7-day nutrition plan from user profile, nutrition assessment, lifestyle data, and rejected foods.
  - Falls back to `offline_fallback.nutrition_weekly_plan` if providers fail.

- `POST /api/ai/swap-meal`
  - Replaces one meal with an alternative.
  - Uses RAG context, Groq generation, local validation, and offline fallback.

- `POST /api/ai/coach-start`
  - Starts AI coach conversation.

- `POST /api/ai/coach-chat`
  - Handles one turn of AI coach conversation.

- `POST /api/ai/coach-finalize`
  - Builds complete profile from collected coach conversation data.

Other AI endpoints exist for SWOT, training plan, diet plan, goal plan, elite weekly plan, coach recommendation, mental/physical/nutrition questions, and assessments.

### RAG

- `POST /api/rag/query`
  - Direct RAG query with source attribution.
  - Uses FAISS search and then LLM answer generation.

- `GET /api/rag/status`
  - RAG readiness and currently loaded KB stats.

- `GET /api/system/kb-status`
  - Knowledge base cache state.
  - Shows loaded goal-specific KBs and cache size.

### Review

- `POST /api/review/submit`
  - Athlete submits plan for expert review.
  - Backend stores in memory only.

- `GET /api/review/expert/{expert_id}`
  - Returns review requests from the in-memory store for one expert.

- `GET /api/review/{request_id}`
  - Returns one review request from memory.

- `PATCH /api/review/{request_id}/status`
  - Updates review status in memory.

- `POST /api/review/{request_id}/approve`
  - Expert approves or publishes a revised plan.
  - Backend stores approval in memory only.

### Support And Uploads

- `POST /api/support/contact`
  - Sends support email through SMTP.
  - Requires `SUPPORT_EMAIL` and `SUPPORT_EMAIL_PASSWORD`.

- `POST /api/chat/upload`
  - Uploads chat images.
  - Accepts jpg/jpeg/png/webp up to 10 MB.
  - Returns public `/uploads/chat/...` URL.

### Placeholder APIs

- `GET /api/auth/health`
- `GET /api/user/health`
- `GET /api/diet/health`

These are currently health/future-route placeholders. Login and user persistence are mostly frontend/Firebase/localStorage driven.

## LocalStorage Keys

### Auth And Session

- `zitlas_token`
- `zitlas_user_role`
- `zitlas_firebase_user`
- `zitlas_expert_id`
- `zitlas_expert_applied`
- `zitlas_athlete_id`
- `user`
- `zitlas_user`

Session storage:
- `zitlas_guest`
- `zitlas_pending_action`
- `user`

### Preferences

- `zitlas_theme`
- `zitlas_lang`

### Assessment And Plan State

- `zitlas_survey`
- `zitlas_goal`
- `zitlas_assessment`
- `zitlas_calculations`
- `zitlas_swot`
- `zitlas_sources`
- `zitlas_plan_id`
- `zitlas_plan_generated_at`
- `zitlas_plan_versions`

Legacy or related keys:
- `nutrition_weekly_plan`
- `athlete_profile`
- `athlete_summary`
- `overall_score`
- `athlete_tier`
- `development_priority`
- `mental_scores`
- `mental_swot`
- `mental_recommendations`
- `mental_assessment`
- `physical_scores`
- `physical_swot`
- `physical_recommendations`
- `physical_bottleneck`
- `physical_assessment`
- `lifestyle_data`
- `nutrition_scores`
- `nutrition_swot`
- `nutrition_recommendations`
- `nutrition_bottleneck`
- `nutrition_assessment`

### Diet And Workout Plans

- `zitlas_diet_plan`
  - New schema:
    - `originalDietPlan`
    - `currentDietPlan`
    - `expertModifications`
    - `isExpertPlan`

- `zitlas_workout_plan`
  - New schema:
    - `originalWorkoutPlan`
    - `currentWorkoutPlan`
    - `workoutModifications`
    - `isExpertPlan`
    - `expertName`
    - `reviewedAt`

- `zitlas_meal_swap_history`

### Review And Expert State

- `zitlas_review_request`
- `zitlas_expert_review`
- `expert_plan_reviews`
- `zitlas_expert_profile`

Older/compatibility keys that are cleared during new plan/review flows:
- `expert_review`
- `expert_diet_override`
- `reviewed_diet_plan`
- `modifiedBy`
- `expertApproval`
- `review_request`
- `expertDiet`
- `expertOverride`
- `dietOverride`
- `reviewStatus`
- `expertReviewedPlan`
- `approvedPlan`
- `expertWorkoutOverride`

Session storage:
- `zitlas_modify_expert`
- `ed_open_chat`

### Chat And Wallet

- `zitlas_chats`
- `zitlas_wallet`

### Profile

- `zitlas_personal_info`

## User Flows

### Login / Role Flow

1. User opens login page.
2. Frontend writes demo or Firebase-derived auth state to localStorage.
3. Role is stored in `zitlas_user_role`.
4. Athlete users go to dashboard.
5. Expert users go to expert dashboard.

The backend auth module currently only exposes a health check. Real auth enforcement is not implemented in FastAPI.

### Athlete Assessment Flow

1. User opens dashboard AI coach.
2. User selects goal:
   - weight loss
   - muscle gain
   - general fitness
   - transformation
3. User answers assessment questions.
4. `frontend/pages/dashboard/ai-coach/ai-coach.js` builds the payload.
5. Frontend calls `POST /api/assessment/generate-plan`.
6. Backend returns assessment, calculations, SWOT, diet plan, workout plan, and RAG sources.
7. Frontend saves the result to localStorage.
8. Dashboard, diet page, weekly plan page, and training day page read from localStorage.

## Diet Generation Flow

### Primary Diet Plan From Assessment

1. `ai-coach.js` calls `POST /api/assessment/generate-plan`.
2. `assessment.py` runs `run_assessment(body)`.
3. Backend chooses RAG queries based on `fitness_goal`.
4. `rag_service.retrieve_context` loads/searches the goal-specific FAISS KB.
5. `_generate_diet_plan` builds a prompt using:
   - user profile
   - calculated calories/protein/water/steps
   - goal type
   - diet preference
   - living situation
   - retrieved RAG context
6. `groq_service.chat` sends JSON-mode LLM request.
7. Backend parses the LLM JSON.
8. Response includes `diet_plan`.
9. Frontend stores:

```json
{
  "originalDietPlan": "...",
  "currentDietPlan": "...",
  "expertModifications": {},
  "isExpertPlan": false
}
```

under `zitlas_diet_plan`.

### Nutrition Weekly Plan Endpoint

The diet page can also call `POST /api/ai/nutrition-weekly-plan`.

Input:
- `user_profile`
- `nutrition_assessment`
- `lifestyle_data`
- `rejected_foods`

Backend:
1. Calls `groq_service.generate_nutrition_weekly_plan`.
2. If all providers fail, returns `offline_fallback.nutrition_weekly_plan`.
3. Expects a structured 7-day meal plan.

## Workout Generation Flow

1. `ai-coach.js` calls `POST /api/assessment/generate-plan`.
2. `assessment.py` runs the assessment calculations.
3. Backend builds a workout RAG query based on `fitness_goal`:
   - weight loss
   - muscle gain
   - general fitness
   - transformation
4. `rag_service.retrieve_context` retrieves goal-specific workout context.
5. `_generate_workout_plan` selects a system prompt based on the goal.
6. The prompt includes:
   - workout preference
   - available time
   - BMI/intensity rules
   - equipment assumptions
   - health goal or transformation details
   - RAG context
7. `groq_service.chat` generates JSON.
8. Backend parses workout JSON.
9. Frontend stores:

```json
{
  "originalWorkoutPlan": "...",
  "currentWorkoutPlan": "...",
  "workoutModifications": {},
  "isExpertPlan": false,
  "expertName": null,
  "reviewedAt": null
}
```

under `zitlas_workout_plan`.

Weekly and day views read `zitlas_workout_plan`, normalize older formats when needed, and render either AI or expert-modified workout data.

## Expert Review Flow

There are two related review paths: diet page verification and coach profile review request. Both rely heavily on localStorage.

### Athlete Sends Review

1. Athlete has an AI-generated plan in localStorage.
2. Athlete selects an expert/nutritionist.
3. Frontend builds a review request containing:
   - assessment
   - calculations
   - SWOT
   - diet plan
   - workout plan
   - goal
   - plan id
   - expert id
   - athlete info
4. Frontend stores request in `zitlas_review_request`.
5. Frontend may call `POST /api/review/submit`.
6. Coach profile flow also stores the review packet inside `zitlas_chats`.
7. If Firebase/Firestore is available, some review requests may also be written there.

### Expert Reviews

1. Expert dashboard reads `zitlas_review_request`, `expert_plan_reviews`, and/or chat review packets.
2. Expert can approve or modify diet/workout.
3. Expert actions update localStorage:
   - `zitlas_expert_review`
   - `expert_plan_reviews`
   - `zitlas_diet_plan`
   - `zitlas_workout_plan`
   - `zitlas_plan_versions`
4. Expert approval may call `POST /api/review/{request_id}/approve`.

### Athlete Receives Review

1. Diet, weekly plan, training day, and coach profile pages check for expert review data.
2. If `planId` matches the active `zitlas_plan_id`, expert modifications are applied.
3. New plan generation clears stale expert review keys to prevent old reviews applying to new plans.

Important risk: `/api/review/*` stores requests in process memory only. Browser localStorage is the real source of truth in most current flows.

## Swap Meal Flow

1. User opens diet page and selects a meal to swap.
2. Frontend collects:
   - meal name
   - meal time
   - current foods
   - reason
   - athlete profile
   - lifestyle data
   - rejected foods
   - previous suggestions
   - fitness goal
3. Frontend calls `POST /api/ai/swap-meal`.
4. Backend builds a RAG query like healthy alternatives for the selected meal and fitness goal.
5. Backend retrieves RAG context from the matching KB.
6. Backend calls `groq_service.generate_meal_swap`.
7. If provider call fails, backend uses `offline_fallback.meal_swap`.
8. Frontend validates returned foods:
   - rejects malformed prompt-leak strings
   - rejects foods already in the rejected list
   - retries up to 2 times
9. User accepts swap.
10. Frontend updates the active day meal inside `weeklyPlan`.
11. Frontend saves updated plan back to `zitlas_diet_plan`.
12. Frontend saves per-meal swap history in `zitlas_meal_swap_history`.

## RAG And KB Flow

Knowledge bases are split by goal:

- `weight_loss`
- `muscle_gain`
- `general_fitness`
- `transformation`

`kb_manager.py` lazy-loads one goal KB on demand and caches up to `MAX_LOADED_KBS = 2` KBs in memory. Older KBs are evicted with LRU behavior.

Each KB uses:
- `faiss.index`
- `chunks_metadata.pkl`
- `pdf_hashes.json`

`rag_service.py` handles:
- PDF text extraction
- document chunking
- embedding generation
- FAISS index creation/loading
- semantic search
- prompt construction
- source attribution

## AI Provider Flow

Primary model:
- Groq `openai/gpt-oss-120b` (env: `GROQ_PRIMARY_MODEL`)

Fallbacks:
- Groq `qwen/qwen3.6-27b` (intra-Groq retry, env: `GROQ_FALLBACK_MODEL`)
- Gemini `gemini-2.5-flash`
- OpenRouter models:
  - `deepseek/deepseek-chat`
  - `meta-llama/llama-3.3-70b-instruct`
  - `qwen/qwen-3-32b`

Offline fallback exists for:
- nutrition weekly plan
- meal swap
- coach finalize profile

## Known Risks

- Most app state is in localStorage, not a backend database.
- Review API state is in memory and resets on server restart.
- Backend auth is not implemented beyond health check.
- Sensitive fitness and profile data is stored client-side.
- Review state can drift between localStorage, in-memory API, chat packets, and Firestore if enabled.
- Some flows depend on Firebase config placeholders.
- RAG and embedding model loading can be memory-heavy on constrained deployments.
- Several files contain encoding/mojibake artifacts in comments or visible strings.
- CORS currently allows only local origins.
- Generated AI JSON can fail parsing; some endpoints return `None` plans rather than a fully recovered response.
