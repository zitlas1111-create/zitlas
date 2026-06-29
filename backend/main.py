"""
ZITLAS Backend — main.py
FastAPI server that serves the frontend and hosts all API routes.

Run from the backend/ directory:
    uvicorn main:app --reload

App opens at:
    http://127.0.0.1:8000
"""

import asyncio
import os
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

# Load environment variables from .env before anything else
load_dotenv(Path(__file__).parent / ".env")

from routes import auth, player, diet, assessment
from routes import ai
from routes import chat
from routes import support
from routes import rag
from routes import review
from routes import system
from services import rag_service

# ── Directory paths ──────────────────────────────────────────────────────────
BASE_DIR     = Path(__file__).parent          # backend/
FRONTEND_DIR = BASE_DIR.parent / "frontend"  # frontend/


# ── Lifespan: startup tasks ───────────────────────────────────────────────────

async def _prewarm_kb(goal: str) -> None:
    """Pre-warm one goal KB in the background; failures never crash the server."""
    from services.kb_manager import kb_manager
    try:
        await asyncio.to_thread(kb_manager.get_kb, goal)
        print(f"[STARTUP] {goal} KB pre-warmed OK")
    except Exception as exc:
        print(f"[STARTUP] {goal} KB pre-warm failed (non-fatal): {exc}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize logger + environment only.
    # rag_service.initialize() is now a lightweight no-op that sets _is_ready=True.
    await asyncio.to_thread(rag_service.initialize)

    try:
        import psutil as _psutil
        _rss = _psutil.Process().memory_info().rss / 1024 / 1024
        print(f"[STARTUP] RAM at startup: {_rss:.1f} MB")
    except Exception:
        pass

    # Skip KB pre-warm on memory-constrained deployments (e.g. Render free tier).
    # Set DISABLE_KB_PREWARM=true in the environment to disable.
    if os.getenv("DISABLE_KB_PREWARM", "false").lower() != "true":
        asyncio.create_task(_prewarm_kb("weight_loss"))
    else:
        print("[STARTUP] KB pre-warm disabled (DISABLE_KB_PREWARM=true) — KBs load on first request")

    yield


# ── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    lifespan=lifespan,
    title="ZITLAS API",
    description="AI-powered weight-loss and nutrition platform — backend API",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# ── CORS (needed once frontend calls APIs) ───────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://127.0.0.1:8000", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── API routers ───────────────────────────────────────────────────────────────
app.include_router(auth.router,       prefix="/api/auth",       tags=["Auth"])
app.include_router(player.router,     prefix="/api/user",       tags=["User"])
app.include_router(diet.router,       prefix="/api/diet",       tags=["Diet"])
app.include_router(assessment.router, prefix="/api/assessment", tags=["Assessment"])
app.include_router(ai.router,         prefix="/api/ai",         tags=["AI"])
app.include_router(rag.router,        prefix="/api/rag",        tags=["RAG"])
app.include_router(support.router,    prefix="/api/support",    tags=["Support"])
app.include_router(review.router,     prefix="/api/review",     tags=["Review"])
app.include_router(system.router,     prefix="/api/system",     tags=["System"])
app.include_router(chat.router,       prefix="/api/chat",       tags=["Chat"])

# ── Root redirect ────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return RedirectResponse(url="/pages/login/login.html")

# ── Serve uploaded chat images ────────────────────────────────────────────────
_UPLOADS_DIR = BASE_DIR / "uploads"
_UPLOADS_DIR.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(_UPLOADS_DIR)), name="uploads")

# ── Serve frontend (must be last — catches everything else) ───────────────────
app.mount("/", StaticFiles(directory=str(FRONTEND_DIR)), name="frontend")
