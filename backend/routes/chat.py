"""
ZITLAS — Chat Upload Route

POST /api/chat/upload  — Upload a chat image; returns a public URL
"""

import uuid
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse

router = APIRouter()

_ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_UPLOAD_DIR = Path(__file__).parent.parent / "uploads" / "chat"


@router.post("/upload")
async def upload_chat_image(file: UploadFile = File(...)) -> JSONResponse:
    print(f"[CHAT UPLOAD] Received file: name={file.filename!r}  type={file.content_type!r}")

    if file.content_type not in _ALLOWED_TYPES:
        print(f"[CHAT UPLOAD] Rejected: unsupported type {file.content_type!r}")
        raise HTTPException(
            status_code=400,
            detail="Only jpg, jpeg, png, and webp images are accepted.",
        )

    content = await file.read()
    print(f"[CHAT UPLOAD] Size: {len(content):,} bytes")

    if len(content) > _MAX_BYTES:
        print(f"[CHAT UPLOAD] Rejected: too large ({len(content):,} bytes)")
        raise HTTPException(status_code=413, detail="Image too large (max 10 MB).")

    _UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

    raw_name = file.filename or ""
    ext = raw_name.rsplit(".", 1)[-1].lower() if "." in raw_name else "jpg"
    if ext not in ("jpg", "jpeg", "png", "webp"):
        ext = "jpg"

    filename = f"{uuid.uuid4().hex}.{ext}"
    (_UPLOAD_DIR / filename).write_bytes(content)

    url = f"/uploads/chat/{filename}"
    print(f"[CHAT UPLOAD] Saved → {url}")
    return JSONResponse({"success": True, "url": url})
