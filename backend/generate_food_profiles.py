"""
ZITLAS — Food Profile Generator (backend/generate_food_profiles.py)

Writes food_profiles/<goal>/<lifestyle>.json — RULES ONLY, never food data.
The 4,500-food dataset (food_dataset/zitlas_food_database.json) remains the
single source of truth; these files just tell FoodRecommendationEngine which
dataset categories/budgets/calorie caps a given goal+lifestyle combination
prefers. Re-run this any time the goal/lifestyle rule tables below change;
it always fully regenerates food_profiles/ from the tables, never hand-edits
individual files.

Usage (from backend/ directory):
    python generate_food_profiles.py
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_ROOT = Path(__file__).parent.parent
_OUT_DIR = _ROOT / "food_profiles"

# ── GOAL rule tables ────────────────────────────────────────────────────────
# Category names are the dataset's exact `category` field values (see
# enrich_food_dataset.py CATEGORY_* tables) — this is what makes profile
# rules line up with the real data without ever storing a food name here.

_GOALS: dict[str, dict[str, Any]] = {
    "weight_loss": {
        "label": "Weight Loss",
        "subGoals": ["Fat Loss", "Six Pack", "Wedding Transformation", "Post Pregnancy",
                     "Obesity", "Beginner Weight Loss"],
        "preferredCategories": ["Healthy Recipes", "Weight Loss Foods", "Vegetables", "Fruits",
                                 "Salads and Soups", "Vegetarian Protein Sources"],
        "avoidCategories": ["Desserts & Sweets", "Fast Foods"],
        "proteinPriority": "High",
        "calories": {"breakfast": 350, "lunch": 500, "dinner": 450},
    },
    "muscle_gain": {
        "label": "Muscle Gain",
        "subGoals": ["Lean Bulk", "Strength", "Bodybuilding", "Athletic Muscle", "Beginner Muscle Gain"],
        "preferredCategories": ["Vegetarian Protein Sources", "Eggs", "Chicken Dishes",
                                 "Protein Supplements", "Weight Gain Foods", "Fish & Seafood", "Mutton & Meat"],
        "avoidCategories": ["Fast Foods"],
        "proteinPriority": "High",
        "calories": {"breakfast": 500, "lunch": 700, "dinner": 650},
    },
    "general_fitness": {
        "label": "General Fitness",
        "subGoals": ["Healthy Lifestyle", "Office Fitness", "College Fitness", "Daily Wellness"],
        "preferredCategories": ["Healthy Recipes", "Indian Breakfast", "Indian Lunch", "Indian Dinner",
                                 "Fruits", "Vegetables", "Salads and Soups"],
        "avoidCategories": ["Fast Foods"],
        "proteinPriority": "Medium",
        "calories": {"breakfast": 400, "lunch": 550, "dinner": 500},
    },
    "athletic_performance": {
        "label": "Athletic Performance",
        "subGoals": ["Cricket", "Football", "Running", "Cycling", "Swimming", "Police", "Army",
                     "Agniveer", "Marathon", "Sports Performance"],
        "preferredCategories": ["Sports Nutrition Foods", "Protein Supplements", "Vegetarian Protein Sources",
                                 "Chicken Dishes", "Eggs", "Fruits", "Beverages"],
        "avoidCategories": ["Fast Foods", "Desserts & Sweets"],
        "proteinPriority": "High",
        "calories": {"breakfast": 500, "lunch": 700, "dinner": 600},
    },
}

# ── LIFESTYLE rule tables ───────────────────────────────────────────────────
_LIFESTYLES: dict[str, dict[str, Any]] = {
    "student": {
        "label": "Student",
        "extraPreferred": ["Indian Breakfast", "Snacks", "Beverages"],
        "extraAvoid": [],
        "budget": "Medium", "difficulty": "Easy",
        "hostelFriendly": False, "easyAvailability": True,
        "calorieMultiplier": 1.0,
    },
    "hostel": {
        "label": "Hostel Student",
        "extraPreferred": ["Hostel Foods", "Healthy Recipes"],
        "extraAvoid": ["Restaurant Foods", "International Foods"],
        "budget": "Low", "difficulty": "Easy",
        "hostelFriendly": True, "easyAvailability": True,
        "calorieMultiplier": 0.95,
    },
    "working_professional": {
        "label": "Working Professional",
        "extraPreferred": ["Restaurant Foods", "Salads and Soups", "Healthy Recipes"],
        "extraAvoid": ["Street Foods"],
        "budget": "High", "difficulty": "Easy",
        "hostelFriendly": False, "easyAvailability": True,
        "calorieMultiplier": 1.0,
    },
    "homemaker": {
        "label": "Homemaker",
        "extraPreferred": ["North Indian Foods", "South Indian Foods", "Gujarati Foods",
                            "Punjabi Foods", "Maharashtrian Foods", "Vegetables"],
        "extraAvoid": ["Fast Foods", "Restaurant Foods"],
        "budget": "Medium", "difficulty": "Medium",
        "hostelFriendly": False, "easyAvailability": True,
        "calorieMultiplier": 1.0,
    },
    "athlete": {
        "label": "Athlete",
        "extraPreferred": ["Sports Nutrition Foods", "Protein Supplements", "Chicken Dishes",
                            "Eggs", "Fish & Seafood"],
        "extraAvoid": ["Fast Foods", "Desserts & Sweets"],
        "budget": "High", "difficulty": "Medium",
        "hostelFriendly": False, "easyAvailability": True,
        "calorieMultiplier": 1.25,
    },
}

# Occupations/situations from the spec that aren't their own file — they map
# onto one of the 5 base lifestyles above with small rule overrides. Kept
# here (not invented at request-time) so the mapping is auditable.
LIFESTYLE_ALIASES: dict[str, dict[str, Any]] = {
    "college_student": {"base": "student"},
    "home": {"base": "homemaker"},
    "night_shift_worker": {"base": "working_professional", "overrides": {"difficulty": "Very Easy"}},
    "travel_frequently": {"base": "working_professional", "overrides": {"preferredCategories_extra": ["Restaurant Foods", "International Foods", "Snacks"]}},
    "budget_friendly": {"base": "student", "overrides": {"budget": "Low"}},
    "premium_lifestyle": {"base": "working_professional", "overrides": {"budget": "High"}},
}

_MEAL_TYPES_BASE = ["Breakfast", "Lunch", "Dinner", "Snack"]
_MEAL_TYPES_PERFORMANCE_EXTRA = ["Pre Workout", "Post Workout"]


def _build_profile(goal_key: str, lifestyle_key: str) -> dict[str, Any]:
    goal = _GOALS[goal_key]
    life = _LIFESTYLES[lifestyle_key]

    avoid = list(dict.fromkeys(goal["avoidCategories"] + life["extraAvoid"]))
    preferred = [
        c for c in dict.fromkeys(goal["preferredCategories"] + life["extraPreferred"])
        if c not in avoid
    ]
    meal_types = list(_MEAL_TYPES_BASE)
    if goal_key in ("muscle_gain", "athletic_performance") or lifestyle_key == "athlete":
        meal_types += _MEAL_TYPES_PERFORMANCE_EXTRA

    mult = life["calorieMultiplier"]
    cal = goal["calories"]

    return {
        "profileName": f"{life['label']} — {goal['label']}",
        "goal": goal["label"],
        "subGoals": goal["subGoals"],
        "preferredCategories": preferred,
        "avoidCategories": avoid,
        "preferredMealTypes": meal_types,
        "budget": life["budget"],
        "difficulty": life["difficulty"],
        "maxCaloriesBreakfast": round(cal["breakfast"] * mult),
        "maxCaloriesLunch": round(cal["lunch"] * mult),
        "maxCaloriesDinner": round(cal["dinner"] * mult),
        "proteinPriority": goal["proteinPriority"],
        "hostelFriendly": life["hostelFriendly"],
        "easyAvailability": life["easyAvailability"],
    }


def main() -> None:
    written = 0
    for goal_key in _GOALS:
        goal_dir = _OUT_DIR / goal_key
        goal_dir.mkdir(parents=True, exist_ok=True)
        for lifestyle_key in _LIFESTYLES:
            profile = _build_profile(goal_key, lifestyle_key)
            path = goal_dir / f"{lifestyle_key}.json"
            path.write_text(json.dumps(profile, ensure_ascii=False, indent=2), encoding="utf-8")
            written += 1
            print(f"[PROFILES] wrote {path.relative_to(_ROOT)}")

    print(f"[PROFILES] {written} profile files written across {len(_GOALS)} goals x {len(_LIFESTYLES)} lifestyles")
    print(f"[PROFILES] {len(LIFESTYLE_ALIASES)} additional occupation aliases map onto these via food_engine.py")


if __name__ == "__main__":
    main()
