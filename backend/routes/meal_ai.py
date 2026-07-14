"""
ZITLAS — AI meal nutrition estimation (backend/routes/meal_ai.py)

POST /api/meal/estimate-nutrition — estimates calories/protein/carbs/fat
and recognized foods from a meal photo, using the same Gemini vision path
already proven for certificate verification (services/gemini_service.py's
analyze_image(), services/certificate_verification.py's prompt/JSON-parsing
pattern, copied here). Populates fields the meal_checkins Firestore schema
already reserves for this purpose (estimatedCalories/Protein/Carbs/Fat,
foodRecognition, confidenceScore — frontend/pages/diet/diet.js ~2057-2059)
that were "never populated" before this route existed. Also used by the
standalone AI-only "Snap Meal" flow (no coach involved), same endpoint.

Firebase-auth-gated (unlike chat.py's plain upload) since this is a real
AI-cost-incurring call that shouldn't be open to anonymous abuse — caller
identity isn't otherwise used here (no wallet/reservation involved, this is
a compute call, not a money one).
"""

from __future__ import annotations

import json
import re

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from services import gemini_service
from services.auth_service import verify_firebase_token

router = APIRouter()

_ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
_MAX_BYTES = 10 * 1024 * 1024  # 10 MB

NUTRITION_PROMPT = """You are a nutrition estimation AI for ZITLAS, a fitness coaching platform. You are examining a photo of a meal an athlete just ate or is about to eat.

STEP 1 — RECOGNIZE the foods visible in the image. List each distinct food/dish you can identify.

STEP 2 — ESTIMATE the nutrition for the ENTIRE plate/meal shown (the whole visible portion, not per 100g):
- calories (kcal, integer)
- protein (grams, integer)
- carbs (grams, integer)
- fat (grams, integer)

Be a careful visual estimator: account for portion size, cooking method (fried vs steamed/grilled), and visible ingredients (oil, sauces, cheese, dressing). If the image does not clearly show food, or you cannot make a reasonable estimate, set confidence_score low but still return your best-effort numeric estimates (never null/omitted).

Respond with ONLY this JSON object, no other text:
{
  "food_recognition": ["food or dish name", "..."],
  "calories": integer,
  "protein": integer,
  "carbs": integer,
  "fat": integer,
  "confidence_score": 0-100
}"""


def _extract_json(text: str) -> dict | None:
    try:
        return json.loads(text.strip())
    except (json.JSONDecodeError, ValueError):
        pass
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group())
        except (json.JSONDecodeError, ValueError):
            pass
    return None


@router.post("/estimate-nutrition")
async def estimate_nutrition(
    file: UploadFile = File(...),
    caller: dict = Depends(verify_firebase_token),
) -> dict:
    print(f"[MEAL AI] request — uid={caller['uid']} filename={file.filename!r} type={file.content_type!r}")

    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail="Only jpg, jpeg, png, and webp images are accepted.")

    content = await file.read()
    print(f"[MEAL AI] size={len(content):,} bytes")
    if len(content) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="Image too large (max 10 MB).")

    try:
        result = await gemini_service.analyze_image(content, file.content_type, NUTRITION_PROMPT)
    except Exception as e:
        print(f"[MEAL AI] Gemini call failed: {type(e).__name__}: {e}")
        raise HTTPException(status_code=502, detail=f"nutrition_estimation_failed: {type(e).__name__}: {e}")

    parsed = _extract_json(result["reply"])
    if not parsed:
        print(f"[MEAL AI] unparseable response: {result['reply'][:300]!r}")
        raise HTTPException(status_code=502, detail="nutrition_estimation_unreadable")

    estimate = {
        "success": True,
        "estimatedCalories": int(parsed.get("calories") or 0),
        "estimatedProtein": int(parsed.get("protein") or 0),
        "estimatedCarbs": int(parsed.get("carbs") or 0),
        "estimatedFat": int(parsed.get("fat") or 0),
        "foodRecognition": parsed.get("food_recognition") or [],
        "confidenceScore": max(0, min(100, int(parsed.get("confidence_score") or 0))),
    }
    print(f"[MEAL AI] estimate — cal={estimate['estimatedCalories']} "
          f"protein={estimate['estimatedProtein']} confidence={estimate['confidenceScore']}")
    return estimate
