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
import traceback
from datetime import datetime, timedelta

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
from trial_config import CLIENT_TRIAL_MODE, PLATFORM_CHARGES_FREE

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
    """Fail closed — unlike push notifications, a coaching request that
    "succeeds" without actually reserving money would be a real financial
    bug, not a degraded-but-harmless feature. Never returns a bare 503: the
    response body always carries the actual reason from
    firestore_service.config_error() (missing env var, bad credential JSON,
    client-construction failure, etc.) or the exact exception if
    get_client() itself raised unexpectedly."""
    try:
        db = firestore_service.get_client()
    except Exception as e:
        print(f"[COACHING] firestore_service.get_client() raised unexpectedly: {type(e).__name__}: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=503,
                             detail=f"coaching_service_unavailable: {type(e).__name__}: {e}")
    if db is None:
        reason = firestore_service.config_error() or "unknown — get_client() returned None with no recorded error"
        print(f"[COACHING] Firestore client unavailable — {reason}")
        raise HTTPException(status_code=503, detail=f"coaching_service_unavailable: {reason}")
    return db


def _age_from_dob(dob) -> int | None:
    """Whole years from a `YYYY-MM-DD` date of birth, or None if unusable."""
    if not dob:
        return None
    try:
        born = datetime.fromisoformat(str(dob)[:10])
    except (ValueError, TypeError):
        return None
    today = now()
    age = today.year - born.year - ((today.month, today.day) < (born.month, born.day))
    return age if 0 < age < 130 else None


def _athlete_profile_summary(user_data: dict | None) -> dict:
    """The minimum an expert needs to judge a coaching request.

    Deliberately NOT the whole user document. An expert deciding on a pending
    request is not yet this athlete's coach, so they get name, photo, goal and
    the body metrics relevant to programming — not email, phone, address,
    wallet or assessment history.

    BMI is computed here from real height/weight rather than read from
    `calculations`: that block is only refreshed when the athlete re-runs the
    Assessment, so it can be months out of date, while height/weight are edited
    directly in Personal Info. Every value is None when the athlete hasn't
    provided it — never a placeholder, because an expert acting on an invented
    weight is worse than one who can see the field is blank.
    """
    data = user_data or {}
    info = data.get("personalInfo") or {}
    survey = data.get("survey") or {}
    goal = data.get("goal") or {}

    def _num(*values):
        for v in values:
            if isinstance(v, (int, float)) and v > 0:
                return float(v)
        return None

    height_cm = _num(info.get("heightCm"), survey.get("height_cm"))
    weight_kg = _num(info.get("weightKg"), survey.get("weight_kg"))

    bmi = None
    if height_cm and weight_kg and 50 < height_cm < 260:
        bmi = round(weight_kg / ((height_cm / 100) ** 2), 1)

    return {
        "photo": info.get("photo") or data.get("photo"),
        "gender": info.get("gender"),
        "age": _age_from_dob(info.get("dob")),
        "heightCm": height_cm,
        "weightKg": weight_kg,
        "bmi": bmi,
        "goalType": goal.get("type"),
    }


class RequestBody(BaseModel):
    expertId: str
    planType: str


class ActionBody(BaseModel):
    requestId: str


@router.post("/request")
async def create_request(body: RequestBody, caller: dict = Depends(verify_firebase_token)):
    print(f"[COACHING REQUEST] [1] request received — expertId={body.expertId} planType={body.planType}")

    if body.planType not in PLAN_TO_FIELD:
        print(f"[COACHING REQUEST] rejected — invalid planType={body.planType!r}")
        raise HTTPException(status_code=400, detail="invalid_plan_type")

    athlete_uid = caller["uid"]
    print(f"[COACHING REQUEST] [2] authentication passed — uid={athlete_uid}")

    # _db() logs its own reason and raises a 503 with that reason attached —
    # never a bare "Service Unavailable" (see _db()'s docstring).
    db = _db()
    print("[COACHING REQUEST] Firestore client acquired")

    expert_ref = db.collection("experts").document(body.expertId)
    user_ref = db.collection("users").document(athlete_uid)
    request_id = "PCR_" + str(int(time.time() * 1000))
    request_ref = db.collection("personal_coach_requests").document(request_id)
    coach_requests = db.collection("personal_coach_requests")

    @firestore.transactional
    def _txn(tx):
        print(f"[COACHING REQUEST] [5] Firestore transaction started — requestId={request_id}")

        expert_snap = expert_ref.get(transaction=tx)
        if not expert_snap.exists:
            print(f"[COACHING REQUEST] expert not found — expertId={body.expertId}")
            raise HTTPException(status_code=404, detail="expert_not_found")
        expert_data = expert_snap.to_dict() or {}
        expert_name = expert_data.get("name") or "Expert"
        pricing = expert_data.get("pricing") or {}
        amount = int(pricing.get(PLAN_TO_FIELD[body.planType]) or PRICING_DEFAULTS[body.planType])
        print(f"[COACHING REQUEST] [4] expert loaded — expertId={body.expertId} "
              f"name={expert_name!r} planType={body.planType} amount={amount}")

        # PLATFORM_CHARGES_FREE (permanent monetization policy) or
        # CLIENT_TRIAL_MODE (temporary trial) — both from backend/
        # trial_config.py: coaching is free; the only paid feature in
        # ZITLAS is the Premium subscription. Zeroing the amount HERE lets
        # the entire existing escrow run unchanged — ₹0 is reserved, the
        # wallet check (available < 0) can never fail, and /accept later
        # debits the stored reservationAmount of ₹0. Flip both flags off
        # and real pricing is live again with no other change.
        if CLIENT_TRIAL_MODE or PLATFORM_CHARGES_FREE:
            print(f"[COACHING REQUEST] free-platform policy active — amount {amount} -> 0")
            amount = 0

        # Duplicate-request / double-spend guard: at most one open
        # (pending) reservation per athlete, platform-wide, at a time.
        open_query = coach_requests.where(filter=FieldFilter("athleteId", "==", athlete_uid)) \
                                    .where(filter=FieldFilter("status", "==", "pending"))
        existing = list(tx.get(open_query))
        if existing:
            print(f"[COACHING REQUEST] blocked — athlete already has an open request "
                  f"({[d.id for d in existing]})")
            raise HTTPException(status_code=409, detail="open_request_exists")

        # Active-relationship guard: an athlete already mid-subscription
        # can't reserve money for (and thus double-book) a second coach.
        # Checks endDateTs, not just status=='active' — a relationship
        # whose 30 days have passed but hasn't been swept yet (the sweep
        # runs every 15 min, see services/coaching_sweep.py) must NOT block
        # renewal; the athlete shouldn't have to wait on the sweep.
        rel_snap = db.collection("personal_coaching").document(athlete_uid).get(transaction=tx)
        if rel_snap.exists:
            rel_data = rel_snap.to_dict() or {}
            rel_end = rel_data.get("endDateTs")
            still_active = rel_data.get("status") == "active" and rel_end is not None and rel_end > now()
            if still_active:
                print(f"[COACHING REQUEST] blocked — athlete already has an active "
                      f"coaching relationship with coachId={rel_data.get('coachId')}")
                raise HTTPException(status_code=409, detail="active_coaching_exists")

        user_snap = user_ref.get(transaction=tx)
        user_data = user_snap.to_dict() if user_snap.exists else {}
        wallet = dict((user_data or {}).get("wallet") or {})
        balance = float(wallet.get("balance", 0) or 0)
        reserved = float(wallet.get("reserved", 0) or 0)
        available = balance - reserved
        print(f"[COACHING REQUEST] [3] wallet loaded — uid={athlete_uid} "
              f"userDocExists={user_snap.exists} balance={balance} reserved={reserved} "
              f"available={available} required={amount}")

        if available < amount:
            print(f"[COACHING REQUEST] insufficient balance — available={available} required={amount}")
            raise HTTPException(status_code=402, detail={
                "error": "insufficient_balance", "available": available, "required": amount,
            })

        _now = now()
        expires = _now + timedelta(hours=RESERVATION_HOURS)

        wallet["reserved"] = reserved + amount
        tx.set(user_ref, {"wallet": wallet}, merge=True)

        athlete_name = (user_data or {}).get("name") or caller.get("name") or "Athlete"
        # PREMIUM: priority flag for the expert's queue (premium requests
        # pin to the top). Read server-side from the athlete's user doc —
        # never client-supplied. Deliberately does NOT change `amount`:
        # Premium waives PLATFORM charges only; the coaching price is the
        # expert's own professional fee and stays fully payable.
        _membership = (user_data or {}).get("membership") or {}
        _expiry = _membership.get("premium_expiry_date")
        _not_expired = True
        if _expiry:
            try:
                _exp_dt = datetime.fromisoformat(str(_expiry).replace("Z", "+00:00"))
                _not_expired = _exp_dt > now()
            except (ValueError, TypeError):
                _not_expired = True  # unparseable expiry — don't strip priority
        is_premium = (_membership.get("plan") == "premium"
                      and _membership.get("active") is not False
                      and _not_expired)
        tx.set(request_ref, {
            "requestId": request_id,
            "athleteId": athlete_uid, "athleteName": athlete_name,
            "expertId": body.expertId, "expertName": expert_name,
            "planType": body.planType, "planLabel": PLAN_LABELS[body.planType],
            "price": amount,
            "status": "pending",
            "isPremium": is_premium,
            "createdAt": _now.isoformat(),
            "updatedAt": _now.isoformat(),
            "reservationAmount": amount,
            "reservedAt": _now.isoformat(),
            "expiresAt": expires.isoformat(),
            "paymentStatus": "reserved",
            # Snapshot of the athlete an expert needs to judge the request.
            #
            # Copied server-side ON PURPOSE rather than read live by the
            # expert's client: Security Rules only let an expert read
            # users/{athleteId} once they are the ACTIVE coach
            # (isActiveCoachOf), and that is exactly right — a pending request
            # must not hand an expert read access to the athlete's whole
            # profile. So the backend, which does have Admin access, copies
            # the few fields the decision actually needs and nothing else.
            # It is a point-in-time snapshot by design: it records what was
            # true when the request was made.
            "athleteProfile": _athlete_profile_summary(user_data),
        })
        print(f"[COACHING REQUEST] [6] reservation created — requestId={request_id} "
              f"amount={amount} newReserved={wallet['reserved']} expiresAt={expires.isoformat()}")
        return {"requestId": request_id, "amount": amount, "expiresAt": expires.isoformat(),
                "athleteName": athlete_name}

    try:
        result = _txn(db.transaction())
    except HTTPException:
        raise
    except Exception as e:
        # Anything NOT already an intentional HTTPException (400/402/404/409
        # above) is unexpected — surface the exact exception, never a bare
        # 503/500, and log the full traceback so Render's logs show the
        # real cause without needing to reproduce it.
        print(f"[COACHING REQUEST] UNEXPECTED transaction failure — uid={athlete_uid} "
              f"expertId={body.expertId}: {type(e).__name__}: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500,
                             detail=f"coaching_request_failed: {type(e).__name__}: {e}")

    try:
        notify(db, athlete_uid, "Request Sent",
               "Your coaching request has been sent. Payment has been securely reserved. "
               "You will only be charged if the expert accepts.",
               category="expert", type="coaching_requested", action="coaches")
        # The EXPERT is the one who has to act, and until now only the athlete
        # was told anything — the expert learned about a request solely by
        # happening to have their dashboard open. Sent after the transaction
        # commits, so a notification can never advertise a request that rolled
        # back.
        notify(db, body.expertId, "New Personal Coaching Request",
               f"{result['athleteName']} has requested you as a Personal Coach.",
               category="expert", type="coaching_request_received",
               action="expert_dashboard", priority="high")
    except Exception:
        # Notification failure must never fail a reservation that already
        # committed — log it and move on.
        print(f"[COACHING REQUEST] notification write failed (non-fatal) — requestId={result['requestId']}")
        print(traceback.format_exc())

    print(f"[COACHING REQUEST] [7] response returned — requestId={result['requestId']} success=True")
    return {"success": True, **result}


@router.post("/accept")
async def accept_request(body: ActionBody, caller: dict = Depends(verify_firebase_token)):
    print(f"[COACHING ACCEPT] request received — requestId={body.requestId} callerUid={caller['uid']}")
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
            "updatedAt": _now.isoformat(),
            "walletTransactionId": wallet_txn_id,
        })

        end_date = _now + timedelta(days=30)
        tx.set(rel_ref, {
            "coachId": expert_uid, "coachName": req.get("expertName"),
            "athleteId": athlete_uid, "athleteName": req.get("athleteName"),
            "planType": req.get("planType"), "planLabel": req.get("planLabel"),
            "startDate": _now.isoformat(), "endDate": end_date.isoformat(),
            # endDateTs is a NATIVE Firestore Timestamp (the raw datetime
            # object, not .isoformat()) — Firestore Security Rules'
            # request.time is a Timestamp and can't be compared against the
            # string endDate above. endDate stays for JS `new Date(...)`
            # parsing (coaching-gate.js and friends); endDateTs exists
            # purely for rules and this sweep's own query to compare against.
            "endDateTs": end_date,
            "status": "active", "subscriptionId": "sub_" + str(int(_now.timestamp() * 1000)),
            "paymentId": wallet_txn_id, "fee": amount, "requestId": body.requestId,
        })

        return {"already": False, "athleteId": athlete_uid, "amount": amount}

    try:
        result = _txn(db.transaction())
    except HTTPException:
        raise
    except Exception as e:
        print(f"[COACHING ACCEPT] UNEXPECTED transaction failure — expertUid={expert_uid} "
              f"requestId={body.requestId}: {type(e).__name__}: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500,
                             detail=f"coaching_accept_failed: {type(e).__name__}: {e}")

    if not result.get("already"):
        try:
            req = (request_ref.get().to_dict() or {})
            amount = result["amount"]
            _paid_msg = (f"Your coaching request has been accepted. ₹{int(amount)} has been "
                         "automatically deducted. Your coaching starts now.")
            _free_msg = "Your coaching request has been accepted. Your coaching starts now."
            notify(db, result["athleteId"], "Congratulations!",
                   _paid_msg if amount and int(amount) > 0 else _free_msg,
                   category="expert", type="coaching_accepted", action="expert_profile",
                   action_id=expert_uid, priority="high")
            notify(db, expert_uid, "Payment received",
                   (req.get("athleteName") or "An athlete") + " just started coaching with you.",
                   category="expert", type="coaching_started", action="expert_dashboard")
        except Exception:
            print(f"[COACHING ACCEPT] notification write failed (non-fatal) — requestId={body.requestId}")
            print(traceback.format_exc())

    return {"success": True, "requestId": body.requestId, **result}


@router.post("/withdraw")
async def withdraw_request(body: ActionBody, caller: dict = Depends(verify_firebase_token)):
    """Athlete-initiated cancellation of their OWN pending request — the
    mirror of /reject (expert-initiated), reusing the exact same
    release_reservation_txn() so the reserved amount is released back to
    `available` identically either way. Only the caller identity check
    differs: /reject requires expertId == caller, this requires
    athleteId == caller. A request that already left 'pending' (accepted,
    declined, expired, or already withdrawn) cannot be withdrawn — the
    money has either moved or already been released."""
    print(f"[COACHING WITHDRAW] request received — requestId={body.requestId} callerUid={caller['uid']}")
    db = _db()
    athlete_uid = caller["uid"]
    request_ref = db.collection("personal_coach_requests").document(body.requestId)

    @firestore.transactional
    def _txn(tx):
        req_snap = request_ref.get(transaction=tx)
        if not req_snap.exists:
            raise HTTPException(status_code=404, detail="request_not_found")
        req = req_snap.to_dict()
        if req.get("athleteId") != athlete_uid:
            raise HTTPException(status_code=403, detail="not_your_request")
        if req.get("status") != "pending":
            if req.get("status") == "withdrawn":
                return {"already": True, "expertId": req.get("expertId")}
            raise HTTPException(status_code=409, detail="not_pending")

        release_reservation_txn(tx, db, request_ref, req, "withdrawn", "released", "withdrawnAt")
        return {"already": False, "expertId": req.get("expertId"), "expertName": req.get("expertName")}

    try:
        result = _txn(db.transaction())
    except HTTPException:
        raise
    except Exception as e:
        print(f"[COACHING WITHDRAW] UNEXPECTED transaction failure — athleteUid={athlete_uid} "
              f"requestId={body.requestId}: {type(e).__name__}: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500,
                             detail=f"coaching_withdraw_failed: {type(e).__name__}: {e}")

    if not result.get("already") and result.get("expertId"):
        try:
            athlete_name = caller.get("name") or "An athlete"
            notify(db, result["expertId"], "Request withdrawn",
                   f"{athlete_name} withdrew their coaching request before you responded.",
                   category="expert", type="coaching_withdrawn", action="expert_dashboard")
        except Exception:
            print(f"[COACHING WITHDRAW] notification write failed (non-fatal) — requestId={body.requestId}")
            print(traceback.format_exc())

    print(f"[COACHING WITHDRAW] success — requestId={body.requestId} athleteUid={athlete_uid}")
    return {"success": True, "requestId": body.requestId, **result}


@router.post("/reject")
async def reject_request(body: ActionBody, caller: dict = Depends(verify_firebase_token)):
    print(f"[COACHING REJECT] request received — requestId={body.requestId} callerUid={caller['uid']}")
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

    try:
        result = _txn(db.transaction())
    except HTTPException:
        raise
    except Exception as e:
        print(f"[COACHING REJECT] UNEXPECTED transaction failure — expertUid={expert_uid} "
              f"requestId={body.requestId}: {type(e).__name__}: {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500,
                             detail=f"coaching_reject_failed: {type(e).__name__}: {e}")

    if not result.get("already"):
        try:
            notify(db, result["athleteId"], "Request declined",
                   "Unfortunately your request was declined. Your reserved amount has been released.",
                   category="expert", type="coaching_declined", action="coaches")
        except Exception:
            print(f"[COACHING REJECT] notification write failed (non-fatal) — requestId={body.requestId}")
            print(traceback.format_exc())

    return {"success": True, "requestId": body.requestId, **result}
