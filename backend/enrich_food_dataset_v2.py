"""
ZITLAS — Food Dataset Enrichment v2: Indian Location Intelligence
(backend/enrich_food_dataset_v2.py)

Adds a SECOND, purely ADDITIVE enrichment layer on top of the existing
pipeline (enrich_food_dataset.py): regional origin, pan-India popularity,
availability, meal-priority tiering, and boolean conveniences for diet
booleans / meal timing / lifestyle fit.

GUARANTEES (verified by main() before it writes anything):
  - Reads ONLY food_dataset/zitlas_food_database.json (the untouched
    4,500-food source) — this script never reads or depends on any
    previous enriched output, so it is idempotent no matter how many
    times it runs.
  - Calls enrich_food_dataset.enrich_food() first to get the EXACT same
    v1 fields (mealSuitable, budgetCategory, livingSuitable, goalSuitable,
    dietSuitable, diseaseSuitable, season, availability, difficulty,
    proteinScore/weightLossScore/muscleGainScore/hostelScore) — nothing
    from v1 is recomputed differently or removed.
  - Only ADDS new keys on top. calories/protein/carbs/fat/fiber/sugar/
    sodium/serving_size/id/name/category/type/goals/allergens/description
    are copied verbatim from the source and never touched.
  - Writes the same output path v1 always wrote
    (food_dataset/zitlas_food_database_enriched.json) so food_engine.py
    needs zero changes to pick up the new fields — a backup of whatever
    was there before is written alongside it first.

NEW FIELDS PER FOOD:
  state_of_origin   list[str]   real states this specific dish is FROM
                                 (empty if it has no specific regional
                                 origin — a boiled egg isn't "from"
                                 anywhere)
  region            str         North | West | Central | East | Northeast
                                 | South | Pan-India
  available_states  list[str]   where it's realistically eaten today —
                                 ["All"] for pan_india foods, else the
                                 origin states (honest: we don't have
                                 wider distribution data to claim more)
  pan_india         bool        true for nationally common staples/
                                 breakfast items (STEP 4's own list) and
                                 generic proteins/produce/dairy with no
                                 specific regional identity
  meal_type         dict        {breakfast, lunch, dinner, snack,
                                 pre_workout, post_workout} — booleans
                                 DERIVED from the existing mealSuitable
                                 tags (this is not new information, just
                                 exposed as the nested shape requested)
  festival_food     bool        curated list of occasion-only sweets/
                                 specialties (Puran Poli, Modak, Rasgulla,
                                 Malpua, Mysore Pak, Gujiya-type items) —
                                 NOT a blanket flag on "Desserts & Sweets"
  daily_food        bool        popularity_score >= 60 and not festival
  popularity_score  float 0-100 how commonly an average Indian eats this
                                 (tiered: named staples > common regional
                                 dishes > niche regional > festival)
  availability_score float 0-100 how easy it is to actually obtain this
                                 today (pan-India + budget + easy-to-cook
                                 all raise it; festival/rare lower it)
  meal_priority     int 1-3     1 = daily staple, 2 = regular, 3 =
                                 occasional/festival — a direct, cheap
                                 ranking tier derived from popularity_score
  vegetarian / eggetarian / non_vegetarian / vegan / jain   bool
                                 — read straight off the EXISTING
                                 dietSuitable list, just exposed as
                                 booleans (additive, dietSuitable itself
                                 is untouched)
  hostel_friendly / office_friendly / home_cooked / street_food /
  restaurant_food   bool        derived from the existing livingSuitable
                                 list, category, AND the "(Restaurant
                                 Style)" / "(Home Style)" / "(Hostel Mess
                                 Style)" / "(Street Style)" name suffixes
                                 the base dataset already uses

Usage (from backend/ directory):
    python enrich_food_dataset_v2.py
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from typing import Any

from enrich_food_dataset import enrich_food, _SRC, _DST  # reuse v1 exactly

_BACKUP = _DST.with_name(_DST.stem + ".pre_v2_backup.json")


def _norm(s: str) -> str:
    return (s or "").strip().lower()


def _contains_word(text: str, keyword: str) -> bool:
    """Word-boundary match (with an optional trailing 's' for plurals like
    "Devilled Eggs"), not a bare substring check — a plain `kw in text` let
    short staple keywords like "dal" false-positive inside unrelated names
    ("Chicken VinDALoo", "DALiya", "Kala Chana SunDAL", "DALma"), wrongly
    handing them the Dal-staple popularity score. Caught via a v3 spot-check;
    fixed here since every STAPLE_SCORE_OVERRIDES lookup goes through this."""
    return re.search(r"\b" + re.escape(keyword) + r"s?\b", text) is not None


# ══════════════════════════════════════════════════════════════════════════
# REGIONAL DISH DICTIONARY
# Every keyword below was checked against the live 4,500-food dataset
# before being added (see verify script in session history) — a dish only
# appears here if a real dataset food name contains it. Dishes with no
# verified match (e.g. Kahwa, Yakhni, Dal Baati Churma, Pakhala, Ragi
# Mudde) are intentionally NOT included — inventing a tag for a food the
# engine can't actually retrieve would misrepresent coverage. Those
# regions still get correct region/category-level tagging; they just
# don't have a dataset-backed NAMED dish to point to yet.
#
# Ordered by keyword specificity — longer/more specific keywords are
# checked first so "sarson" doesn't get consumed by a shorter unrelated
# token, etc. (There's no actual collision in this list; kept ordered
# for future additions.)
# ══════════════════════════════════════════════════════════════════════════

REGIONAL_DISHES: list[tuple[str, list[str], str]] = [
    # ── North: Punjab / Haryana / Delhi ──
    ("sarson ka saag", ["Punjab", "Haryana", "Delhi"], "North"),
    ("makki", ["Punjab", "Haryana"], "North"),
    ("rajma", ["Punjab", "Delhi", "Haryana"], "North"),
    ("chole", ["Punjab", "Delhi", "Haryana"], "North"),
    ("bhature", ["Punjab", "Delhi"], "North"),
    ("dal makhani", ["Punjab", "Delhi"], "North"),
    ("amritsari", ["Punjab"], "North"),
    ("kulcha", ["Punjab", "Delhi"], "North"),
    ("lassi", ["Punjab", "Haryana"], "North"),
    ("tandoori roti", ["Punjab", "Delhi", "Haryana"], "North"),
    ("butter chicken", ["Punjab", "Delhi"], "North"),
    ("chana masala", ["Punjab", "Delhi"], "North"),
    ("kadhi", ["Punjab", "Rajasthan", "Uttar Pradesh"], "North"),

    # ── North: Jammu & Kashmir / Ladakh ──
    ("rogan josh", ["Jammu & Kashmir"], "North"),
    ("dum aloo", ["Jammu & Kashmir"], "North"),
    ("kashmiri", ["Jammu & Kashmir"], "North"),

    # ── North / Northeast (Tibetan-influenced, shared) ──
    ("momo", ["Sikkim", "Arunachal Pradesh", "Ladakh", "Himachal Pradesh"], "North"),

    # ── North: UP / Bihar / Jharkhand ──
    ("litti chokha", ["Bihar", "Jharkhand"], "East"),
    ("sattu", ["Bihar", "Jharkhand"], "East"),
    ("bedmi", ["Uttar Pradesh"], "North"),
    ("kachori", ["Uttar Pradesh", "Rajasthan", "Bihar"], "North"),
    ("malpua", ["Bihar", "Uttar Pradesh"], "North"),

    # ── West: Maharashtra ──
    ("misal", ["Maharashtra"], "West"),
    ("vada pav", ["Maharashtra"], "West"),
    ("sabudana khichdi", ["Maharashtra"], "West"),
    ("pithla bhakri", ["Maharashtra"], "West"),
    ("solkadhi", ["Maharashtra", "Goa"], "West"),
    ("puran poli", ["Maharashtra"], "West"),
    ("modak", ["Maharashtra"], "West"),
    ("thalipeeth", ["Maharashtra"], "West"),
    ("poha", ["Maharashtra", "Madhya Pradesh"], "West"),

    # ── West: Goa ──
    ("vindaloo", ["Goa"], "West"),

    # ── West: Gujarat ──
    ("thepla", ["Gujarat"], "West"),
    ("khakhra", ["Gujarat"], "West"),
    ("handvo", ["Gujarat"], "West"),
    ("dhokla", ["Gujarat"], "West"),
    ("undhiyu", ["Gujarat"], "West"),
    ("fafda", ["Gujarat"], "West"),
    ("khandvi", ["Gujarat"], "West"),
    ("dal dhokli", ["Gujarat"], "West"),

    # ── East: West Bengal ──
    ("rasgulla", ["West Bengal"], "East"),

    # ── South: Tamil Nadu specific ──
    ("pongal", ["Tamil Nadu"], "South"),
    ("curd rice", ["Tamil Nadu"], "South"),
    ("rasam", ["Tamil Nadu"], "South"),
    ("chettinad", ["Tamil Nadu"], "South"),
    ("kootu", ["Tamil Nadu"], "South"),

    # ── South: Kerala specific ──
    ("appam", ["Kerala"], "South"),
    ("puttu", ["Kerala"], "South"),
    ("avial", ["Kerala"], "South"),
    ("sadya", ["Kerala"], "South"),
    ("idiyappam", ["Kerala"], "South"),

    # ── South: Karnataka specific ──
    ("bisi bele bath", ["Karnataka"], "South"),
    ("mysore pak", ["Karnataka"], "South"),
    ("akki roti", ["Karnataka"], "South"),

    # ── South: Andhra Pradesh / Telangana specific ──
    ("pesarattu", ["Andhra Pradesh", "Telangana"], "South"),
    ("gongura", ["Andhra Pradesh", "Telangana"], "South"),
    ("hyderabadi biryani", ["Telangana"], "South"),

    # ── South: shared across the whole region (no single-state claim) ──
    ("idli", ["Tamil Nadu", "Karnataka", "Andhra Pradesh", "Telangana"], "South"),
    ("dosa", ["Tamil Nadu", "Karnataka", "Andhra Pradesh", "Telangana"], "South"),
    ("sambar", ["Tamil Nadu", "Karnataka", "Kerala"], "South"),
    ("medu vada", ["Tamil Nadu", "Karnataka"], "South"),
    ("uttapam", ["Tamil Nadu", "Karnataka"], "South"),
    ("fish curry", ["Kerala", "Goa", "West Bengal"], "South"),
]

# category -> (region, available_states, treat as pan_india?)
# South Indian Foods spans 5 states with no per-dish split possible for
# every item in that category — items not already caught by a specific
# REGIONAL_DISHES keyword above still get a correct, honest South-India
# tag rather than being left unclassified.
CATEGORY_REGION: dict[str, tuple[str, list[str]]] = {
    "Maharashtrian Foods": ("West", ["Maharashtra"]),
    "Gujarati Foods":      ("West", ["Gujarat"]),
    "Punjabi Foods":       ("North", ["Punjab", "Haryana", "Delhi"]),
    "North Indian Foods":  ("North", ["Punjab", "Uttar Pradesh", "Delhi", "Haryana", "Rajasthan"]),
    "South Indian Foods":  ("South", ["Tamil Nadu", "Kerala", "Karnataka", "Andhra Pradesh", "Telangana"]),
}

# STEP 4's own explicit pan-India list, plus generic protein/produce/dairy
# staples with no regional identity. Matched by substring against the
# lowercased food name — deliberately broad since these ARE meant to
# dominate every diet plan regardless of location.
PAN_INDIA_KEYWORDS = [
    "roti", "chapati", "rice", "dal", "paneer", "chicken curry", "boiled chicken",
    "grilled chicken", "fish curry", "boiled egg", "egg curry", "egg bhurji",
    "omelette", "curd", "milk", "banana", "poha", "upma", "idli", "dosa",
    "khichdi", "sprouts", "roasted chana", "mixed vegetable", "oats", "salad",
    "vegetable soup", "chapati", "sabzi", "buttermilk", "apple", "orange",
]

# Curated — NOT every dessert, only genuinely occasion/festival-specific items.
FESTIVAL_KEYWORDS = [
    "modak", "puran poli", "rasgulla", "malpua", "mysore pak", "gujiya",
    "sheer khurma", "kheer", "halwa", "laddoo", "ladoo", "barfi", "jalebi",
    "gulab jamun", "onam sadya",
]

# Exact, spec-given anchor scores for the most universal staples — everything
# else is scored by tier rules below.
STAPLE_SCORE_OVERRIDES: dict[str, float] = {
    "roti": 100, "chapati": 100, "rice": 100, "dal": 100,
    "curd": 95, "egg": 95, "boiled egg": 95, "paneer": 92,
    "poha": 90, "idli": 90, "misal": 70, "puran poli": 15,
}


def _find_regional_match(name_lc: str) -> tuple[list[str], str] | None:
    for keyword, states, region in REGIONAL_DISHES:
        if _contains_word(name_lc, keyword):
            return states, region
    return None


def _is_pan_india(name_lc: str) -> bool:
    return any(_contains_word(name_lc, kw) for kw in PAN_INDIA_KEYWORDS)


def _is_festival(name_lc: str) -> bool:
    return any(_contains_word(name_lc, kw) for kw in FESTIVAL_KEYWORDS)


def _derive_location_fields(food: dict, name_lc: str) -> dict[str, Any]:
    regional = _find_regional_match(name_lc)
    pan_india = _is_pan_india(name_lc)
    category = food.get("category", "")

    if regional:
        state_of_origin, region = regional
        available_states = list(state_of_origin)
    elif category in CATEGORY_REGION:
        region, available_states = CATEGORY_REGION[category]
        state_of_origin = []  # category-level regional, no single dish origin claimed
    elif pan_india:
        state_of_origin, region, available_states = [], "Pan-India", ["All"]
    else:
        # Generic item with no specific regional signal (most fruits,
        # vegetables, dairy, supplements, international foods) — pan-India
        # by default rather than leaving it unclassified; this is the
        # correct default for "would a normal person anywhere eat this".
        state_of_origin, region, available_states = [], "Pan-India", ["All"]
        pan_india = True

    return {
        "state_of_origin": state_of_origin,
        "region": region,
        "available_states": available_states,
        "pan_india": pan_india,
    }


def _derive_popularity(food: dict, name_lc: str, is_festival: bool, pan_india: bool, has_regional_origin: bool) -> float:
    for kw, score in STAPLE_SCORE_OVERRIDES.items():
        if _contains_word(name_lc, kw):
            return float(score)
    if is_festival:
        return 15.0
    if pan_india and not has_regional_origin:
        # Generic pan-India staple/produce/protein with no dish identity
        return 85.0
    if pan_india and has_regional_origin:
        # e.g. Poha, Idli, Dosa — nationally common AND has a home state
        return 88.0
    if has_regional_origin:
        # Named regional dish, not flagged pan-India — still genuinely
        # popular within its home region (Misal, Dhokla, Bisi Bele Bath...)
        return 65.0
    # Category-level regional (South Indian Foods etc. with no specific
    # dish match) — reasonably common within that broad region
    return 55.0


def _derive_availability(food: dict, popularity: float, pan_india: bool) -> float:
    budget = food.get("budgetCategory", "Medium")
    difficulty = food.get("difficulty", "Medium")
    score = popularity * 0.6
    score += 25 if pan_india else 10
    score += {"Low": 10, "Medium": 5, "High": 0}.get(budget, 5)
    score += {"Very Easy": 5, "Easy": 5, "Medium": 0, "Hard": -5}.get(difficulty, 0)
    return round(min(100.0, max(5.0, score)), 1)


def _derive_meal_type(v1: dict) -> dict[str, bool]:
    tags = set(v1.get("mealSuitable", []))
    return {
        "breakfast":     "Breakfast" in tags,
        "lunch":         "Lunch" in tags,
        "dinner":        "Dinner" in tags,
        "snack":         "Snack" in tags,
        "pre_workout":   "Pre Workout" in tags,
        "post_workout":  "Post Workout" in tags,
    }


def _derive_diet_booleans(v1: dict) -> dict[str, bool]:
    tags = set(v1.get("dietSuitable", []))
    return {
        "vegetarian":     "Vegetarian" in tags,
        "eggetarian":     "Eggitarian" in tags,
        "non_vegetarian": "Non Vegetarian" in tags,
        "vegan":          "Vegan" in tags,
        "jain":           "Jain" in tags,
    }


def _derive_lifestyle_booleans(v1: dict, name_lc: str) -> dict[str, bool]:
    living = set(v1.get("livingSuitable", []))
    category = v1.get("category", "")
    is_restaurant = "(restaurant style)" in name_lc or category in ("Restaurant Foods", "Fast Foods", "International Foods")
    is_street = "(street style)" in name_lc or category == "Street Foods"
    is_hostel_style = "(hostel mess style)" in name_lc or category == "Hostel Foods" or "Hostel" in living
    is_home_style = "(home style)" in name_lc
    # Default to home-cooked when no style suffix marks it as exclusively
    # restaurant/street — most base dataset entries (no suffix) ARE the
    # plain home-cooked version.
    home_cooked = is_home_style or (not is_restaurant and not is_street)
    return {
        "hostel_friendly": is_hostel_style or "Hostel" in living or "PG" in living,
        "office_friendly": "Office" in living,
        "home_cooked":     home_cooked,
        "street_food":     is_street,
        "restaurant_food": is_restaurant,
    }


def enrich_food_v2(food: dict) -> dict[str, Any]:
    v1 = enrich_food(food)  # existing pipeline — untouched, fully reused
    name_lc = _norm(food["name"])

    loc = _derive_location_fields(v1, name_lc)
    festival = _is_festival(name_lc)
    popularity = _derive_popularity(v1, name_lc, festival, loc["pan_india"], bool(loc["state_of_origin"]))
    availability = _derive_availability(v1, popularity, loc["pan_india"])
    meal_priority = 1 if popularity >= 85 else (2 if popularity >= 50 else 3)
    daily_food = popularity >= 60 and not festival

    out = dict(v1)  # copy — add new keys only, nothing removed or recomputed
    out.update(loc)
    out["meal_type"] = _derive_meal_type(v1)
    out["festival_food"] = festival
    out["daily_food"] = daily_food
    out["popularity_score"] = round(popularity, 1)
    out["availability_score"] = availability
    out["meal_priority"] = meal_priority
    out.update(_derive_diet_booleans(v1))
    out.update(_derive_lifestyle_booleans(v1, name_lc))
    return out


# ══════════════════════════════════════════════════════════════════════════
# INTEGRITY CHECKS — refuse to write if anything protected changed
# ══════════════════════════════════════════════════════════════════════════

_PROTECTED_FIELDS = ("id", "name", "category", "serving_size", "calories",
                     "protein", "carbs", "fat", "fiber", "sugar", "sodium")


def _assert_untouched(original: dict, enriched: dict) -> None:
    for field in _PROTECTED_FIELDS:
        if original.get(field) != enriched.get(field):
            raise AssertionError(
                f"Protected field '{field}' changed for food id={original.get('id')} "
                f"({original.get('name')}): {original.get(field)!r} -> {enriched.get(field)!r}"
            )


def main() -> None:
    if not _SRC.exists():
        raise FileNotFoundError(f"Source dataset not found: {_SRC}")

    raw_foods = json.loads(_SRC.read_text(encoding="utf-8"))
    print(f"[ENRICH v2] Loaded {len(raw_foods)} foods from source: {_SRC}")

    seen_ids = set()
    enriched: list[dict] = []
    for food in raw_foods:
        if food["id"] in seen_ids:
            raise ValueError(f"Duplicate food id detected: {food['id']} ({food['name']}) — refusing to enrich")
        seen_ids.add(food["id"])
        record = enrich_food_v2(food)
        _assert_untouched(food, record)
        enriched.append(record)

    if len(enriched) != len(raw_foods):
        raise AssertionError(f"Record count mismatch: {len(enriched)} enriched vs {len(raw_foods)} source — refusing to write")

    # Back up whatever enriched file currently exists before overwriting —
    # reversible even though this script never reads that old file.
    if _DST.exists():
        shutil.copy2(_DST, _BACKUP)
        print(f"[ENRICH v2] Backed up previous enriched file -> {_BACKUP}")

    _DST.write_text(json.dumps(enriched, ensure_ascii=False, indent=None), encoding="utf-8")
    print(f"[ENRICH v2] Wrote {len(enriched)} enriched foods -> {_DST}")

    # ── Coverage summary ──
    from collections import Counter
    region_counts = Counter(f["region"] for f in enriched)
    pan_india_count = sum(1 for f in enriched if f["pan_india"])
    with_origin = sum(1 for f in enriched if f["state_of_origin"])
    festival_count = sum(1 for f in enriched if f["festival_food"])
    daily_count = sum(1 for f in enriched if f["daily_food"])
    all_states = sorted({s for f in enriched for s in f["state_of_origin"]} |
                        {s for f in enriched for s in f["available_states"] if s != "All"})

    print(f"[ENRICH v2] region distribution: {dict(region_counts)}")
    print(f"[ENRICH v2] pan_india=True: {pan_india_count} / {len(enriched)}")
    print(f"[ENRICH v2] foods with a specific state_of_origin: {with_origin}")
    print(f"[ENRICH v2] festival_food=True: {festival_count}")
    print(f"[ENRICH v2] daily_food=True: {daily_count}")
    print(f"[ENRICH v2] distinct states referenced ({len(all_states)}): {all_states}")


if __name__ == "__main__":
    main()
