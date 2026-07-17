"""
ZITLAS — Razorpay Standard Checkout routes (backend/routes/payment.py)

POST /api/payment/create-order — creates a Razorpay order for the caller's
own wallet recharge amount and records it server-side
(razorpay_orders/{orderId}) so /verify has an authoritative amount to
credit later. The amount itself is trusted at CREATE time (it's the user's
own choice of how much to add to their own wallet, not a price being
enforced against them — unlike routes/coaching.py's plan pricing, there is
no "correct" amount here to protect against a manipulated client value).
What must never be trusted from the client is whether a payment actually
happened — that's what /verify's signature check establishes.

POST /api/payment/verify — verifies the HMAC-SHA256 signature Razorpay's
checkout returns and, ONLY on a match, credits the wallet inside a
Firestore transaction — reusing the exact wallet-mutation shape
established in routes/coaching.py (same wallet doc fields, same
wallet_transactions audit-log shape) so this new money-in path looks
identical to the wallet's other credit paths to any code that reads it
back (cloud-sync.js, wallet.js, etc.).
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore
from pydantic import BaseModel

from services import firestore_service, razorpay_service
from services.auth_service import verify_firebase_token

router = APIRouter()

# ── Premium Membership pricing (SERVER-authoritative — the client sends
#    only 'monthly'|'yearly'; the price can never be manipulated) ──
MEMBERSHIP_PRICES_RUPEES = {"monthly": 149, "yearly": 999}
MEMBERSHIP_DURATION_DAYS = {"monthly": 30, "yearly": 365}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _db() -> firestore.Client:
    db = firestore_service.get_client()
    if db is None:
        reason = firestore_service.config_error() or "unknown — get_client() returned None with no recorded error"
        print(f"[PAYMENT] Firestore client unavailable — {reason}")
        raise HTTPException(status_code=503, detail=f"payment_service_unavailable: {reason}")
    return db


class CreateOrderBody(BaseModel):
    amount: float  # rupees — matches every other price/amount field in this codebase (₹, not paise)


class VerifyBody(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class MembershipOrderBody(BaseModel):
    billing: str  # 'monthly' | 'yearly' — price resolved server-side


@router.post("/create-order")
async def create_order(body: CreateOrderBody, caller: dict = Depends(verify_firebase_token)):
    uid = caller["uid"]
    print(f"[PAYMENT CREATE-ORDER] uid={uid} amount=₹{body.amount}")

    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="invalid_amount")

    amount_paise = int(round(body.amount * 100))
    try:
        # Razorpay caps `receipt` at 40 chars. A Firebase uid alone is ~28,
        # so "wallet_<uid>_<ms-timestamp>" (~49) blew past that in
        # production (see Render logs — BAD_REQUEST_ERROR on every order).
        # The uid isn't needed here for correctness — razorpay_orders/{id}
        # already stores it — this is just a merchant-facing label, so a
        # short timestamp-only receipt is enough. "wallet_" + a 13-digit
        # ms timestamp is 20 chars, safely under the limit indefinitely.
        order = razorpay_service.create_order(
            amount_paise, receipt=f"wallet_{int(time.time() * 1000)}"
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    db = _db()
    db.collection("razorpay_orders").document(order["order_id"]).set({
        "orderId": order["order_id"], "uid": uid, "amountPaise": order["amount"],
        "currency": order["currency"], "status": "created", "createdAt": _now().isoformat(),
    })

    print(f"[PAYMENT CREATE-ORDER] order recorded — orderId={order['order_id']} amountPaise={order['amount']}")
    return {
        "order_id": order["order_id"], "amount": order["amount"],
        "currency": order["currency"], "key_id": order["key_id"],
    }


@router.post("/verify")
async def verify_payment(body: VerifyBody, caller: dict = Depends(verify_firebase_token)):
    uid = caller["uid"]
    print(f"[PAYMENT VERIFY] uid={uid} orderId={body.razorpay_order_id} paymentId={body.razorpay_payment_id}")

    if not razorpay_service.verify_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    ):
        print(f"[PAYMENT VERIFY] signature mismatch — orderId={body.razorpay_order_id} — wallet NOT credited")
        raise HTTPException(status_code=400, detail="signature_mismatch")

    db = _db()
    order_ref = db.collection("razorpay_orders").document(body.razorpay_order_id)
    user_ref = db.collection("users").document(uid)
    wallet_txn_id = "txn_" + body.razorpay_payment_id

    @firestore.transactional
    def _txn(tx):
        order_snap = order_ref.get(transaction=tx)
        if not order_snap.exists:
            raise HTTPException(status_code=404, detail="order_not_found")
        order = order_snap.to_dict()
        if order.get("uid") != uid:
            raise HTTPException(status_code=403, detail="not_your_order")
        if order.get("status") == "paid":
            # Idempotent retry (double-fire of the success handler, etc.) —
            # not an error, and must NOT credit a second time. Still returns
            # `balance` (the CURRENT one, unchanged) so the frontend's
            # response-shape assumption holds on every path, not just the
            # first-time-credited one.
            existing_wallet = (user_ref.get(transaction=tx).to_dict() or {}).get("wallet") or {}
            return {"already": True, "amount": order["amountPaise"] / 100.0,
                    "balance": float(existing_wallet.get("balance", 0) or 0)}

        amount_rupees = order["amountPaise"] / 100.0
        user_snap = user_ref.get(transaction=tx)
        user_data = user_snap.to_dict() if user_snap.exists else {}
        wallet = dict((user_data or {}).get("wallet") or {})
        balance_before = float(wallet.get("balance", 0) or 0)

        wallet["balance"] = balance_before + amount_rupees
        wallet["total_added"] = float(wallet.get("total_added", 0) or 0) + amount_rupees
        transactions = list(wallet.get("transactions", []))
        transactions.append({
            "id": wallet_txn_id, "type": "credit", "amount": amount_rupees,
            "description": "Added Funds via Razorpay", "date": _now().isoformat(),
        })
        wallet["transactions"] = transactions
        tx.set(user_ref, {"wallet": wallet}, merge=True)

        tx.set(db.collection("wallet_transactions").document(wallet_txn_id), {
            "transactionId": wallet_txn_id, "serviceType": "wallet_recharge", "userId": uid,
            "amount": amount_rupees, "walletBefore": balance_before, "walletAfter": wallet["balance"],
            "method": "razorpay", "razorpayOrderId": body.razorpay_order_id,
            "razorpayPaymentId": body.razorpay_payment_id, "status": "success",
            "createdAt": _now().isoformat(),
        })

        tx.update(order_ref, {
            "status": "paid", "razorpayPaymentId": body.razorpay_payment_id, "paidAt": _now().isoformat(),
        })
        return {"already": False, "amount": amount_rupees, "balance": wallet["balance"]}

    try:
        result = _txn(db.transaction())
    except HTTPException:
        raise
    except Exception as e:
        print(f"[PAYMENT VERIFY] unexpected failure — uid={uid} orderId={body.razorpay_order_id}: "
              f"{type(e).__name__}: {e}")
        raise HTTPException(status_code=500, detail=f"payment_credit_failed: {type(e).__name__}: {e}")

    print(f"[PAYMENT VERIFY] wallet credited — uid={uid} amount=₹{result['amount']} already={result.get('already')}")
    return {"success": True, **result}


# ══════════════════════════════════════════════════════════════════════
# PREMIUM MEMBERSHIP — the ONLY paid feature in ZITLAS
# (₹149/month or ₹999/year; every expert service is free platform-wide,
# see trial_config.PLATFORM_CHARGES_FREE). Same create→checkout→verify
# contract as the wallet flow above, with two hard rules:
#   1. The price is resolved SERVER-side from the billing period — the
#      client cannot choose an amount.
#   2. Premium activates ONLY inside /membership/verify, after the HMAC
#      signature check — never optimistically on the client.
# ══════════════════════════════════════════════════════════════════════

@router.post("/membership/create-order")
async def create_membership_order(body: MembershipOrderBody, caller: dict = Depends(verify_firebase_token)):
    uid = caller["uid"]
    billing = (body.billing or "").strip().lower()
    if billing not in MEMBERSHIP_PRICES_RUPEES:
        raise HTTPException(status_code=400, detail="invalid_billing_period")

    amount_rupees = MEMBERSHIP_PRICES_RUPEES[billing]
    amount_paise = amount_rupees * 100
    print(f"[MEMBERSHIP CREATE-ORDER] uid={uid} billing={billing} amount=₹{amount_rupees}")

    try:
        order = razorpay_service.create_order(
            amount_paise, receipt=f"premium_{int(time.time() * 1000)}"
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    db = _db()
    db.collection("razorpay_orders").document(order["order_id"]).set({
        "orderId": order["order_id"], "uid": uid, "amountPaise": order["amount"],
        "currency": order["currency"], "status": "created",
        "purpose": "membership", "billing": billing,
        "createdAt": _now().isoformat(),
    })

    print(f"[MEMBERSHIP CREATE-ORDER] order recorded — orderId={order['order_id']}")
    return {
        "order_id": order["order_id"], "amount": order["amount"],
        "currency": order["currency"], "key_id": order["key_id"],
        "billing": billing, "price_rupees": amount_rupees,
    }


@router.post("/membership/verify")
async def verify_membership_payment(body: VerifyBody, caller: dict = Depends(verify_firebase_token)):
    uid = caller["uid"]
    print(f"[MEMBERSHIP VERIFY] uid={uid} orderId={body.razorpay_order_id}")

    if not razorpay_service.verify_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    ):
        print(f"[MEMBERSHIP VERIFY] signature mismatch — orderId={body.razorpay_order_id} — premium NOT activated")
        raise HTTPException(status_code=400, detail="signature_mismatch")

    db = _db()
    order_ref = db.collection("razorpay_orders").document(body.razorpay_order_id)
    user_ref = db.collection("users").document(uid)
    txn_id = "txn_" + body.razorpay_payment_id

    @firestore.transactional
    def _txn(tx):
        order_snap = order_ref.get(transaction=tx)
        if not order_snap.exists:
            raise HTTPException(status_code=404, detail="order_not_found")
        order = order_snap.to_dict()
        if order.get("uid") != uid:
            raise HTTPException(status_code=403, detail="not_your_order")
        if order.get("purpose") != "membership":
            raise HTTPException(status_code=400, detail="not_a_membership_order")
        if order.get("status") == "paid":
            # Idempotent retry — return the membership already written.
            existing = (user_ref.get(transaction=tx).to_dict() or {}).get("membership") or {}
            return {"already": True, "membership": existing}

        billing = order.get("billing") or "monthly"
        start = _now()
        expiry = start + timedelta(days=MEMBERSHIP_DURATION_DAYS.get(billing, 30))
        membership = {
            "plan": "premium",
            "billing": billing,
            "premium_plan": billing,
            "active": True,
            "started_at": start.isoformat(),
            "premium_start_date": start.isoformat(),
            "premium_expiry_date": expiry.isoformat(),
            "payment_id": body.razorpay_payment_id,
            "order_id": body.razorpay_order_id,
            "payment_status": "paid",
        }
        tx.set(user_ref, {
            "membership": membership,
            "membershipUpdatedAt": start.isoformat(),
        }, merge=True)

        # Same audit-log collection every other payment writes to.
        tx.set(db.collection("wallet_transactions").document(txn_id), {
            "transactionId": txn_id, "serviceType": "premium_membership", "userId": uid,
            "amount": order["amountPaise"] / 100.0, "billing": billing,
            "method": "razorpay", "razorpayOrderId": body.razorpay_order_id,
            "razorpayPaymentId": body.razorpay_payment_id, "status": "success",
            "createdAt": start.isoformat(),
        })

        tx.update(order_ref, {
            "status": "paid", "razorpayPaymentId": body.razorpay_payment_id,
            "paidAt": start.isoformat(),
        })
        return {"already": False, "membership": membership}

    try:
        result = _txn(db.transaction())
    except HTTPException:
        raise
    except Exception as e:
        print(f"[MEMBERSHIP VERIFY] unexpected failure — uid={uid}: {type(e).__name__}: {e}")
        raise HTTPException(status_code=500, detail=f"membership_activation_failed: {type(e).__name__}: {e}")

    print(f"[MEMBERSHIP VERIFY] premium activated — uid={uid} already={result.get('already')}")
    return {"success": True, **result}
