"""Quick test for offline_fallback 7-day unique meals and oats rejection."""
from services import offline_fallback

plan = offline_fallback.nutrition_weekly_plan(
    player_profile={"role": "batsman", "goal": "Improve batting", "age": 16},
    lifestyle_data={
        "living_situation": "hostel",
        "diet_type": "vegetarian",
        "daily_budget": "Rs 100",
        "favorite_foods": ["Poha", "Idli", "Paneer"],
        "disliked_foods": ["Oats"],
        "allergies": [],
    },
    rejected_foods=["Oats"],
)

print("Plan name:", plan["plan_name"])
print()
breakfasts = []
for day in plan["days"]:
    bf = ", ".join(day["meals"][0]["foods"])
    print(f"{day['day']:<10} | {day['theme']:<35} | Breakfast: {bf}")
    breakfasts.append(bf)

unique_bfs = len(set(breakfasts))
all_foods  = [f for d in plan["days"] for m in d["meals"] for f in m["foods"]]
oats_found = any("oat" in f.lower() for f in all_foods)

print()
print(f"Unique breakfast sets : {unique_bfs}/7 (should be 7)")
print(f"Oats appear in plan  : {oats_found} (should be False)")
