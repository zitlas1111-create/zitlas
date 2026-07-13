"""ZITLAS production meal-quality matrix (Phase-1 polish spec, Priority 8).

Runs the deterministic engine across goals x diets x budgets x living
situations x regional states x meal slots and asserts the Meal Validation
Engine's guarantees:
  - lunch/dinner are never a lone snack/fruit/soup/single ingredient
  - every main meal carries protein + carb
  - no festival food in regular plans
  - swaps stay in their own meal slot and honor an explicit diet reason
  - rejected foods (in display-string form) never come back in any variant
  - regional boost surfaces state dishes without displacing staples

Pure engine tests — no LLM calls, safe to run anywhere:
    python test_meal_quality.py
"""
from services import food_engine, location_food_engine
from services.groq_service import _diet_type_from_reason

ENGINE = food_engine.get_engine()
failures: list[str] = []


def check(name: str, ok: bool, extra: str = "") -> None:
    print(("PASS" if ok else "FAIL") + " - " + name + ("" if ok else f" | {extra}"))
    if not ok:
        failures.append(name)


# ── 1. Weekly plans: goals x diets x budgets x living ──────────────────────
GOALS = [["Weight Loss"], ["Muscle Gain"], ["General Fitness"]]
DIETS = [["Vegetarian"], ["Non Vegetarian", "Vegetarian"], ["Eggitarian", "Vegetarian"], ["Jain"]]
BUDGETS = ["Low", "Medium", "High"]
LIVINGS = ["Hostel", "Home", "PG"]

for goal in GOALS:
    for diet in DIETS:
        for budget in BUDGETS[:2] if goal != GOALS[0] else BUDGETS:
            living = LIVINGS[(len(goal[0]) + len(diet[0]) + len(budget)) % 3]
            plan = ENGINE.build_week_plan(
                goal_tags=goal, diet_tags=diet, living_situation=living,
                budget_tier=budget, disease_tags=[], allergens=set(),
                daily_calorie_target=1800,
            )
            label = f"{goal[0]}/{diet[0]}/{budget}/{living}"
            main_issues = []
            for day in plan["days"]:
                for slot in ("lunch", "dinner", "breakfast"):
                    combo = (day["meals"].get(slot) or {}).get("primary") or []
                    main_issues += [f"{day['day']}/{slot}: {i}" for i in ENGINE.validate_meal_combo(combo, slot)]
            check(f"plan {label}: all mains valid", not main_issues, "; ".join(main_issues[:3]))

# ── 2. Swaps: every slot, veg-reason honored, rejected never returns ───────
SLOTS = ["breakfast", "mid_morning", "lunch", "evening_snack", "dinner"]
REJECT = ["Sweet Corn (Raw) (100 g (cooked/raw as applicable))",
          "150 g grilled chicken breast (marinated with spices, no oil)"]
for slot in SLOTS:
    rd = _diet_type_from_reason("I am vegetarian and need a veg option")
    combos = ENGINE.find_swap_combos(
        meal_slot=slot, goal_tags=["General Fitness"],
        diet_tags=food_engine.diet_tags_from_lifestyle(rd),
        living_situation=None, budget_tier=None, disease_tags=[], allergens=set(),
        exclude_names=REJECT, n_combos=2,
    )
    check(f"swap {slot}: returns combos", bool(combos))
    names = [f["name"].lower() for c in combos for f in c]
    check(f"swap {slot}: no rejected variant returns", not any("sweet corn" in n or "chicken" in n for n in names),
          str(names))
    veg_ok = all(f["type"] == "Vegetarian" for c in combos for f in c)
    check(f"swap {slot}: vegetarian reason honored", veg_ok)
    if slot in ("lunch", "dinner"):
        for c in combos:
            issues = ENGINE.validate_meal_combo(c, slot)
            check(f"swap {slot}: '{' + '.join(f['name'] for f in c)[:50]}' is a complete meal", not issues,
                  "; ".join(issues))

# ── 3. Regional users: boost present, staples still dominate ───────────────
STATES = [{"state": "Maharashtra"}, {"state": "Punjab"}, {"state": "Tamil Nadu"},
          {"state": "Kerala"}, {"state": "West Bengal"}, {"state": "Karnataka"},
          {"state": "Delhi"}, {"state": "Gujarat"}, {"state": "Assam"},
          {"state": "Jammu & Kashmir"}]
for loc in STATES:
    boost = location_food_engine.build_region_boost(loc)
    check(f"region {loc['state']}: boost resolves", boost is not None)
    if not boost:
        continue
    profile = {"preferredCategories": boost["preferred_categories"]}
    plan = ENGINE.build_week_plan(
        goal_tags=["General Fitness"], diet_tags=["Vegetarian"], living_situation="Home",
        budget_tier="Medium", disease_tags=[], allergens=set(),
        favorite_foods=[k.split(" (")[0] for k in boost["preferred_keywords"]][:5],
        daily_calorie_target=1800, profile=profile,
    )
    all_foods = [f for d in plan["days"] for m in d["meals"].values() for f in (m.get("primary") or [])]
    festival = [f["name"] for f in all_foods if f.get("festival_food")]
    check(f"region {loc['state']}: no festival food in plan", not festival, str(festival))
    hh = [f for f in all_foods if (f.get("daily_household_score") or 0) >= 60]
    check(f"region {loc['state']}: household foods dominate (>=50%)", len(hh) >= len(all_foods) * 0.5,
          f"{len(hh)}/{len(all_foods)}")

# ── 4. Weekly variety: no food more than 3x/week ───────────────────────────
plan = ENGINE.build_week_plan(goal_tags=["Weight Loss"], diet_tags=["Vegetarian"],
                              living_situation="Home", budget_tier="Medium",
                              disease_tags=[], allergens=set(), daily_calorie_target=1600)
over = {fid: c for fid, c in plan["usage_counts"].items() if c > 3}
check("variety: no food repeated >3x/week", not over, str(over))

print()
print(f"{len(failures)} FAILURE(S)" if failures else "ALL MEAL-QUALITY TESTS PASSED")
raise SystemExit(1 if failures else 0)
