"""
ZITLAS — System Routes

GET  /api/system/kb-status   — Knowledge base lazy-loading cache status
GET  /api/system/trial-mode  — Whether CLIENT_TRIAL_MODE is on (coach payments free)
POST /api/system/test-push   — Send a test web-push notification to a token
"""

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services.kb_manager import kb_manager
from services import push_service
from trial_config import CLIENT_TRIAL_MODE

router = APIRouter()


@router.get("/trial-mode")
async def trial_mode() -> dict[str, bool]:
    """
    Single source of truth for the temporary client trial
    (backend/trial_config.py). The frontend payment layer
    (assets/js/payment-service.js) reads this at page load; when true,
    every coach-related charge is granted free while Premium and wallet
    recharge stay live.
    """
    return {"clientTrialMode": CLIENT_TRIAL_MODE}


@router.get("/kb-status")
async def kb_status() -> dict[str, Any]:
    """
    Knowledge base cache status.

    Shows which per-goal FAISS indexes are currently held in RAM,
    how many chunks each contains, and the LRU cache limit.

    Response shape:
        {
            "loaded_kbs":      ["weight_loss", "general_fitness"],
            "cache_size":      2,
            "memory_optimized": true
        }

    loaded_kbs is empty at startup; it grows as users trigger goal-specific
    requests.  Old entries are evicted (LRU) when cache_size would exceed
    the configured maximum.
    """
    stats = kb_manager.get_cache_stats()
    return {
        "loaded_kbs":      stats["loaded_kbs"],
        "cache_size":      stats["cache_size"],
        "memory_optimized": True,
    }


class TestPushRequest(BaseModel):
    token: str = Field(..., min_length=20, description="FCM device token (frontend: localStorage zitlas_push_token)")
    title: str = Field(default="ZITLAS test notification")
    body:  str = Field(default="If you can read this, web push works end to end. 🎉")


@router.post("/test-push")
async def test_push(req: TestPushRequest) -> dict[str, Any]:
    """
    End-to-end push verification: sends one real FCM message to one device
    token. Requires FIREBASE_SERVICE_ACCOUNT_JSON (or _FILE) in the
    environment — returns 503 with setup instructions until it's configured,
    so the endpoint is safe to ship before the credential exists.
    """
    if not push_service.is_configured():
        raise HTTPException(
            status_code=503,
            detail="Push sending is not configured. Set FIREBASE_SERVICE_ACCOUNT_JSON "
                   "(Firebase console -> Project settings -> Service accounts -> "
                   "Generate new private key) in the backend environment.",
        )
    result = push_service.send_to_token(req.token, req.title, req.body,
                                        data={"category": "system", "type": "test"})
    if not result.get("ok"):
        raise HTTPException(status_code=502, detail=result.get("detail"))
    return {"success": True, "detail": result.get("detail")}
