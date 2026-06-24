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

router = APIRouter()


@router.get("/health")
async def diet_health():
    return {"module": "diet", "status": "ready"}
