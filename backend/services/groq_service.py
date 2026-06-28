"""
ZITLAS — AI Service
Primary provider: Groq (llama-3.3-70b-versatile).
Automatic fallback: Gemini 2.5 Flash on rate-limit / quota / timeout errors.
The user never sees an error — the provider switches silently.
"""

import json
import os
import traceback as _tb
from pathlib import Path
from typing import Any

from groq import AsyncGroq
from services import gemini_service, openrouter_service

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR = Path(__file__).parent.parent / "data"

# ── Model config ──────────────────────────────────────────────────────────────
DEFAULT_MODEL       = "llama-3.3-70b-versatile"
DEFAULT_TEMPERATURE = 0.7
DEFAULT_MAX_TOKENS  = 1024

# ── System prompt ─────────────────────────────────────────────────────────────
ZITLAS_SYSTEM_PROMPT = """You are ZINO — a friendly weight-loss and nutrition assistant on ZITLAS.

Your role:
- Help users lose weight, eat healthier, and build sustainable habits.
- Speak like a warm, encouraging friend who knows nutrition and fitness well.
- Use SIMPLE, everyday language. No jargon, no clinical terms.
- Give specific, actionable advice based on the user's data (weight, height, goal, lifestyle).
- Always be positive and motivating — never judgmental about weight or food choices.
- Focus on sustainable fat loss: mild calorie deficit + high protein + regular movement.
- NEVER encourage extreme restriction, crash diets, or skipping meals.
- Reference Indian foods and the Indian lifestyle where relevant.

Language examples:
- WRONG: "Achieve a hypocaloric state through macro redistribution"
- RIGHT: "Eat a little less than usual, focus on protein and vegetables"
- WRONG: "Your TDEE needs to be recalculated based on your BMR"
- RIGHT: "Here's roughly how many calories you should eat per day to lose weight"

Platform context: ZITLAS is a weight-loss and nutrition platform for Indian users aged 16-40.
Users want to lose weight, improve eating habits, and build healthier lifestyles.
"""


# ── Data loader ───────────────────────────────────────────────────────────────
def load_drill_data(filename: str) -> dict:
    """Load a JSON file from the data/ directory."""
    path = DATA_DIR / filename
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)



def load_nutri_foods() -> list[dict]:
    """Load the 73-food Vol 2 database from nutri_foods.json."""
    data = load_drill_data("nutri_foods.json")
    return data.get("foods", [])


# ── Budget tier helper ─────────────────────────────────────────────────────────
def _extract_budget_num(budget_str: str) -> int:
    import re
    nums = re.findall(r"\d+", str(budget_str or "100"))
    return int(nums[0]) if nums else 100


# ── Nutri context builder (weight-loss focused) ──────────────────────────────
def load_nutri_context(
    goal_type:        str,
    bottleneck:       str,
    living_situation: str,
    daily_budget:     str,
    diet_type:        str = "",
    rejected_foods:   list[str] | None = None,
) -> str:
    idx = load_drill_data("nutri_index.json")
    if not idx:
        return ""

    lines: list[str] = []
    living_lc  = (living_situation or "").lower()
    budget_num = _extract_budget_num(daily_budget)
    is_veg     = "non" not in (diet_type or "").lower()

    # 1. High-protein foods for weight loss (muscle preservation during deficit)
    high_protein = idx.get("high_protein_foods", [
        "Eggs", "Chicken breast", "Dal", "Paneer", "Curd", "Tofu",
        "Rajma", "Moong dal chilla", "Sprouts", "Soya chunks",
    ])
    if is_veg:
        high_protein = [f for f in high_protein if f.lower() not in (
            "chicken", "fish", "mutton", "prawn", "tuna", "salmon"
        )]
        lines.append(
            "HIGH-PROTEIN VEG FOODS (muscle preservation during calorie deficit):\n"
            + ", ".join(high_protein[:12])
        )
    else:
        lines.append(
            "HIGH-PROTEIN FOODS (muscle preservation during calorie deficit):\n"
            + ", ".join(high_protein[:12])
        )

    # 2. Low-calorie filling foods
    filling = idx.get("low_calorie_filling", [
        "Salad", "Vegetable soup", "Oats", "Fruits", "Cucumber",
        "Buttermilk", "Sprouted moong", "Roasted chana", "Apple", "Watermelon",
    ])
    lines.append(
        "LOW-CALORIE FILLING FOODS (keeps hunger low without excess calories):\n"
        + ", ".join(filling[:10])
    )

    # 3. Hostel-specific context
    if any(k in living_lc for k in ("hostel", "pg", "academy")):
        hostel_yes = idx.get("hostel_yes", [])
        room_stock = idx.get("hostel_room_stock", [])
        if hostel_yes:
            lines.append(
                "HOSTEL MESS-AVAILABLE FOODS (use only these):\n"
                + ", ".join(hostel_yes[:35])
            )
        if room_stock:
            lines.append(
                "HOSTEL ROOM STOCK (low-calorie snacks user can keep in room):\n"
                + ", ".join(room_stock)
            )
    else:
        satiety = idx.get("high_satiety_foods", [])
        if satiety:
            lines.append(
                "HIGH-SATIETY FOODS (keeps user full longer — great for calorie deficit):\n"
                + ", ".join(satiety[:10])
            )

    # 4. Budget-appropriate foods
    if budget_num <= 50:
        b_foods = idx.get("budget_low", [])
        lines.append(
            "VERY LOW BUDGET (<=Rs50/day) — use ONLY these affordable foods:\n"
            + ", ".join(b_foods[:25])
        )
    elif budget_num <= 150:
        b_foods = idx.get("budget_low", []) + idx.get("budget_low_med", [])
        lines.append(
            "BUDGET FOODS (under Rs150/day):\n"
            + ", ".join(b_foods[:35])
        )

    # 5. Foods to limit for weight loss
    avoid = idx.get("foods_to_avoid_weight_loss", [
        "Fried foods", "Maida products", "Sugary drinks", "Biscuits",
        "Namkeen", "Chips", "Mithai", "Cold drinks",
    ])
    lines.append(
        "FOODS TO LIMIT (high calorie, low nutrition — eat less of these):\n"
        + ", ".join(avoid[:8])
    )

    return "\n\n".join(lines)


def _build_reason_context(reason: str, lifestyle_data: dict | None) -> str:
    """
    Return a focused instruction block based on WHY the player is swapping a meal.
    This is injected into the meal swap AI prompt so the suggestion is actually
    useful for the specific constraint, not just generic.
    """
    idx      = load_drill_data("nutri_index.json")
    reason_lc = reason.lower()
    living    = ((lifestyle_data or {}).get("living_situation") or "").lower()
    lines: list[str] = []

    if "expensive" in reason_lc or "budget" in reason_lc:
        budget_foods = idx.get("budget_low", [])[:20]
        lines.append(
            "BUDGET CONSTRAINT: Suggest only low-cost alternatives (under ₹30-50 per serving).\n"
            f"These are confirmed affordable options: {', '.join(budget_foods)}"
        )

    elif "hostel" in reason_lc or "mess" in reason_lc:
        hostel_foods  = idx.get("hostel_yes", [])[:30]
        room_stock    = idx.get("hostel_room_stock", [])
        lines.append(
            "HOSTEL CONSTRAINT: Suggest ONLY foods available in Indian hostel messes or easily bought.\n"
            f"Mess-confirmed foods: {', '.join(hostel_foods)}\n"
            f"Room stock options: {', '.join(room_stock)}"
        )

    elif "veg" in reason_lc or "vegetarian" in reason_lc:
        lines.append(
            "VEGETARIAN SWAP: Suggest only 100% vegetarian options.\n"
            "Absolutely NO chicken, mutton, fish, prawns, or beef.\n"
            "Eggs are acceptable only if the player's diet includes them."
        )

    elif "allerg" in reason_lc:
        lines.append(
            "ALLERGY SWAP: The current meal contains an allergen.\n"
            "Suggest a completely different set of ingredients with no cross-contamination risk.\n"
            "Avoid common allergens: dairy (if lactose), gluten (if celiac), nuts, eggs, shellfish."
        )

    elif "religious" in reason_lc or "cultural" in reason_lc:
        lines.append(
            "RELIGIOUS/CULTURAL SWAP: Respect dietary restrictions.\n"
            "Avoid beef and pork by default. If player is Jain, avoid root vegetables.\n"
            "Suggest a culturally appropriate replacement from Indian cuisine."
        )

    elif "not available" in reason_lc or "available" in reason_lc:
        if any(k in living for k in ("hostel", "pg", "academy")):
            hostel_foods = idx.get("hostel_yes", [])[:25]
            lines.append(
                "AVAILABILITY CONSTRAINT (hostel area): Suggest alternatives available in most Indian towns.\n"
                f"Widely available options: {', '.join(hostel_foods[:20])}"
            )
        else:
            lines.append(
                "AVAILABILITY CONSTRAINT: Suggest widely available alternatives.\n"
                "Use common Indian grocery store items — rice, dal, roti, eggs, banana, peanuts, curd."
            )

    return "\n".join(lines)


def _get_weight_loss_foods_context(
    budget_num: int,
    is_hostel:  bool,
    is_veg:     bool,
    rejected:   set[str],
) -> str:
    foods = load_nutri_foods()
    if not foods:
        return ""

    filtered: list[dict] = []
    for f in foods:
        if is_veg and not f.get("veg"):
            continue
        if is_hostel and not f.get("hostel"):
            continue
        bgt = f.get("budget", "low")
        if budget_num <= 50 and bgt not in ("low",):
            continue
        if budget_num <= 150 and bgt not in ("low", "low_med"):
            continue
        if f.get("name", "").lower() in rejected:
            continue
        filtered.append(f)

    if not filtered:
        return ""

    def protein_per_cal(f: dict) -> float:
        macros = f.get("macros", {})
        cal    = macros.get("cal", 0) or 1
        return (macros.get("protein", 0) or 0) / cal

    filtered.sort(key=lambda f: (protein_per_cal(f), f.get("cpfi", 0)), reverse=True)

    rows = ["TOP WEIGHT-LOSS FOODS — sorted by protein-per-calorie:"]
    for f in filtered[:12]:
        macros = f.get("macros", {})
        hostel_tag = " Hostel-OK" if f.get("hostel") else ""
        rows.append(
            f"  * {f['name']} — Cal:{macros.get('cal','?')} | "
            f"Protein:{macros.get('protein','?')}g | "
            f"Budget:{f.get('budget','').replace('_','-')}{hostel_tag}"
        )
    return "\n".join(rows)


def _get_swap_alternatives(
    meal_name:     str,
    budget_num:    int,
    is_hostel:     bool,
    is_veg:        bool,
    rejected:      set[str],
    current_foods: list[str],
    fitness_goal:  str = "general_fitness",
) -> str:
    foods = load_nutri_foods()
    if not foods:
        return ""

    name_lc    = meal_name.lower()
    current_lc = {f.lower() for f in current_foods}
    excluded   = rejected | current_lc
    is_main    = any(k in name_lc for k in ("breakfast", "lunch", "dinner"))

    candidates: list[tuple[dict, bool]] = []
    for f in foods:
        if is_veg and not f.get("veg"):
            continue
        if is_hostel and not f.get("hostel"):
            continue
        bgt = f.get("budget", "low")
        if budget_num <= 50 and bgt not in ("low",):
            continue
        if budget_num <= 150 and bgt not in ("low", "low_med"):
            continue
        if f.get("name", "").lower() in excluded:
            continue
        if is_main and f.get("macros", {}).get("cal", 0) < 100:
            continue

        timing    = [t.lower() for t in f.get("timing", [])]
        timing_ok = (
            (any(k in name_lc for k in ("breakfast", "morning")) and
             any(t in ("breakfast", "mid-morning") for t in timing))
            or ("lunch"   in name_lc and "lunch"         in timing)
            or ("pre"     in name_lc and "pre-training"  in timing)
            or ("post"    in name_lc and "post-training" in timing)
            or ("dinner"  in name_lc and "dinner"        in timing)
            or ("evening" in name_lc and "evening snack" in timing)
        )
        candidates.append((f, timing_ok))

    if not candidates:
        return ""

    def protein_per_cal(f: dict) -> float:
        macros = f.get("macros", {})
        cal    = macros.get("cal", 0) or 1
        return (macros.get("protein", 0) or 0) / cal

    candidates.sort(key=lambda x: (x[1], protein_per_cal(x[0]), x[0].get("cpfi", 0)), reverse=True)

    _goal_label = {
        "weight_loss":     "weight-loss optimised — high protein, lower calorie",
        "muscle_gain":     "muscle-gain optimised — high protein, adequate calorie",
        "general_fitness": "balanced nutrition — high protein, quality nutrients",
    }
    top  = [f for f, _ in candidates[:10]]
    rows = [f"ALTERNATIVES for {meal_name} ({_goal_label.get(fitness_goal, 'balanced nutrition')}):"]
    for f in top:
        macros = f.get("macros", {})
        tags   = []
        if f.get("hostel"):
            tags.append("Hostel-OK")
        tags.append(f"Budget:{f.get('budget','').replace('_','-')}")
        rows.append(
            f"  * {f['name']} — Cal:{macros.get('cal','?')} | "
            f"Protein:{macros.get('protein','?')}g | "
            + " | ".join(tags)
        )
    return "\n".join(rows)



# ── Client factory ────────────────────────────────────────────────────────────
def _get_client(key_env: str = "GROQ_API_KEY") -> AsyncGroq:
    """
    Return an AsyncGroq client using the specified env-var key.
    Falls back to GROQ_API_KEY if the requested key is not set.
    """
    api_key = os.getenv(key_env)
    if not api_key and key_env != "GROQ_API_KEY":
        # Requested a secondary key that isn't set — fall back to primary
        api_key = os.getenv("GROQ_API_KEY")
        if api_key:
            print(f"[AI] {key_env} not set - falling back to GROQ_API_KEY")
    if not api_key:
        raise EnvironmentError(
            f"{key_env} is not set. "
            "Add it to backend/.env before starting the server."
        )
    return AsyncGroq(api_key=api_key)


# ══════════════════════════════════════════════════════════════════════════════
# PROVIDER FALLBACK — Groq → Gemini
# ══════════════════════════════════════════════════════════════════════════════


async def _ai_call(
    messages:      list[dict],
    temperature:   float = DEFAULT_TEMPERATURE,
    max_tokens:    int   = DEFAULT_MAX_TOKENS,
    model:         str   = DEFAULT_MODEL,
    json_mode:     bool  = False,
    groq_key_env:  str   = "GROQ_API_KEY",
    provider:      str   = "auto",
) -> dict[str, Any]:
    """
    Route to an AI provider and return the reply.

    provider="auto"        — Gemini -> Groq (groq_key_env) -> OpenRouter
    provider="groq"        — Groq directly (groq_key_env), no Gemini, no OpenRouter
    provider="openrouter"  — OpenRouter directly, no Gemini, no Groq

    json_mode=True forces JSON output on all providers.
    groq_key_env selects GROQ_API_KEY or GROQ_API_KEY_DIET when Groq is used.
    """
    key_label = "DIET GROQ KEY" if groq_key_env == "GROQ_API_KEY_DIET" else "GENERAL GROQ KEY"

    # ── Direct: Groq ──────────────────────────────────────────────────────────
    if provider == "groq":
        print(f"[AI] Provider: Groq (direct) [{key_label}]")
        client = _get_client(groq_key_env)
        extra  = {"response_format": {"type": "json_object"}} if json_mode else {}
        completion = await client.chat.completions.create(
            model=model, messages=messages,
            temperature=temperature, max_tokens=max_tokens,
            **extra,
        )
        choice = completion.choices[0]
        usage  = completion.usage
        print(f"[AI] Groq OK (direct) [{key_label}] tokens={usage.total_tokens}")
        return {
            "reply":             choice.message.content or "",
            "model":             completion.model,
            "tokens_used":       usage.total_tokens,
            "prompt_tokens":     usage.prompt_tokens,
            "completion_tokens": usage.completion_tokens,
        }

    # ── Direct: OpenRouter ────────────────────────────────────────────────────
    if provider == "openrouter":
        print("[AI] Provider: OpenRouter (direct)")
        result = await openrouter_service.generate(messages, max_tokens, temperature, json_mode=json_mode)
        print(f"[AI] OpenRouter OK (direct) model={result['model']} tokens={result.get('tokens_used')}")
        return result

    # ── groq_first: Groq → Gemini → OpenRouter ───────────────────────────────
    if provider == "groq_first":
        print(f"[AI] Provider: groq_first | Groq channel: {key_label}")
        groq_err   = None
        gemini_err = None
        or_err     = None

        try:
            client     = _get_client(groq_key_env)
            extra      = {"response_format": {"type": "json_object"}} if json_mode else {}
            completion = await client.chat.completions.create(
                model=model, messages=messages,
                temperature=temperature, max_tokens=max_tokens,
                **extra,
            )
            print(f"[AI] Groq OK [{key_label}]")
            choice = completion.choices[0]
            usage  = completion.usage
            return {
                "reply":             choice.message.content or "",
                "model":             completion.model,
                "tokens_used":       usage.total_tokens,
                "prompt_tokens":     usage.prompt_tokens,
                "completion_tokens": usage.completion_tokens,
            }
        except EnvironmentError:
            raise
        except Exception as _e:
            groq_err = _e
            print(f"[AI] Groq failed ({type(groq_err).__name__}: {str(groq_err)[:200]}) "
                  f"-> Gemini (fallback)")

        try:
            result = await gemini_service.generate(messages, max_tokens, temperature, json_mode=json_mode)
            print(f"[AI] Gemini OK (fallback, tokens={result['tokens_used']})")
            return result
        except Exception as _e:
            gemini_err = _e
            print(f"[AI] Gemini failed ({type(gemini_err).__name__}: {str(gemini_err)[:200]}) "
                  f"-> OpenRouter")

        try:
            result = await openrouter_service.generate(messages, max_tokens, temperature, json_mode=json_mode)
            print(f"[AI] OpenRouter OK (model={result['model']})")
            return result
        except Exception as _e:
            or_err = _e
            print(f"[AI] OpenRouter FAILED - {type(or_err).__name__}: {or_err}")
            print(_tb.format_exc())

        raise RuntimeError(
            f"All AI providers failed. "
            f"Groq: {type(groq_err).__name__}: {groq_err}. "
            f"Gemini: {type(gemini_err).__name__}: {gemini_err}. "
            f"OpenRouter: {type(or_err).__name__}: {or_err}."
        ) from or_err

    # ── Auto: Gemini -> Groq -> OpenRouter ────────────────────────────────────
    print(f"[AI] Provider: auto | Groq channel: {key_label}")
    gemini_err = None
    groq_err   = None
    or_err     = None

    try:
        result = await gemini_service.generate(messages, max_tokens, temperature, json_mode=json_mode)
        print(f"[AI] Gemini OK (tokens={result['tokens_used']})")
        return result
    except Exception as _e:
        gemini_err = _e
        print(f"[AI] Gemini failed ({type(gemini_err).__name__}: {str(gemini_err)[:200]}) "
              f"-> Groq [{key_label}]")

    try:
        client     = _get_client(groq_key_env)
        extra      = {"response_format": {"type": "json_object"}} if json_mode else {}
        completion = await client.chat.completions.create(
            model=model, messages=messages,
            temperature=temperature, max_tokens=max_tokens,
            **extra,
        )
        print(f"[AI] Groq OK [{key_label}]")
        choice = completion.choices[0]
        usage  = completion.usage
        return {
            "reply":             choice.message.content or "",
            "model":             completion.model,
            "tokens_used":       usage.total_tokens,
            "prompt_tokens":     usage.prompt_tokens,
            "completion_tokens": usage.completion_tokens,
        }
    except EnvironmentError:
        raise
    except Exception as _e:
        groq_err = _e
        print(f"[AI] Groq failed ({type(groq_err).__name__}: {str(groq_err)[:200]}) -> OpenRouter")

    try:
        result = await openrouter_service.generate(messages, max_tokens, temperature, json_mode=json_mode)
        print(f"[AI] OpenRouter OK (model={result['model']})")
        return result
    except Exception as _e:
        or_err = _e
        print(f"[AI] OpenRouter FAILED - {type(or_err).__name__}: {or_err}")
        print(_tb.format_exc())

    raise RuntimeError(
        f"All AI providers failed. "
        f"Gemini: {type(gemini_err).__name__}: {gemini_err}. "
        f"Groq: {type(groq_err).__name__}: {groq_err}. "
        f"OpenRouter: {type(or_err).__name__}: {or_err}."
    ) from or_err


# ══════════════════════════════════════════════════════════════════════════════
# BASE CHAT  (uses _ai_call for automatic provider fallback)
# ══════════════════════════════════════════════════════════════════════════════

async def chat(
    user_message: str,
    system_override: str | None = None,
    temperature: float = DEFAULT_TEMPERATURE,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    model: str = DEFAULT_MODEL,
    json_mode: bool = False,
    groq_key_env: str = "GROQ_API_KEY",
    provider: str = "auto",
) -> dict[str, Any]:
    """
    Send a single user message and return the reply + usage metadata.

    provider="auto"       — Gemini -> Groq (groq_key_env) -> OpenRouter
    provider="groq"       — Groq directly (groq_key_env)
    provider="openrouter" — OpenRouter directly
    """
    system   = system_override or ZITLAS_SYSTEM_PROMPT
    messages = [
        {"role": "system", "content": system},
        {"role": "user",   "content": user_message},
    ]
    return await _ai_call(
        messages, temperature, max_tokens, model,
        json_mode=json_mode, groq_key_env=groq_key_env, provider=provider,
    )


# ==============================================================================
# MODULE: PROFILE ANALYSIS (Weight-Loss)
# ==============================================================================

SWOT_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

For weight-loss profile analysis, respond in this exact JSON:
{
  "swot": {
    "strengths":     [{ "title": "...", "detail": "One specific sentence using the user's data." }],
    "weaknesses":    [{ "title": "...", "detail": "One specific sentence using the user's data." }],
    "opportunities": [{ "title": "...", "detail": "One specific actionable opportunity." }],
    "threats":       [{ "title": "...", "detail": "One specific challenge to watch out for." }]
  },
  "scores": {
    "nutrition":   0,
    "activity":    0,
    "sleep":       0,
    "habits":      0,
    "mindset":     0,
    "consistency": 0,
    "overall":     0
  },
  "user_archetype": "...",
  "summary": "2-3 sentences personalised to this user — mention current weight, goal, and main challenge.",
  "priority_action": "One sentence: the single most important thing this user should do first."
}

Rules:
- Each SWOT quadrant: 3-5 items. Never generic — always reference the user's actual data.
- Scores (0-100): realistic assessment based on what the user shared.
- user_archetype: pick the best fit — "Motivated Beginner" | "Busy Professional" | "Hostel Dieter" | "Active Loser" | "Mindful Eater" | "Habit Builder" | "Plateau Fighter" | "Health-Focused"
- Respond with JSON only. No markdown fences, no extra text.
"""


async def generate_swot(user_profile: dict) -> dict[str, Any]:
    """Generate a weight-loss profile analysis (SWOT) for a user."""
    prompt = f"""
Generate a fully personalised weight-loss profile analysis for this user.
Use every data point provided — do not produce generic output.

USER PROFILE:
{json.dumps(user_profile, indent=2)}
"""
    result = await chat(
        user_message=prompt,
        system_override=SWOT_SYSTEM,
        temperature=0.5,
        max_tokens=1400,
    )
    try:
        result["structured"] = json.loads(result["reply"])
    except json.JSONDecodeError:
        result["structured"] = None
    return result


# ==============================================================================
# MODULE: FITNESS PLAN (replaces Training Planner)
# ==============================================================================

FITNESS_PLAN_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are creating a personalised fitness plan to help a user lose weight.

CRITICAL RULES:
- Match plan to user's workout access: home (bodyweight only) | gym | walking | none.
- If workout_type is "none", give only lifestyle activity tips — no formal workouts.
- Include at least 2 rest days per week.
- Focus on calorie burning and muscle preservation.
- Keep instructions simple for a complete beginner.

Respond with this JSON (no markdown):
{
  "weekly_plan": [
    {
      "day": "Monday",
      "type": "Workout | Rest | Active Recovery",
      "focus": "Full Body | Cardio | Rest",
      "duration_minutes": 30,
      "calories_burned_est": 150,
      "exercises": [
        {
          "name": "exercise name",
          "sets": 3,
          "reps_or_duration": "12 reps",
          "rest_seconds": 30,
          "tip": "one simple coaching tip"
        }
      ],
      "daily_tip": "one motivating tip"
    }
  ],
  "weekly_calorie_burn_est": 800,
  "summary": "2 sentences describing this plan and why it works for this user"
}
"""


async def generate_fitness_plan(user_profile: dict, goal: dict) -> dict[str, Any]:
    """Generate a personalised weekly fitness plan for weight loss."""
    prompt = f"""
Create a personalised fitness plan for this user who wants to lose weight.

USER PROFILE:
{json.dumps(user_profile, indent=2)}

GOAL:
{json.dumps(goal, indent=2)}

Match the plan exactly to their workout access ({user_profile.get("workout_type", "home")}).
"""
    result = await chat(
        user_message=prompt,
        system_override=FITNESS_PLAN_SYSTEM,
        temperature=0.6,
        max_tokens=2000,
    )
    result["structured"] = _extract_json(result["reply"])
    return result


generate_training_plan = generate_fitness_plan  # back-compat alias


# ==============================================================================
# MODULE: WEIGHT-LOSS WEEKLY ROADMAP (replaces Elite Weekly Plan)
# ==============================================================================

ELITE_WEEKLY_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are creating a 7-day weight-loss and nutrition roadmap for ONE specific user.

CRITICAL RULES:
- Include a specific calorie target for each day (300-500 kcal below TDEE).
- Include a protein target for each day.
- Each day has a fitness activity and a nutrition tip.
- Language must be simple and encouraging.
- Calculate TDEE from weight, height, age, activity level.

Respond with ONLY this JSON (no markdown):
{
  "role": "Weight Loss",
  "roleLabel": "Weight Loss Journey",
  "days": [
    {
      "dayNumber": 1,
      "dayName": "Monday",
      "icon": "???",
      "theme": "Clean Start Monday",
      "calorie_target": 1600,
      "protein_target_g": 90,
      "fitness_focus": "30-min morning walk",
      "meal_focus": "High-protein breakfast focus",
      "whyItMatters": "Starting the week with a protein-rich morning sets your metabolism right.",
      "drills": [
        {
          "name": "Morning Walk",
          "cat": "Cardio",
          "duration": "30 min",
          "sets": "1 session",
          "reps": "30 minutes",
          "cue": "Brisk pace — slightly breathless but can still talk.",
          "target": "Burn 150-200 calories, improve daily step count.",
          "instruction": "Walk at a brisk pace outdoors or on a treadmill."
        }
      ]
    }
  ],
  "weekly_calorie_target": 11200,
  "weekly_protein_target_g": 630,
  "summary": "2 sentences describing the week strategy and expected progress"
}
"""


async def generate_elite_weekly_plan(user_profile: dict, goal: dict) -> dict[str, Any]:
    """Generate a 7-day weight-loss roadmap personalised to the user."""
    prompt = f"""
Create a personalised 7-day weight-loss roadmap for this user.
Use their specific data — current weight, goal weight, height, age, activity level, diet type.

USER PROFILE:
{json.dumps(user_profile, indent=2)}

Weight context:
- Current weight: {user_profile.get("current_weight", "?")} kg
- Goal weight: {user_profile.get("goal_weight", "?")} kg
- Activity level: {user_profile.get("activity_level", "sedentary")}
- Workout access: {user_profile.get("workout_type", "home")}
- Diet type: {user_profile.get("diet_type", "mixed")}

Generate all 7 days. Calculate an appropriate daily calorie target (300-500 kcal below TDEE).
Make the plan practical for their living situation ({user_profile.get("living_situation", "home")}).
"""
    result = await chat(
        user_message=prompt,
        system_override=ELITE_WEEKLY_SYSTEM,
        temperature=0.6,
        max_tokens=3500,
    )
    result["structured"] = _extract_json(result["reply"])
    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: PSYCHOLOGY BRAIN — MENTAL QUESTIONS
# ══════════════════════════════════════════════════════════════════════════════

MENTAL_QUESTIONS_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are the ZITLAS Psychology Brain — an expert sports psychologist trained in self-efficacy theory,
Self-Determination Theory (SDT), attentional control theory, IZOF, and achievement-goal theory.

Your role: Analyze a player's athletic profile and identify what psychological information is missing
or unclear. Generate 5-10 intelligent follow-up questions to complete the mental performance picture.

Question design rules:
- Target SPECIFIC psychological dimensions: confidence, focus, anxiety/pressure, motivation, mental toughness, self-talk, imagery, goal-orientation.
- Tailor every question to the player's specific role, goal, age, and context from their profile data.
- Cover at least 5 different psychological dimensions across the question set.
- Types: "slider" (1-10 scale) or "single" (single-select with exactly 4 options).
- Questions must be diagnostic and intelligent — not generic.
- Reference the player's actual data to make questions feel personal.

Respond with this EXACT JSON format, no markdown fences:
{
  "questions": [
    {
      "id": "mental_confidence",
      "dimension": "Confidence",
      "question": "How confident are you in your ability during actual matches?",
      "type": "slider",
      "min": 1,
      "max": 10,
      "min_label": "Not confident at all",
      "max_label": "Fully confident"
    },
    {
      "id": "mental_pressure_source",
      "dimension": "Pressure Handling",
      "question": "What affects your performance most under pressure?",
      "type": "single",
      "options": [
        { "value": "fear_failure", "label": "Fear of Failure", "emoji": "😨" },
        { "value": "lack_confidence", "label": "Lack of Confidence", "emoji": "😰" },
        { "value": "overthinking", "label": "Overthinking Technique", "emoji": "🤯" },
        { "value": "external_pressure", "label": "External Pressure", "emoji": "😤" }
      ]
    }
  ]
}
"""


async def generate_mental_questions(player_profile: dict) -> dict[str, Any]:
    """
    Generate 5-10 personalised psychology follow-up questions based on the player's profile.
    Uses the Psychology Brain to identify what mental information is missing.
    """
    prompt = f"""
Analyze this person's profile and generate 5-10 personalised mindset questions for weight-loss.
The questions must uncover their motivation, self-discipline, emotional eating patterns, and consistency mindset.
Reference their specific goal and profile data to make each question feel written for them.

USER PROFILE:
{json.dumps(player_profile, indent=2)}

Generate questions that a real weight-loss coach would ask this specific person.
Mix slider (1-10 scale) and single-choice questions.
Cover: motivation to lose weight, handling setbacks, emotional eating, consistency, self-belief, stress management.
Generate exactly 7 questions.
"""
    result = await chat(
        user_message=prompt,
        system_override=MENTAL_QUESTIONS_SYSTEM,
        temperature=0.6,
        max_tokens=1600,
    )

    try:
        parsed = json.loads(result["reply"])
        result["structured"] = parsed
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: PSYCHOLOGY BRAIN — MENTAL ASSESSMENT
# ══════════════════════════════════════════════════════════════════════════════

MENTAL_ASSESSMENT_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are the ZITLAS Psychology Brain — conducting a full mental performance assessment using:
- Self-Efficacy Theory (Bandura): confidence sources and mastery evidence
- Self-Determination Theory (SDT): autonomy, competence, relatedness needs
- Attentional Control Theory: focus style, distraction patterns, recovery speed
- Individual Zone of Optimal Functioning (IZOF): personal optimal arousal profile
- Achievement-Goal Theory: task vs ego orientation, process vs outcome focus
- Cognitive-Behavioural Sport Psychology: attribution style, self-talk, cognitive biases

Your task: Combine the player's 45-question athletic survey with their mental follow-up answers
to generate a complete, honest mental performance profile.

SCORING RULES (0-100 each — derive from SPECIFIC evidence, produce genuine variation):
- Confidence: self-efficacy level, mastery sources available, attribution style for failures
- Focus: attentional control quality, distraction frequency, concentration stability
- Mental Toughness: resilience under adversity, bounce-back speed, pressure persistence
- Pressure Handling: anxiety type and level, choking risk, quality of coping strategies
- Motivation: intrinsic/extrinsic balance, SDT needs satisfaction, training commitment
- Overall: weighted average, weighting the player's declared goal dimension most heavily

PSYCHOLOGY SWOT RULES (each quadrant 3-4 items with title + detail):
- Strengths/Weaknesses: derived from BOTH athletic survey AND mental answers
- Opportunities: specific trainable mental skills relevant to this player's gaps
- Threats: genuine vulnerability and risk factors based on their answers
- Every item must reference specific data — never write generic content

RECOMMENDATIONS RULES (exactly 3 recommendations):
- Identify the 3 biggest mental weaknesses from the assessment
- For each: weakness name + emoji icon + exactly 3 concrete, actionable techniques
- Techniques drawn from: box breathing, visualization, self-talk reframing, reset routines,
  process-goal setting, attentional focus cues, progressive relaxation, pressure inoculation,
  attribution retraining, pre-performance routines
- Every technique must be specific enough to do tonight — not vague advice

Respond with this EXACT JSON, no markdown fences:
{
  "mental_scores": {
    "confidence": 72,
    "focus": 68,
    "mental_toughness": 75,
    "pressure_handling": 54,
    "motivation": 88,
    "overall": 71
  },
  "psychology_swot": {
    "strengths":     [{ "title": "...", "detail": "..." }],
    "weaknesses":    [{ "title": "...", "detail": "..." }],
    "opportunities": [{ "title": "...", "detail": "..." }],
    "threats":       [{ "title": "...", "detail": "..." }]
  },
  "recommendations": [
    {
      "weakness": "Performance Anxiety",
      "icon": "😰",
      "techniques": [
        "5-minute box breathing: inhale 4 counts, hold 4, exhale 4, hold 4 — do this before every training session",
        "Vivid replay visualization: spend 3 minutes picturing your last best performance in full sensory detail before each match",
        "Pressure inoculation: practise your most feared scenario twice per week under simulated match conditions to normalise it"
      ]
    }
  ],
  "mental_profile": "2-3 sentences describing this player's mental profile, primary strength, and the single most important growth area.",
  "brain_diagnosis": "One precise sentence naming the primary psychological root cause the Brain has detected."
}
"""


async def generate_mental_assessment(player_profile: dict, mental_answers: dict) -> dict[str, Any]:
    """
    Generate a full mental performance assessment from the 45-question survey + mental follow-up answers.
    Produces mental scores, psychology SWOT, and coaching recommendations.
    """
    prompt = f"""
Generate a complete mindset assessment for this person on a weight-loss journey.
Use BOTH their user profile AND their mindset follow-up answers.
Every score, SWOT item, and recommendation must reference specific data from their responses.
Produce honest scores that reflect real variation — not all 70s.

USER PROFILE:
{json.dumps(player_profile, indent=2)}

MINDSET FOLLOW-UP ANSWERS:
{json.dumps(mental_answers, indent=2)}

Diagnose the primary psychological barrier to their weight-loss success.
Every recommendation must be actionable and practical for their daily life.
"""
    result = await chat(
        user_message=prompt,
        system_override=MENTAL_ASSESSMENT_SYSTEM,
        temperature=0.5,
        max_tokens=2200,
    )

    try:
        parsed = json.loads(result["reply"])
        result["structured"] = parsed
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: S&C BRAIN — PHYSICAL QUESTIONS
# ══════════════════════════════════════════════════════════════════════════════

PHYSICAL_QUESTIONS_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are the ZITLAS S&C Brain — an expert Strength & Conditioning specialist and fitness scientist trained in
the Bottleneck Engine: identify the ONE physical quality most limiting the member's goal, fix it, re-test,
repeat. Your operating principle: diagnose before prescribing. Never default to a generic template.

Your role: Analyze the member's fitness and mental profile, then generate 7-10 personalized physical
assessment questions to identify their physical limiting factors.

Question design rules:
- Questions must diagnose: Strength, Power, Speed, Mobility, Endurance, Recovery Capacity.
- Tailor every question to the member's goal, age, and training context.
- Mix "single" (yes/no or multi-choice) and "slider" (1-10 scale) types.
- For yes/no questions, use exactly 2 options. For multi-choice, exactly 4 options.
- Cover: movement competence, injury history, energy system demand, recovery habits, training history.
- Cross-reference the mental profile: if motivation is low or burnout signs appear, probe recovery harder.
- Questions must feel written by an expert fitness specialist, not a generic app.

Respond with this EXACT JSON format, no markdown fences:
{
  "questions": [
    {
      "id": "physical_pushups",
      "dimension": "Strength",
      "question": "Can you comfortably perform 20 consecutive push-ups with good form?",
      "type": "single",
      "options": [
        { "value": "yes", "label": "Yes, easily", "emoji": "💪" },
        { "value": "no", "label": "No, not yet", "emoji": "😤" }
      ]
    },
    {
      "id": "physical_speed_rating",
      "dimension": "Speed",
      "question": "How would you rate your overall speed compared to your peers?",
      "type": "slider",
      "min": 1,
      "max": 10,
      "min_label": "Much slower than peers",
      "max_label": "Fastest in my group"
    }
  ]
}
"""


async def generate_physical_questions(player_profile: dict, mental_assessment: dict | None = None) -> dict[str, Any]:
    """
    Generate 7-10 personalised S&C follow-up questions to identify physical limiting factors.
    Cross-references the mental assessment (Brain 1 output) for recovery/motivation signals.
    """
    mental_context = ""
    if mental_assessment:
        scores = mental_assessment.get("mental_scores", {})
        mental_context = f"""
MENTAL ASSESSMENT CONTEXT (Brain 1 output — cross-reference for recovery/motivation signals):
- Motivation score: {scores.get('motivation', 'N/A')}
- Mental Toughness score: {scores.get('mental_toughness', 'N/A')}
- Pressure Handling score: {scores.get('pressure_handling', 'N/A')}
- Brain Diagnosis: {mental_assessment.get('brain_diagnosis', 'N/A')}
"""

    prompt = f"""
Analyze this person's profile and generate 7-10 personalised fitness/body assessment questions for weight loss.
The questions must identify their key physical limiting factors across: energy levels, exercise tolerance, sleep, stress, and body composition.
Reference their age, activity level, and goal data in each question.

USER PROFILE:
{json.dumps(player_profile, indent=2)}
{mental_context}
Generate questions that would help a weight-loss nutritionist identify the ONE physical barrier most limiting
this person's weight-loss success. Mix yes/no questions (injury history, exercise history) with 1-10 sliders
(self-rated energy, stamina). Generate exactly 8 questions.
"""
    result = await chat(
        user_message=prompt,
        system_override=PHYSICAL_QUESTIONS_SYSTEM,
        temperature=0.6,
        max_tokens=1600,
    )

    try:
        parsed = json.loads(result["reply"])
        result["structured"] = parsed
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: S&C BRAIN — PHYSICAL ASSESSMENT
# ══════════════════════════════════════════════════════════════════════════════

PHYSICAL_ASSESSMENT_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are the ZITLAS S&C Brain — a sports scientist and elite Strength & Conditioning coach using the
ZITLAS Bottleneck Engine to identify the single biggest physical limiting factor for this athlete's goal.

Your frameworks:
- Specificity (SAID): the body adapts to exactly what it's asked to do
- Bottleneck Engine: find the ONE quality furthest below goal requirement and target it
- Prerequisite chain: movement competence → strength → power → speed; fix the lowest broken link
- Force-velocity curve: distinguish strength-limited from velocity-limited athletes
- Energy system matching: aerobic base drives recovery between sprints in intermittent sports
- Load management: poor recovery or fatigue caps ALL qualities — check this first
- Youth safety (12-17): never prescribe maximal loading; technique before load

SCORING RULES (0-100 each — derive from SPECIFIC evidence, produce genuine variation):
- Strength: movement competence answers, strength-training frequency, bodyweight tests (pushups/squats)
- Power: explosive training history, sport-specific power indicators, strength-to-power ratio
- Speed: self-rated speed, sport context, agility/change-of-direction answers
- Mobility: joint restriction answers, injury patterns that suggest compensation, movement complaints
- Endurance: conditioning history, stamina ratings, repeated-sprint type answers
- Recovery Capacity: sleep data, tiredness after training, training days vs recovery days ratio
- Overall: weighted average with heaviest weight on the qualities most critical to the declared goal

BOTTLENECK IDENTIFICATION RULES (THE MOST IMPORTANT OUTPUT):
Apply the priority logic in order:
1. Safety/pain first — if injury/pain is present, that IS the bottleneck
2. Recovery/readiness next — if sleep < 6h or tiredness is chronic, recovery caps everything
3. Prerequisites before outputs — movement competence then strength before power
4. The single quality furthest below the goal's requirement
5. Expression/technique — if capacity exists but doesn't transfer

PHYSICAL SWOT RULES (3-4 items per quadrant, title + detail):
- Reference specific answers from BOTH the survey and physical questions
- Opportunities = trainable physical qualities with highest ROI for this player's goal
- Threats = injury-risk factors and performance-limiting patterns specific to this player

RECOMMENDATIONS RULES (exactly 3):
- One recommendation per identified weakness, targeting the 3 biggest physical gaps
- 3 specific, actionable techniques per recommendation
- Techniques must be concrete exercises or practices (not generic advice)
- For youth athletes: bodyweight/technique emphasis, no maximal loading

Respond with this EXACT JSON, no markdown fences:
{
  "physical_scores": {
    "strength": 71,
    "power": 58,
    "speed": 76,
    "mobility": 43,
    "endurance": 80,
    "recovery_capacity": 69,
    "overall": 66
  },
  "physical_bottleneck": {
    "quality": "Mobility",
    "icon": "🦵",
    "reason": "One precise sentence: why this quality is the primary bottleneck for THIS player's specific goal.",
    "priority": "critical"
  },
  "physical_swot": {
    "strengths":     [{ "title": "...", "detail": "..." }],
    "weaknesses":    [{ "title": "...", "detail": "..." }],
    "opportunities": [{ "title": "...", "detail": "..." }],
    "threats":       [{ "title": "...", "detail": "..." }]
  },
  "recommendations": [
    {
      "weakness": "Mobility",
      "icon": "🦵",
      "techniques": [
        "Hip 90/90 mobility drill: 2x90 seconds per side before every training session",
        "Ankle dorsiflexion wall drill: 3x10 reps per side, slow and controlled",
        "Dynamic leg-swing warm-up: 10 forward/back + 10 side-to-side per leg before any field session"
      ]
    }
  ],
  "physical_profile": "2-3 sentences describing the player's physical profile, primary strength, and key growth area.",
  "bottleneck_explanation": "One sentence naming the bottleneck and its direct impact on this player's declared goal."
}
"""


async def generate_physical_assessment(
    player_profile: dict,
    physical_answers: dict,
    mental_assessment: dict | None = None,
) -> dict[str, Any]:
    """
    Generate a full physical performance assessment using the S&C Brain Bottleneck Engine.
    Combines the 45-question survey, physical follow-up answers, and mental assessment (Brain 1).
    """
    mental_context = ""
    if mental_assessment:
        scores = mental_assessment.get("mental_scores", {})
        mental_context = f"""
MENTAL PROFILE CONTEXT (Brain 1 output — use to cross-reference recovery/motivation patterns):
Mental Scores: {json.dumps(scores, indent=2)}
Brain Diagnosis: {mental_assessment.get('brain_diagnosis', 'N/A')}
Mental Profile: {mental_assessment.get('mental_profile', 'N/A')}
"""

    prompt = f"""
Generate a complete fitness/body assessment for this person on a weight-loss journey.
Identify the SINGLE physical barrier most limiting their weight-loss success.

USER PROFILE:
{json.dumps(player_profile, indent=2)}

FITNESS FOLLOW-UP ANSWERS:
{json.dumps(physical_answers, indent=2)}
{mental_context}
Produce honest scores with real variation based on the data.
Name the ONE physical bottleneck clearly and explain why it limits weight loss for this specific person.
Every recommendation must be practical and actionable for their daily life.
"""
    result = await chat(
        user_message=prompt,
        system_override=PHYSICAL_ASSESSMENT_SYSTEM,
        temperature=0.5,
        max_tokens=2200,
    )

    try:
        parsed = json.loads(result["reply"])
        result["structured"] = parsed
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: NUTRITION BRAIN — QUESTIONS
# ══════════════════════════════════════════════════════════════════════════════

NUTRITION_QUESTIONS_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are the ZITLAS Nutrition Brain — an expert weight-loss nutritionist.
Your goal: assess the user's eating habits to identify what causes weight gain.

Generate 8-10 practical questions about:
- Meal frequency and timing
- Breakfast habits
- How often they eat junk food / outside food
- Whether they skip meals
- Late-night eating habits
- Emotional eating
- Protein awareness

For a weight-loss platform, you SHOULD ask about eating patterns that cause overeating.
Frame all questions positively and non-judgmentally.

Question types: "single" (4 simple options) or "slider" (1-10 scale). Mix both.

Respond with EXACT JSON, no markdown fences:
{
  "questions": [
    {
      "id": "nutr_meal_count",
      "dimension": "Meal Consistency",
      "question": "How many meals do you eat in a typical day?",
      "type": "single",
      "options": [
        { "value": "1_2", "label": "1-2 meals", "emoji": "???" },
        { "value": "3",   "label": "3 meals",   "emoji": "????" },
        { "value": "4",   "label": "4 meals",   "emoji": "???" },
        { "value": "5+",  "label": "5+ meals",  "emoji": "???" }
      ]
    },
    {
      "id": "nutr_junk_food",
      "dimension": "Food Quality",
      "question": "How often do you eat junk food or fast food?",
      "type": "slider",
      "min": 1,
      "max": 10,
      "min_label": "Rarely / never",
      "max_label": "Almost every day"
    }
  ]
}
"""


async def generate_nutrition_questions(
    player_profile: dict,
    mental_assessment: dict | None = None,
    physical_assessment: dict | None = None,
    lifestyle_data: dict | None = None,
) -> dict[str, Any]:
    """
    Generate 8-10 personalised practical nutrition questions.
    Cross-references Brain 1 (mental), Brain 2 (physical), and lifestyle data.
    """
    cross_brain = ""
    if mental_assessment:
        ms = mental_assessment.get("mental_scores", {})
        cross_brain += f"\nMental context — motivation: {ms.get('motivation', 'N/A')}\n"
    if physical_assessment:
        ps = physical_assessment.get("physical_scores", {})
        pb = physical_assessment.get("physical_bottleneck", {})
        cross_brain += f"Physical context — recovery: {ps.get('recovery_capacity', 'N/A')}, " \
                       f"physical weakness: {pb.get('quality', 'N/A')}\n"

    lifestyle_context = ""
    if lifestyle_data:
        lifestyle_context = f"""
LIFESTYLE CONTEXT (already known — do NOT repeat these questions):
- Where they live: {lifestyle_data.get('living_situation', 'unknown')}
- Diet type: {lifestyle_data.get('diet_type', 'unknown')}
- Available foods: {', '.join(lifestyle_data.get('available_foods', []) or [])}
- Kitchen access: {lifestyle_data.get('cooking_access', 'unknown')}
- Budget: {lifestyle_data.get('daily_budget', 'unknown')}
- Water intake: {lifestyle_data.get('water_intake', 'unknown')}

Since you already know these facts, focus remaining questions on:
- How regularly they eat meals
- What they eat before and after training
- How their energy feels during practice
- Whether they skip breakfast
- Their current eating habits and patterns
"""

    prompt = f"""
Generate 8-10 simple, friendly nutrition questions for this person who wants to lose weight.
Questions must be in plain language — easy to understand and answer.
Focus on: meal timing, breakfast habits, junk food frequency, emotional eating, late-night snacking, meal skipping.
DO NOT repeat questions about things already known from their lifestyle (see below).
Generate exactly 8 questions. Mix single-choice and slider types.
Use friendly, casual language — not medical or scientific terms.

USER PROFILE:
{json.dumps(player_profile, indent=2)}
{cross_brain}
{lifestyle_context}
"""
    result = await chat(
        user_message=prompt,
        system_override=NUTRITION_QUESTIONS_SYSTEM,
        temperature=0.6,
        max_tokens=1800,
    )

    try:
        parsed = json.loads(result["reply"])
        result["structured"] = parsed
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: NUTRITION BRAIN — ASSESSMENT
# ══════════════════════════════════════════════════════════════════════════════

NUTRITION_ASSESSMENT_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are generating a weight-loss nutrition assessment from a user's answers.

FOR WEIGHT LOSS you MUST include:
- A specific daily calorie target (calculated from height, weight, age, activity level)
- A daily protein goal in grams (0.9g per kg of goal body weight)
- Their main eating habit that causes weight gain
- Specific food swaps to reduce calories

Use Harris-Benedict equation to estimate TDEE, then subtract 400-500 kcal for weight loss deficit.

Respond with ONLY this JSON (no markdown):
{
  "nutrition_scores": {
    "meal_consistency":  0,
    "food_quality":      0,
    "protein_intake":    0,
    "hydration":         0,
    "meal_timing":       0,
    "junk_food_control": 0,
    "overall":           0
  },
  "daily_calorie_target": 1600,
  "daily_protein_target_g": 90,
  "nutrition_bottleneck": {
    "area": "main problem area",
    "detail": "one simple sentence about the main eating problem"
  },
  "top_food_swaps": [
    { "from": "current food", "to": "healthier swap", "calories_saved": 150 }
  ],
  "nutrition_swot": {
    "strengths":     ["specific positive eating habits"],
    "weaknesses":    ["specific eating problems"],
    "opportunities": ["quick wins for better nutrition"],
    "threats":       ["habits that could derail weight loss"]
  },
  "nutrition_recommendations": [
    "specific, simple, actionable tip"
  ],
  "nutrition_summary": "2 sentences: their main nutrition issue and what to focus on first"
}
"""


async def generate_nutrition_assessment(
    player_profile: dict,
    nutrition_answers: dict,
    mental_assessment: dict | None = None,
    physical_assessment: dict | None = None,
    lifestyle_data: dict | None = None,
) -> dict[str, Any]:
    """
    Generate a full nutrition performance assessment using the Nutrition Bottleneck Engine.
    Combines the 45-question survey, nutrition answers, and Brain 1/2 context.
    """
    cross_brain = ""
    if mental_assessment:
        ms = mental_assessment.get("mental_scores", {})
        cross_brain += f"""
BRAIN 1 CONTEXT (Psychology):
- Motivation: {ms.get('motivation', 'N/A')}
- Mental Toughness: {ms.get('mental_toughness', 'N/A')}
- Brain Diagnosis: {mental_assessment.get('brain_diagnosis', 'N/A')}
"""
    if physical_assessment:
        ps = physical_assessment.get("physical_scores", {})
        pb = physical_assessment.get("physical_bottleneck", {})
        cross_brain += f"""
BRAIN 2 CONTEXT (Physical):
- Recovery Capacity: {ps.get('recovery_capacity', 'N/A')}
- Endurance: {ps.get('endurance', 'N/A')}
- Physical Bottleneck: {pb.get('quality', 'N/A')} — {pb.get('reason', '')}
"""

    lifestyle_context = ""
    if lifestyle_data:
        lifestyle_context = f"""
LIFESTYLE CONTEXT (use to make recommendations realistic):
- Where they live: {lifestyle_data.get('living_situation', 'unknown')}
- Foods available: {', '.join(lifestyle_data.get('available_foods', []) or [])}
- Kitchen access: {lifestyle_data.get('cooking_access', 'unknown')}
- Daily budget: {lifestyle_data.get('daily_budget', 'unknown')}
- Diet type: {lifestyle_data.get('diet_type', 'unknown')}
- Allergies/restrictions: {', '.join((lifestyle_data.get('allergies', []) or []))}
- Favourite foods: {', '.join(lifestyle_data.get('favorite_foods', []) or [])}
- Foods they dislike: {', '.join(lifestyle_data.get('disliked_foods', []) or [])}
- Water intake: {lifestyle_data.get('water_intake', 'unknown')}
"""

    prompt = f"""
Generate a simple, friendly nutrition assessment for this person on a weight-loss journey.
Use plain language — write like a friendly weight-loss coach, not a doctor.
Find the ONE biggest eating habit that's causing their weight gain.
Give a specific daily calorie target and protein goal based on their data.
Give recommendations that are realistic for their actual living situation and budget.

USER PROFILE:
{json.dumps(player_profile, indent=2)}

NUTRITION ANSWERS:
{json.dumps(nutrition_answers, indent=2)}
{cross_brain}
{lifestyle_context}
Include specific calorie targets and protein goals.
Every recommendation must be something they can actually do today given their living situation.
Use simple words. Avoid medical or science terms.
"""
    result = await chat(
        user_message=prompt,
        system_override=NUTRITION_ASSESSMENT_SYSTEM,
        temperature=0.5,
        max_tokens=2200,
    )

    try:
        parsed = json.loads(result["reply"])
        result["structured"] = parsed
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: NUTRITION BRAIN — 7-DAY WEEKLY MEAL PLAN
# ══════════════════════════════════════════════════════════════════════════════

NUTRITION_WEEKLY_PLAN_SYSTEM = ZITLAS_SYSTEM_PROMPT + """

You are creating a 7-day weight-loss meal plan. Include specific calorie counts for every meal.

CRITICAL RULES:
- Every meal must include calorie counts.
- Total daily calories must match the user's calorie target for weight loss.
- Prioritise high-protein, high-fibre foods — they reduce hunger.
- Include only foods realistic for the user's situation (hostel/home).
- Match the user's diet type exactly (veg/non-veg/mixed).
- Use common Indian foods: dal, rice, roti, sabzi, curd, eggs, chicken, etc.
- Keep variety — don't repeat the same meal more than 3 times in a week.
- Include approximate portion sizes (cups/bowls/pieces, not grams).

Respond with ONLY this JSON (no markdown):
{
  "days": [
    {
      "day": "Monday",
      "total_calories": 1600,
      "total_protein_g": 90,
      "meals": {
        "breakfast": {
          "name": "Meal name",
          "foods": ["Food 1 (1 bowl)", "Food 2 (2 pieces)"],
          "calories": 350,
          "protein_g": 20,
          "tip": "one practical tip"
        },
        "mid_morning": {
          "name": "Snack name",
          "foods": ["Food 1 (1 cup)"],
          "calories": 100,
          "protein_g": 5,
          "tip": "tip"
        },
        "lunch": {
          "name": "Meal name",
          "foods": ["Food 1", "Food 2"],
          "calories": 450,
          "protein_g": 25,
          "tip": "tip"
        },
        "evening_snack": {
          "name": "Snack name",
          "foods": ["Food 1"],
          "calories": 100,
          "protein_g": 8,
          "tip": "tip"
        },
        "dinner": {
          "name": "Meal name",
          "foods": ["Food 1", "Food 2"],
          "calories": 400,
          "protein_g": 25,
          "tip": "tip"
        }
      },
      "water_target_litres": 2.5,
      "daily_tip": "one weight-loss tip for today"
    }
  ],
  "weekly_calorie_avg": 1600,
  "weekly_protein_avg_g": 90,
  "plan_notes": "2 sentences explaining the plan strategy and expected results"
}
"""


async def generate_nutrition_weekly_plan(
    player_profile: dict,
    nutrition_assessment: dict | None = None,
    lifestyle_data: dict | None = None,
    rejected_foods: list[str] | None = None,
) -> dict[str, Any]:
    """
    Generate a fully personalised 7-day meal plan using the athlete's complete profile
    and nutrition assessment (Brain 3 output). Different goals/bottlenecks → different plans.
    """
    nutrition_context = ""
    if nutrition_assessment:
        scores     = nutrition_assessment.get("nutrition_scores", {})
        bottleneck = nutrition_assessment.get("nutrition_bottleneck", {})
        nutrition_context = f"""
NUTRITION ASSESSMENT (Brain 3 output):
- Overall Nutrition Score: {scores.get('overall', 'N/A')}
- Meal Consistency Score: {scores.get('meal_consistency', 'N/A')}
- Energy Availability Score: {scores.get('energy_availability', 'N/A')}
- Hydration Score: {scores.get('hydration', 'N/A')}
- Recovery Nutrition Score: {scores.get('recovery_nutrition', 'N/A')}
- Performance Nutrition Score: {scores.get('performance_nutrition', 'N/A')}
- PRIMARY NUTRITION BOTTLENECK: {bottleneck.get('quality', 'N/A')} — {bottleneck.get('reason', '')}
- Nutrition Profile: {nutrition_assessment.get('nutrition_profile', 'N/A')}
"""

    ld = lifestyle_data or {}
    lifestyle_context = ""
    if lifestyle_data:
        lifestyle_context = f"""
LIFESTYLE & FOOD CONTEXT (CRITICAL — use this to make the plan realistic):
- Where they live: {ld.get('living_situation', 'unknown')}
- Foods available to them: {', '.join(ld.get('available_foods', []) or ['general Indian food'])}
- Kitchen/cooking access: {ld.get('cooking_access', 'unknown')}
- Daily food budget: {ld.get('daily_budget', 'unknown')}
- Diet type: {ld.get('diet_type', 'unknown')}
- Allergies/restrictions: {', '.join(ld.get('allergies', []) or ['none'])}
- Favourite foods: {', '.join(ld.get('favorite_foods', []) or ['general'])}
- Foods they dislike: {', '.join(ld.get('disliked_foods', []) or ['none'])}
- Daily water intake: {ld.get('water_intake', 'unknown')}

CRITICAL RULES based on lifestyle:
- If living in HOSTEL/PG: ONLY use foods available in hostel mess + easily bought from shops. NO complex recipes.
- If NO kitchen access: ZERO cooking required. Only mess food, ready-to-eat, or simple bought items.
- If BUDGET is low (₹0-50): Use hostel mess food only. No buying from shops.
- If VEGETARIAN: Absolutely NO meat, chicken, fish. Eggs only if diet_type includes eggs.
- If DISLIKED foods are listed: NEVER include them in ANY meal.
- If ALLERGIES listed: STRICTLY avoid those foods.
- ALWAYS include at least one food from their FAVOURITES in each day.
- Suggest foods that can realistically be obtained in their situation.
"""

    rejected_context = ""
    if rejected_foods:
        rejected_context = f"""
PERMANENTLY REJECTED FOODS — NEVER include ANY of these in any meal, on any day, for any reason:
{', '.join(rejected_foods)}
This list is non-negotiable. The player has already refused these foods.
"""

    nutri_context = load_nutri_context(
        goal_type=player_profile.get("goal_type", player_profile.get("goal", "Weight Loss")),
        bottleneck=(nutrition_assessment or {}).get("nutrition_bottleneck", {}).get("area", ""),
        living_situation=ld.get("living_situation", ""),
        daily_budget=ld.get("daily_budget", "100"),
        diet_type=ld.get("diet_type", ""),
        rejected_foods=rejected_foods,
    )

    prompt = f"""
Generate a fully personalised 7-day WEIGHT-LOSS meal plan for this user.
Use EVERY data point to make this plan unique to them — their goal weight, age, activity level, bottleneck, AND living situation.
The plan MUST be realistic for the user's actual life — where they live, what they can access, and their budget.

CRITICAL: A hostel student with no kitchen gets COMPLETELY DIFFERENT meals than someone at home with a full kitchen.

DO NOT DEFAULT TO GENERIC FOODS:
- Use the user's FAVOURITE FOODS and vary meals day-to-day — Monday breakfast must differ from Tuesday's.
- Hostel users: ONLY mess-available food + things easily bought from canteen or nearby shop.
- Budget under Rs100/day: free mess food only — NO buying from outside unless it's chai or a banana.
- Each meal MUST include specific calorie counts. Total daily calories must be at the calorie target.
- Include high-protein foods at EVERY meal to preserve muscle during weight loss.

ZITLAS NUTRITION KNOWLEDGE BASE (India-appropriate weight-loss foods):
{nutri_context}

USER PROFILE:
{json.dumps(player_profile, indent=2)}
{nutrition_context}
{lifestyle_context}
{rejected_context}
Include calorie counts and protein grams for every meal.
Frame everything around sustainable fat loss — eating the right foods, not starving.
Use simple language — this user wants practical everyday advice.
"""
    # 8000 tokens: a 7-day x 6-meal plan with full purpose text runs 4500-7000 tokens.
    # 4000 was too low -- the response was truncated mid-JSON causing structured=None.
    result = await chat(
        user_message=prompt,
        system_override=NUTRITION_WEEKLY_PLAN_SYSTEM,
        temperature=0.6,
        max_tokens=8000,
        json_mode=True,
        groq_key_env="GROQ_API_KEY_DIET",
        provider="groq",
    )

    # ── Debug logging ──────────────────────────────────────────────────────────
    raw: str = result.get("reply") or ""
    raw_len = len(raw)
    ends_with_brace = raw.rstrip().endswith("}")
    print(f"\n[nutrition-weekly-plan] Raw response — {raw_len} chars")
    print(f"[nutrition-weekly-plan] First 500 chars: {raw[:500]}")
    print(f"[nutrition-weekly-plan] Last 500 chars:  {raw[-500:]}")
    print(f"[nutrition-weekly-plan] Ends with '}}'  : {ends_with_brace}")

    # ── Parse — try strict JSON first, then fence-aware extractor ─────────────
    parsed: dict | None = None
    try:
        parsed = json.loads(raw)
        days_count = len((parsed or {}).get("days", []))
        print(f"[nutrition-weekly-plan] json.loads() OK — days: {days_count}")
        if days_count != 7:
            print(f"[nutrition-weekly-plan] WARNING — expected 7 days, got {days_count}")
    except json.JSONDecodeError as _e:
        print(f"[nutrition-weekly-plan] json.loads() FAILED: {type(_e).__name__}: {_e}")
        parsed = _extract_json(raw)
        if parsed:
            print("[nutrition-weekly-plan] _extract_json() recovered object "
                  f"— days: {len((parsed or {}).get('days', []))}")
        else:
            print("[nutrition-weekly-plan] _extract_json() also failed — structured=None")

    result["structured"] = parsed

    if parsed:
        report = _check_food_diversity(parsed)
        result["diversity_report"] = report
        _log_diversity_report(report, label="WEEKLY PLAN")
        if not report["validation_passed"] and report["repeated_foods_found"]:
            violations_text = "\n".join(
                f"  - {v}" for v in report["repeated_foods_found"][:10]
            )
            reroll_prompt = prompt + f"""

⚠️ DIVERSITY VIOLATION — REGENERATE WITH FIX:
Your previous response had these food repetition problems:
{violations_text}

Fix EVERY violation above. Replace repeated foods with different options.
Keep the same 7-day structure and meal timing but use more varied ingredients.
Respond with the corrected JSON only.
"""
            reroll = await chat(
                user_message=reroll_prompt,
                system_override=NUTRITION_WEEKLY_PLAN_SYSTEM,
                temperature=0.7,
                max_tokens=8000,
                json_mode=True,
                groq_key_env="GROQ_API_KEY_DIET",
                provider="groq",
            )
            reroll_raw: str = reroll.get("reply") or ""
            print(f"[nutrition-weekly-plan] Re-roll raw length: {len(reroll_raw)} chars")
            rerolled: dict | None = None
            try:
                rerolled = json.loads(reroll_raw)
            except json.JSONDecodeError as _e2:
                print(f"[nutrition-weekly-plan] Re-roll json.loads() FAILED: {_e2}")
                rerolled = _extract_json(reroll_raw)
            if rerolled:
                reroll_report = _check_food_diversity(rerolled)
                _log_diversity_report(reroll_report, label="WEEKLY PLAN RE-ROLL")
                result["structured"] = rerolled
                result["diversity_report"] = reroll_report
                result["rerolled"] = True

    return result


async def recommend_coaches(player_profile: dict, available_coaches: list[dict]) -> dict[str, Any]:
    """
    Recommend the best coaches from available_coaches for a player's current goal.
    """
    prompt = f"""
A person on a weight-loss journey needs a nutrition/fitness coach recommendation.

USER PROFILE:
{json.dumps(player_profile, indent=2)}

AVAILABLE COACHES:
{json.dumps(available_coaches, indent=2)}

Recommend the top 2 coaches from the list with reasoning.
Format as JSON:
{{
  "recommendations": [
    {{
      "coach_id": "...",
      "coach_name": "...",
      "match_score": N,  // 0-100
      "reason": "...",
      "focus_areas": ["..."]
    }}
  ],
  "advice": "One sentence of general coaching advice for this player."
}}
Respond with JSON only.
"""
    result = await chat(
        user_message=prompt,
        temperature=0.4,
        max_tokens=600,
    )

    try:
        result["structured"] = json.loads(result["reply"])
    except json.JSONDecodeError:
        result["structured"] = None

    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: MEAL SWAP — replace one meal with a realistic alternative
# ══════════════════════════════════════════════════════════════════════════════

_MEAL_SWAP_JSON_SCHEMA = """
Respond with ONLY this JSON (no markdown):
{
  "swap": {
    "name": "Swap meal name",
    "foods": ["Food 1 (portion)", "Food 2 (portion)"],
    "calories": 350,
    "protein_g": 22,
    "reason": "Why this is a better choice"
  },
  "alternative": {
    "name": "Alternative option name",
    "foods": ["Food 1", "Food 2"],
    "calories": 300,
    "protein_g": 18,
    "reason": "Why this alternative works"
  },
  "tips": ["practical tip 1", "practical tip 2"],
  "calories_saved": 150
}"""

_MEAL_SWAP_RULES: dict[str, str] = {
    "weight_loss": """\
You are suggesting a healthier meal swap for someone on a weight-loss plan.

RULES:
- The swap should be equal or lower in calories than the current meal.
- The swap should have equal or higher protein.
- Must be practical and available in India (hostel/home context matters).
- Respect the user's diet type (vegetarian/non-vegetarian).
- Give ONE primary swap and ONE alternative swap.
- Explain clearly WHY this swap is better for weight loss.""",

    "muscle_gain": """\
You are suggesting a meal swap for someone focused on muscle gain and hypertrophy.

RULES:
- The swap should have equal or higher protein than the current meal.
- Calories should be maintained or slightly higher (building muscle requires adequate fuel).
- Must be practical and available in India (hostel/home context matters).
- Respect the user's diet type (vegetarian/non-vegetarian).
- Give ONE primary swap and ONE alternative swap.
- Explain clearly WHY this swap supports muscle building and recovery.""",

    "general_fitness": """\
You are suggesting a balanced meal swap for someone focused on general fitness and overall wellbeing.

RULES:
- The swap should maintain good nutrient balance: adequate protein, quality carbs, healthy fats.
- Calories should be appropriate — focus on food quality and nutrition, not just calorie reduction.
- Must be practical and available in India (hostel/home context matters).
- Respect the user's diet type (vegetarian/non-vegetarian).
- Give ONE primary swap and ONE alternative swap.
- Explain clearly WHY this swap supports balanced nutrition and fitness goals.""",
}

# Keep legacy constant so nothing outside this file breaks if imported
MEAL_SWAP_SYSTEM = ZITLAS_SYSTEM_PROMPT + "\n\n" + _MEAL_SWAP_RULES["weight_loss"] + _MEAL_SWAP_JSON_SCHEMA


def _build_meal_swap_system(fitness_goal: str) -> str:
    """Return a goal-aware system prompt for the meal swap module."""
    rules = _MEAL_SWAP_RULES.get(fitness_goal, _MEAL_SWAP_RULES["general_fitness"])
    return ZITLAS_SYSTEM_PROMPT + "\n\n" + rules + _MEAL_SWAP_JSON_SCHEMA


async def generate_meal_swap(
    meal_name: str,
    meal_time: str,
    current_foods: list[str],
    reason: str,
    player_profile: dict,
    lifestyle_data: dict | None = None,
    rejected_foods: list[str] | None = None,
    previous_suggestions: list[list[str]] | None = None,
    fitness_goal: str = "general_fitness",
    rag_context: str = "",
) -> dict[str, Any]:
    """
    Generate a realistic replacement for a single meal based on the player's
    reason for swapping, fitness goal, and lifestyle/food context.
    """
    _goal_label_map = {
        "weight_loss":     "weight loss",
        "muscle_gain":     "muscle gain",
        "general_fitness": "general fitness",
    }
    print(f"[SWAP AI] {fitness_goal} prompt")
    lifestyle_context = ""
    if lifestyle_data:
        lifestyle_context = f"""
LIFESTYLE CONTEXT:
- Living situation: {lifestyle_data.get('living_situation', 'unknown')}
- Available foods: {', '.join(lifestyle_data.get('available_foods', []) or ['general food'])}
- Kitchen access: {lifestyle_data.get('cooking_access', 'unknown')}
- Daily budget: {lifestyle_data.get('daily_budget', 'unknown')}
- Diet type: {lifestyle_data.get('diet_type', 'unknown')}
- Foods to avoid: {', '.join((lifestyle_data.get('allergies', []) or []) + (lifestyle_data.get('disliked_foods', []) or []))}
- Favourite foods: {', '.join(lifestyle_data.get('favorite_foods', []) or [])}
"""

    # Auto-add diet-type forbidden foods so the AI never violates them
    diet_type = ((lifestyle_data or {}).get('diet_type') or '') if lifestyle_data else ''
    diet_type_lower = diet_type.lower()
    auto_forbidden: list[str] = []
    if any(k in diet_type_lower for k in ('vegetarian', 'veg', 'jain', 'vegan')):
        auto_forbidden += ['Chicken', 'Mutton', 'Fish', 'Salmon', 'Tuna', 'Prawns', 'Beef', 'Pork', 'Lamb', 'Meat']
    if 'vegan' in diet_type_lower:
        auto_forbidden += ['Milk', 'Curd', 'Paneer', 'Ghee', 'Butter', 'Cheese', 'Whey']
    allergies    = ((lifestyle_data or {}).get('allergies') or []) if lifestyle_data else []
    disliked     = ((lifestyle_data or {}).get('disliked_foods') or []) if lifestyle_data else []
    egg_triggers = {'egg', 'eggs', 'no egg', 'no eggs', 'egg-free'}
    if any(t in (f.lower() for f in allergies + disliked) for t in egg_triggers):
        auto_forbidden += ['Egg', 'Eggs', 'Omelette', 'Boiled Egg', 'Scrambled Egg']

    # Merge: explicit rejected + current meal foods + auto-forbidden (deduped)
    all_rejected = list(dict.fromkeys((rejected_foods or []) + current_foods + auto_forbidden))

    rejected_context = ""
    if all_rejected:
        food_list = '\n'.join(f'  - {f}' for f in all_rejected)
        rejected_context = f"""
⚠️ FORBIDDEN FOODS — NEVER include ANY of the following. Not as a standalone item, not as a named ingredient, not inside a dish name:
{food_list}

The player is replacing a meal that contained: {', '.join(current_foods)}
These are FORBIDDEN — do NOT suggest them or any dish that contains them.
"""

    previous_context = ""
    if previous_suggestions:
        lines = "\n".join(
            f"  Option {i+1}: {', '.join(foods)}"
            for i, foods in enumerate(previous_suggestions)
            if foods
        )
        previous_context = f"""
ALREADY SUGGESTED THIS SESSION — DO NOT REPEAT ANY OF THESE:
{lines}
You MUST generate a COMPLETELY DIFFERENT meal with different ingredients.
"""

    reason_context = _build_reason_context(reason, lifestyle_data)

    ld_safe      = lifestyle_data or {}
    swap_alts    = _get_swap_alternatives(
        meal_name=meal_name,
        budget_num=_extract_budget_num(ld_safe.get("daily_budget", "100")),
        is_hostel=any(k in (ld_safe.get("living_situation", "") or "").lower()
                      for k in ("hostel", "pg", "academy")),
        is_veg="non" not in (ld_safe.get("diet_type", "") or "").lower(),
        rejected={f.lower() for f in (rejected_foods or [])},
        current_foods=current_foods,
        fitness_goal=fitness_goal,
    )

    meal_name_lc  = meal_name.lower()
    is_main_meal  = any(k in meal_name_lc for k in ("breakfast", "lunch", "dinner"))
    meal_type_rule = (
        f"⚠️ This is a {meal_name} — a COMPLETE MAIN MEAL. "
        "The replacement MUST contain at least 2 solid food items (rice/roti/dal/protein/sabzi). "
        "Do NOT replace it with a single drink, juice, or hydration item."
    ) if is_main_meal else (
        f"This is a {meal_name} — a snack or recovery slot. A single item or drink is acceptable."
    )

    # Build goal-aware descriptors for the user prompt
    _goal_action = {
        "weight_loss":     "lower in calories but higher in protein",
        "muscle_gain":     "high in protein with adequate calories for muscle building",
        "general_fitness": "balanced in nutrients with good protein and food quality",
    }
    _goal_line = {
        "weight_loss":     (
            f"Lose weight (calorie target: {player_profile.get('daily_calorie_target', '1600')} kcal/day)"
        ),
        "muscle_gain":     (
            f"Build muscle (protein target: {player_profile.get('daily_protein_target', '150')}g/day)"
        ),
        "general_fitness": "General fitness and balanced nutrition",
    }

    rag_block = ""
    if rag_context:
        rag_block = f"""
NUTRITION KNOWLEDGE BASE (use this to inform your suggestion):
{rag_context}
---
"""

    prompt = f"""
Help this user swap one meal in line with their {_goal_label_map.get(fitness_goal, 'fitness')} goal.

MEAL TO SWAP: {meal_name} at {meal_time}
Current foods: {', '.join(current_foods)}
Reason for swapping: {reason}

{meal_type_rule}

USER:
- Age: {player_profile.get('age', 'unknown')}
- Goal: {_goal_line.get(fitness_goal, 'General fitness')}
{lifestyle_context}
{reason_context}
{rag_block}
{swap_alts}
{rejected_context}
{previous_context}
Suggest a realistic replacement that is {_goal_action.get(fitness_goal, 'balanced and nutritious')}.
Prefer foods from the NUTRI DATABASE list above — pre-verified for budget and availability.
The replacement MUST NOT contain: {', '.join(all_rejected) if all_rejected else 'N/A'}.
Avoid ALL previously suggested meals listed above. Keep it practical and filling.
"""
    result = await chat(
        user_message=prompt,
        system_override=_build_meal_swap_system(fitness_goal),
        temperature=0.7,
        max_tokens=400,
        groq_key_env="GROQ_API_KEY_DIET",
        provider="groq",
    )

    result["structured"] = _extract_json(result["reply"])
    return result


# ══════════════════════════════════════════════════════════════════════════════
# MODULE: AI COACH — Conversational Assessment (replaces 45-question survey)
# ══════════════════════════════════════════════════════════════════════════════

def _extract_json(text: str) -> dict | None:
    """Extract a JSON object from text that may contain markdown fences."""
    try:
        return json.loads(text.strip())
    except json.JSONDecodeError:
        pass
    import re
    # Strip markdown code fences
    m = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    # Find any JSON object
    m = re.search(r'\{.*\}', text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group())
        except json.JSONDecodeError:
            pass
    return None


async def coach_start() -> dict[str, Any]:
    """Return Zino's opening message for weight-loss onboarding. Static."""
    structured = {
        "reaction": "",
        "question": (
            "Hey! I'm Zino, your personal weight-loss coach!\n\n"
            "I'll ask you a few easy questions — then I'll build a meal plan "
            "and fitness plan made just for you.\n\n"
            "Let's start! What's your main goal?"
        ),
        "question_type": "options",
        "options": [
            {"label": "Lose Weight",        "emoji": "scale", "value": "lose_weight"},
            {"label": "Eat Healthier",       "emoji": "salad", "value": "eat_healthier"},
            {"label": "Build Better Habits", "emoji": "arrows", "value": "build_habits"},
            {"label": "All of the above",    "emoji": "target", "value": "all"},
        ],
        "extracted_data": {},
        "phase": "goal",
        "is_complete": False,
    }
    return {
        "reply":       structured["question"],
        "model":       DEFAULT_MODEL,
        "tokens_used": 0,
        "structured":  structured,
    }


async def coach_chat(
    conversation_history: list[dict],
    collected_data: dict,
    current_phase: str,
    turn_count: int,
) -> dict[str, Any]:
    """Minimal reaction-only turn. Frontend owns all question/phase logic."""
    player_answer = "ready"
    for msg in reversed(conversation_history):
        if msg.get("role") == "user":
            player_answer = msg.get("content", "ready")
            break

    system_msg = (
        "You are Zino, a friendly weight-loss coach. "
        "The user just answered a question. "
        "Write ONE short warm reaction (max 8 words). "
        "Do NOT repeat their answer. "
        'Return ONLY JSON: {"reaction": "short reaction here", "extracted_data": {}}'
    )

    messages = [
        {"role": "system", "content": system_msg},
        {"role": "user",   "content": player_answer},
    ]

    result     = await _ai_call(messages, temperature=0.8, max_tokens=80)
    reply      = result["reply"]
    structured = _extract_json(reply)
    if not structured:
        structured = {"reaction": "Got it!", "extracted_data": {}}

    structured.setdefault("question",      "")
    structured.setdefault("question_type", "options")
    structured.setdefault("options",       [])
    structured.setdefault("phase",         current_phase)
    structured.setdefault("is_complete",   False)

    return {
        "reply":       reply,
        "model":       result["model"],
        "tokens_used": result["tokens_used"],
        "structured":  structured,
    }


COACH_FINALIZE_SYSTEM = """You are Zino's AI engine. Build a weight-loss user profile from the coaching conversation.

RULES:
- goal_type: "Weight Loss" | "Nutrition" | "Fitness" | "Habits" | "Custom"
- Calculate BMI from height + current_weight. Mark as underweight/normal/overweight/obese.
- Calculate estimated daily calorie target: 300-500 kcal below TDEE (Harris-Benedict).
- daily_protein_target_g: 0.9g x goal body weight in kg
- fitness_level: "Sedentary" | "Lightly Active" | "Moderately Active" | "Very Active"
- Every text field: max one short sentence.
- Return ONLY the JSON below. No markdown, no extra text.

{
  "athlete_profile": {
    "primary_goal": "Weight Loss | Eat Healthier | Build Habits | All",
    "current_weight": 75,
    "goal_weight": 65,
    "height": 165,
    "bmi": 27.5,
    "bmi_category": "Overweight",
    "age": 22,
    "gender": "male | female | not_specified",
    "activity_level": "sedentary | lightly_active | moderately_active | very_active",
    "eating_habit": "main eating habit that causes weight gain",
    "living_situation": "home | hostel | outside",
    "cooking_access": "full | limited | none",
    "workout_type": "home | gym | walking | none",
    "diet_type": "vegetarian | non-vegetarian | mixed",
    "daily_budget": "Rs100",
    "favorite_foods": ["food1", "food2"],
    "disliked_foods": ["food1"],
    "sleep_hours": 7,
    "goal_type": "Weight Loss",
    "current_value": 75,
    "target_value": 65,
    "daily_calorie_target": 1600,
    "daily_protein_target_g": 90,
    "development_priority": "one sentence on the main focus area",
    "mental_bottleneck": "main psychological challenge",
    "physical_bottleneck": "main physical challenge",
    "nutrition_bottleneck": "main nutrition challenge"
  },
  "development_priority": "one sentence on the #1 thing to focus on first",
  "athlete_tier": "Sedentary | Lightly Active | Moderately Active | Very Active",
  "athlete_summary": "one encouraging sentence about this person's weight-loss journey",
  "lifestyle_data": {
    "living_situation": "home | hostel | outside",
    "diet_type": "vegetarian | non-vegetarian | mixed",
    "cooking_access": "full | limited | none",
    "daily_budget": "Rs100",
    "favorite_foods": [],
    "disliked_foods": [],
    "allergies": [],
    "water_intake": "adequate | low | high"
  }
}"""


async def coach_finalize(
    conversation_history: list[dict],
    collected_data: dict,
) -> dict[str, Any]:
    """Build the complete weight-loss user profile from the coaching conversation."""
    prompt = f"""
Build a complete weight-loss user profile from this coaching conversation.
Use the collected data as the primary source. Fill in reasonable defaults for anything missing.

COLLECTED DATA:
{json.dumps(collected_data, indent=2)}

FULL CONVERSATION (for context):
{json.dumps(conversation_history, indent=2)}

Calculate the daily calorie target from their weight, height, age, and activity level.
Calculate protein target as 0.9g per kg of their goal weight.
Make all text simple and encouraging.
"""
    result = await chat(
        user_message=prompt,
        system_override=COACH_FINALIZE_SYSTEM,
        temperature=0.4,
        max_tokens=4000,
    )

    _reply = result.get("reply", "")
    result["structured"] = _extract_json(_reply)

    _ok = result["structured"] is not None
    print(f"[coach_finalize] len(reply)={len(_reply) if isinstance(_reply, str) else '?'} "
          f"| parsed={'YES' if _ok else 'NO'} "
          f"| structured is None={not _ok}")
    return result
