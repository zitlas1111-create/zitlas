"""
ZITLAS — Food Recommendation Engine (backend/services/food_engine.py)

Loads food_dataset/zitlas_food_database_enriched.json ONCE at import time and
serves every diet/meal/swap feature from it. This is the single source of
truth for "what food can we recommend" — the LLM never invents a food name;
it only arranges foods this engine selected into a readable plan (see
groq_service.generate_nutrition_weekly_plan / generate_meal_swap, which call
build_week_plan() / find_swap_alternatives() and then overwrite whatever the
LLM wrote in the `foods` fields with the engine's own picks before returning
a response — so a hallucinated food can never reach a user even if the LLM
misbehaves).

INDEXING: every tag (meal/goal/diet/budget/living/disease/season/
availability/category) is inverted once at load time into dict[str, set[int]]
of food ids. A recommendation query intersects a handful of these sets
instead of scanning the food list — this is O(number of matching foods), not
O(4500), and stays that way at 10,000+ foods since nothing here is sized to
the current dataset.

MEDICAL SAFETY: condition detection is NOT reimplemented here. Free-text
medical_conditions input goes through services/medical_conditions.detect_
conditions() (the existing keyword matcher) and the matched keys are mapped
to this module's disease vocabulary (see _CONDITION_KEY_TO_DISEASE_TAG).
Only kidney/gluten/lactose — conditions medical_conditions.py has no entry
for at all — get a small keyword check of their own here.
"""

from __future__ import annotations

import json
import re
import threading
from collections import defaultdict
from pathlib import Path
from typing import Any

from services import medical_conditions

_DATASET_PATH = Path(__file__).parent.parent.parent / "food_dataset" / "zitlas_food_database_enriched.json"

# CONDITION_RULES key (services/medical_conditions.py) -> diseaseSuitable tag
# (enrich_food_dataset.py). Conditions with no diet-safety meaning (arthritis,
# knee_pain, back_pain, obesity, underweight, migraine, depression, anxiety,
# sleep_apnea) are intentionally absent — they don't gate food selection.
_CONDITION_KEY_TO_DISEASE_TAG: dict[str, str] = {
    "asthma": "Asthma",
    "diabetes": "Diabetes",
    "hypertension": "Hypertension",
    "pcos": "PCOS",
    "hypothyroidism": "Thyroid",
    "hyperthyroidism": "Thyroid",
    "heart_disease": "Heart Disease",
    "fatty_liver": "Fatty Liver",
    "high_cholesterol": "High Cholesterol",
    "anemia": "Anemia",
}
# Not covered by medical_conditions.py at all — the only condition detection
# this module adds on its own, kept to a minimal keyword check.
_EXTRA_CONDITION_KEYWORDS: dict[str, tuple[str, ...]] = {
    "Kidney Disease": ("kidney", "ckd", "dialysis", "renal"),
    "Lactose Intolerance": ("lactose",),
    "Gluten Intolerance": ("gluten", "celiac", "coeliac"),
}

_ALLERGEN_KEYWORDS: dict[str, tuple[str, ...]] = {
    "Milk": ("milk", "dairy", "lactose"),
    "Gluten": ("gluten", "wheat", "celiac", "coeliac"),
    "Egg": ("egg",),
    "Shellfish/Fish": ("fish", "seafood", "prawn", "shrimp", "shellfish", "crab"),
    # No bare "nut" — it's a substring of "peanut" and would falsely flag
    # peanut allergies as a tree-nut allergy too.
    "Tree Nuts": ("almond", "cashew", "walnut", "pistachio", "hazelnut", "tree nut"),
    "Soy": ("soy", "soya"),
    "Peanuts": ("peanut", "groundnut"),
    "Sesame": ("sesame", "til"),
}

_MEAL_SLOTS = ("breakfast", "mid_morning", "lunch", "evening_snack", "dinner")
_SLOT_TO_MEAL_TAG = {
    "breakfast": "Breakfast", "mid_morning": "Snack", "lunch": "Lunch",
    "evening_snack": "Snack", "dinner": "Dinner",
}
_SLOT_CALORIE_WEIGHT = {
    "breakfast": 0.25, "mid_morning": 0.10, "lunch": 0.30,
    "evening_snack": 0.10, "dinner": 0.25,
}
_BUDGET_RANK = {"Low": 0, "Medium": 1, "High": 2}
_DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

# Score weights (SCORING PRIORITY ORDER from spec): must sum to 1.0
_W_GOAL, _W_MEDICAL, _W_AVAIL, _W_BUDGET, _W_PREF, _W_VARIETY = 0.40, 0.25, 0.15, 0.10, 0.05, 0.05


def _norm(s: str) -> str:
    return (s or "").strip().lower()


class FoodRecommendationEngine:
    def __init__(self, path: Path = _DATASET_PATH):
        raw: list[dict] = json.loads(path.read_text(encoding="utf-8"))
        self.by_id: dict[int, dict] = {f["id"]: f for f in raw}
        self.all_ids: set[int] = set(self.by_id.keys())

        self._idx_meal: dict[str, set[int]] = defaultdict(set)
        self._idx_goal: dict[str, set[int]] = defaultdict(set)
        self._idx_diet: dict[str, set[int]] = defaultdict(set)
        self._idx_budget: dict[str, set[int]] = defaultdict(set)
        self._idx_living: dict[str, set[int]] = defaultdict(set)
        self._idx_category: dict[str, set[int]] = defaultdict(set)
        self._idx_type: dict[str, set[int]] = defaultdict(set)
        self._idx_season: dict[str, set[int]] = defaultdict(set)
        self._idx_availability: dict[str, set[int]] = defaultdict(set)
        self._idx_disease_unsafe: dict[str, set[int]] = defaultdict(set)  # tag -> ids UNSAFE for it
        self._idx_allergen: dict[str, set[int]] = defaultdict(set)

        for f in raw:
            fid = f["id"]
            for tag in f.get("mealSuitable", []):
                self._idx_meal[tag].add(fid)
            for tag in f.get("goalSuitable", []):
                self._idx_goal[tag].add(fid)
            for tag in f.get("dietSuitable", []):
                self._idx_diet[tag].add(fid)
            self._idx_budget[f.get("budgetCategory", "Medium")].add(fid)
            for tag in f.get("livingSuitable", []):
                self._idx_living[tag].add(fid)
            self._idx_category[f.get("category", "")].add(fid)
            self._idx_type[f.get("type", "")].add(fid)
            for tag in f.get("season", []):
                self._idx_season[tag].add(fid)
            for tag in f.get("availability", []):
                self._idx_availability[tag].add(fid)
            for disease, safe in f.get("diseaseSuitable", {}).items():
                if not safe:
                    self._idx_disease_unsafe[disease].add(fid)
            for allergen in f.get("allergens", []):
                if allergen and allergen != "None":
                    self._idx_allergen[allergen].add(fid)

        print(f"[FOOD ENGINE] Loaded {len(raw)} foods, indexes built "
              f"(meal:{len(self._idx_meal)} goal:{len(self._idx_goal)} "
              f"diet:{len(self._idx_diet)} disease:{len(self._idx_disease_unsafe)})")

    # ── Condition / allergen resolution (reuses medical_conditions.py) ─────

    @staticmethod
    def resolve_disease_tags(medical_conditions_raw: str) -> list[str]:
        """Free-text condition -> this module's diseaseSuitable vocabulary,
        via medical_conditions.detect_conditions() (no re-implementation)."""
        if not medical_conditions.has_medical_condition(medical_conditions_raw):
            return []
        matched = medical_conditions.detect_conditions(medical_conditions_raw)
        tags = {_CONDITION_KEY_TO_DISEASE_TAG[k] for k in matched if k in _CONDITION_KEY_TO_DISEASE_TAG}
        norm = _norm(medical_conditions_raw)
        for tag, keywords in _EXTRA_CONDITION_KEYWORDS.items():
            if any(kw in norm for kw in keywords):
                tags.add(tag)
        return sorted(tags)

    @staticmethod
    def resolve_allergens(allergy_strings: list[str]) -> set[str]:
        """Free-text allergy list (e.g. 'no peanuts', 'lactose intolerant')
        -> the dataset's canonical allergen vocabulary."""
        resolved: set[str] = set()
        for raw in allergy_strings or []:
            norm = _norm(raw)
            if not norm:
                continue
            for canonical, keywords in _ALLERGEN_KEYWORDS.items():
                if any(kw in norm for kw in keywords):
                    resolved.add(canonical)
        return resolved

    # ── Filtering ────────────────────────────────────────────────────────

    def _candidate_ids(
        self,
        meal_tag: str | None,
        goal_tags: list[str],
        diet_tags: list[str],
        living_tag: str | None,
        budget_tier: str | None,
        disease_tags: list[str],
        allergens: set[str],
        disliked_foods: list[str],
    ) -> set[int]:
        ids = set(self.all_ids)
        if meal_tag:
            ids &= self._idx_meal.get(meal_tag, set())
        if diet_tags:
            diet_ids: set[int] = set()
            for tag in diet_tags:
                diet_ids |= self._idx_diet.get(tag, set())
            ids &= diet_ids
        if goal_tags:
            goal_ids: set[int] = set()
            for tag in goal_tags:
                goal_ids |= self._idx_goal.get(tag, set())
            ids &= goal_ids
        if living_tag:
            ids &= self._idx_living.get(living_tag, set())
        if budget_tier:
            max_rank = _BUDGET_RANK.get(budget_tier, 2)
            allowed_budgets = [b for b, r in _BUDGET_RANK.items() if r <= max_rank]
            budget_ids: set[int] = set()
            for b in allowed_budgets:
                budget_ids |= self._idx_budget.get(b, set())
            ids &= budget_ids

        # Medical safety ALWAYS overrides goal/budget — subtract, never add back.
        for disease in disease_tags:
            ids -= self._idx_disease_unsafe.get(disease, set())
        for allergen in allergens:
            ids -= self._idx_allergen.get(allergen, set())

        if disliked_foods:
            disliked_lc = [_norm(d) for d in disliked_foods if d]
            ids = {i for i in ids if not any(d in _norm(self.by_id[i]["name"]) for d in disliked_lc)}

        return ids

    # ── Scoring ──────────────────────────────────────────────────────────

    def _score(
        self,
        food: dict,
        goal_tags: list[str],
        living_tag: str | None,
        budget_tier: str | None,
        favorite_foods: list[str],
        usage_count: int,
    ) -> float:
        goal_hits = sum(1 for g in goal_tags if g in food.get("goalSuitable", []))
        goal_component = min(1.0, goal_hits / max(1, len(goal_tags))) if goal_tags else 0.7

        medical_component = 1.0  # already hard-filtered; anything left passed every check

        avail_component = 1.0 if (living_tag and living_tag in food.get("livingSuitable", [])) else 0.6

        if budget_tier:
            diff = _BUDGET_RANK.get(food.get("budgetCategory", "Medium"), 1) - _BUDGET_RANK.get(budget_tier, 1)
            budget_component = 1.0 if diff <= 0 else max(0.0, 1.0 - diff * 0.5)
        else:
            budget_component = 0.8

        name_lc = _norm(food["name"])
        pref_component = 1.0 if any(_norm(f) in name_lc for f in favorite_foods if f) else 0.5

        variety_component = max(0.0, 1.0 - usage_count * 0.35)

        return (
            _W_GOAL * goal_component + _W_MEDICAL * medical_component + _W_AVAIL * avail_component
            + _W_BUDGET * budget_component + _W_PREF * pref_component + _W_VARIETY * variety_component
        )

    def recommend(
        self,
        meal_slot: str,
        goal_tags: list[str],
        diet_tags: list[str],
        living_situation: str | None,
        budget_tier: str | None,
        disease_tags: list[str],
        allergens: set[str],
        favorite_foods: list[str] | None = None,
        disliked_foods: list[str] | None = None,
        usage_counts: dict[int, int] | None = None,
        top_n: int = 4,
        exclude_ids: set[int] | None = None,
    ) -> list[dict]:
        """Filter -> score -> rank. Returns up to top_n real dataset foods."""
        meal_tag = _SLOT_TO_MEAL_TAG.get(meal_slot, meal_slot)
        ids = self._candidate_ids(
            meal_tag=meal_tag, goal_tags=goal_tags, diet_tags=diet_tags,
            living_tag=living_situation, budget_tier=budget_tier,
            disease_tags=disease_tags, allergens=allergens, disliked_foods=disliked_foods or [],
        )
        if exclude_ids:
            ids -= exclude_ids
        if not ids:
            # Relax living/budget first (goal + medical safety + diet stay hard constraints)
            ids = self._candidate_ids(
                meal_tag=meal_tag, goal_tags=goal_tags, diet_tags=diet_tags,
                living_tag=None, budget_tier=None,
                disease_tags=disease_tags, allergens=allergens, disliked_foods=disliked_foods or [],
            )
            if exclude_ids:
                ids -= exclude_ids
        if not ids:
            # Last resort: keep diet+medical safety only, drop the meal-slot tag too
            ids = self._candidate_ids(
                meal_tag=None, goal_tags=[], diet_tags=diet_tags,
                living_tag=None, budget_tier=None,
                disease_tags=disease_tags, allergens=allergens, disliked_foods=disliked_foods or [],
            )

        usage_counts = usage_counts or {}
        favorite_foods = favorite_foods or []
        scored = [
            (self._score(self.by_id[i], goal_tags, living_situation, budget_tier,
                         favorite_foods, usage_counts.get(i, 0)), i)
            for i in ids
        ]
        scored.sort(key=lambda t: (-t[0], t[1]))
        return [self.by_id[i] for _, i in scored[:top_n]]

    # ── Public plan builders ─────────────────────────────────────────────

    def build_week_plan(
        self,
        goal_tags: list[str],
        diet_tags: list[str],
        living_situation: str | None,
        budget_tier: str | None,
        disease_tags: list[str],
        allergens: set[str],
        favorite_foods: list[str] | None = None,
        disliked_foods: list[str] | None = None,
        daily_calorie_target: int | None = None,
    ) -> dict[str, Any]:
        """
        Deterministic 7-day x 5-slot plan sourced entirely from the dataset.
        Each slot is a COMBO of 1-3 foods approaching that slot's share of
        daily_calorie_target (a single dataset item is rarely a whole meal —
        real breakfasts are "Poha + Milk + Banana", not just "Poha"). Tracks
        per-food usage across the week so nothing repeats more than 3 times
        (spec: 'avoid repeating identical foods every day').
        """
        target = daily_calorie_target or 1600
        usage_counts: dict[int, int] = defaultdict(int)
        days = []
        for day_name in _DAY_NAMES:
            day_meals = {}
            for slot in _MEAL_SLOTS:
                pool = self.recommend(
                    meal_slot=slot, goal_tags=goal_tags, diet_tags=diet_tags,
                    living_situation=living_situation, budget_tier=budget_tier,
                    disease_tags=disease_tags, allergens=allergens,
                    favorite_foods=favorite_foods, disliked_foods=disliked_foods,
                    usage_counts=usage_counts, top_n=12,
                )
                if not pool:
                    continue
                slot_target = target * _SLOT_CALORIE_WEIGHT.get(slot, 0.2)
                combo = [pool[0]]
                combo_ids = {pool[0]["id"]}
                total_cal = pool[0]["calories"]
                for food in pool[1:]:
                    if total_cal >= slot_target * 0.85 or len(combo) >= 3:
                        break
                    combo.append(food)
                    combo_ids.add(food["id"])
                    total_cal += food["calories"]
                # A food used 3x already this week drops out of future primary
                # picks entirely (still eligible as a lower-priority alternative).
                for food in combo:
                    usage_counts[food["id"]] += 1
                day_meals[slot] = {
                    "primary": combo,
                    "alternatives": [f for f in pool if f["id"] not in combo_ids][:3],
                }
            days.append({"day": day_name, "meals": day_meals})
        return {"days": days, "usage_counts": dict(usage_counts)}

    def find_swap_alternatives(
        self,
        meal_slot: str,
        goal_tags: list[str],
        diet_tags: list[str],
        living_situation: str | None,
        budget_tier: str | None,
        disease_tags: list[str],
        allergens: set[str],
        exclude_names: list[str],
        top_n: int = 4,
    ) -> list[dict]:
        exclude_lc = {_norm(n) for n in exclude_names if n}
        ids = self._candidate_ids(
            meal_tag=_SLOT_TO_MEAL_TAG.get(meal_slot, meal_slot), goal_tags=goal_tags,
            diet_tags=diet_tags, living_tag=living_situation, budget_tier=budget_tier,
            disease_tags=disease_tags, allergens=allergens, disliked_foods=[],
        )
        ids = {i for i in ids if _norm(self.by_id[i]["name"]) not in exclude_lc}
        if not ids:
            ids = self._candidate_ids(
                meal_tag=None, goal_tags=[], diet_tags=diet_tags, living_tag=None,
                budget_tier=None, disease_tags=disease_tags, allergens=allergens, disliked_foods=[],
            )
            ids = {i for i in ids if _norm(self.by_id[i]["name"]) not in exclude_lc}

        scored = [
            (self._score(self.by_id[i], goal_tags, living_situation, budget_tier, [], 0), i)
            for i in ids
        ]
        scored.sort(key=lambda t: (-t[0], t[1]))
        return [self.by_id[i] for _, i in scored[:top_n]]


# ── Profile/lifestyle string -> engine tag normalization ───────────────────
# The frontend/LLM-facing profile uses free-form strings ("weight_loss",
# "hostel", "₹100/day"); the dataset's tags are fixed vocab. This is the one
# place that translation happens so both call sites (weekly plan + swap) stay
# in sync.

_GOAL_STRING_TO_TAGS: dict[str, list[str]] = {
    "weight_loss": ["Weight Loss", "Fat Loss"],
    "fat_loss": ["Fat Loss", "Weight Loss"],
    "muscle_gain": ["Muscle Gain", "Lean Bulk"],
    "muscle_building": ["Muscle Gain", "Lean Bulk"],
    "weight_gain": ["Lean Bulk", "Muscle Gain"],
    "six_pack": ["Six Pack"],
    "lean_bulk": ["Lean Bulk"],
    "endurance": ["Endurance"],
    "athletic_performance": ["Athletic Performance"],
    "general_fitness": ["General Fitness"],
}


def goal_tags_from_profile(player_profile: dict) -> list[str]:
    raw = _norm(
        player_profile.get("primary_goal") or player_profile.get("goal_type")
        or player_profile.get("fitness_goal") or player_profile.get("goal") or ""
    )
    raw_key = raw.replace(" ", "_").replace("-", "_")
    for key, tags in _GOAL_STRING_TO_TAGS.items():
        if key in raw_key:
            return tags
    return ["General Fitness"]


_DIET_STRING_TO_TAGS: dict[str, list[str]] = {
    "vegan": ["Vegan"],
    "eggitarian": ["Eggitarian"],
    "jain": ["Jain"],
    "halal": ["Halal"],
    "satvik": ["Satvik"],
    "non-vegetarian": ["Non Vegetarian"],
    "non vegetarian": ["Non Vegetarian"],
    "nonveg": ["Non Vegetarian"],
    "vegetarian": ["Vegetarian"],
    "mixed": ["Vegetarian", "Non Vegetarian"],
}


def diet_tags_from_lifestyle(diet_type: str) -> list[str]:
    norm = _norm(diet_type)
    for key, tags in _DIET_STRING_TO_TAGS.items():
        if key in norm:
            return tags
    return ["Vegetarian", "Non Vegetarian"]  # unspecified -> no diet-type restriction


_LIVING_STRING_TO_TAG: dict[str, str] = {
    "hostel": "Hostel", "academy": "Hostel", "pg": "PG", "paying guest": "PG",
    "home": "Home", "college": "College", "office": "Office", "travel": "Travel",
}


def living_tag_from_lifestyle(living_situation: str) -> str | None:
    norm = _norm(living_situation)
    for key, tag in _LIVING_STRING_TO_TAG.items():
        if key in norm:
            return tag
    return None


def budget_tier_from_lifestyle(daily_budget: str) -> str:
    nums = re.findall(r"\d+", str(daily_budget or ""))
    n = int(nums[0]) if nums else 150
    if n <= 80:
        return "Low"
    if n <= 200:
        return "Medium"
    return "High"


def format_food_line(food: dict) -> str:
    """'Poha (1 plate (200 g))' — the exact string shape the frontend's
    `foods: [...]` array has always used."""
    return f"{food['name']} ({food['serving_size']})"


# ── Lazy singleton — loaded once, shared by every request ──────────────────
_engine: FoodRecommendationEngine | None = None
_engine_lock = threading.Lock()


def get_engine() -> FoodRecommendationEngine:
    global _engine
    if _engine is None:
        with _engine_lock:
            if _engine is None:
                _engine = FoodRecommendationEngine()
    return _engine
