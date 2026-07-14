"""
ZITLAS — Personal Coaching escrow route tests (backend/tests/test_coaching.py)

Exercises the REAL routes/coaching.py and services/coaching_sweep.py
against fake_firestore.py's in-process fake (see that file's docstring for
what it does and doesn't reproduce). Builds a minimal FastAPI app with just
the coaching router — not the full main.py — so this suite doesn't pull in
RAG/KB loading or any other unrelated startup cost.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from google.cloud import firestore

sys.path.insert(0, str(Path(__file__).parent.parent))

from routes import coaching  # noqa: E402
from services import coaching_sweep, firestore_service  # noqa: E402
from tests.fake_firestore import FakeClient, fake_transactional  # noqa: E402

ATHLETE_UID = "athlete_1"
EXPERT_UID = "expert_1"


@pytest.fixture
def fake_db(monkeypatch):
    client = FakeClient()
    monkeypatch.setattr(firestore_service, "get_client", lambda: client)
    monkeypatch.setattr(firestore, "transactional", fake_transactional)

    client.store["experts/expert_1"] = {
        "name": "Coach Test",
        "pricing": {"coachingDietPrice": 499, "coachingTrainingPrice": 699, "coachingCompletePrice": 999},
    }
    return client


@pytest.fixture
def app():
    a = FastAPI()
    a.include_router(coaching.router, prefix="/api/coaching")
    return a


@pytest.fixture
def client(app):
    return TestClient(app)


def _as(app, uid):
    """Make subsequent requests through `app` authenticate as `uid`."""
    app.dependency_overrides[coaching.verify_firebase_token] = lambda: {"uid": uid, "email": None, "name": "Test"}


def _set_wallet(fake_db, uid, balance=0, reserved=0):
    fake_db.store[f"users/{uid}"] = {"wallet": {"balance": balance, "reserved": reserved,
                                                 "total_added": balance, "total_spent": 0, "transactions": []}}


def test_happy_path_reserve_accept_activates(fake_db, app, client):
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)

    r = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["amount"] == 499
    request_id = body["requestId"]

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["balance"] == 1000, "reserving must not touch balance"
    assert wallet["reserved"] == 499

    req_doc = fake_db.store[f"personal_coach_requests/{request_id}"]
    assert req_doc["status"] == "pending"
    assert req_doc["paymentStatus"] == "reserved"

    # Relationship must NOT exist before acceptance.
    assert fake_db.store.get(f"personal_coaching/{ATHLETE_UID}") is None

    _as(app, EXPERT_UID)
    r = client.post("/api/coaching/accept", json={"requestId": request_id})
    assert r.status_code == 200, r.text

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["balance"] == 501, "balance - reserved amount"
    assert wallet["reserved"] == 0, "reservation fully released back on debit"

    req_doc = fake_db.store[f"personal_coach_requests/{request_id}"]
    assert req_doc["status"] == "active"
    assert req_doc["paymentStatus"] == "debited"

    rel = fake_db.store[f"personal_coaching/{ATHLETE_UID}"]
    assert rel["status"] == "active"
    assert rel["coachId"] == EXPERT_UID

    txn = fake_db.store[f"wallet_transactions/{req_doc['walletTransactionId']}"]
    assert txn["grossAmount"] == 499
    assert txn["platformFee"] == round(499 * 0.20)
    assert txn["expertAmount"] == 499 - round(499 * 0.20)

    notifs = [d for p, d in fake_db.store.items() if p.startswith("notifications/")]
    assert any(n["userId"] == ATHLETE_UID and n["type"] == "coaching_accepted" for n in notifs)
    assert any(n["userId"] == EXPERT_UID and n["type"] == "coaching_started" for n in notifs)


def test_insufficient_balance_blocks_reservation(fake_db, app, client):
    _set_wallet(fake_db, ATHLETE_UID, balance=100)
    _as(app, ATHLETE_UID)

    r = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"})
    assert r.status_code == 402
    detail = r.json()["detail"]
    assert detail["error"] == "insufficient_balance"
    assert detail["available"] == 100
    assert detail["required"] == 499

    created = [p for p in fake_db.store if p.startswith("personal_coach_requests/") and fake_db.store[p]]
    assert created == [], "no request doc should be created when the reservation is rejected"
    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["reserved"] == 0, "a rejected reservation must never touch reserved"


def test_reject_releases_reservation(fake_db, app, client):
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)
    request_id = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"}).json()["requestId"]

    _as(app, EXPERT_UID)
    r = client.post("/api/coaching/reject", json={"requestId": request_id})
    assert r.status_code == 200, r.text

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["balance"] == 1000, "balance untouched on reject"
    assert wallet["reserved"] == 0, "reservation released"

    req_doc = fake_db.store[f"personal_coach_requests/{request_id}"]
    assert req_doc["status"] == "declined"
    assert req_doc["paymentStatus"] == "released"
    assert fake_db.store.get(f"personal_coaching/{ATHLETE_UID}") is None

    notifs = [d for p, d in fake_db.store.items() if p.startswith("notifications/")]
    assert any(n["userId"] == ATHLETE_UID and n["type"] == "coaching_declined" for n in notifs)


def test_expiry_sweep_releases_reservation(fake_db, app, client, monkeypatch):
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)
    request_id = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"}).json()["requestId"]

    # Backdate expiresAt so the sweep picks it up without waiting 48h.
    fake_db.store[f"personal_coach_requests/{request_id}"]["expiresAt"] = "2000-01-01T00:00:00+00:00"

    released = coaching_sweep.sweep_expired_requests()
    assert released == 1

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["reserved"] == 0
    req_doc = fake_db.store[f"personal_coach_requests/{request_id}"]
    assert req_doc["status"] == "expired"
    assert req_doc["paymentStatus"] == "released_expired"

    # Running the sweep again must be a no-op (idempotent).
    assert coaching_sweep.sweep_expired_requests() == 0


def test_expiry_sweep_skips_already_accepted(fake_db, app, client):
    """A request the expert accepted in the same window the sweep is
    scanning must be left alone — no race between a human decision and the
    sweep (routes/coaching.py's docstring claims this; verify it)."""
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)
    request_id = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"}).json()["requestId"]

    _as(app, EXPERT_UID)
    client.post("/api/coaching/accept", json={"requestId": request_id})

    fake_db.store[f"personal_coach_requests/{request_id}"]["expiresAt"] = "2000-01-01T00:00:00+00:00"
    released = coaching_sweep.sweep_expired_requests()
    assert released == 0

    req_doc = fake_db.store[f"personal_coach_requests/{request_id}"]
    assert req_doc["status"] == "active", "sweep must not clobber an already-active request"


def test_duplicate_request_blocked(fake_db, app, client):
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)

    r1 = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"})
    assert r1.status_code == 200

    r2 = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "training"})
    assert r2.status_code == 409
    assert r2.json()["detail"] == "open_request_exists"

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["reserved"] == 499, "the second (rejected) attempt must not double-reserve"


def test_double_accept_is_idempotent_not_double_debit(fake_db, app, client):
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)
    request_id = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"}).json()["requestId"]

    _as(app, EXPERT_UID)
    r1 = client.post("/api/coaching/accept", json={"requestId": request_id})
    assert r1.status_code == 200
    r2 = client.post("/api/coaching/accept", json={"requestId": request_id})
    assert r2.status_code == 200
    assert r2.json()["already"] is True

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["balance"] == 501, "CRITICAL — must not be debited twice"


def test_expert_cannot_accept_someone_elses_request(fake_db, app, client):
    _set_wallet(fake_db, ATHLETE_UID, balance=1000)
    _as(app, ATHLETE_UID)
    request_id = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"}).json()["requestId"]

    _as(app, "some_other_expert")
    r = client.post("/api/coaching/accept", json={"requestId": request_id})
    assert r.status_code == 403

    wallet = fake_db.store[f"users/{ATHLETE_UID}"]["wallet"]
    assert wallet["reserved"] == 499, "an unauthorized accept attempt must not touch money"


def test_unauthenticated_request_rejected(app, client):
    app.dependency_overrides.pop(coaching.verify_firebase_token, None)
    r = client.post("/api/coaching/request", json={"expertId": EXPERT_UID, "planType": "diet"})
    assert r.status_code == 401
