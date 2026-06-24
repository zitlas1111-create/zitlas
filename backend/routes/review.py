"""
ZITLAS — Review Request Routes

POST   /api/review/submit                — Athlete submits diet plan for expert review
GET    /api/review/{request_id}          — Get review request by ID
GET    /api/review/expert/{expert_id}    — Get all requests for an expert
PATCH  /api/review/{request_id}/status  — Expert updates status (start review)
POST   /api/review/{request_id}/approve — Expert approves plan (with optional edits)
"""

from datetime import datetime, timezone
from typing import Any, Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

# In-memory store (matches localStorage-first architecture)
_store: dict[str, dict] = {}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


# ── Pydantic models ──────────────────────────────────────────────────────────

class ReviewSubmitRequest(BaseModel):
    id:           str
    athleteId:    Optional[str] = None
    athlete_name: Optional[str] = "Athlete"
    expertId:     str
    status:       Optional[str] = "pending"
    submittedAt:  Optional[str] = None
    context:      Optional[Any] = None   # {assessment, calculations, swot, diet_plan, workout_plan}
    goal:         Optional[Any] = None
    planId:       Optional[str] = None
    fee:          Optional[int] = None
    note:         Optional[str] = None


class StatusUpdate(BaseModel):
    status:    str
    expertId:  Optional[str] = None


class ApproveRequest(BaseModel):
    expertId:        str
    expertName:      str
    status:          str = "approved"   # "approved" | "revised_plan_published"
    expertNotes:     Optional[str] = None
    updatedDietPlan: Optional[Any] = None
    approvedAt:      Optional[str] = None


# ── Routes ───────────────────────────────────────────────────────────────────

@router.post("/submit")
async def submit_review(body: ReviewSubmitRequest):
    """Athlete submits their AI diet plan for expert review."""
    req = body.dict()
    req["submittedAt"] = req.get("submittedAt") or _now()
    req["status"]      = "pending"
    _store[body.id]    = req
    return {
        "success":   True,
        "requestId": body.id,
        "status":    "pending",
    }


@router.get("/expert/{expert_id}")
async def get_expert_reviews(expert_id: str):
    """Get all review requests assigned to a specific expert."""
    requests = [
        r for r in _store.values()
        if r.get("expertId") == expert_id
    ]
    requests.sort(key=lambda r: r.get("submittedAt", ""), reverse=True)
    return {"success": True, "expertId": expert_id, "requests": requests, "count": len(requests)}


@router.get("/{request_id}")
async def get_review(request_id: str):
    """Get a single review request by ID."""
    req = _store.get(request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Review request not found.")
    return req


@router.patch("/{request_id}/status")
async def update_status(request_id: str, body: StatusUpdate):
    """Expert updates review status (e.g. pending → expert_reviewing)."""
    req = _store.get(request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Review request not found.")
    req["status"]    = body.status
    req["updatedAt"] = _now()
    if body.expertId:
        req["expertId"] = body.expertId
    return {"success": True, "requestId": request_id, "status": body.status}


@router.post("/{request_id}/approve")
async def approve_review(request_id: str, body: ApproveRequest):
    """Expert approves the diet plan, optionally with modifications."""
    req = _store.get(request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Review request not found.")

    req["status"]      = body.status
    req["expertId"]    = body.expertId
    req["expertName"]  = body.expertName
    req["expertNotes"] = body.expertNotes
    req["approvedAt"]  = body.approvedAt or _now()
    req["updatedAt"]   = _now()
    if body.updatedDietPlan:
        req["updatedDietPlan"] = body.updatedDietPlan

    return {
        "success":   True,
        "requestId": request_id,
        "status":    body.status,
        "message":   f"Plan {body.status} by {body.expertName}",
    }
