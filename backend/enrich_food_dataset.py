"""
ZITLAS — Food Dataset Enrichment (backend/enrich_food_dataset.py)

Reads food_dataset/zitlas_food_database.json (4,500 foods, never modified)
and writes food_dataset/zitlas_food_database_enriched.json with derived
metadata attached to every food: mealSuitable, budgetCategory, livingSuitable,
goalSuitable, dietSuitable, diseaseSuitable, season, availability, difficulty,
plus numeric scores (proteinScore, weightLossScore, muscleGainScore,
hostelScore) the ranking engine uses for tie-breaking.

Every tag is DERIVED algorithmically from fields already on each food
(category, macros, type, allergens, name/description) — nothing is
hand-annotated per food. Re-run this any time the base dataset changes;
it is idempotent and never touches the source file.

Usage (from backend/ directory):
    python enrich_food_dataset.py
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_ROOT = Path(__file__).parent.parent
_SRC = _ROOT / "food_dataset" / "zitlas_food_database.json"
_DST = _ROOT / "food_dataset" / "zitlas_food_database_enriched.json"


# ══════════════════════════════════════════════════════════════════════════
# CATEGORY → BASE TAG TABLES
# ══════════════════════════════════════════════════════════════════════════

CATEGORY_MEAL: dict[str, list[str]] = {
    "Indian Breakfast":            ["Breakfast"],
    "Indian Lunch":                ["Lunch"],
    "Indian Dinner":                ["Dinner"],
    "Fruits":                       ["Snack", "Pre Workout", "Breakfast"],
    "Vegetables":                   ["Lunch", "Dinner"],
    "Dairy Products":               ["Breakfast", "Snack", "Late Night"],
    "Eggs":                         ["Breakfast", "Post Workout"],
    "Chicken Dishes":               ["Lunch", "Dinner", "Post Workout"],
    "Fish & Seafood":               ["Lunch", "Dinner"],
    "Mutton & Meat":                ["Lunch", "Dinner"],
    "Vegetarian Protein Sources":   ["Lunch", "Dinner", "Post Workout"],
    "South Indian Foods":           ["Breakfast", "Lunch", "Dinner"],
    "North Indian Foods":           ["Lunch", "Dinner"],
    "Maharashtrian Foods":          ["Breakfast", "Lunch", "Dinner"],
    "Gujarati Foods":               ["Lunch", "Dinner", "Snack"],
    "Punjabi Foods":                ["Lunch", "Dinner"],
    "Street Foods":                 ["Snack"],
    "Fast Foods":                   ["Snack"],
    "Snacks":                       ["Snack"],
    "Desserts & Sweets":            ["Snack", "Late Night"],
    "Beverages":                    ["Pre Workout", "Post Workout", "Snack"],
    "Protein Supplements":          ["Post Workout", "Breakfast", "Snack"],
    "Healthy Recipes":              ["Breakfast", "Lunch", "Dinner", "Snack"],
    "Weight Loss Foods":            ["Breakfast", "Lunch", "Dinner", "Snack"],
    "Weight Gain Foods":            ["Breakfast", "Lunch", "Dinner", "Post Workout"],
    "Sports Nutrition Foods":       ["Pre Workout", "Post Workout"],
    "Hostel Foods":                 ["Breakfast", "Lunch", "Dinner", "Snack"],
    "Restaurant Foods":             ["Lunch", "Dinner"],
    "International Foods":          ["Lunch", "Dinner"],
    "Salads and Soups":             ["Lunch", "Dinner", "Snack"],
}

CATEGORY_BUDGET: dict[str, str] = {
    "Indian Breakfast": "Low", "Indian Lunch": "Low", "Indian Dinner": "Low",
    "Fruits": "Medium", "Vegetables": "Low", "Dairy Products": "Low",
    "Eggs": "Low", "Chicken Dishes": "Medium", "Fish & Seafood": "High",
    "Mutton & Meat": "High", "Vegetarian Protein Sources": "Medium",
    "South Indian Foods": "Low", "North Indian Foods": "Medium",
    "Maharashtrian Foods": "Low", "Gujarati Foods": "Low", "Punjabi Foods": "Medium",
    "Street Foods": "Low", "Fast Foods": "Medium", "Snacks": "Low",
    "Desserts & Sweets": "Medium", "Beverages": "Low", "Protein Supplements": "High",
    "Healthy Recipes": "Medium", "Weight Loss Foods": "Medium", "Weight Gain Foods": "Medium",
    "Sports Nutrition Foods": "High", "Hostel Foods": "Low", "Restaurant Foods": "High",
    "International Foods": "High", "Salads and Soups": "Medium",
}

CATEGORY_LIVING: dict[str, list[str]] = {
    "Indian Breakfast": ["Hostel", "PG", "Home", "College", "Office"],
    "Indian Lunch": ["Hostel", "PG", "Home", "College", "Office"],
    "Indian Dinner": ["Hostel", "PG", "Home", "College"],
    "Fruits": ["Hostel", "PG", "Home", "College", "Office", "Travel"],
    "Vegetables": ["Home", "PG"],
    "Dairy Products": ["Hostel", "PG", "Home", "College", "Office", "Travel"],
    "Eggs": ["Hostel", "PG", "Home", "College"],
    "Chicken Dishes": ["Home", "PG"],
    "Fish & Seafood": ["Home"],
    "Mutton & Meat": ["Home"],
    "Vegetarian Protein Sources": ["Home", "PG", "Hostel"],
    "South Indian Foods": ["Home", "PG", "Hostel", "College"],
    "North Indian Foods": ["Home", "PG", "Hostel", "College"],
    "Maharashtrian Foods": ["Home", "PG"],
    "Gujarati Foods": ["Home", "PG"],
    "Punjabi Foods": ["Home", "PG"],
    "Street Foods": ["Hostel", "PG", "College", "Travel"],
    "Fast Foods": ["Hostel", "PG", "College", "Office", "Travel"],
    "Snacks": ["Hostel", "PG", "Home", "College", "Office", "Travel"],
    "Desserts & Sweets": ["Home", "PG", "College", "Office"],
    "Beverages": ["Hostel", "PG", "Home", "College", "Office", "Travel"],
    "Protein Supplements": ["Hostel", "PG", "Home", "College", "Office", "Travel"],
    "Healthy Recipes": ["Home", "PG"],
    "Weight Loss Foods": ["Home", "PG", "Hostel", "College", "Office"],
    "Weight Gain Foods": ["Home", "PG", "Hostel", "College"],
    "Sports Nutrition Foods": ["Hostel", "PG", "Home", "College", "Office", "Travel"],
    "Hostel Foods": ["Hostel", "PG", "College"],
    "Restaurant Foods": ["Office", "Travel", "Home"],
    "International Foods": ["Office", "Travel", "Home"],
    "Salads and Soups": ["Home", "PG", "Office"],
}

CATEGORY_AVAILABILITY: dict[str, list[str]] = {
    "Indian Breakfast": ["Hostel Mess", "Easy to Cook"],
    "Indian Lunch": ["Hostel Mess", "Requires Cooking"],
    "Indian Dinner": ["Hostel Mess", "Requires Cooking"],
    "Fruits": ["Indian Grocery", "Ready to Eat"],
    "Vegetables": ["Indian Grocery", "Requires Cooking"],
    "Dairy Products": ["Indian Grocery", "Ready to Eat"],
    "Eggs": ["Indian Grocery", "Easy to Cook"],
    "Chicken Dishes": ["Requires Cooking", "Restaurant"],
    "Fish & Seafood": ["Requires Cooking", "Restaurant"],
    "Mutton & Meat": ["Requires Cooking", "Restaurant"],
    "Vegetarian Protein Sources": ["Indian Grocery", "Easy to Cook"],
    "South Indian Foods": ["Hostel Mess", "Requires Cooking", "Restaurant"],
    "North Indian Foods": ["Hostel Mess", "Requires Cooking", "Restaurant"],
    "Maharashtrian Foods": ["Requires Cooking", "Hostel Mess"],
    "Gujarati Foods": ["Requires Cooking", "Hostel Mess"],
    "Punjabi Foods": ["Requires Cooking", "Restaurant"],
    "Street Foods": ["Restaurant", "Ready to Eat"],
    "Fast Foods": ["Restaurant", "Ready to Eat"],
    "Snacks": ["Indian Grocery", "Ready to Eat"],
    "Desserts & Sweets": ["Indian Grocery", "Ready to Eat"],
    "Beverages": ["Indian Grocery", "Ready to Eat", "Easy to Cook"],
    "Protein Supplements": ["Indian Grocery", "Ready to Eat"],
    "Healthy Recipes": ["Requires Cooking", "Easy to Cook"],
    "Weight Loss Foods": ["Easy to Cook", "Indian Grocery"],
    "Weight Gain Foods": ["Requires Cooking", "Indian Grocery"],
    "Sports Nutrition Foods": ["Indian Grocery", "Ready to Eat"],
    "Hostel Foods": ["Hostel Mess", "Ready to Eat"],
    "Restaurant Foods": ["Restaurant"],
    "International Foods": ["Restaurant", "Requires Cooking"],
    "Salads and Soups": ["Easy to Cook", "Requires Cooking"],
}

CATEGORY_DIFFICULTY: dict[str, str] = {
    "Indian Breakfast": "Easy", "Indian Lunch": "Medium", "Indian Dinner": "Medium",
    "Fruits": "Very Easy", "Vegetables": "Medium", "Dairy Products": "Very Easy",
    "Eggs": "Very Easy", "Chicken Dishes": "Medium", "Fish & Seafood": "Hard",
    "Mutton & Meat": "Hard", "Vegetarian Protein Sources": "Easy",
    "South Indian Foods": "Medium", "North Indian Foods": "Medium",
    "Maharashtrian Foods": "Medium", "Gujarati Foods": "Medium", "Punjabi Foods": "Hard",
    "Street Foods": "Medium", "Fast Foods": "Easy", "Snacks": "Easy",
    "Desserts & Sweets": "Medium", "Beverages": "Very Easy", "Protein Supplements": "Very Easy",
    "Healthy Recipes": "Medium", "Weight Loss Foods": "Easy", "Weight Gain Foods": "Medium",
    "Sports Nutrition Foods": "Very Easy", "Hostel Foods": "Easy", "Restaurant Foods": "Hard",
    "International Foods": "Hard", "Salads and Soups": "Easy",
}

_DIFFICULTY_ORDER = ["Very Easy", "Easy", "Medium", "Hard"]

_EASY_KEYWORDS = ("boiled", "raw", "sliced", "roasted", "toast", "juice", "shake")
_HARD_KEYWORDS = ("biryani", "korma", "restaurant style", "stuffed", "roast (whole)")

_SUMMER_KW = (
    "lassi", "juice", "watermelon", "mango", "coconut water", "chaas", "buttermilk",
    "kulfi", "ice cream", "sattu", "cucumber", "muskmelon", "tender coconut", "sugarcane",
)
_WINTER_KW = (
    "soup", "stew", "halwa", "kheer", "ginger tea", "kadha", "gajar", "til", "sarson",
    "makki", "gud", "jaggery", "hot chocolate", "moong dal halwa",
)
_MONSOON_KW = ("pakora", "bhaji", "corn", "khichdi", "masala chai", "garlic soup", "bhutta")

_VEGAN_EXCLUDE_KW = (
    "milk", "curd", "paneer", "ghee", "butter", "cheese", "yogurt", "yoghurt",
    "cream", "khoya", "honey", "egg", "lassi", "malai",
)
_JAIN_EXCLUDE_KW = ("onion", "garlic", "potato", "aloo", "pyaz", "lehsun", "lahsun", "mushroom")
_HALAL_EXCLUDE_KW = ("pork", "bacon", "ham", "wine", "beer", "alcohol")
_SATVIK_EXCLUDE_KW = _JAIN_EXCLUDE_KW + ("egg",)
_SATVIK_EXCLUDE_CATEGORIES = {"Fast Foods", "Street Foods", "Desserts & Sweets"}

# Kidney / gluten / lactose are not covered by services/medical_conditions.py
# (that module only tracks conditions with exercise+diet prompt rules); this
# is the ONLY new keyword-based detection this file adds — everything else
# medical reuses backend/services/medical_conditions.py at query time.
_GLUTEN_KEYWORDS = ("wheat", "roti", "chapati", "bread", "naan", "paratha", "maida", "suji",
                     "rava", "upma", "poha", "pasta", "noodles", "biscuit", "cake", "bun",
                     "paav", "pav", "cookie", "cracker")
_KIDNEY_HIGH_RISK_CATEGORIES = {"Protein Supplements", "Mutton & Meat", "Fish & Seafood"}

# Cooking ingredients, not standalone dishes — "Khoya (Mawa)" is something you
# cook WITH, not a snack on its own. Category-level heuristics alone tag all
# of Dairy Products as Snack/Breakfast-suitable; this keyword list removes
# the subset that's really a recipe ingredient.
_INGREDIENT_ONLY_KEYWORDS = ("khoya", "mawa", "condensed milk", "evaporated milk", "heavy cream")


def _norm(v: str) -> str:
    return (v or "").lower()


def _contains_any(text: str, keywords: tuple[str, ...]) -> bool:
    text = _norm(text)
    return any(kw in text for kw in keywords)


def _bump_budget(tier: str) -> str:
    return {"Low": "Medium", "Medium": "High", "High": "High"}.get(tier, tier)


# ══════════════════════════════════════════════════════════════════════════
# PER-FOOD DERIVATION
# ══════════════════════════════════════════════════════════════════════════

def _derive_meal_suitable(food: dict) -> list[str]:
    cat = food["category"]
    tags = set(CATEGORY_MEAL.get(cat, ["Snack"]))
    protein, calories, carbs, fat = food["protein"], food["calories"], food["carbs"], food["fat"]

    if protein >= 15 and calories <= 250:
        tags.add("Post Workout")
    if carbs >= 20 and fat <= 5 and calories <= 200:
        tags.add("Pre Workout")
    if calories <= 150 and protein >= 5 and fat <= 5:
        tags.add("Late Night")

    text = f"{food['name']} {food['description']}"
    if _contains_any(text, _INGREDIENT_ONLY_KEYWORDS):
        tags -= {"Snack", "Breakfast", "Late Night"}

    return sorted(tags) or ["Snack"]


def _derive_budget_category(food: dict) -> str:
    tier = CATEGORY_BUDGET.get(food["category"], "Medium")
    if food["type"] == "Non-Vegetarian" and food["category"] != "Eggs":
        tier = _bump_budget(tier)
    return tier


def _derive_living_suitable(food: dict) -> list[str]:
    return list(CATEGORY_LIVING.get(food["category"], ["Home"]))


def _derive_availability(food: dict) -> list[str]:
    return list(CATEGORY_AVAILABILITY.get(food["category"], ["Indian Grocery"]))


def _derive_difficulty(food: dict) -> str:
    base = CATEGORY_DIFFICULTY.get(food["category"], "Medium")
    text = f"{food['name']} {food['description']}"
    idx = _DIFFICULTY_ORDER.index(base)
    if _contains_any(text, _EASY_KEYWORDS):
        idx = max(0, idx - 1)
    if _contains_any(text, _HARD_KEYWORDS):
        idx = min(len(_DIFFICULTY_ORDER) - 1, idx + 1)
    return _DIFFICULTY_ORDER[idx]


def _derive_season(food: dict) -> list[str]:
    text = f"{food['name']} {food['description']}"
    tags = []
    if _contains_any(text, _SUMMER_KW):
        tags.append("Summer")
    if _contains_any(text, _WINTER_KW):
        tags.append("Winter")
    if _contains_any(text, _MONSOON_KW):
        tags.append("Monsoon")
    return tags or ["All Season"]


def _derive_goal_suitable(food: dict) -> list[str]:
    tags = set(food.get("goals", []))
    # Translate the dataset's 4 base goals + macros into the full 8-goal vocab.
    if "Weight Loss" in tags or (food["calories"] <= 200 and food["fiber"] >= 2 and food["fat"] <= 8):
        tags.update({"Weight Loss", "Fat Loss"})
    if food["protein"] >= 15 and food["calories"] <= 300 and food["fat"] <= 10:
        tags.add("Six Pack")
    if "Weight Gain" in tags or (food["calories"] >= 300 and food["carbs"] >= 30):
        tags.add("Lean Bulk")
    if "Muscle Building" in tags or food["protein"] >= 15:
        tags.add("Muscle Gain")
    if food["carbs"] >= 30 and food["calories"] >= 150:
        tags.add("Endurance")
    if food["protein"] >= 12 and food["carbs"] >= 20:
        tags.add("Athletic Performance")
    if "General Fitness" in tags or not tags:
        tags.add("General Fitness")
    return sorted(tags)


def _derive_diet_suitable(food: dict) -> list[str]:
    text = f"{food['name']} {food['description']}"
    allergens = set(food.get("allergens", []))
    is_veg = food["type"] == "Vegetarian"
    tags = ["Vegetarian" if is_veg else "Non Vegetarian"]

    if is_veg or food["category"] == "Eggs":
        tags.append("Eggitarian")
    if is_veg and "Milk" not in allergens and "Egg" not in allergens \
            and food["category"] not in ("Dairy Products", "Eggs", "Desserts & Sweets") \
            and not _contains_any(text, _VEGAN_EXCLUDE_KW):
        tags.append("Vegan")
    if is_veg and not _contains_any(text, _JAIN_EXCLUDE_KW):
        tags.append("Jain")
    if not _contains_any(text, _HALAL_EXCLUDE_KW):
        tags.append("Halal")
    if is_veg and food["category"] not in _SATVIK_EXCLUDE_CATEGORIES \
            and not _contains_any(text, _SATVIK_EXCLUDE_KW):
        tags.append("Satvik")
    return tags


def _derive_disease_suitable(food: dict) -> dict[str, bool]:
    """
    True = safe to recommend for someone with this condition.
    Thresholds are per-serving (this dataset's macros are already per
    serving_size, not per 100g) and deliberately conservative — see
    services/medical_conditions.py for the exercise/diet-rule side of the
    same conditions; this is the missing nutrient-threshold layer for
    filtering the FOOD dataset itself, keyed to match those condition names
    wherever they overlap so the food engine can reuse one detection pass.
    """
    cal, protein, carbs, fat = food["calories"], food["protein"], food["carbs"], food["fat"]
    fiber, sugar, sodium = food["fiber"], food["sugar"], food["sodium"]
    cat = food["category"]
    text = f"{food['name']} {food['description']}"

    diabetes = not (sugar > 10 or cat == "Desserts & Sweets" or (carbs > 40 and fiber < 2))
    hypertension = sodium <= 400
    heart_disease = not (fat > 20 or sodium > 400 or cat in ("Fast Foods", "Desserts & Sweets"))
    kidney_disease = not (sodium > 400 or protein > 30 or cat in _KIDNEY_HIGH_RISK_CATEGORIES)
    fatty_liver = not (fat > 20 or sugar > 15 or cat in ("Desserts & Sweets", "Fast Foods"))
    high_cholesterol = not (fat > 20 and cat in ("Mutton & Meat", "Desserts & Sweets", "Fast Foods"))
    anemia = cat not in ("Beverages", "Desserts & Sweets")
    pcos = not (sugar > 10 or cat in ("Desserts & Sweets", "Fast Foods"))
    thyroid = not (sugar > 15 or cat in ("Fast Foods", "Desserts & Sweets"))
    asthma = cat not in ("Fast Foods",) and not _contains_any(text, ("fried",))
    # Desserts often use milk/khoya/ghee even when the dataset's own allergens
    # field is "None" (that field is coarse) — err conservative for a
    # medical filter rather than trust an under-tagged allergen list.
    lactose_intolerance = "Milk" not in food.get("allergens", []) and cat not in ("Dairy Products", "Desserts & Sweets")
    gluten_intolerance = "Gluten" not in food.get("allergens", []) and not _contains_any(text, _GLUTEN_KEYWORDS)
    food_allergies = food.get("allergens", ["None"]) == ["None"]

    return {
        "Asthma": asthma,
        "Diabetes": diabetes,
        "Hypertension": hypertension,
        "PCOS": pcos,
        "Thyroid": thyroid,
        "Heart Disease": heart_disease,
        "Kidney Disease": kidney_disease,
        "Fatty Liver": fatty_liver,
        "High Cholesterol": high_cholesterol,
        "Anemia": anemia,
        "Lactose Intolerance": lactose_intolerance,
        "Gluten Intolerance": gluten_intolerance,
        "Food Allergies": food_allergies,
        "None": True,
    }


def _derive_scores(food: dict) -> dict[str, float]:
    cal = max(food["calories"], 1)
    protein_density = food["protein"] / cal * 100      # protein g per 100 kcal
    protein_score = round(min(100, protein_density * 12), 1)
    weight_loss_score = round(min(100, max(0, (250 - cal) / 250 * 60 + food["fiber"] * 5 + protein_density * 4)), 1)
    muscle_gain_score = round(min(100, protein_density * 10 + (food["carbs"] / cal * 100) * 2), 1)
    hostel_score = round(min(100, (100 if food["category"] == "Hostel Foods" else 40)
                              + (20 if _derive_budget_category(food) == "Low" else 0)
                              + (20 if _derive_difficulty(food) in ("Very Easy", "Easy") else 0)), 1)
    return {
        "proteinScore": protein_score,
        "weightLossScore": weight_loss_score,
        "muscleGainScore": muscle_gain_score,
        "hostelScore": hostel_score,
    }


def enrich_food(food: dict) -> dict[str, Any]:
    enriched = dict(food)  # never mutate/duplicate — copy, add new keys only
    enriched["mealSuitable"] = _derive_meal_suitable(food)
    enriched["budgetCategory"] = _derive_budget_category(food)
    enriched["livingSuitable"] = _derive_living_suitable(food)
    enriched["goalSuitable"] = _derive_goal_suitable(food)
    enriched["dietSuitable"] = _derive_diet_suitable(food)
    enriched["diseaseSuitable"] = _derive_disease_suitable(food)
    enriched["season"] = _derive_season(food)
    enriched["availability"] = _derive_availability(food)
    enriched["difficulty"] = _derive_difficulty(food)
    enriched.update(_derive_scores(food))
    return enriched


def main() -> None:
    if not _SRC.exists():
        raise FileNotFoundError(f"Source dataset not found: {_SRC}")

    foods = json.loads(_SRC.read_text(encoding="utf-8"))
    print(f"[ENRICH] Loaded {len(foods)} foods from {_SRC}")

    seen_ids = set()
    enriched = []
    for food in foods:
        if food["id"] in seen_ids:
            raise ValueError(f"Duplicate food id detected: {food['id']} ({food['name']}) — refusing to enrich")
        seen_ids.add(food["id"])
        enriched.append(enrich_food(food))

    _DST.write_text(json.dumps(enriched, ensure_ascii=False, indent=None), encoding="utf-8")
    print(f"[ENRICH] Wrote {len(enriched)} enriched foods -> {_DST}")

    # Quick sanity summary
    from collections import Counter
    meal_counts = Counter(t for f in enriched for t in f["mealSuitable"])
    budget_counts = Counter(f["budgetCategory"] for f in enriched)
    print(f"[ENRICH] mealSuitable distribution: {dict(meal_counts)}")
    print(f"[ENRICH] budgetCategory distribution: {dict(budget_counts)}")


if __name__ == "__main__":
    main()
