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

import google.auth.transport.requests
from fastapi import Header, HTTPException
from google.oauth2 import id_token

_PROJECT_ID = "zitlas-b8677"
_request = google.auth.transport.requests.Request()


async def verify_firebase_token(authorization: str | None = Header(default=None)) -> dict:
    """Raises 401 on a missing/invalid/expired token. On success returns
    {"uid", "email", "name"} taken from the verified token claims."""
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

    print(f"[AUTH] token verified OK — uid={claims['sub']}")
    return {"uid": claims["sub"], "email": claims.get("email"), "name": claims.get("name")}
