"""
ZITLAS — Offline Fallback Service
Returns structured responses when ALL AI providers (Groq, Gemini, OpenRouter) fail.
The day/meal SKELETON below (themes, tips, timing labels, emoji, colors) is
static presentational content — that's fine to hand-write. The actual
`foods` in every meal come from services/food_engine.py at call time, same
single 4,500-food dataset as the AI path, so a provider outage never serves
a food from anywhere else (nutri_foods.json's dynamic pool and the
hardcoded _SWAP_POOLS below are kept only as a last-resort default for the
near-impossible case where the engine itself returns nothing for a slot).
"""

from __future__ import annotations
import json
import re
from pathlib import Path
from typing import Any

from services import food_engine, location_food_engine

_DATA_DIR = Path(__file__).parent.parent / "data"


def _load_nutri_foods() -> list[dict]:
    """Load nutri_foods.json — returns empty list if unavailable."""
    path = _DATA_DIR / "nutri_foods.json"
    if not path.exists():
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f).get("foods", [])
    except Exception:
        return []


def _nutri_swap_pool(
    meal_name:     str,
    meal_time:     str,
    budget_str:    str,
    is_hostel:     bool,
    is_veg:        bool,
    rejected:      set[str],
    current_foods: list[str],
) -> list[list[str]]:
    """
    Query nutri_foods.json and return swap-candidate food lists, filtered by
    budget, hostel, veg/non-veg, and exclusion of rejected/current meal foods.
    Sorted by protein-per-calorie for weight-loss optimisation.
    """
    foods = _load_nutri_foods()
    if not foods:
        return []

    nums       = re.findall(r"\d+", str(budget_str or "100"))
    budget_num = int(nums[0]) if nums else 100

    name_lc    = meal_name.lower()
    current_lc = {f.lower() for f in current_foods}
    excluded   = rejected | current_lc

    _DRINK_CAT_KW = {"drink", "juice", "electrolyte", "water", "beverage", "tea", "coffee", "lassi", "smoothie", "shake"}
    _DRINK_NAME_KW = ("juice", "water", "ors", "nimbu pani", "lassi", "tea", "coffee", "smoothie", "shake", "soda")
    is_main_meal = any(k in name_lc for k in ("breakfast", "lunch", "dinner"))

    def _is_drink(food: dict) -> bool:
        cat  = food.get("category", "").lower()
        nm   = food.get("name", "").lower()
        return any(k in cat for k in _DRINK_CAT_KW) or any(k in nm for k in _DRINK_NAME_KW)

    def _protein_per_cal(food: dict) -> float:
        macros = food.get("macros", {})
        cal    = macros.get("cal", 0) or 1
        return (macros.get("protein", 0) or 0) / cal

    candidates: list[tuple[str, float, bool]] = []
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
        name = f.get("name", "")
        if name.lower() in excluded:
            continue
        if is_main_meal and _is_drink(f):
            continue
        if is_main_meal and f.get("macros", {}).get("cal", 0) < 100:
            continue

        timing    = [t.lower() for t in f.get("timing", [])]
        timing_ok = (
            (any(k in name_lc for k in ("breakfast", "morning")) and
             any(t in ("breakfast", "mid-morning") for t in timing))
            or ("lunch"    in name_lc and "lunch"         in timing)
            or ("pre"      in name_lc and "pre-training"  in timing)
            or ("post"     in name_lc and "post-training" in timing)
            or ("recovery" in name_lc and "post-training" in timing)
            or ("dinner"   in name_lc and "dinner"        in timing)
            or ("evening"  in name_lc and "evening snack" in timing)
        )

        candidates.append((name, _protein_per_cal(f), timing_ok))

    if not candidates:
        return []

    # Timing match first, then protein-per-calorie (weight-loss optimised)
    candidates.sort(key=lambda x: (x[2], x[1]), reverse=True)
    return [[c[0]] for c in candidates[:8]]


# ══════════════════════════════════════════════════════════════════════════════
# TEMPLATE SETS — 7 unique days per living/diet context
# ══════════════════════════════════════════════════════════════════════════════

_HOSTEL_DAYS = [
    {   # Monday
        "theme": "Mess Energy Monday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Poha with groundnuts", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd (mess)", "Banana"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rice (mess)", "Dal", "Aloo sabzi", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Parle-G biscuits", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Dal (mess)", "Roti", "Buttermilk"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi (mess)", "Pickle", "Curd"]},
        ],
        "tip": "Poha gives steady carbs — great way to start a training week.",
    },
    {   # Tuesday
        "theme": "Protein Focus Tuesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Upma (mess)", "Boiled egg (if available)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Handful of peanuts"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rajma or Chana (mess)", "Rice", "Roti", "Onion salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Bread + Peanut butter", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Soya chunks curry (mess)", "Roti", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti (mess)", "Rice", "Chaas"]},
        ],
        "tip": "Rajma is one of the best plant proteins available in any hostel mess.",
    },
    {   # Wednesday
        "theme": "Recovery Boost Wednesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Idli (mess)", "Sambar", "Coconut chutney"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Banana", "Curd", "Water"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal tadka (mess)", "Rice", "Sabzi", "Pickle"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Dates (4-5)", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer sabzi (mess)", "Roti", "Salad"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Roti", "Dahi", "Sabzi (mess)"]},
        ],
        "tip": "Dates before training give a quick natural energy spike — keep them in your bag.",
    },
    {   # Thursday
        "theme": "Carb Load Thursday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Paratha or Poori (mess)", "Aloo sabzi", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd (mess)", "Jaggery piece"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rice (extra serving)", "Dal makhani (mess)", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana (2)", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Soya chunks curry (mess)", "Roti (2)", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Chapati (mess)", "Mixed sabzi", "Raita"]},
        ],
        "tip": "On hard training days, eat more carbs at lunch — rice and dal together are perfect.",
    },
    {   # Friday
        "theme": "Strength Day Fuel Friday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Vermicelli upma (mess)", "Chai", "Banana"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Roasted chana (bought)", "Water"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Chole (mess)", "Rice", "Roti", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Peanut butter toast", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Rajma or Paneer (mess)", "Rice", "Buttermilk"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi (mess)", "Raita", "Salad"]},
        ],
        "tip": "Chole has great iron and protein — eat a full lunch before evening training.",
    },
    {   # Saturday
        "theme": "Weekly Check-In Saturday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Poha with peas (mess)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Banana", "Walnuts (4)"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal (mess)", "Rice", "Aloo gobi sabzi", "Curd"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Toast + Jam", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer or Dal (mess)", "Roti", "Salad", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti (mess)", "Chaas", "Fruit"]},
        ],
        "tip": "Sleep well after today — Sunday rest means Monday's deficit eating is stronger.",
    },
    {   # Sunday — rest and recovery
        "theme": "Rest & Rebuild Sunday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "8:00 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Idli (mess)", "Sambar", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "11:00 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd with fruit", "Almonds (6)"]},
            {"meal_name": "Lunch",        "time": "1:30 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rice", "Dal makhani (mess)", "Mixed sabzi", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Light snack: biscuits + chai"]},
            {"meal_name": "Recovery",     "time": "6:30 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer (mess)", "Roti", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:00 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi (mess)", "Pickle", "Dahi"]},
        ],
        "tip": "Today is about recovering — eat regularly, sleep by 10 PM, start next week strong.",
    },
]

_HOME_VEG_DAYS = [
    {   # Monday
        "theme": "Plant Power Monday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Moong dal cheela (2)", "Curd", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Banana", "Milk 1 glass", "Soaked almonds (6)"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal makhani", "Rice", "Roti", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Toast + Peanut butter", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer bhurji", "Roti", "Curd", "Salad"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi", "Sabzi", "Pickle", "Buttermilk"]},
        ],
        "tip": "Moong dal cheela is a perfect high-protein plant breakfast for a member.",
    },
    {   # Tuesday
        "theme": "Strength Build Tuesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Paratha (2)", "Dahi", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Roasted chana (handful)", "Water"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rajma chawal", "Salad", "Curd"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Dates (5)", "Bread + Jam", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Soya chunks curry", "Rice", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti", "Dal", "Buttermilk"]},
        ],
        "tip": "Rajma is a complete protein — eat it on your hardest training days.",
    },
    {   # Wednesday
        "theme": "Recovery Wednesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Idli (3)", "Sambar", "Coconut chutney"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd with seasonal fruit", "Almonds (8)"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Chole", "Roti", "Rice", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana (2)", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer or Tofu stir-fry", "Roti", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi", "Raita", "Salad"]},
        ],
        "tip": "Idli with sambar is light and easy to digest — perfect before a midweek session.",
    },
    {   # Thursday
        "theme": "Power Carb Thursday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Poha with peas and peanuts", "Chai", "Banana"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Jaggery piece"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Palak paneer", "Roti", "Rice", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Toast", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer or Rajma", "Roti", "Sabzi", "Buttermilk"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Dalia", "Curd", "Salad"]},
        ],
        "tip": "Palak paneer = iron + protein in one dish — great for Thursday energy.",
    },
    {   # Friday
        "theme": "Endurance Friday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Upma with vegetables", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd", "Soaked walnuts (5)"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal fry", "Roti", "Rice", "Kachumber salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Peanut butter toast", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer bhurji", "Roti", "Salad", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti", "Dal", "Fruit"]},
        ],
        "tip": "Walnuts support brain function — staying mentally sharp makes sticking to your plan easier.",
    },
    {   # Saturday
        "theme": "Active Saturday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Dosa with sambar and chutney"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Almonds (6)"]},
            {"meal_name": "Lunch",        "time": "12:30 PM", "emoji": "🍽️", "color": "#F97316", "foods": ["Light dal", "Roti", "Curd rice", "Salad"]},
            {"meal_name": "Pre-Training", "time": "3:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Biscuits", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "6:30 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer or Rajma", "Roti", "Sabzi"]},
            {"meal_name": "Dinner",       "time": "8:00 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi", "Curd", "Salad"]},
        ],
        "tip": "Keep Saturday lunch moderate — less oil and a smaller portion helps you stay within your calorie target.",
    },
    {   # Sunday
        "theme": "Rest & Reset Sunday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "8:00 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Rava idli or Semolina cheela", "Chutney", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "11:00 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Fruit bowl (seasonal)", "Milk"]},
            {"meal_name": "Lunch",        "time": "1:30 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rajma or Chole", "Rice", "Sabzi", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Light snack: chana or nuts"]},
            {"meal_name": "Recovery",     "time": "6:30 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer sabzi", "Roti", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Dalia", "Curd", "Salad"]},
        ],
        "tip": "Rest day still needs good food — don't undereat just because you didn't train.",
    },
]

_HOME_NONVEG_DAYS = [
    {   # Monday
        "theme": "Power Start Monday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["2 Egg parathas", "Dahi", "Milk"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Banana", "Peanuts (handful)", "Water"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Chicken curry", "Rice", "Roti", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Peanut butter toast", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg whites (3)", "Roti", "Sabzi", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Dal", "Rice", "Sabzi", "Salad"]},
        ],
        "tip": "Eggs in the morning + chicken at lunch = the simplest muscle-building formula.",
    },
    {   # Tuesday
        "theme": "Endurance Tuesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Scrambled eggs (3)", "Brown bread (2 slices)", "Milk"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd", "Jaggery", "Walnuts (5)"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Fish curry", "Rice", "Roti", "Onion salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Dates (4)", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Chicken or Paneer", "Rice", "Sabzi", "Buttermilk"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Roti", "Sabzi", "Salad", "Curd"]},
        ],
        "tip": "Fish is lighter than chicken — easier to digest, still high in protein.",
    },
    {   # Wednesday
        "theme": "Recovery Wednesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Poha with peanuts", "Boiled eggs (2)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Banana", "Milk 1 glass", "Almonds"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal", "Rice", "Egg curry", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Toast + Peanut butter", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg bhurji (3 eggs)", "Roti", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti", "Dal soup", "Salad"]},
        ],
        "tip": "Egg bhurji after training is quick, cheap, and packed with recovery protein.",
    },
    {   # Thursday
        "theme": "Power Carb Thursday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Chicken keema paratha", "Dahi", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Banana"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rajma or Dal", "Rice (extra)", "Sabzi", "Curd"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana (2)", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Chicken curry", "Roti", "Sabzi"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Roti", "Dal", "Salad", "Buttermilk"]},
        ],
        "tip": "Heavy training day = more rice at lunch. Carbs are fuel, not the enemy.",
    },
    {   # Friday
        "theme": "Strength Friday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Omelette (3 eggs)", "Brown bread", "Milk"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd", "Walnuts (4)", "Jaggery"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Mutton or Chicken curry", "Rice", "Roti", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Peanut butter toast", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg curry or Paneer", "Roti", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi", "Curd", "Salad"]},
        ],
        "tip": "A 3-egg omelette breakfast sets you up for a strong Friday session.",
    },
    {   # Saturday
        "theme": "Active Saturday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Idli or Upma (light)", "Boiled egg (1)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Banana", "Milk 1 glass"]},
            {"meal_name": "Lunch",        "time": "12:30 PM", "emoji": "🍽️", "color": "#F97316", "foods": ["Chicken soup / light curry", "Rice", "Curd", "Salad"]},
            {"meal_name": "Pre-Training", "time": "3:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Toast + Banana", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "6:30 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Chicken tikka or Egg bhurji", "Roti", "Sabzi"]},
            {"meal_name": "Dinner",       "time": "8:00 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Roti", "Dal", "Sabzi", "Curd"]},
        ],
        "tip": "Keep Saturday lunch lighter than usual — easier digestion means more energy for your workout.",
    },
    {   # Sunday
        "theme": "Rest & Rebuild Sunday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "8:00 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Upma or Poha", "Eggs (2)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "11:00 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Fruit bowl", "Milk", "Almonds"]},
            {"meal_name": "Lunch",        "time": "1:30 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Chicken curry (home style)", "Rice", "Salad", "Curd"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Light snack: chana or biscuits"]},
            {"meal_name": "Recovery",     "time": "6:30 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg bhurji or Paneer", "Roti", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi", "Raita", "Salad"]},
        ],
        "tip": "Sunday is recovery — still eat protein at every meal so muscles rebuild overnight.",
    },
]

_HOSTEL_NONVEG_DAYS = [
    {   # Monday
        "theme": "Mess Protein Monday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Bread omelette (2 eggs, canteen)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Boiled egg (1)", "Banana"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Egg curry (mess)", "Rice", "Roti", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana", "Peanuts (handful)", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Dal (mess)", "Roti", "Buttermilk"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti (mess)", "Rice", "Raita"]},
        ],
        "tip": "A bread omelette from the canteen is one of the best hostel breakfasts for a member.",
    },
    {   # Tuesday
        "theme": "Egg Power Tuesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Poha (mess)", "Boiled eggs (2)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Peanut chikki"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal (mess)", "Rice", "Aloo sabzi", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Bread + Peanut butter", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg bhurji (3 eggs)", "Roti", "Curd"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi (mess)", "Pickle", "Chaas"]},
        ],
        "tip": "Eggs are available in most hostel canteens — boil them yourself if needed.",
    },
    {   # Wednesday
        "theme": "Recovery Wednesday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Upma (mess)", "Masala omelette (canteen)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Banana", "Roasted chana"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rajma (mess)", "Rice", "Roti", "Onion salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Dates (5)", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg curry (mess)", "Roti", "Salad"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Roti", "Sabzi (mess)", "Curd"]},
        ],
        "tip": "Rajma at lunch gives you the protein + carbs to power through an afternoon session.",
    },
    {   # Thursday
        "theme": "Carb Load Thursday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Egg paratha (canteen)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd (mess)", "Jaggery piece"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Rice (extra)", "Dal makhani (mess)", "Soya chunks curry", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Banana (2)", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Paneer sabzi (mess)", "Roti", "Buttermilk"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Roti (mess)", "Mixed sabzi", "Raita"]},
        ],
        "tip": "Hard training day — load up on rice at lunch so you have fuel for the evening session.",
    },
    {   # Friday
        "theme": "Strength Friday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Idli (mess)", "Sambar", "Boiled egg (1)"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Banana"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Chole (mess)", "Rice", "Roti", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Peanut butter toast", "Water"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg bhurji (3 eggs)", "Roti", "Dal"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi (mess)", "Curd", "Salad"]},
        ],
        "tip": "Chole has iron + protein — eat a full lunch to fuel the evening session.",
    },
    {   # Saturday
        "theme": "Weekly Check-In Saturday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "7:30 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Poha (mess)", "Masala omelette (canteen)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "10:30 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Milk 1 glass", "Walnuts (4)"]},
            {"meal_name": "Lunch",        "time": "1:00 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal (mess)", "Rice", "Paneer sabzi", "Curd"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Toast + Jam", "Water 500ml"]},
            {"meal_name": "Recovery",     "time": "7:00 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg curry or Dal (mess)", "Roti", "Salad"]},
            {"meal_name": "Dinner",       "time": "8:30 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Sabzi + Roti (mess)", "Chaas", "Banana"]},
        ],
        "tip": "Keep Saturday lunch light and high-protein — it helps you finish the week within your calorie target.",
    },
    {   # Sunday — rest and recovery
        "theme": "Rest & Rebuild Sunday",
        "meals": [
            {"meal_name": "Breakfast",    "time": "8:00 AM",  "emoji": "🌅", "color": "#FF8A00", "foods": ["Idli or Upma (mess)", "Boiled eggs (2)", "Chai"]},
            {"meal_name": "Mid-Morning",  "time": "11:00 AM", "emoji": "🥤", "color": "#22C55E", "foods": ["Curd with fruit", "Peanuts"]},
            {"meal_name": "Lunch",        "time": "1:30 PM",  "emoji": "🍽️", "color": "#F97316", "foods": ["Dal makhani (mess)", "Rice", "Sabzi", "Salad"]},
            {"meal_name": "Pre-Training", "time": "4:30 PM",  "emoji": "⚡",  "color": "#EF4444", "foods": ["Light snack: biscuits + chai"]},
            {"meal_name": "Recovery",     "time": "6:30 PM",  "emoji": "💪", "color": "#A855F7", "foods": ["Egg bhurji or Paneer (mess)", "Roti"]},
            {"meal_name": "Dinner",       "time": "8:00 PM",  "emoji": "🫕", "color": "#3B82F6", "foods": ["Khichdi (mess)", "Pickle", "Dahi"]},
        ],
        "tip": "Rest day — still eat your protein and sleep by 10 PM to start next week strong.",
    },
]

_DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

_HYDRATION_NOTES = [
    "Start the week right — 2.5 litres target. Drink 500ml on waking before chai.",
    "Sip every 30 minutes during training — don't wait until thirsty.",
    "Add nimbu paani or coconut water for electrolytes after today's session.",
    "Thursday hard session needs 3 litres — carry your bottle everywhere today.",
    "Pre-weekend: drink 500ml extra today to stay sharp on Saturday.",
    "Active Saturday: drink 500ml before your workout and 500ml after — hydration speeds fat metabolism.",
    "Rest day still needs 2 litres — recovery is when hydration matters most.",
]

_MEAL_PURPOSE_MAP = {
    "Breakfast":    "Kickstart metabolism and fuel morning training.",
    "Mid-Morning":  "Sustain energy between breakfast and lunch.",
    "Lunch":        "Main carb and protein refuel for afternoon training.",
    "Pre-Training": "Quick energy boost 45 minutes before training.",
    "Recovery":     "Post-training protein and carb window to rebuild muscles.",
    "Dinner":       "Light recovery meal to support overnight repair.",
    "Snack":        "Bridge energy between main meals.",
}


# ══════════════════════════════════════════════════════════════════════════════
# SWAP MEAL POOLS
# ══════════════════════════════════════════════════════════════════════════════

_SWAP_POOLS = {
    "breakfast": {
        True:  [
            ["Poha with groundnuts", "Chai"], ["Upma", "Curd"], ["Idli with sambar", "Chutney"],
            ["Paratha with curd"], ["Moong dal cheela", "Curd"], ["Rava dosa", "Sambar"], ["Dalia", "Milk"],
        ],
        False: [
            ["Egg paratha (2)", "Milk"], ["Scrambled eggs (3)", "Brown bread"], ["Poha", "Boiled eggs (2)"],
            ["Omelette + toast", "Milk"], ["Egg bhurji + roti", "Chai"], ["Upma + boiled egg", "Chai"],
        ],
    },
    "mid_morning": {
        True:  [
            ["Banana", "Curd"], ["Milk 1 glass", "Peanuts"],
            ["Roasted chana", "Water"], ["Dates (5)", "Water"],
            ["Sprout salad", "Nimbu pani"], ["Jaggery piece", "Milk"],
        ],
        False: [
            ["Boiled egg (1)", "Banana"], ["Milk 1 glass", "Peanuts"],
            ["Banana", "Curd"], ["Dates (5)", "Roasted chana"],
            ["Peanut chikki", "Water"],
        ],
    },
    "budget": {
        True:  [
            ["Poha", "Chai"], ["Dal + Roti", "Water"], ["Banana", "Peanuts (handful)"],
            ["Khichdi", "Curd"], ["Upma", "Chai"], ["Idli", "Sambar"],
            ["Rajma Chawal"], ["Moong Dal Cheela", "Chai"], ["Sattu Drink", "Banana"],
        ],
        False: [
            ["Boiled egg (1)", "Bread", "Chai"], ["Poha", "Chai"], ["Dal + Roti"],
            ["Egg bhurji", "Roti"], ["Khichdi"], ["Banana", "Peanuts (handful)"],
            ["Moong Dal Cheela", "Chai"],
        ],
    },
    "hostel": {
        True:  [
            ["Curd (mess)", "Roti"], ["Dal (mess)", "Rice"], ["Sabzi + Roti (mess)"],
            ["Khichdi (mess)", "Curd"], ["Poha (mess)", "Chai"], ["Upma (mess)", "Chai"],
            ["Rajma (mess)", "Rice"], ["Soya chunks curry (mess)", "Roti"],
        ],
        False: [
            ["Egg curry (mess)", "Roti"], ["Boiled egg (2)", "Bread + Peanut butter"],
            ["Dal (mess)", "Rice"], ["Sabzi + Roti (mess)"], ["Khichdi (mess)", "Curd"],
            ["Bread omelette (mess canteen)", "Chai"], ["Poha (mess)", "Chai"],
        ],
    },
    "lunch": {
        True:  [
            ["Dal tadka", "Rice", "Sabzi", "Salad"], ["Rajma chawal", "Curd"],
            ["Chole roti", "Buttermilk"], ["Palak paneer", "Roti", "Dal"],
            ["Paneer bhurji", "Roti", "Salad"], ["Dahi rice", "Sabzi"],
        ],
        False: [
            ["Dal", "Rice", "Chicken curry", "Salad"], ["Fish curry", "Rice", "Roti"],
            ["Egg curry", "Roti", "Dal"], ["Chicken rice bowl", "Curd"],
            ["Chicken soup", "Roti", "Salad"], ["Mutton curry", "Rice"],
        ],
    },
    "pre": {
        True:  [
            ["Banana", "Bread + Jam", "Water"], ["Dates (5)", "Biscuits"], ["Curd rice", "Water"],
            ["Roasted chana", "Water"], ["Toast + Honey", "Water"],
        ],
        False: [
            ["Banana", "Peanut butter toast", "Water"], ["Dates (5)", "Toast"],
            ["Banana + Boiled egg"], ["Bread + egg", "Water"], ["Roasted chana + banana"],
        ],
    },
    "recovery": {
        True:  [
            ["Paneer bhurji", "Roti", "Curd"], ["Soya chunks curry", "Rice"],
            ["Curd", "Banana", "Bread slices"], ["Rajma + rice", "Buttermilk"],
        ],
        False: [
            ["Chicken curry", "Roti", "Salad"], ["Egg bhurji (3)", "Roti", "Curd"],
            ["Paneer sabzi", "Rice", "Dal"], ["Chicken + roti", "Buttermilk"],
        ],
    },
    "dinner": {
        True:  [
            ["Khichdi", "Curd", "Salad"], ["Roti", "Dal", "Sabzi"],
            ["Dalia", "Curd"], ["Sabzi + roti", "Raita"], ["Curd rice", "Pickle"],
        ],
        False: [
            ["Khichdi", "Curd", "Salad"], ["Roti", "Dal", "Sabzi"],
            ["Egg curry", "Roti", "Salad"], ["Chicken + roti", "Curd"],
        ],
    },
}


def _is_veg(diet_type: str) -> bool:
    return "non" not in diet_type.lower()


def _pick_template_set(living: str, diet: str) -> list[dict]:
    is_hostel = any(k in living.lower() for k in ("hostel", "pg", "academy"))
    if is_hostel:
        return _HOSTEL_DAYS if _is_veg(diet) else _HOSTEL_NONVEG_DAYS
    if _is_veg(diet):
        return _HOME_VEG_DAYS
    return _HOME_NONVEG_DAYS


def _filter_rejected(foods: list[str], rejected: set) -> list[str]:
    kept = [f for f in foods if f.lower() not in rejected]
    return kept or ["Roti", "Dal", "Sabzi"]


_OFFLINE_SLOT_MAP = {
    "breakfast": "breakfast", "mid-morning": "mid_morning", "snack": "evening_snack",
    "lunch": "lunch", "pre-training": "mid_morning", "recovery": "evening_snack",
    "dinner": "dinner",
}


def _engine_context(player_profile: dict | None, lifestyle_data: dict | None):
    ld = lifestyle_data or {}
    pp = player_profile or {}
    # Region boost (geo-aware food intelligence) — additive only; a user with
    # no saved location gets profile=None + no favorites, i.e. unchanged offline
    # behavior. Now folds in BOTH the regional categories (profile) AND the
    # regional keyword favorites, matching the main groq path
    # (_engine_query_context) instead of the weaker categories-only signal.
    region_boost = location_food_engine.build_region_boost(pp.get("location") or ld.get("location"))
    profile = {"preferredCategories": region_boost["preferred_categories"]} if region_boost else None
    favorite_foods = list(region_boost["preferred_keywords"]) if region_boost else []
    return {
        "goal_tags": food_engine.goal_tags_from_profile(pp),
        "diet_tags": food_engine.diet_tags_from_lifestyle(ld.get("diet_type", "")),
        "living_tag": food_engine.living_tag_from_lifestyle(ld.get("living_situation", "")),
        "budget_tier": food_engine.budget_tier_from_lifestyle(ld.get("daily_budget", "")),
        "disease_tags": food_engine.FoodRecommendationEngine.resolve_disease_tags(
            pp.get("medical_conditions") or pp.get("medical_condition") or ""),
        "allergens": food_engine.FoodRecommendationEngine.resolve_allergens(ld.get("allergies", [])),
        "profile": profile,
        "favorite_foods": favorite_foods,
    }


def _engine_foods_for_slot(engine, meal_name: str, ctx: dict, usage_counts: dict, rejected: set) -> list[str] | None:
    slot = _OFFLINE_SLOT_MAP.get(meal_name.lower(), "lunch")
    # Rank a WIDER pool, then COMPOSE a complete plate for main slots via the
    # same build_meal_combo/validate_meal_combo the main path uses — so a
    # side dish (e.g. Poha Chivda) can never stand alone as a lunch/dinner in
    # offline mode (the "Sweet Corn dinner" failure pattern). Snack/breakfast
    # slots keep the top pick(s). This closes the offline-only completeness gap
    # without changing the online behavior at all.
    pool = engine.recommend(
        meal_slot=slot, goal_tags=ctx["goal_tags"], diet_tags=ctx["diet_tags"],
        living_situation=ctx["living_tag"], budget_tier=ctx["budget_tier"],
        disease_tags=ctx["disease_tags"], allergens=ctx["allergens"],
        favorite_foods=ctx.get("favorite_foods") or [],
        disliked_foods=list(rejected), usage_counts=usage_counts,
        top_n=10 if slot in ("lunch", "dinner") else 3,
        profile=ctx.get("profile"),
    )
    if not pool:
        return None

    if slot in ("lunch", "dinner"):
        combo = engine.build_meal_combo(pool, slot, None)
        # If the composed plate still fails validation (tiny/edge pools), fall
        # back to the top 2 ranked picks rather than returning nothing.
        picks = combo if combo and not engine.validate_meal_combo(combo, slot) else pool[:2]
    else:
        picks = pool[:1]

    for f in picks:
        usage_counts[f["id"]] = usage_counts.get(f["id"], 0) + 1
    return [food_engine.format_food_line(f) for f in picks]


# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

def nutrition_weekly_plan(
    player_profile: dict,
    lifestyle_data:  dict | None,
    rejected_foods:  list[str] | None = None,
) -> dict[str, Any]:
    """7-day offline meal plan. Day themes/tips/timing are a static skeleton
    (fine — that's presentation, not a food claim); every `foods` value comes
    from FoodRecommendationEngine so an AI-provider outage never serves a
    food outside the 4,500-item dataset."""
    ld       = lifestyle_data or {}
    living   = ld.get("living_situation", "home")
    diet     = ld.get("diet_type", "mixed")
    goal     = (player_profile or {}).get("primary_goal", "lose weight")
    calorie_target = (player_profile or {}).get("daily_calorie_target", "")
    rejected = {f.lower() for f in (rejected_foods or [])}

    templates = _pick_template_set(living, diet)
    engine = food_engine.get_engine()
    ctx = _engine_context(player_profile, ld)
    usage_counts: dict[int, int] = {}
    days: list[dict] = []

    for i, day_name in enumerate(_DAY_NAMES):
        # Each index i maps to a unique template (templates has exactly 7 entries)
        tmpl  = templates[i % len(templates)]
        meals = []
        for m in tmpl["meals"]:
            engine_foods = _engine_foods_for_slot(engine, m["meal_name"], ctx, usage_counts, rejected)
            foods = engine_foods if engine_foods else _filter_rejected(m["foods"], rejected)
            meals.append({
                "meal_name": m["meal_name"],
                "time":      m["time"],
                "emoji":     m["emoji"],
                "color":     m["color"],
                "foods":     foods,
                "purpose":   _MEAL_PURPOSE_MAP.get(m["meal_name"], f"Supports your {goal} goal."),
            })
        days.append({
            "day":            day_name,
            "day_type":       "Rest Day" if i == 6 else "Training Day",
            "theme":          tmpl["theme"],
            "meals":          meals,
            "hydration_note": _HYDRATION_NOTES[i],
            "nutrition_tip":  tmpl["tip"],
        })

    calorie_note = f" Target: {calorie_target} kcal/day." if calorie_target else ""
    print(f"[Offline] nutrition_weekly_plan (engine-sourced): goal={goal} / {living} / {diet}")
    return {
        "plan_name":              "7-Day Weight-Loss Meal Plan",
        "nutrition_focus":         f"Calorie deficit eating to support your goal: {goal}.{calorie_note}",
        "hydration_daily_target":  "2.5 litres",
        "days":                    days,
        "weekly_notes": (
            "Eat at regular intervals — skipping meals causes overeating later. "
            "Focus on: protein at every meal, vegetables to stay full, and 2.5 litres of water daily."
        ),
    }


def meal_swap(
    meal_name:            str,
    meal_time:            str,
    current_foods:        list[str],
    reason:               str,
    lifestyle_data:       dict | None,
    rejected_foods:       list[str] | None = None,
    previous_suggestions: list[list[str]] | None = None,
    player_profile:       dict | None = None,
) -> dict[str, Any]:
    """Single meal swap — sourced from FoodRecommendationEngine (same dataset
    as the AI path). nutri_foods.json's dynamic pool and the hardcoded
    _SWAP_POOLS below only run if the engine itself returns nothing for this
    slot, which shouldn't happen across a 4,500-food dataset outside a
    pathological combination of diet+medical+allergy restrictions."""
    ld        = lifestyle_data or {}
    diet      = ld.get("diet_type", "mixed")
    veg       = _is_veg(diet)
    rejected  = {f.lower() for f in (rejected_foods or [])}
    for prev in (previous_suggestions or []):
        rejected.update(f.lower() for f in prev)

    from services.groq_service import _meal_slot_from_name, _diet_type_from_reason  # substring-based; robust to arbitrary user-facing meal names

    engine = food_engine.get_engine()
    ctx = _engine_context(player_profile, ld)
    # An explicit diet constraint in the swap reason ("I am vegetarian")
    # overrides the stored diet_type — same rule as the online path.
    reason_diet = _diet_type_from_reason(reason)
    diet_tags = food_engine.diet_tags_from_lifestyle(reason_diet) if reason_diet else ctx["diet_tags"]
    slot = _meal_slot_from_name(meal_name, meal_time)
    exclude_names = list(current_foods) + list(rejected)
    combos = engine.find_swap_combos(
        meal_slot=slot, goal_tags=ctx["goal_tags"], diet_tags=diet_tags,
        living_situation=ctx["living_tag"], budget_tier=ctx["budget_tier"],
        disease_tags=ctx["disease_tags"], allergens=ctx["allergens"],
        exclude_names=exclude_names, n_combos=2,
    )

    if combos:
        def _combo_block(combo, label):
            return {
                "name": " + ".join(f["name"] for f in combo),
                "foods": [food_engine.format_food_line(f) for f in combo],
                "calories": round(sum(f["calories"] for f in combo)),
                "protein_g": round(sum(f["protein"] for f in combo), 1),
                "reason": f"{label} that fits your situation ({reason}).",
            }
        swap_block = _combo_block(combos[0], "A practical replacement")
        alt_block = _combo_block(combos[1], "Another option") if len(combos) > 1 else None
        print(f"[Offline] meal_swap (engine-sourced): {meal_name} -> {swap_block['foods']}")
        return {"swap": swap_block, "alternative": alt_block, "tips": [], "calories_saved": 0}

    # ── Last-resort legacy pools — only reached if the engine returns
    #    nothing at all for this slot+filters combination. ──────────────────
    is_hostel = any(k in ld.get("living_situation", "").lower() for k in ("hostel", "pg", "academy"))
    nutri_pool = _nutri_swap_pool(
        meal_name=meal_name, meal_time=meal_time, budget_str=ld.get("daily_budget", "100"),
        is_hostel=is_hostel, is_veg=veg, rejected=rejected, current_foods=current_foods,
    )
    chosen = None
    for candidate in nutri_pool:
        if not any(f.lower() in rejected for f in candidate):
            chosen = candidate
            break
    if not chosen:
        reason_lc = reason.lower()
        name_lc   = meal_name.lower()
        if "expensive" in reason_lc or "budget" in reason_lc:
            key = "budget"
        elif "hostel" in reason_lc or "mess" in reason_lc:
            key = "hostel"
        elif "mid" in name_lc or ("morning" in name_lc and "breakfast" not in name_lc):
            key = "mid_morning"
        elif "breakfast" in name_lc:
            key = "breakfast"
        elif "lunch" in name_lc:
            key = "lunch"
        elif "pre" in name_lc or "training" in name_lc:
            key = "pre"
        elif "recovery" in name_lc or "post" in name_lc:
            key = "recovery"
        else:
            key = "dinner"
        pool = _SWAP_POOLS.get(key, _SWAP_POOLS["dinner"])[veg]
        for candidate in pool:
            if not any(f.lower() in rejected for f in candidate):
                chosen = candidate
                break
    if not chosen:
        chosen = ["Roti", "Dal", "Sabzi"]

    print(f"[Offline] meal_swap (legacy last-resort): {meal_name} -> {chosen} (reason: {reason})")
    reason_text = f"A practical replacement that fits your situation ({reason})."
    return {
        "swap": {"name": f"{meal_name} Alternative", "foods": chosen, "calories": 0, "protein_g": 0, "reason": reason_text},
        "alternative": None,
        "tips": [],
        "calories_saved": 0,
    }


def coach_finalize_profile(collected_data: dict) -> dict[str, Any]:
    """Build a weight-loss user profile from collected conversation data when AI fails."""
    primary_goal    = collected_data.get("primary_goal", "Lose Weight")
    current_weight  = float(collected_data.get("current_weight") or 75)
    goal_weight     = float(collected_data.get("goal_weight") or 65)
    height_cm       = float(collected_data.get("height") or 170)
    age             = int(collected_data.get("age") or 25)
    activity_level  = collected_data.get("activity_level", "lightly_active")
    eating_habit    = collected_data.get("eating_habit", "mixed")
    workout_type    = collected_data.get("workout_type", "home")
    living          = collected_data.get("living_situation", "home")
    diet            = collected_data.get("diet_type", "mixed")
    fav_foods       = collected_data.get("favorite_foods") or []
    disliked        = collected_data.get("disliked_foods")  or []
    allergies       = collected_data.get("allergies")       or []
    daily_bud       = collected_data.get("daily_budget", "₹100")
    cooking         = collected_data.get("cooking_access", "full" if "home" in str(living).lower() else "none")
    sleep           = int(collected_data.get("sleep_hours") or 7)

    is_hostel = any(k in str(living).lower() for k in ("hostel", "pg", "academy"))

    # BMI and category
    height_m = height_cm / 100
    bmi = round(current_weight / (height_m ** 2), 1)
    if bmi < 18.5:
        bmi_cat = "Underweight"
    elif bmi < 25:
        bmi_cat = "Normal"
    elif bmi < 30:
        bmi_cat = "Overweight"
    else:
        bmi_cat = "Obese"

    # Harris-Benedict TDEE (simplified, assume male if unknown)
    bmr = 10 * current_weight + 6.25 * height_cm - 5 * age + 5
    activity_multipliers = {
        "sedentary": 1.2, "lightly_active": 1.375,
        "moderately_active": 1.55, "very_active": 1.725,
    }
    tdee = bmr * activity_multipliers.get(activity_level, 1.375)
    calorie_target = round(tdee - 400)
    protein_target = round(goal_weight * 0.9)

    weight_to_lose = round(current_weight - goal_weight, 1)
    if weight_to_lose <= 5:
        tier = "Beginner"
    elif weight_to_lose <= 15:
        tier = "Intermediate"
    else:
        tier = "Advanced"

    print(f"[Offline] coach_finalize: goal={primary_goal} bmi={bmi} cal={calorie_target} tier={tier}")
    return {
        "athlete_profile": {
            "primary_goal":           primary_goal,
            "current_weight":         current_weight,
            "goal_weight":            goal_weight,
            "height":                 height_cm,
            "bmi":                    bmi,
            "bmi_category":           bmi_cat,
            "age":                    age,
            "gender":                 collected_data.get("gender", "not_specified"),
            "activity_level":         activity_level,
            "eating_habit":           eating_habit,
            "workout_type":           workout_type,
            "daily_calorie_target":   calorie_target,
            "daily_protein_target_g": protein_target,
            "sleep_hours":            sleep,
            "commitment":             collected_data.get("commitment", "High"),
            "motivation":             "High",
            "energy_level":           "Moderate",
            "hardest_thing":          "Staying consistent with healthy eating",
            "improvements_wanted":    ["Consistent calorie deficit", "More protein", "Better sleep"],
            "nutrition_bottleneck":   (
                "Hostel mess constraints make calorie tracking harder" if is_hostel
                else "Snacking and portion control"
            ),
            "development_priority":   f"Reach {goal_weight}kg through daily calorie deficit and protein focus",
        },
        "lifestyle_data": {
            "living_situation": living,
            "diet_type":        diet,
            "available_foods":  collected_data.get("available_foods") or ["General Indian food"],
            "cooking_access":   cooking,
            "daily_budget":     daily_bud,
            "water_intake":     collected_data.get("water_intake", "adequate"),
            "favorite_foods":   fav_foods,
            "disliked_foods":   disliked,
            "allergies":        allergies,
        },
        "overall_swot": {
            "strengths":     ["Committed to change", "Clear weight goal set"],
            "weaknesses":    ["Needs consistent calorie tracking", "Improve meal timing"],
            "opportunities": ["Structured meal plan will accelerate progress"],
            "threats":       ["Weekend overeating", "Low protein leading to muscle loss"],
        },
        "development_priority": f"Lose {weight_to_lose}kg by maintaining a {calorie_target} kcal/day diet",
        "athlete_tier":         tier,
        "athlete_summary": (
            f"You are starting your weight-loss journey with {weight_to_lose}kg to lose. "
            f"Your daily target is {calorie_target} kcal and {protein_target}g protein. Stay consistent!"
        ),
    }
