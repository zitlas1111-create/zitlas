"""
ZITLAS — Personal Coaching 48h expiry sweep (backend/services/coaching_sweep.py)

Runs periodically (in-process APScheduler job, wired in main.py's lifespan)
to release reservations for requests the expert never responded to within
48 hours. Not an HTTP route — called directly by the scheduler, so it must
never raise on a routine "not configured" condition (mirrors push_service's
no-op-when-unconfigured pattern, unlike routes/coaching.py's HTTP routes,
which fail closed with a 503 since a client is actively waiting on those).

Each expired request is released in its OWN transaction that re-checks
status == 'pending' fresh — if the expert accepted or rejected in the same
window the sweep is scanning, that request is simply skipped (already
handled, no-op), so there's no race between a human decision and the sweep.
"""

from __future__ import annotations

from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from services import firestore_service
from services.coaching_service import notify, now, release_reservation_txn


def _release_one(db, request_ref):
    @firestore.transactional
    def _txn(tx):
        req_snap = request_ref.get(transaction=tx)
        if not req_snap.exists:
            return None
        req = req_snap.to_dict()
        if req.get("status") != "pending":
            return None  # already accepted/rejected/expired by something else
        return release_reservation_txn(tx, db, request_ref, req, "expired",
                                        "released_expired", "expiredAt"), req

    result = _txn(db.transaction())
    if result is None:
        return
    athlete_uid, req = result
    notify(db, athlete_uid, "Request expired",
           (req.get("expertName") or "The expert") + " didn't respond in time. "
           "Your reserved amount has been released.",
           category="expert", type="coaching_expired", action="coaches")


def sweep_expired_requests() -> int:
    """Returns the number of requests released. Safe to call even when
    Firestore isn't configured (logs and returns 0, same as push's no-op)."""
    db = firestore_service.get_client()
    if db is None:
        print("[COACHING SWEEP] skipped — Firestore not configured")
        return 0

    now_iso = now().isoformat()
    query = db.collection("personal_coach_requests") \
              .where(filter=FieldFilter("status", "==", "pending")) \
              .where(filter=FieldFilter("expiresAt", "<=", now_iso))

    released = 0
    for doc in query.stream():
        try:
            _release_one(db, doc.reference)
            released += 1
        except Exception as e:
            print(f"[COACHING SWEEP] failed to release {doc.id}: {type(e).__name__}: {e}")

    if released:
        print(f"[COACHING SWEEP] released {released} expired reservation(s)")
    return released
