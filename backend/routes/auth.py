"""
ZITLAS — Auth Routes

Endpoints:
  GET  /api/auth/health        Liveness probe
  POST /api/auth/webview-token Mint a Firebase custom token for the embedded
                               Personal Coaching WebView (auth bridge).

Future endpoints:
  POST /api/auth/register    Register a new player
  POST /api/auth/login       Login and return JWT token
  POST /api/auth/logout      Invalidate session
  GET  /api/auth/me          Return current user profile
  POST /api/auth/refresh     Refresh access token
"""

from fastapi import APIRouter, Depends, HTTPException

from services.auth_service import verify_firebase_token
from services import identity_service

router = APIRouter()


@router.get("/health")
async def auth_health():
    return {"module": "auth", "status": "ready"}


@router.post("/webview-token")
async def webview_token(caller: dict = Depends(verify_firebase_token)):
    """Exchange the caller's verified Firebase ID token for a short-lived
    custom token, used ONLY to sign the Personal Coaching WebView into the same
    Firebase account the native app is already signed into (see
    identity_service.create_custom_token for the full rationale).

    The caller identity comes entirely from the verified Bearer token — the
    minted token is always for the CALLER's own uid, never a client-supplied
    one, so this cannot be used to impersonate another user."""
    uid = caller["uid"]
    token = identity_service.create_custom_token(uid)
    if not token:
        # Admin credentials unconfigured or minting failed — the WebView cannot
        # authenticate without this, so fail loudly rather than returning null.
        raise HTTPException(status_code=503, detail="custom_token_unavailable")
    return {"customToken": token, "uid": uid}
