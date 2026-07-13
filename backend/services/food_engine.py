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

_ROOT = Path(__file__).parent.parent.parent
_DATASET_PATH = _ROOT / "food_dataset" / "zitlas_food_database_enriched.json"
_PROFILES_DIR = _ROOT / "food_profiles"

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


_TRAILING_PAREN_RE = re.compile(r"\s*\([^()]*\)\s*$")


def _base_dish_name(name: str) -> str:
    """Strip trailing "(...)" style-suffixes ("(Home Style)", "(Restaurant
    Style)", "(Punjabi)", ...) repeatedly, so "Dal Makhani (Punjabi) (Light
    / Low-Oil Version)" and "Dal Makhani" collapse to the same base name."""
    base = name
    while True:
        stripped = _TRAILING_PAREN_RE.sub("", base)
        if stripped == base:
            return _norm(base)
        base = stripped


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
        # STEP 11 (geo enrichment, enrich_food_dataset_v2.py): index the
        # new state_of_origin/region fields the same way as every other
        # tag — this is what lets location_food_engine.py derive its
        # regional boost straight from the dataset instead of a hand-typed
        # dish list, and stays correct automatically as the dataset grows.
        self._idx_state: dict[str, set[int]] = defaultdict(set)
        self._idx_region: dict[str, set[int]] = defaultdict(set)

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
            for state in f.get("state_of_origin", []):
                self._idx_state[state].add(fid)
            self._idx_region[f.get("region", "Pan-India")].add(fid)

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
    # Stage order per spec: Medical -> Allergies -> Diet -> Goal -> SubGoal ->
    # Lifestyle -> Budget -> Living -> MealType -> Season -> Variety.
    # Medical, Allergies, Diet, and a profile's avoidCategories are PROTECTED
    # (folded into `base`, never relaxed — serving an unsafe or wrong-diet
    # food is never an acceptable "relax the filter" outcome). Everything
    # from Goal onward relaxes from the tail if it empties the candidate set,
    # so an over-constrained query degrades gracefully instead of returning
    # nothing. Variety has no filter stage — it's a scoring component only,
    # via the usage_count penalty in _score().

    def _union(self, index: dict[str, set[int]], tags) -> set[int]:
        out: set[int] = set()
        for t in tags:
            out |= index.get(t, set())
        return out

    def _budget_ids(self, budget_tier: str) -> set[int]:
        max_rank = _BUDGET_RANK.get(budget_tier, 2)
        allowed = [b for b, r in _BUDGET_RANK.items() if r <= max_rank]
        return self._union(self._idx_budget, allowed)

    def _pipeline_ids(
        self,
        disease_tags: list[str],
        allergens: set[str],
        diet_tags: list[str],
        goal_tags: list[str],
        subgoal_tag: str | None,
        profile: dict | None,
        budget_tier: str | None,
        living_tag: str | None,
        meal_tag: str | None,
        season_tag: str | None,
        disliked_foods: list[str] | None = None,
        max_prep_minutes: int | None = None,
    ) -> set[int]:
        profile = profile or {}
        avoid_categories = set(profile.get("avoidCategories") or [])
        preferred_categories = set(profile.get("preferredCategories") or [])

        # Stages 1-2: Medical, Allergies — always applied, never relaxed.
        base = set(self.all_ids)
        for disease in disease_tags:
            base -= self._idx_disease_unsafe.get(disease, set())
        for allergen in allergens:
            base -= self._idx_allergen.get(allergen, set())
        if disliked_foods:
            disliked_lc = [_norm(d) for d in disliked_foods if d]
            base = {i for i in base if not any(d in _norm(self.by_id[i]["name"]) for d in disliked_lc)}

        # Stage 3: Diet Preference — never relaxed (never serve meat to a
        # vegetarian just because the candidate pool got thin).
        if diet_tags:
            diet_ids = self._union(self._idx_diet, diet_tags)
            if base & diet_ids:
                base &= diet_ids

        # Lifestyle's avoidCategories is a hard exclude too (a weight-loss
        # profile that says "avoid Desserts & Sweets" means it, not "prefer
        # not to") — folded into `base` alongside diet for the same reason.
        if avoid_categories:
            avoid_ids = self._union(self._idx_category, avoid_categories)
            if base - avoid_ids:
                base -= avoid_ids

        # Stages 4-9: Goal -> SubGoal -> Lifestyle(preferred) -> Budget ->
        # Living -> MealType -> Season. Relaxed from the tail on empty result.
        stages: list[tuple[str, set[int] | None]] = [
            ("goal", self._union(self._idx_goal, goal_tags) if goal_tags else None),
            ("subgoal", self._idx_goal.get(subgoal_tag) if subgoal_tag else None),
            ("lifestyle_preferred", self._union(self._idx_category, preferred_categories) if preferred_categories else None),
            ("budget", self._budget_ids(budget_tier) if budget_tier else None),
            ("living", self._idx_living.get(living_tag) if living_tag else None),
            ("meal", self._idx_meal.get(meal_tag) if meal_tag else None),
            ("season", self._idx_season.get(season_tag) if season_tag else None),
            # STEP 14 (time intelligence): a relaxable preference, not a hard
            # cut — someone with 10 minutes shouldn't get zero food options
            # just because everything left in a thin pool takes 15.
            ("prep_time", (
                {i for i in self.all_ids if self.by_id[i].get("preparation_time_minutes", 20) <= max_prep_minutes}
                if max_prep_minutes else None
            )),
        ]
        active = [(n, s) for n, s in stages if s is not None]

        for cut in range(len(active), -1, -1):
            ids = set(base)
            for _, s in active[:cut]:
                ids &= s
            if ids:
                return ids
        return base

    # ── Scoring ──────────────────────────────────────────────────────────

    def _score(
        self,
        food: dict,
        goal_tags: list[str],
        living_tag: str | None,
        budget_tier: str | None,
        favorite_foods: list[str],
        usage_count: int,
        profile: dict | None = None,
    ) -> float:
        goal_hits = sum(1 for g in goal_tags if g in food.get("goalSuitable", []))
        goal_component = min(1.0, goal_hits / max(1, len(goal_tags))) if goal_tags else 0.7

        medical_component = 1.0  # already hard-filtered; anything left passed every check

        avail_component = 1.0 if (living_tag and living_tag in food.get("livingSuitable", [])) else 0.6
        # STEP 7/9 (geo enrichment): blend in the dataset's own popularity/
        # availability signal ("would a normal person actually eat this
        # today?") — folded into the existing Availability bucket, same
        # convention as every other profile-rule bonus above, so the
        # documented 40/25/15/10/5/5 weight formula never changes shape.
        pop_avail = food.get("availability_score")
        if pop_avail is not None:
            avail_component = min(1.0, avail_component * 0.5 + (pop_avail / 100.0) * 0.5)

        if budget_tier:
            diff = _BUDGET_RANK.get(food.get("budgetCategory", "Medium"), 1) - _BUDGET_RANK.get(budget_tier, 1)
            budget_component = 1.0 if diff <= 0 else max(0.0, 1.0 - diff * 0.5)
        else:
            budget_component = 0.8

        name_lc = _norm(food["name"])
        pref_component = 1.0 if any(_norm(f) in name_lc for f in favorite_foods if f) else 0.5

        # Profile-rule bonuses fold into the existing Availability/Preference
        # buckets rather than adding new weight categories (keeps the 40/25/
        # 15/10/5/5 formula intact) — a food matching the occupation profile's
        # preferred categories/difficulty/protein priority ranks higher among
        # otherwise-equal candidates.
        if profile:
            if food.get("category") in (profile.get("preferredCategories") or []):
                pref_component = min(1.0, pref_component + 0.3)
            if profile.get("difficulty") and food.get("difficulty") == profile["difficulty"]:
                avail_component = min(1.0, avail_component + 0.2)
            if profile.get("hostelFriendly") and "Hostel" in food.get("livingSuitable", []):
                avail_component = min(1.0, avail_component + 0.2)
            if profile.get("proteinPriority") == "High" and food.get("proteinScore", 0) >= 50:
                goal_component = min(1.0, goal_component + 0.15)

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
        profile: dict | None = None,
        subgoal_tag: str | None = None,
        season_tag: str | None = None,
        max_prep_minutes: int | None = None,
    ) -> list[dict]:
        """Filter -> score -> rank. Returns up to top_n real dataset foods."""
        meal_tag = _SLOT_TO_MEAL_TAG.get(meal_slot, meal_slot)
        ids = self._pipeline_ids(
            disease_tags=disease_tags, allergens=allergens, diet_tags=diet_tags,
            goal_tags=goal_tags, subgoal_tag=subgoal_tag, profile=profile,
            budget_tier=budget_tier, living_tag=living_situation, meal_tag=meal_tag,
            season_tag=season_tag, disliked_foods=disliked_foods,
            max_prep_minutes=max_prep_minutes,
        )
        if exclude_ids:
            ids -= exclude_ids
            if not ids:
                # exclude_ids ate the whole relaxed pool (e.g. a very small
                # variety window) — retry once without it rather than return empty.
                ids = self._pipeline_ids(
                    disease_tags=disease_tags, allergens=allergens, diet_tags=diet_tags,
                    goal_tags=goal_tags, subgoal_tag=subgoal_tag, profile=profile,
                    budget_tier=budget_tier, living_tag=living_situation, meal_tag=meal_tag,
                    season_tag=season_tag, disliked_foods=disliked_foods,
                    max_prep_minutes=max_prep_minutes,
                )

        usage_counts = usage_counts or {}
        favorite_foods = favorite_foods or []
        scored = [
            (self._score(self.by_id[i], goal_tags, living_situation, budget_tier,
                         favorite_foods, usage_counts.get(i, 0), profile), i)
            for i in ids
        ]
        scored.sort(key=lambda t: (-t[0], t[1]))
        return [self.by_id[i] for _, i in scored[:top_n]]

    # ── Location-aware queries (STEP 11: data-driven regional boost) ──────
    # These replace the earlier hand-typed dish-list approach in
    # location_food_engine.py — the dataset's own state_of_origin/region/
    # popularity_score fields (enrich_food_dataset_v2.py) are now the single
    # source of truth for "what's eaten in this state", so coverage grows
    # automatically as the dataset grows instead of needing a code change.

    def foods_by_state(self, state: str, limit: int = 8) -> list[dict]:
        """Top-N DISTINCT dishes whose state_of_origin includes `state`,
        ranked by popularity_score. Deduplicates "(Home Style)"/"(Restaurant
        Style)"/"(Street Style)"/"(Hostel Mess Style)" variants of the same
        dish to ONE entry (its highest-scoring variant) first — otherwise a
        single very popular pan-India dish with 8 style-variants (e.g. Poha)
        can fill the entire result and crowd out every other dish the state
        actually has, which defeats the point of asking "what's eaten here"."""
        ids = self._idx_state.get(state, set())
        foods = sorted((self.by_id[i] for i in ids), key=lambda f: -(f.get("popularity_score") or 0))
        seen_base_names: set[str] = set()
        deduped = []
        for f in foods:
            base = _base_dish_name(f["name"])
            if base in seen_base_names:
                continue
            seen_base_names.add(base)
            deduped.append(f)
        return deduped[:limit]

    def regional_categories_for_state(self, state: str, limit: int = 6) -> list[str]:
        """Food categories most associated with a state's regional dishes,
        ordered by how many of that state's foods fall in each category."""
        ids = self._idx_state.get(state, set())
        counts: dict[str, int] = defaultdict(int)
        for i in ids:
            cat = self.by_id[i].get("category")
            if cat:
                counts[cat] += 1
        return [c for c, _ in sorted(counts.items(), key=lambda kv: -kv[1])[:limit]]

    def foods_by_region(self, region: str, limit: int = 8) -> list[dict]:
        """Top-N foods for a broader region label (North/South/East/West/
        Pan-India), ranked by popularity_score."""
        ids = self._idx_region.get(region, set())
        foods = [self.by_id[i] for i in ids]
        foods.sort(key=lambda f: -(f.get("popularity_score") or 0))
        return foods[:limit]

    # ── Public plan builders ─────────────────────────────────────────────

    # STEP 6 (realistic meal engine): categories that, on their own, are a
    # snack/side/produce item rather than a full meal — "would a normal
    # person eat ONLY this for dinner?" is no for all of these. Dinner's
    # anchor (the combo's first, calorie-anchoring pick) is never chosen
    # from this list when a real alternative exists in the same ranked pool
    # — the combo-filler below still runs normally afterward, so a dinner
    # can still include a side salad/vegetable, just never AS the anchor.
    _INCOMPLETE_MEAL_CATEGORIES = frozenset({
        "Vegetables", "Salads and Soups", "Fruits", "Beverages",
        "Protein Supplements", "Desserts & Sweets",
    })

    def _pick_anchor(self, pool: list[dict], slot: str) -> dict:
        if slot != "dinner":
            return pool[0]
        for food in pool:
            if food.get("category") not in self._INCOMPLETE_MEAL_CATEGORIES:
                return food
        return pool[0]  # nothing better in this pool — never return an empty meal

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
        profile: dict | None = None,
        subgoal_tag: str | None = None,
        season_tag: str | None = None,
        max_prep_minutes: int | None = None,
    ) -> dict[str, Any]:
        """
        Deterministic 7-day x 5-slot plan sourced entirely from the dataset.
        Each slot is a COMBO of 1-3 foods approaching that slot's share of
        daily_calorie_target, or the occupation profile's own maxCalories*
        cap when one is loaded (a single dataset item is rarely a whole meal
        — real breakfasts are "Poha + Milk + Banana", not just "Poha").
        Tracks per-food usage across the week so nothing repeats more than
        3 times (spec: 'avoid repeating identical foods every day').
        """
        target = daily_calorie_target or 1600
        profile = profile or {}
        slot_calorie_cap = {
            "breakfast": profile.get("maxCaloriesBreakfast"),
            "lunch": profile.get("maxCaloriesLunch"),
            "dinner": profile.get("maxCaloriesDinner"),
        }
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
                    profile=profile, subgoal_tag=subgoal_tag, season_tag=season_tag,
                    max_prep_minutes=max_prep_minutes,
                )
                if not pool:
                    continue
                slot_target = slot_calorie_cap.get(slot) or (target * _SLOT_CALORIE_WEIGHT.get(slot, 0.2))
                anchor = self._pick_anchor(pool, slot)
                combo = [anchor]
                combo_ids = {anchor["id"]}
                total_cal = anchor["calories"]
                for food in pool:
                    if food["id"] in combo_ids:
                        continue
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
        plan = {"days": days, "usage_counts": dict(usage_counts)}
        plan["validation"] = self.validate_week_plan(plan, target)
        if not plan["validation"]["passed"]:
            print(f"[FOOD ENGINE] Plan validation flagged issues: {plan['validation']['issues']}")
        return plan

    # STEP 15 (AI validation): a cheap, deterministic post-hoc checklist —
    # this engine's filter pipeline already structurally prevents most of
    # the spec's failure modes (medical/diet/budget are hard filters, not
    # suggestions), so this is a defensive double-check, not a generator.
    # Never raises — a flagged plan is still returned and logged, since a
    # rules-based engine re-running the same deterministic pipeline would
    # just reproduce the same result rather than "regenerate" something new.
    def validate_week_plan(self, plan: dict, daily_calorie_target: int) -> dict[str, Any]:
        issues: list[str] = []
        for day in plan["days"]:
            day_name = day["day"]
            day_cal = 0
            for slot, meal in day["meals"].items():
                primary = meal.get("primary") or []
                if not primary:
                    issues.append(f"{day_name}/{slot}: empty meal")
                    continue
                day_cal += sum(f.get("calories", 0) for f in primary)
                if slot == "dinner" and len(primary) == 1 and \
                        primary[0].get("category") in self._INCOMPLETE_MEAL_CATEGORIES:
                    issues.append(f"{day_name}/dinner: single-item incomplete meal ({primary[0]['name']})")
                for f in primary:
                    if f.get("festival_food"):
                        issues.append(f"{day_name}/{slot}: festival food in a regular plan ({f['name']})")
            if daily_calorie_target and not (0.75 * daily_calorie_target <= day_cal <= 1.25 * daily_calorie_target):
                issues.append(f"{day_name}: total calories {day_cal} outside ±25% of target {daily_calorie_target}")
        food_counts: dict[int, int] = defaultdict(int)
        for day in plan["days"]:
            for meal in day["meals"].values():
                for f in meal.get("primary") or []:
                    food_counts[f["id"]] += 1
        for fid, count in food_counts.items():
            if count > 3:
                issues.append(f"food id={fid} repeated {count}x this week (limit 3)")
        return {"passed": not issues, "issues": issues}

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
        profile: dict | None = None,
        subgoal_tag: str | None = None,
        season_tag: str | None = None,
    ) -> list[dict]:
        exclude_lc = {_norm(n) for n in exclude_names if n}
        ids = self._pipeline_ids(
            disease_tags=disease_tags, allergens=allergens, diet_tags=diet_tags,
            goal_tags=goal_tags, subgoal_tag=subgoal_tag, profile=profile,
            budget_tier=budget_tier, living_tag=living_situation,
            meal_tag=_SLOT_TO_MEAL_TAG.get(meal_slot, meal_slot), season_tag=season_tag,
        )
        ids = {i for i in ids if _norm(self.by_id[i]["name"]) not in exclude_lc}
        if not ids:
            ids = self._pipeline_ids(
                disease_tags=disease_tags, allergens=allergens, diet_tags=diet_tags,
                goal_tags=[], subgoal_tag=None, profile=None,
                budget_tier=None, living_tag=None, meal_tag=None, season_tag=None,
            )
            ids = {i for i in ids if _norm(self.by_id[i]["name"]) not in exclude_lc}

        scored = [
            (self._score(self.by_id[i], goal_tags, living_situation, budget_tier, [], 0, profile), i)
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


# ── Occupation/goal-folder resolution for food_profiles/ (rules only, never
# food data — see generate_food_profiles.py). Distinct from
# goal_tags_from_profile() above: that maps to goalSuitable dataset tags,
# this maps to one of the 4 food_profiles/ folder names. ─────────────────────

_GOAL_KEY_ALIASES: dict[str, str] = {
    "weight_loss": "weight_loss", "fat_loss": "weight_loss", "six_pack": "weight_loss",
    "wedding_transformation": "weight_loss", "post_pregnancy": "weight_loss", "obesity": "weight_loss",
    "muscle_gain": "muscle_gain", "muscle_building": "muscle_gain", "weight_gain": "muscle_gain",
    "lean_bulk": "muscle_gain", "bodybuilding": "muscle_gain", "strength": "muscle_gain",
    "general_fitness": "general_fitness", "healthy_lifestyle": "general_fitness",
    "athletic_performance": "athletic_performance", "endurance": "athletic_performance",
    "sports_performance": "athletic_performance", "marathon": "athletic_performance",
}


def resolve_goal_key(player_profile: dict) -> str:
    """-> one of the 4 food_profiles/ goal folder names."""
    raw = _norm(
        player_profile.get("primary_goal") or player_profile.get("goal_type")
        or player_profile.get("fitness_goal") or player_profile.get("goal") or ""
    )
    raw_key = raw.replace(" ", "_").replace("-", "_")
    for key, folder in _GOAL_KEY_ALIASES.items():
        if key in raw_key:
            return folder
    return "general_fitness"


# food_profiles/<goal>/ only ships 5 base lifestyle files (student, hostel,
# working_professional, homemaker, athlete) — every occupation the spec asks
# to "support" maps onto one of those 5 (see generate_food_profiles.py's
# LIFESTYLE_ALIASES for the same mapping, kept in sync by hand since one is a
# one-time generator and this is the runtime resolver).
_LIFESTYLE_KEY_ALIASES: dict[str, str] = {
    "hostel": "hostel", "pg": "hostel", "academy": "hostel",
    "college": "student", "university": "student", "student": "student",
    "homemaker": "homemaker", "housewife": "homemaker", "home_maker": "homemaker", "home": "homemaker",
    "athlete": "athlete", "sportsperson": "athlete", "professional_athlete": "athlete",
    "working_professional": "working_professional", "job": "working_professional",
    "office": "working_professional", "employee": "working_professional",
    "night_shift": "working_professional", "travel": "working_professional",
    "premium": "working_professional",
}


def resolve_lifestyle_key(player_profile: dict, lifestyle_data: dict | None) -> str:
    """-> one of the 5 food_profiles/<goal>/ file names."""
    ld = lifestyle_data or {}
    raw = _norm(
        player_profile.get("occupation") or player_profile.get("profession")
        or player_profile.get("role") or ld.get("occupation") or ld.get("living_situation") or ""
    )
    raw_key = raw.replace(" ", "_").replace("-", "_")
    for key, base in _LIFESTYLE_KEY_ALIASES.items():
        if key in raw_key:
            return base
    return "student"  # no usable signal — this app's majority user base


def resolve_subgoal(player_profile: dict) -> str | None:
    raw = (
        player_profile.get("sub_goal") or player_profile.get("subgoal")
        or player_profile.get("secondary_goal") or ""
    )
    return raw.strip() if isinstance(raw, str) and raw.strip() else None


_CURRENT_MONTH_TO_SEASON: dict[int, str] = {
    12: "Winter", 1: "Winter", 2: "Winter",
    3: "Summer", 4: "Summer", 5: "Summer", 6: "Summer",
    7: "Monsoon", 8: "Monsoon", 9: "Monsoon",
    10: "All Season", 11: "All Season",
}


def current_season(month: int | None = None) -> str:
    import datetime
    month = month or datetime.date.today().month
    return _CURRENT_MONTH_TO_SEASON.get(month, "All Season")


_profile_cache: dict[tuple[str, str], dict] = {}


def load_profile(goal_key: str, lifestyle_key: str) -> dict:
    """Load+cache a food_profiles/<goal>/<lifestyle>.json rule file. Falls
    back to a neutral, unrestrictive profile for an unrecognised combination
    rather than erroring — goal/medical/diet filtering upstream still holds."""
    cache_key = (goal_key, lifestyle_key)
    if cache_key in _profile_cache:
        return _profile_cache[cache_key]

    path = _PROFILES_DIR / goal_key / f"{lifestyle_key}.json"
    if path.exists():
        profile = json.loads(path.read_text(encoding="utf-8"))
    else:
        print(f"[FOOD ENGINE] No profile at {path} — using neutral fallback profile")
        profile = {
            "profileName": f"{lifestyle_key} - {goal_key}", "goal": goal_key, "subGoals": [],
            "preferredCategories": [], "avoidCategories": [], "preferredMealTypes": [],
            "budget": None, "difficulty": None, "maxCaloriesBreakfast": None,
            "maxCaloriesLunch": None, "maxCaloriesDinner": None, "proteinPriority": "Medium",
            "hostelFriendly": False, "easyAvailability": True,
        }
    _profile_cache[cache_key] = profile
    return profile


def load_profile_for_user(player_profile: dict, lifestyle_data: dict | None) -> dict:
    """The one call groq_service.py needs — resolves goal+lifestyle from the
    raw profile/lifestyle dicts and returns the matching rule file."""
    goal_key = resolve_goal_key(player_profile)
    lifestyle_key = resolve_lifestyle_key(player_profile, lifestyle_data)
    return load_profile(goal_key, lifestyle_key)


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
