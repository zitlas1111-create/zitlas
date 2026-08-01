"""
ZITLAS — Diet Routes

Future endpoints:
  GET    /api/diet/plan               Get current AI diet plan
  POST   /api/diet/generate           Generate new AI diet plan (GPT-4)
  GET    /api/diet/log                Get meal log history
  POST   /api/diet/log                Log a meal
  DELETE /api/diet/log/{id}           Delete a meal log entry
  GET    /api/diet/nutrition          Daily nutrition summary
  GET    /api/diet/recommendations    Sport-specific food recommendations
"""

from fastapi import APIRouter

from services import food_engine

router = APIRouter()


@router.get("/health")
async def diet_health():
    return {"module": "diet", "status": "ready"}


# ══════════════════════════════════════════════════════════════════════════════
# GET /api/diet/foods/search — food-database lookup for the expert's Swap Food
# ══════════════════════════════════════════════════════════════════════════════
#
# Backs the expert plan editor's "Swap" action. Reads the SAME 4,500-food
# dataset every generation/swap path already uses (services/food_engine.py), so
# an expert can only ever substitute a food the rest of the system knows how to
# score, and never invent one.
#
# Read-only and deterministic: no LLM, no writes.

@router.get("/foods/search")
async def search_foods(
    q: str = "",
    category: str | None = None,
    region: str | None = None,
    goal: str | None = None,
    diet: str | None = None,
    min_protein: float | None = None,
    max_calories: float | None = None,
    limit: int = 30,
) -> dict:
    """Search the food database by name/category, with optional nutrition and
    suitability filters.

    Every filter is ANDed and every one is optional, so an expert can start
    from a bare name search and narrow only if they need to.
    """
    engine = food_engine.get_engine()
    needle = (q or "").strip().lower()
    limit = max(1, min(limit, 100))

    results = []
    for food in engine.by_id.values():
        name = str(food.get("name", ""))
        if needle and needle not in name.lower():
            continue
        if category and food.get("category") != category:
            continue
        if region and food.get("region") != region:
            continue
        if goal and goal not in (food.get("goalSuitable") or []):
            continue
        if diet and diet not in (food.get("dietSuitable") or []):
            continue
        if min_protein is not None and (food.get("protein") or 0) < min_protein:
            continue
        if max_calories is not None and (food.get("calories") or 0) > max_calories:
            continue
        results.append(food)

    # Popularity first: an expert scanning a list wants the food an athlete is
    # actually likely to find and recognise at the top.
    results.sort(key=lambda f: -(f.get("popularity_score") or 0))

    return {
        "module": "food_search",
        "query": q,
        "count": len(results),
        "foods": [
            {
                "id": f.get("id"),
                "name": f.get("name"),
                "serving_size": f.get("serving_size"),
                "calories": f.get("calories"),
                "protein": f.get("protein"),
                "carbs": f.get("carbs"),
                "fat": f.get("fat"),
                "category": f.get("category"),
                "region": f.get("region"),
                "type": f.get("type"),
                # The exact display string the plans store, so the editor can
                # insert a food in the same shape the generator produces.
                "display": food_engine.format_food_line(f),
            }
            for f in results[:limit]
        ],
    }
