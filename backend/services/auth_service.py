"""
ZITLAS — Firebase ID token verification (backend/services/auth_service.py)

FastAPI dependency for routes that must know WHO the caller actually is,
server-side — the coaching escrow endpoints (routes/coaching.py) are the
first routes in this backend that need this; every existing route is
unauthenticated compute (see main.py, no Authorization handling anywhere
else). A reservation/accept/reject call that trusted a client-supplied
userId could be spoofed to reserve or release someone else's money.

Uses google.oauth2.id_token.verify_firebase_token — stateless verification
against Firebase's public JWKs, no service-account credential needed for
this part (unlike firestore_service.py). Consistent with this codebase's
existing preference for google-auth over the heavier firebase-admin
package (see push_service.py).
"""

from __future__ import annotations

import os

import google.auth.transport.requests
from fastapi import Depends, Header, HTTPException
from google.oauth2 import id_token

_PROJECT_ID = "zitlas-b8677"
_request = google.auth.transport.requests.Request()

# Bootstrap admins. Custom claims (request.auth.token.admin) are the primary
# admin signal once set via identity_service, but there's a chicken-and-egg at
# first setup — nobody can grant the first admin claim without already being
# admin. This env allowlist (comma-separated Firebase UIDs) breaks that cycle:
# any uid listed here is treated as admin server-side regardless of claims, so
# the very first certificate approval / claim grant can be performed. Leave it
# set for your ops accounts; it is checked ONLY server-side (never trusted from
# the client) and is independent of the client-writable users/{uid}.role field.
_ADMIN_UIDS = {
    u.strip() for u in (os.getenv("ZITLAS_ADMIN_UIDS") or "").split(",") if u.strip()
}


async def verify_firebase_token(authorization: str | None = Header(default=None)) -> dict:
    """Raises 401 on a missing/invalid/expired token. On success returns
    {"uid", "email", "name", "admin", "expert"} — the last two read from
    custom claims baked into the verified token (never client-forgeable)."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing_token")

    token = authorization[len("Bearer "):].strip()
    if not token:
        raise HTTPException(status_code=401, detail="missing_token")

    try:
        claims = id_token.verify_firebase_token(token, _request, audience=_PROJECT_ID)
    except Exception as e:
        print(f"[AUTH] token verification failed: {type(e).__name__}: {e}")
        raise HTTPException(status_code=401, detail="invalid_token")

    if not claims or not claims.get("sub"):
        print(f"[AUTH] token verified but missing 'sub' claim — claims keys={list((claims or {}).keys())}")
        raise HTTPException(status_code=401, detail="invalid_token")

    uid = claims["sub"]
    print(f"[AUTH] token verified OK — uid={uid}")
    return {
        "uid": uid,
        "email": claims.get("email"),
        "name": claims.get("name"),
        # Custom claims (may be absent → default False). Admin is also granted
        # via the bootstrap env allowlist above.
        "admin": bool(claims.get("admin")) or (uid in _ADMIN_UIDS),
        "expert": bool(claims.get("expert")),
    }


def is_admin(caller: dict) -> bool:
    return bool(caller.get("admin"))


async def require_admin(caller: dict = Depends(verify_firebase_token)) -> dict:
    """FastAPI dependency: 401 if unauthenticated, 403 if the caller is not an
    admin (by custom claim or ZITLAS_ADMIN_UIDS allowlist). Use on privileged
    routes (certificate/expert approval)."""
    if not is_admin(caller):
        print(f"[AUTH] admin-only route denied for uid={caller.get('uid')}")
        raise HTTPException(status_code=403, detail="admin_required")
    return caller
