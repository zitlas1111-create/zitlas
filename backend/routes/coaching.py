"""
ZITLAS — Personal Coaching escrow: reserve / accept / reject
(backend/routes/coaching.py)

Replaces the old flow (request -> expert accepts -> athlete manually pays)
with an Uber/Airbnb-style reserve-then-auto-debit escrow: the athlete's
wallet balance is reserved (locked, not spent) the instant a request is
sent; if the expert accepts, the reservation auto-debits and coaching
activates atomically with no manual payment step; if the expert declines,
or 48 hours pass with no response (services/coaching_sweep.py), the
reservation auto-releases.

This is the first feature in this backend with real Firestore Admin access
and real Firebase-ID-token auth (see services/firestore_service.py,
services/auth_service.py) — every prior route is deliberately
Firestore-free client-authenticated compute. That changes here on purpose:
"is there enough balance / is this the right price / does this reservation
belong to this caller" can only be enforced server-side, where the frontend
cannot spoof the check.

Data model:
  users/{uid}.wallet gains `reserved` (number, default 0). `available` is
  ALWAYS computed as balance - reserved, never stored, so it can't drift.
  Reserving increases `reserved` only. Accepting debits both `balance` and
  `reserved` together (net available is unchanged — the money already left
  `available` at reserve time). Rejecting/expiring decreases `reserved`
  only (balance untouched).

  personal_coach_requests/{requestId} (existing collection, extended) gains
  reservationAmount, reservedAt, expiresAt, and paymentStatus
  ('reserved'|'debited'|'released'|'released_expired').

Recovery: every balance/status mutation here happens inside ONE Firestore
transaction (@firestore.transactional) — a process crash mid-request can
only leave the transaction fully committed or fully rolled back, never a
half-reserved/half-released state. That atomicity guarantee is the entire
"recovery system" this feature needs; there is no separate recovery code,
and there shouldn't be one.
"""

from __future__ import annotations

import time
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel

from services import firestore_service
from services.auth_service import verify_firebase_token
from services.coaching_service import (
    PLATFORM_FEE_PERCENT,
    RESERVATION_HOURS,
    notify,
    now,
    release_reservation_txn,
)

router = APIRouter()

PLAN_TO_FIELD = {
    "diet": "coachingDietPrice",
    "training": "coachingTrainingPrice",
    "complete": "coachingCompletePrice",
}
# Mirrors frontend/pages/coaches/cprofile.js PRICING_DEFAULTS (coaching subset) —
# experts who haven't opened Pricing & Services yet still get these.
PRICING_DEFAULTS = {"diet": 499, "training": 699, "complete": 999}
PLAN_LABELS = {
    "diet": "Diet Coaching",
    "training": "Training Coaching",
    "complete": "Complete Transformation",
}


def _db() -> firestore.Client:
    db = firestore_service.get_client()
    if db is None:
        # Fail closed — unlike push notifications, a coaching request that
        # "succeeds" without actually reserving money would be a real
        # financial bug, not a degraded-but-harmless feature.
        raise HTTPException(status_code=503, detail="coaching_service_unavailable")
    return db


class RequestBody(BaseModel):
    expertId: str
    planType: str


class ActionBody(BaseModel):
    requestId: str


@router.post("/request")
async def create_request(body: RequestBody, caller: dict = Depends(verify_firebase_token)):
    if body.planType not in PLAN_TO_FIELD:
        raise HTTPException(status_code=400, detail="invalid_plan_type")

    db = _db()
    athlete_uid = caller["uid"]
    expert_ref = db.collection("experts").document(body.expertId)
    user_ref = db.collection("users").document(athlete_uid)
    request_id = "PCR_" + str(int(time.time() * 1000))
    request_ref = db.collection("personal_coach_requests").document(request_id)
    coach_requests = db.collection("personal_coach_requests")

    @firestore.transactional
    def _txn(tx):
        expert_snap = expert_ref.get(transaction=tx)
        if not expert_snap.exists:
            raise HTTPException(status_code=404, detail="expert_not_found")
        expert_data = expert_snap.to_dict() or {}
        expert_name = expert_data.get("name") or "Expert"
        pricing = expert_data.get("pricing") or {}
        amount = int(pricing.get(PLAN_TO_FIELD[body.planType]) or PRICING_DEFAULTS[body.planType])

        # Duplicate-request / double-spend guard: at most one open
        # (pending) reservation per athlete, platform-wide, at a time.
        open_query = coach_requests.where(filter=FieldFilter("athleteId", "==", athlete_uid)) \
                                    .where(filter=FieldFilter("status", "==", "pending"))
        if list(tx.get(open_query)):
            raise HTTPException(status_code=409, detail="open_request_exists")

        user_snap = user_ref.get(transaction=tx)
        user_data = user_snap.to_dict() if user_snap.exists else {}
        wallet = dict((user_data or {}).get("wallet") or {})
        balance = float(wallet.get("balance", 0) or 0)
        reserved = float(wallet.get("reserved", 0) or 0)
        available = balance - reserved
        if available < amount:
            raise HTTPException(status_code=402, detail={
                "error": "insufficient_balance", "available": available, "required": amount,
            })

        _now = now()
        expires = _now + timedelta(hours=RESERVATION_HOURS)

        wallet["reserved"] = reserved + amount
        tx.set(user_ref, {"wallet": wallet}, merge=True)

        athlete_name = (user_data or {}).get("name") or caller.get("name") or "Athlete"
        tx.set(request_ref, {
            "requestId": request_id,
            "athleteId": athlete_uid, "athleteName": athlete_name,
            "expertId": body.expertId, "expertName": expert_name,
            "planType": body.planType, "planLabel": PLAN_LABELS[body.planType],
            "price": amount,
            "status": "pending",
            "createdAt": _now.isoformat(),
            "reservationAmount": amount,
            "reservedAt": _now.isoformat(),
            "expiresAt": expires.isoformat(),
            "paymentStatus": "reserved",
        })
        return {"requestId": request_id, "amount": amount, "expiresAt": expires.isoformat()}

    result = _txn(db.transaction())

    notify(db, athlete_uid, "Request Sent",
           "Your coaching request has been sent. Payment has been securely reserved. "
           "You will only be charged if the expert accepts.",
           category="expert", type="coaching_requested", action="coaches")

    return {"success": True, **result}


@router.post("/accept")
async def accept_request(body: ActionBody, caller: dict = Depends(verify_firebase_token)):
    db = _db()
    expert_uid = caller["uid"]
    request_ref = db.collection("personal_coach_requests").document(body.requestId)
    wallet_txn_id = "txn_" + str(int(time.time() * 1000)) + "_srv"

    @firestore.transactional
    def _txn(tx):
        req_snap = request_ref.get(transaction=tx)
        if not req_snap.exists:
            raise HTTPException(status_code=404, detail="request_not_found")
        req = req_snap.to_dict()
        if req.get("expertId") != expert_uid:
            raise HTTPException(status_code=403, detail="not_your_request")
        if req.get("status") != "pending":
            # Idempotent retry (double-click / dropped response) — not an error.
            if req.get("paymentStatus") == "debited":
                return {"already": True, "athleteId": req.get("athleteId"), "amount": req.get("reservationAmount")}
            raise HTTPException(status_code=409, detail="not_pending")

        athlete_uid = req["athleteId"]
        amount = float(req.get("reservationAmount") or req.get("price") or 0)
        user_ref = db.collection("users").document(athlete_uid)
        rel_ref = db.collection("personal_coaching").document(athlete_uid)

        user_snap = user_ref.get(transaction=tx)
        user_data = user_snap.to_dict() if user_snap.exists else {}
        wallet = dict((user_data or {}).get("wallet") or {})
        balance = float(wallet.get("balance", 0) or 0)
        reserved = float(wallet.get("reserved", 0) or 0)

        rel_snap = rel_ref.get(transaction=tx)
        existing_rel = rel_snap.to_dict() if rel_snap.exists else None
        if existing_rel and existing_rel.get("status") == "active" and existing_rel.get("coachId") != expert_uid:
            raise HTTPException(status_code=409, detail="athlete_has_other_active_coach")

        fee = round(amount * PLATFORM_FEE_PERCENT)
        expert_amount = amount - fee
        _now = now()

        wallet["balance"] = balance - amount
        wallet["reserved"] = max(0.0, reserved - amount)
        wallet["total_spent"] = float(wallet.get("total_spent", 0) or 0) + amount
        transactions = list(wallet.get("transactions", []))
        transactions.append({
            "id": wallet_txn_id, "type": "debit", "amount": amount,
            "description": req.get("planLabel") or "Personal Coaching",
            "date": _now.isoformat(),
        })
        wallet["transactions"] = transactions
        tx.set(user_ref, {"wallet": wallet}, merge=True)

        tx.set(db.collection("wallet_transactions").document(wallet_txn_id), {
            "transactionId": wallet_txn_id, "serviceType": "coaching",
            "expertId": expert_uid, "userId": athlete_uid, "amount": amount,
            "walletBefore": balance, "walletAfter": wallet["balance"],
            "grossAmount": amount, "platformFee": fee, "expertAmount": expert_amount,
            "status": "success", "createdAt": _now.isoformat(),
        })

        tx.update(request_ref, {
            "status": "active", "paymentStatus": "debited",
            "acceptedAt": _now.isoformat(), "activatedAt": _now.isoformat(),
            "walletTransactionId": wallet_txn_id,
        })

        end_date = _now + timedelta(days=30)
        tx.set(rel_ref, {
            "coachId": expert_uid, "coachName": req.get("expertName"),
            "athleteId": athlete_uid, "athleteName": req.get("athleteName"),
            "planType": req.get("planType"), "planLabel": req.get("planLabel"),
            "startDate": _now.isoformat(), "endDate": end_date.isoformat(),
            "status": "active", "subscriptionId": "sub_" + str(int(_now.timestamp() * 1000)),
            "paymentId": wallet_txn_id, "fee": amount, "requestId": body.requestId,
        })

        return {"already": False, "athleteId": athlete_uid, "amount": amount}

    result = _txn(db.transaction())

    if not result.get("already"):
        req = (request_ref.get().to_dict() or {})
        amount = result["amount"]
        notify(db, result["athleteId"], "Congratulations!",
               f"Your coaching request has been accepted. ₹{int(amount)} has been "
               "automatically deducted. Your coaching starts now.",
               category="expert", type="coaching_accepted", action="expert_profile",
               action_id=expert_uid, priority="high")
        notify(db, expert_uid, "Payment received",
               (req.get("athleteName") or "An athlete") + " just started coaching with you.",
               category="expert", type="coaching_started", action="expert_dashboard")

    return {"success": True, "requestId": body.requestId, **result}


@router.post("/reject")
async def reject_request(body: ActionBody, caller: dict = Depends(verify_firebase_token)):
    db = _db()
    expert_uid = caller["uid"]
    request_ref = db.collection("personal_coach_requests").document(body.requestId)

    @firestore.transactional
    def _txn(tx):
        req_snap = request_ref.get(transaction=tx)
        if not req_snap.exists:
            raise HTTPException(status_code=404, detail="request_not_found")
        req = req_snap.to_dict()
        if req.get("expertId") != expert_uid:
            raise HTTPException(status_code=403, detail="not_your_request")
        if req.get("status") != "pending":
            if req.get("paymentStatus") == "released":
                return {"already": True, "athleteId": req.get("athleteId")}
            raise HTTPException(status_code=409, detail="not_pending")

        athlete_uid = release_reservation_txn(tx, db, request_ref, req,
                                               "declined", "released", "declinedAt")
        return {"already": False, "athleteId": athlete_uid}

    result = _txn(db.transaction())

    if not result.get("already"):
        notify(db, result["athleteId"], "Request declined",
               "Unfortunately your request was declined. Your reserved amount has been released.",
               category="expert", type="coaching_declined", action="coaches")

    return {"success": True, "requestId": body.requestId, **result}
