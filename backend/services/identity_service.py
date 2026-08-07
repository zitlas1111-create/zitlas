"""
ZITLAS — Firebase Auth custom-claims writer (backend/services/identity_service.py)

Sets custom claims ({"expert": true} / {"admin": true}) on a Firebase Auth
user so Firestore Security Rules can gate privileged reads on
`request.auth.token.expert` / `request.auth.token.admin` — claims the client
CANNOT forge (Google signs them into the ID token; only the service-account
credential can set them).

MECHANISM — the official Firebase Admin Python SDK
(`firebase_admin.auth.set_custom_user_claims`). This REPLACES an earlier
hand-rolled Identity Toolkit REST call: custom claims are a Firebase Auth
feature with NO google-cloud-python equivalent (unlike Firestore, which uses
google-cloud-firestore, or FCM, which uses the REST v1 API), so the codebase's
usual "avoid firebase-admin" preference does not apply here — the SDK is the
only officially supported, tested path, and it handles the endpoint,
serialization, reserved-claim validation, and the 1000-byte claim limit for us.

APP ISOLATION — initializes a DEDICATED named Firebase app ("zitlas-claims")
exactly once, guarded so repeated calls / hot reloads never raise
"app already exists". Uses the SAME service-account source as the rest of the
backend (FIREBASE_SERVICE_ACCOUNT_JSON / _FILE). All auth calls pass app=<this
app> so we never touch or create the default app.

CLAIM MERGING — set_custom_user_claims OVERWRITES the entire claims object, so
every write here first READS the user's existing claims and merges, preserving
unrelated claims. Passing a claim value of None removes just that key.

BEST-EFFORT — claim propagation only matters for the Security-Rules layer; the
backend's own authority checks never depend on it (admin = ZITLAS_ADMIN_UIDS
allowlist or an existing admin claim; expert authorization in rules is
relationship-based). So a False return is a soft warning, never fatal — the
privileged Firestore write it accompanies has already happened via the Admin
SDK. Claims apply on the user's NEXT ID-token refresh (~1h, or immediately if
the client calls getIdToken(true) / re-logs in).
"""

from __future__ import annotations

import json
import os
import threading

_APP_NAME = "zitlas-claims"
_app = None
_init_attempted = False
_lock = threading.Lock()


def _service_account_info():
    """Return the service-account as a dict (from JSON env) or a file path,
    or None when unconfigured — same source as services/google_credentials."""
    raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE")
    if raw:
        try:
            return json.loads(raw)
        except Exception as e:
            print(f"[IDENTITY] FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON: {type(e).__name__}: {e}")
            return None
    if path and os.path.exists(path):
        return path
    return None


def _get_app():
    """Lazily initialize (once) a dedicated named Firebase Admin app. Returns
    the app or None when credentials are unconfigured / init fails."""
    global _app, _init_attempted
    if _app is not None:
        return _app
    with _lock:
        if _app is not None:
            return _app
        if _init_attempted:
            return None
        _init_attempted = True
        try:
            import firebase_admin
            from firebase_admin import credentials

            # Reuse an already-created app of this name if one exists (e.g. a
            # prior init in the same process) instead of creating a duplicate.
            try:
                _app = firebase_admin.get_app(_APP_NAME)
                print(f"[IDENTITY] reusing existing Firebase app '{_APP_NAME}'")
                return _app
            except ValueError:
                pass  # not yet created — create below

            info = _service_account_info()
            if info is None:
                print("[IDENTITY] no service-account credentials — custom claims disabled "
                      "(set FIREBASE_SERVICE_ACCOUNT_JSON / _FILE)")
                return None
            cred = credentials.Certificate(info)
            _app = firebase_admin.initialize_app(cred, name=_APP_NAME)
            print(f"[IDENTITY] Firebase Admin app '{_APP_NAME}' initialized")
            return _app
        except Exception as e:
            print(f"[IDENTITY] Firebase Admin init failed: {type(e).__name__}: {e}")
            _app = None
            return None


def set_claims(uid: str, updates: dict) -> bool:
    """Merge `updates` into the user's existing custom claims and persist.
    A value of None removes that key. Returns True on success, False otherwise.
    NEVER raises — a False return is a soft warning (see module docstring)."""
    if not uid:
        return False
    app = _get_app()
    if app is None:
        return False
    try:
        from firebase_admin import auth

        user = auth.get_user(uid, app=app)
        current = dict(user.custom_claims or {})
        for k, v in (updates or {}).items():
            if v is None:
                current.pop(k, None)
            else:
                current[k] = v
        # set_custom_user_claims replaces the whole object → pass the merged one
        # (or None to clear entirely, which we never do here).
        auth.set_custom_user_claims(uid, current if current else None, app=app)
        print(f"[IDENTITY] custom claims updated uid={uid} claims={current}")
        return True
    except Exception as e:
        print(f"[IDENTITY] set_claims failed uid={uid}: {type(e).__name__}: {e}")
        return False


def create_custom_token(uid: str) -> str | None:
    """Mint a short-lived Firebase custom token for `uid`, or None when the
    Admin app is unconfigured / minting fails.

    This is the auth bridge for the Personal Coaching WebView: the Flutter app
    is signed in with the NATIVE Firebase SDK, but the embedded Website runs the
    Firebase JS SDK, and the two sessions are NOT shared. The Flutter side hands
    this token to the WebView, which calls `signInWithCustomToken` to establish
    a real WEB session for the SAME uid — so the Website's `onSnapshot` listeners
    (chat, meal reviews, coaching status) satisfy the existing Firestore rules
    without a second login. After that first exchange the JS SDK maintains its
    own refresh token, so the token's ~1h lifetime does not limit the session.

    Reuses the same dedicated Admin app as set_claims() — no extra credential
    wiring. NEVER raises."""
    if not uid:
        return None
    app = _get_app()
    if app is None:
        return None
    try:
        from firebase_admin import auth

        token = auth.create_custom_token(uid, app=app)
        # The SDK returns bytes; the JSON response and the JS SDK both want str.
        if isinstance(token, (bytes, bytearray)):
            token = token.decode("utf-8")
        print(f"[IDENTITY] custom token minted uid={uid}")
        return token
    except Exception as e:
        print(f"[IDENTITY] create_custom_token failed uid={uid}: {type(e).__name__}: {e}")
        return None


def grant_expert(uid: str) -> bool:
    return set_claims(uid, {"expert": True})


def revoke_expert(uid: str) -> bool:
    return set_claims(uid, {"expert": None})


def grant_admin(uid: str) -> bool:
    return set_claims(uid, {"admin": True})


def revoke_admin(uid: str) -> bool:
    return set_claims(uid, {"admin": None})
