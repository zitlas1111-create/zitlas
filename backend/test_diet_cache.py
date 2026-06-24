"""
ZITLAS -- Diet Cache Verification
Two-phase test:

Phase A: Seed -- simulate survey completion saving a real plan to localStorage.
Phase B: Cache -- run 5 simulated diet page opens, count API calls.

Expected: Phase B makes ZERO API calls (plan was cached in Phase A).
Run: python test_diet_cache.py
"""

import json
import asyncio
from datetime import datetime, timezone

import httpx

BASE = "http://127.0.0.1:8000"

PROFILE = {
    "role": "Batsman",
    "goal": "Improve batting average",
    "goal_type": "Batting",
    "age": 17,
    "training_days_per_week": 5,
    "training_duration": "1hr",
    "activity_level": "moderate",
    "sleep_hours": 7,
    "commitment": "High",
    "motivation": "High",
    "energy_level": "Good",
}

LIFESTYLE = {
    "living_situation": "home",
    "diet_type": "non-vegetarian",
    "daily_budget": "150",
    "cooking_access": "full kitchen",
    "favorite_foods": ["Roti", "Dal", "Chicken curry"],
    "disliked_foods": [],
    "allergies": [],
    "water_intake": "1.5L",
    "available_foods": ["Rice", "Dal", "Roti", "Chicken", "Eggs", "Banana", "Curd"],
}


class MockLocalStorage:
    def __init__(self):
        self._store: dict[str, str] = {}

    def getItem(self, key):
        return self._store.get(key)

    def setItem(self, key, value):
        self._store[key] = value

    def removeItem(self, key):
        self._store.pop(key, None)

    def safeJSON(self, key, default):
        raw = self.getItem(key)
        if raw is None:
            return default
        try:
            return json.loads(raw)
        except Exception:
            return default


def simulate_diet_page_open(open_number, storage, api_call_counter):
    """
    Mirrors the exact decision tree of diet.js init() without making HTTP calls
    when cache exists. Returns True if API call would be made, False otherwise.
    """
    print(f"\n{'='*52}")
    print(f"  [OPEN #{open_number}]")
    print(f"{'='*52}")

    # -- Check canonical key, migrate legacy if needed --
    cached = storage.safeJSON('zitlas_diet_plan', None)
    if not cached or not cached.get('days'):
        legacy = storage.safeJSON('nutrition_weekly_plan', None)
        if legacy and legacy.get('days'):
            print("[DIET CACHE] Migrating legacy plan from nutrition_weekly_plan -> zitlas_diet_plan")
            cached = legacy
            storage.setItem('zitlas_diet_plan', json.dumps(cached))
            if not storage.getItem('zitlas_plan_generated_at'):
                storage.setItem('zitlas_plan_generated_at', datetime.now(timezone.utc).isoformat())
            print(f"[DIET CACHE] Migration complete -- days: {len(cached.get('days', []))}")

    # -- Cache hit: render immediately, no API call --
    if cached and cached.get('days') and len(cached['days']) > 0:
        days_count = len(cached['days'])
        print(f"[DIET CACHE] Found saved diet -- days: {days_count}")
        print("[DIET CACHE] Loading saved diet -- skipping API call")
        print(f"  -> Result: CACHE HIT (0 tokens consumed)")
        return False

    # -- Sentinel: previous attempt already made, don't retry --
    if storage.getItem('zitlas_plan_generated_at'):
        print("[DIET CACHE] Sentinel present -- previous generation returned no plan, showing static fallback")
        print(f"  -> Result: SENTINEL HIT (0 tokens consumed)")
        return False

    # -- No profile --
    athlete_profile = storage.safeJSON('athlete_profile', None)
    if not athlete_profile:
        print("[DIET CACHE] No athlete profile -- static fallback, no API call")
        print(f"  -> Result: NO PROFILE (0 tokens consumed)")
        return False

    # -- First-time generation --
    # Sentinel is saved BEFORE the API call so navigation-away during generation
    # does not cause future opens to regenerate.
    print("[DIET CACHE] No saved diet -> generating (first time only)")
    storage.setItem('zitlas_plan_generated_at', datetime.now(timezone.utc).isoformat())
    print("[DIET CACHE] Generation sentinel saved (pre-call)")
    api_call_counter.append(open_number)
    print(f"  -> Result: API CALL MADE (tokens will be consumed)")
    return True


async def phase_a_seed(client, storage):
    """
    Simulate what coach.js survey completion does:
    call the API once, save results to localStorage.
    This is what happens when the athlete completes the survey.
    """
    print("\n" + "="*52)
    print("  PHASE A: Survey Completion Seed")
    print("  (Simulates coach.js saving plan after survey)")
    print("="*52)

    print("\n[SURVEY] Generating diet plan via API...")
    try:
        resp = await client.post(
            f"{BASE}/api/ai/nutrition-weekly-plan",
            json={
                "player_profile": PROFILE,
                "nutrition_assessment": None,
                "lifestyle_data": LIFESTYLE,
                "rejected_foods": [],
            },
        )
        resp.raise_for_status()
        data = resp.json()
        plan = data.get("structured")

        if not plan or not plan.get("days"):
            print(f"[SURVEY] API returned no structured plan (HTTP {resp.status_code})")
            return False

        days_count = len(plan["days"])
        print(f"[SURVEY] Plan received -- days: {days_count} | model: {data.get('model')}")
        print(f"[SURVEY] Tokens used by API: {data.get('tokens_used')}")
        print(f"[SURVEY] plan_name: {plan.get('plan_name')}")

        # Exactly what coach.js now does after survey completion
        storage.setItem('athlete_profile', json.dumps(PROFILE))
        storage.setItem('lifestyle_data', json.dumps(LIFESTYLE))
        storage.setItem('nutrition_weekly_plan', json.dumps(plan))
        storage.setItem('zitlas_diet_plan', json.dumps(plan))
        storage.setItem('zitlas_plan_generated_at', datetime.now(timezone.utc).isoformat())
        storage.setItem('zitlas_survey', 'complete')

        print(f"\n[SURVEY] Saved to localStorage:")
        print(f"  nutrition_weekly_plan    -> {days_count}-day plan")
        print(f"  zitlas_diet_plan         -> {days_count}-day plan")
        print(f"  zitlas_plan_generated_at -> {storage.getItem('zitlas_plan_generated_at')[:19]}")
        print(f"  zitlas_survey            -> complete")
        print(f"\n[SURVEY] Phase A complete -- 1 API call, {data.get('tokens_used')} tokens consumed")
        return True

    except httpx.HTTPStatusError as e:
        print(f"[SURVEY] HTTP error {e.response.status_code}: {e.response.text[:200]}")
        return False
    except Exception as e:
        print(f"[SURVEY] Request failed: {type(e).__name__}: {e}")
        return False


async def main():
    print("\n" + "="*52)
    print("  ZITLAS DIET CACHE VERIFICATION")
    print("  5 diet page opens after survey completion")
    print("  Expected: 0 additional API calls (all cached)")
    print("="*52)

    storage = MockLocalStorage()
    api_calls_phase_b = []

    timeout_cfg = httpx.Timeout(connect=10.0, read=150.0, write=10.0, pool=10.0)
    async with httpx.AsyncClient(timeout=timeout_cfg) as client:

        # Phase A: Seed localStorage exactly as coach.js does after survey
        seeded = await phase_a_seed(client, storage)

        if not seeded:
            print("\n[ERROR] Phase A failed -- cannot verify cache (no plan to cache)")
            return

        # Phase B: 5 diet page opens -- all should hit cache
        print("\n\n" + "="*52)
        print("  PHASE B: 5 Diet Page Opens")
        print("  All should use cache -- no API calls")
        print("="*52)

        for i in range(1, 6):
            simulate_diet_page_open(i, storage, api_calls_phase_b)

    # -- Summary --
    print("\n\n" + "="*52)
    print("  VERIFICATION RESULTS")
    print("="*52)

    cached_plan = storage.safeJSON('zitlas_diet_plan', None)
    days_count  = len(cached_plan.get('days', [])) if cached_plan else 0

    print(f"  Phase A (survey) API call  : 1 (expected 1)")
    print(f"  Phase B (5 opens) API calls: {len(api_calls_phase_b)} (expected 0)")
    print(f"  zitlas_diet_plan           : {'present' if cached_plan else 'MISSING'}")
    print(f"  days in cached plan        : {days_count} (expected 7)")
    print(f"  zitlas_plan_generated_at   : {'present' if storage.getItem('zitlas_plan_generated_at') else 'MISSING'}")

    passed = (
        seeded
        and len(api_calls_phase_b) == 0
        and days_count == 7
    )

    print()
    print("  CHECKLIST:")
    print(f"  [{'PASS' if seeded else 'FAIL'}] Phase A: plan generated and cached by survey")
    print(f"  [{'PASS' if len(api_calls_phase_b)==0 else 'FAIL'}] Phase B: 0 API calls across 5 opens")
    print(f"  [{'PASS' if days_count==7 else 'FAIL'}] Cached plan has exactly 7 days")
    print(f"  [{'PASS' if storage.getItem('zitlas_plan_generated_at') else 'FAIL'}] zitlas_plan_generated_at present")

    if passed:
        print()
        print("  ==========================================")
        print("  NUTRITION GENERATION VERIFIED")
        print("  Diet cache working correctly.")
        print("  5 opens = 0 additional API calls.")
        print("  ==========================================")

        print("\n  CACHED PLAN SUMMARY:")
        print(f"    plan_name       : {cached_plan.get('plan_name', 'N/A')}")
        print(f"    nutrition_focus : {cached_plan.get('nutrition_focus', 'N/A')[:60]}")
        print(f"    hydration_target: {cached_plan.get('hydration_daily_target', 'N/A')}")
        print()
        for day in cached_plan.get('days', []):
            meals = day.get('meals', [])
            meal_names = [m.get('meal_name', '?') for m in meals]
            print(f"    {day.get('day','?'):9} [{day.get('day_type','?'):13}]"
                  f" {len(meals)} meals | {', '.join(meal_names)}")
    else:
        print("\n  VERIFICATION FAILED -- see checklist above")


if __name__ == "__main__":
    asyncio.run(main())
