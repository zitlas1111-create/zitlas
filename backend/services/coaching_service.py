"""
ZITLAS — Shared Personal Coaching escrow logic (backend/services/coaching_service.py)

Transaction/notification helpers shared between the reserve/accept/reject
HTTP routes (routes/coaching.py) and the 48h expiry sweep
(services/coaching_sweep.py) — kept here, not in routes/coaching.py, so the
background sweep (no FastAPI request context, runs from an APScheduler job)
never has to import from a routes module.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

# Mirrors frontend/assets/js/payment-service.js PLATFORM_FEE_PERCENT.
PLATFORM_FEE_PERCENT = 0.20
RESERVATION_HOURS = 48


def now() -> datetime:
    return datetime.now(timezone.utc)


def notify(db, user_id, title, message, *, category="expert", type=None,
           action=None, action_id=None, priority="medium"):
    """Mirrors frontend/assets/js/notification-center.js's send() doc shape
    exactly, so notifications.js renders these identically to client-sent ones."""
    if not user_id:
        return
    notif_id = "notif_" + uuid.uuid4().hex[:20]
    db.collection("notifications").document(notif_id).set({
        "notificationId": notif_id, "userId": user_id,
        "title": title, "message": message or "",
        "category": category, "icon": None, "type": type,
        "action": action, "actionId": action_id, "expertId": None,
        "isRead": False, "priority": priority,
        "createdAt": now().isoformat(),
    })


def release_reservation_txn(tx, db, request_ref, req: dict, new_status: str,
                             new_payment_status: str, ts_field: str) -> str:
    """Shared release logic for expert-reject (routes/coaching.py) and the
    48h expiry sweep (coaching_sweep.py) — both cases just differ in which
    terminal status/timestamp field to write. Caller must have already
    verified req['status'] == 'pending' inside the SAME transaction.
    Returns the athlete's uid (for the post-commit notification)."""
    athlete_uid = req["athleteId"]
    amount = float(req.get("reservationAmount") or req.get("price") or 0)
    user_ref = db.collection("users").document(athlete_uid)
    user_snap = user_ref.get(transaction=tx)
    user_data = user_snap.to_dict() if user_snap.exists else {}
    wallet = dict((user_data or {}).get("wallet") or {})
    reserved = float(wallet.get("reserved", 0) or 0)

    wallet["reserved"] = max(0.0, reserved - amount)
    tx.set(user_ref, {"wallet": wallet}, merge=True)

    update = {"status": new_status, "paymentStatus": new_payment_status}
    update[ts_field] = now().isoformat()
    tx.update(request_ref, update)
    return athlete_uid
