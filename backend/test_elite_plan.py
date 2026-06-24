"""
ZITLAS — Elite Weekly Plan Debug Test
======================================
Runs generate_elite_weekly_plan() for two contrasting players
and prints every debug step to the terminal.

Usage (from backend/ directory):
    python test_elite_plan.py

The backend server does NOT need to be running.
GROQ_API_KEY must be set in backend/.env
"""

import asyncio
import json
import sys
import os
from pathlib import Path

# Force UTF-8 output so Groq emoji responses don't crash on Windows cp1252
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Load .env so GROQ_API_KEY is available
from dotenv import load_dotenv
load_dotenv(Path(__file__).parent / ".env")

# Add backend/ to path so imports work
sys.path.insert(0, str(Path(__file__).parent))
from services import groq_service


# ══════════════════════════════════════════════════════════════════════════════
# PLAYER A — Batsman / Shot Selection / Footwork Against Spin
# ══════════════════════════════════════════════════════════════════════════════
PLAYER_A = {
    "role":                    "Batsman",
    "goal":                    "Improve Shot Selection",
    "improvements_wanted":     "Footwork Against Spin",
    "long_term_ambition":      "Represent district and state-level cricket",
    "age":                     19,
    "gender":                  "Male",
    "height":                  175,
    "weight":                  68,
    "training_days_per_week":  5,
    "training_duration":       "1hr",
    "activity_level":          "Moderate",
    "sleep_hours":             7,
    "tiredness_after_training":"Moderate",
    "injury_current":          "None",
    "injury_past":             "None",
    "motivation":              "High",
    "commitment":              "High",
    "fitness_pushups":         25,
    "fitness_squats":          30,
    "fitness_run_duration":    "20min",
    "energy_level":            "Good",
    "endurance_stamina":       "Moderate",
    "endurance_match":         "Can bat 20 overs comfortably",
    "timeline":                "3 months",
    "junk_food_frequency":     "2-3 times a week",
    "water_intake":            "2L",
    "food_type":               "Vegetarian",
    "supplements":             "None",
}

GOAL_A = {
    "type":          "Batting",
    "current_value": 32,
    "target_value":  50,
    "end_date":      "2026-09-01",
}


# ══════════════════════════════════════════════════════════════════════════════
# PLAYER B — Bowler / Yorker Execution / Death Over Accuracy
# ══════════════════════════════════════════════════════════════════════════════
PLAYER_B = {
    "role":                    "Bowler",
    "goal":                    "Improve Yorker Execution",
    "improvements_wanted":     "Death Over Accuracy",
    "long_term_ambition":      "Play state-level T20 cricket",
    "age":                     21,
    "gender":                  "Male",
    "height":                  182,
    "weight":                  78,
    "training_days_per_week":  4,
    "training_duration":       "2hr",
    "activity_level":          "High",
    "sleep_hours":             8,
    "tiredness_after_training":"Low",
    "injury_current":          "None",
    "injury_past":             "Shoulder strain (resolved 6 months ago)",
    "motivation":              "Very High",
    "commitment":              "Elite",
    "fitness_pushups":         40,
    "fitness_squats":          50,
    "fitness_run_duration":    "35min",
    "energy_level":            "Excellent",
    "endurance_stamina":       "High",
    "endurance_match":         "Can bowl full 20 overs across 2 spells",
    "timeline":                "2 months",
    "junk_food_frequency":     "Rarely",
    "water_intake":            "3L",
    "food_type":               "Non-Vegetarian",
    "supplements":             "Whey protein, creatine",
}

GOAL_B = {
    "type":          "Bowling",
    "current_value": 7.2,
    "target_value":  5.5,
    "end_date":      "2026-08-01",
}


# ══════════════════════════════════════════════════════════════════════════════
# TEST RUNNER
# ══════════════════════════════════════════════════════════════════════════════
async def run_player_test(label: str, player_profile: dict, goal: dict) -> None:
    banner = "#" * 70
    print(f"\n{banner}")
    print(f"  RUNNING TEST: {label}")
    print(f"{banner}\n")

    try:
        # This call will internally print Steps 1, 2, and 3 via debug prints
        result = await groq_service.generate_elite_weekly_plan(player_profile, goal)

        print("\n" + "=" * 70)
        print("PARSE STATUS")
        print("=" * 70)
        if result["structured"]:
            days_generated = len(result["structured"].get("days", []))
            print(f"  JSON parse:     SUCCESS")
            print(f"  Days generated: {days_generated}")
            print(f"  Tokens used:    {result['tokens_used']}")
            print(f"  Model:          {result['model']}")
        else:
            print("  JSON parse:     FAILED — response was not valid JSON")
            print("  (Check Step 3 output above for the raw Groq response)")
        print("=" * 70 + "\n")

    except Exception as exc:
        print(f"\n[ERROR] Test failed for {label}")
        print(f"  {type(exc).__name__}: {exc}\n")


async def main() -> None:
    print("\n" + "#" * 70)
    print("  ZITLAS — ELITE WEEKLY PLAN DEBUG TEST")
    print("  Two contrasting players. Compare prompts and responses.")
    print("#" * 70)

    await run_player_test(
        "PLAYER A — Batsman / Improve Shot Selection / Footwork Against Spin",
        PLAYER_A,
        GOAL_A,
    )

    print("\n\n" + "-" * 70)
    print("  PLAYER A COMPLETE. Starting Player B in 3 seconds…")
    print("-" * 70 + "\n")

    await asyncio.sleep(3)  # small gap so terminal output is readable

    await run_player_test(
        "PLAYER B — Bowler / Improve Yorker Execution / Death Over Accuracy",
        PLAYER_B,
        GOAL_B,
    )

    print("\n" + "#" * 70)
    print("  ALL TESTS COMPLETE")
    print("  Validation checklist:")
    print("  [PASS]  Both Step 1 blocks should show DIFFERENT role/goal/weakness")
    print("  [PASS]  Both Step 2 prompts should reference DIFFERENT profile values")
    print("  [PASS]  Both Step 3 responses should produce DIFFERENT drills/themes")
    print("  [FAIL]  If prompts or responses look the same -- personalisation is broken")
    print("#" * 70 + "\n")


if __name__ == "__main__":
    asyncio.run(main())
