"""
ZITLAS — Auth Routes

Future endpoints:
  POST /api/auth/register    Register a new player
  POST /api/auth/login       Login and return JWT token
  POST /api/auth/logout      Invalidate session
  GET  /api/auth/me          Return current user profile
  POST /api/auth/refresh     Refresh access token
"""

from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def auth_health():
    return {"module": "auth", "status": "ready"}
