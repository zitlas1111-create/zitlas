"""
ZITLAS — FCM push sender (backend/services/push_service.py)

Delivers web-push notifications to the tokens the frontend stores in
users/{uid}.pushTokens (assets/js/push-notifications.js). Uses the FCM
HTTP v1 API with a Firebase service account — google-auth is already a
transitive dependency of google-genai, so no new requirements.

Credential loading (env var names, configuration) lives in
services/google_credentials.py, shared with services/firestore_service.py.

Without credentials every send is a clean no-op that reports
{"configured": false} — nothing in the app depends on push succeeding.
Get the file from Firebase console -> Project settings -> Service
accounts -> Generate new private key.
"""

from __future__ import annotations

from typing import Any

from services.google_credentials import load_credentials, last_error

_PROJECT_ID = "zitlas-b8677"
_FCM_URL = f"https://fcm.googleapis.com/v1/projects/{_PROJECT_ID}/messages:send"
_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


def _load_credentials():
    return load_credentials([_SCOPE])


def is_configured() -> bool:
    return _load_credentials() is not None


def _access_token() -> str:
    import google.auth.transport.requests

    creds = _load_credentials()
    creds.refresh(google.auth.transport.requests.Request())
    return creds.token


def send_to_token(token: str, title: str, body: str, data: dict[str, str] | None = None) -> dict[str, Any]:
    """Send one notification to one device token via FCM HTTP v1.
    Returns {ok, status, detail}; never raises for delivery failures so a
    dead token in a user's list can't break the loop over their devices."""
    if not is_configured():
        return {"ok": False, "configured": False, "detail": last_error([_SCOPE])}

    import requests

    message = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "data": {str(k): str(v) for k, v in (data or {}).items()},
            "webpush": {
                "fcm_options": {"link": (data or {}).get("url", "/pages/notifications/notifications.html")},
            },
        }
    }
    try:
        r = requests.post(
            _FCM_URL,
            headers={"Authorization": f"Bearer {_access_token()}",
                     "Content-Type": "application/json"},
            json=message,
            timeout=15,
        )
        ok = r.status_code == 200
        detail = r.json() if r.headers.get("content-type", "").startswith("application/json") else r.text[:300]
        if not ok:
            print(f"[PUSH] send failed ({r.status_code}): {str(detail)[:200]}")
        return {"ok": ok, "configured": True, "status": r.status_code, "detail": detail}
    except Exception as e:
        print(f"[PUSH] send error: {type(e).__name__}: {e}")
        return {"ok": False, "configured": True, "detail": f"{type(e).__name__}: {e}"}
