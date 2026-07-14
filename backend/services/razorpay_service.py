"""
ZITLAS — Razorpay Standard Checkout integration (backend/services/razorpay_service.py)

Order creation (Razorpay Orders API) + payment-signature verification.
Uses raw HTTP (requests) with HTTP Basic Auth, not the `razorpay` PyPI
package — consistent with this backend's existing pattern for third-party
REST APIs (see services/push_service.py's FCM integration, which makes the
same deliberate choice over pulling in a heavier official SDK).

Credentials: RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET, read from the
environment (backend/.env, loaded by main.py's load_dotenv() before
anything else runs). KEY_SECRET never leaves this process — it's used only
to sign the Basic Auth header and to compute the HMAC below, never
returned to a caller.
"""

from __future__ import annotations

import hashlib
import hmac
import os

import requests

_ORDERS_URL = "https://api.razorpay.com/v1/orders"
_MIN_AMOUNT_PAISE = 100  # Razorpay's own minimum order amount


def _credentials() -> tuple[str, str] | None:
    key_id = os.getenv("RAZORPAY_KEY_ID")
    key_secret = os.getenv("RAZORPAY_KEY_SECRET")
    if not key_id or not key_secret:
        return None
    return key_id, key_secret


def is_configured() -> bool:
    return _credentials() is not None


def create_order(amount_paise: int, currency: str = "INR", receipt: str | None = None) -> dict:
    """
    Creates a Razorpay order. Returns {order_id, amount, currency, key_id}
    on success — key_id is included so the frontend never has to know it
    separately (still not the secret, safe to return).

    Raises ValueError for a sub-minimum amount (caller should turn this
    into a 400). Raises RuntimeError for a Razorpay API error or missing
    credentials (caller should turn this into 401/500 per which it is).
    """
    if amount_paise < _MIN_AMOUNT_PAISE:
        raise ValueError(f"amount must be >= {_MIN_AMOUNT_PAISE} paise (got {amount_paise})")

    creds = _credentials()
    if creds is None:
        raise RuntimeError("razorpay_not_configured: set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET in the environment")
    key_id, key_secret = creds

    payload = {"amount": int(amount_paise), "currency": currency}
    if receipt:
        payload["receipt"] = receipt

    print(f"[RAZORPAY] creating order — amount={amount_paise} currency={currency} receipt={receipt!r}")
    try:
        r = requests.post(_ORDERS_URL, json=payload, auth=(key_id, key_secret), timeout=15)
    except requests.RequestException as e:
        print(f"[RAZORPAY] order creation network error: {type(e).__name__}: {e}")
        raise RuntimeError(f"razorpay_network_error: {type(e).__name__}: {e}")

    if r.status_code == 401:
        print(f"[RAZORPAY] order creation auth failure ({r.status_code}): {r.text[:300]}")
        raise PermissionError(f"razorpay_auth_failed: {r.text[:300]}")
    if r.status_code >= 400:
        print(f"[RAZORPAY] order creation failed ({r.status_code}): {r.text[:300]}")
        raise RuntimeError(f"razorpay_api_error ({r.status_code}): {r.text[:300]}")

    data = r.json()
    print(f"[RAZORPAY] order created — id={data.get('id')} amount={data.get('amount')}")
    return {
        "order_id": data["id"],
        "amount": data["amount"],
        "currency": data["currency"],
        "key_id": key_id,
    }


def verify_signature(order_id: str, payment_id: str, signature: str) -> bool:
    """
    HMAC-SHA256(order_id + "|" + payment_id, KEY_SECRET), compared to
    `signature` in constant time (hmac.compare_digest — a plain `==` would
    leak timing information about how many leading bytes matched).
    Returns False (never raises) if credentials aren't configured — a
    verification that can't run must never be treated as a pass.
    """
    creds = _credentials()
    if creds is None:
        print("[RAZORPAY] verify_signature called but credentials not configured — failing closed")
        return False
    _, key_secret = creds

    expected = hmac.new(
        key_secret.encode("utf-8"),
        f"{order_id}|{payment_id}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    ok = hmac.compare_digest(expected, signature or "")
    print(f"[RAZORPAY] signature verify — order_id={order_id} payment_id={payment_id} match={ok}")
    return ok
