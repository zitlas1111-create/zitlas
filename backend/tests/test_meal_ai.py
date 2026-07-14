"""
ZITLAS — Meal AI nutrition estimation route tests (backend/tests/test_meal_ai.py)

Exercises the REAL routes/meal_ai.py with services.gemini_service.analyze_image
mocked out (no real Gemini call) — mirrors the auth-override pattern from
test_coaching.py. Builds a minimal FastAPI app with just this router.
"""

from __future__ import annotations

import io
import json
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).parent.parent))

from routes import meal_ai  # noqa: E402
from services import gemini_service  # noqa: E402

ATHLETE_UID = "athlete_1"


@pytest.fixture
def app():
    a = FastAPI()
    a.include_router(meal_ai.router, prefix="/api/meal")
    a.dependency_overrides[meal_ai.verify_firebase_token] = lambda: {"uid": ATHLETE_UID, "email": None, "name": "Test"}
    return a


@pytest.fixture
def client(app):
    return TestClient(app)


def _fake_image_file():
    return {"file": ("meal.jpg", io.BytesIO(b"\xff\xd8\xff\xe0fakejpeg"), "image/jpeg")}


def test_estimate_nutrition_happy_path(app, client, monkeypatch):
    async def fake_analyze_image(image_bytes, mime_type, prompt, max_tokens=1500):
        return {"reply": json.dumps({
            "food_recognition": ["chapati", "paneer bhurji"],
            "calories": 450, "protein": 28, "carbs": 40, "fat": 18,
            "confidence_score": 82,
        }), "model": "gemini-2.5-flash"}

    monkeypatch.setattr(gemini_service, "analyze_image", fake_analyze_image)

    r = client.post("/api/meal/estimate-nutrition", files=_fake_image_file())
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["success"] is True
    assert body["estimatedCalories"] == 450
    assert body["estimatedProtein"] == 28
    assert body["confidenceScore"] == 82
    assert body["foodRecognition"] == ["chapati", "paneer bhurji"]


def test_estimate_nutrition_unparseable_response_is_502(app, client, monkeypatch):
    async def fake_analyze_image(image_bytes, mime_type, prompt, max_tokens=1500):
        return {"reply": "not json at all", "model": "gemini-2.5-flash"}

    monkeypatch.setattr(gemini_service, "analyze_image", fake_analyze_image)

    r = client.post("/api/meal/estimate-nutrition", files=_fake_image_file())
    assert r.status_code == 502
    assert r.json()["detail"] == "nutrition_estimation_unreadable"


def test_estimate_nutrition_gemini_failure_is_502_not_bare(app, client, monkeypatch):
    async def fake_analyze_image(image_bytes, mime_type, prompt, max_tokens=1500):
        raise RuntimeError("upstream quota exceeded")

    monkeypatch.setattr(gemini_service, "analyze_image", fake_analyze_image)

    r = client.post("/api/meal/estimate-nutrition", files=_fake_image_file())
    assert r.status_code == 502
    assert "upstream quota exceeded" in r.json()["detail"]


def test_estimate_nutrition_rejects_bad_content_type(app, client):
    r = client.post("/api/meal/estimate-nutrition",
                     files={"file": ("meal.txt", io.BytesIO(b"not an image"), "text/plain")})
    assert r.status_code == 400


def test_estimate_nutrition_unauthenticated_rejected(app, client):
    app.dependency_overrides.pop(meal_ai.verify_firebase_token, None)
    r = client.post("/api/meal/estimate-nutrition", files=_fake_image_file())
    assert r.status_code == 401
