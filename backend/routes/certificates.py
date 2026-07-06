"""
ZITLAS — Expert Certificate Verification Route

POST /api/certificates/verify — AI-validates + OCRs an uploaded coaching
certificate. Only accepted (is_certificate=true) files are saved to disk;
rejected uploads are discarded immediately, matching the product
requirement to never persist a non-certificate file.

This route does NOT touch Firestore — same architecture as every other
route in this backend. It returns the computed result; the frontend (in the
expert's authenticated session) persists the expert_certificates/{id} doc
and recomputes experts/{uid}.verified. See CLAUDE.md for why: this project
has no Firebase Admin SDK anywhere in the backend, Firestore is
frontend-only throughout.
"""

import uuid
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from services import certificate_verification

router = APIRouter()

_ALLOWED_TYPES = {
    "image/jpeg": "jpg",
    "image/png":  "png",
    "application/pdf": "pdf",
}
_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_UPLOAD_DIR = Path(__file__).parent.parent / "uploads" / "certificates"


@router.post("/verify")
async def verify_certificate(
    expertId: str = Form(...),
    file: UploadFile = File(...),
) -> JSONResponse:
    print(f"[CERT VERIFY] expertId={expertId}  filename={file.filename!r}  type={file.content_type!r}")

    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail="Only JPG, PNG, and PDF files are accepted.")

    content = await file.read()
    print(f"[CERT VERIFY] size={len(content):,} bytes")
    if len(content) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="File too large (max 10 MB).")

    # PDF -> rasterize page 1 to PNG for the vision model. The ORIGINAL PDF
    # (not the raster) is what gets saved/served if the upload is accepted.
    analysis_bytes, analysis_mime = content, file.content_type
    if file.content_type == "application/pdf":
        try:
            import fitz  # PyMuPDF
            pdf = fitz.open(stream=content, filetype="pdf")
            if pdf.page_count < 1:
                raise ValueError("empty PDF")
            pix = pdf[0].get_pixmap(dpi=200)
            analysis_bytes = pix.tobytes("png")
            analysis_mime = "image/png"
            pdf.close()
        except Exception as e:
            print(f"[CERT VERIFY] PDF rasterize failed: {e}")
            raise HTTPException(status_code=400, detail="Could not read this PDF — please upload a clearer file.")

    try:
        analysis = await certificate_verification.verify_certificate_image(analysis_bytes, analysis_mime)
    except Exception as e:
        print(f"[CERT VERIFY] AI verification failed: {e}")
        raise HTTPException(status_code=502, detail=f"Verification AI is unavailable right now: {e}")

    print(f"[CERT VERIFY] is_certificate={analysis.get('is_certificate')} "
          f"confidence={analysis.get('verification_confidence')}")

    if not analysis.get("is_certificate"):
        return JSONResponse({
            "accepted": False,
            "reason": analysis.get("rejection_reason")
                      or "This doesn't appear to be a professional coaching certificate.",
        })

    # Accepted — now persist the ORIGINAL uploaded file.
    _UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    ext = _ALLOWED_TYPES[file.content_type]
    filename = f"{uuid.uuid4().hex}.{ext}"
    (_UPLOAD_DIR / filename).write_bytes(content)
    url = f"/uploads/certificates/{filename}"
    print(f"[CERT VERIFY] saved -> {url}")

    status, score = certificate_verification.compute_status(analysis)

    return JSONResponse({
        "accepted": True,
        "certificateUrl": url,
        "fileType": file.content_type,
        "coachName": analysis.get("coach_name"),
        "certificateName": analysis.get("certificate_name"),
        "issuingOrganization": analysis.get("issuing_organization"),
        "certificateNumber": analysis.get("certificate_number"),
        "issuedDate": analysis.get("issued_date"),
        "expiryDate": analysis.get("expiry_date"),
        "verificationScore": score,
        "verificationStatus": status,
        "flags": {
            "hasOfficialLogo":  bool(analysis.get("has_official_logo")),
            "hasSignature":     bool(analysis.get("has_signature")),
            "hasQrCode":        bool(analysis.get("has_qr_code")),
            "hasStampOrSeal":   bool(analysis.get("has_stamp_or_seal")),
            "signsOfTampering": bool(analysis.get("signs_of_tampering")),
            "isBlurry":         bool(analysis.get("is_blurry")),
            "hasCroppedText":   bool(analysis.get("has_cropped_text")),
            "missingIssuer":    bool(analysis.get("missing_issuer")),
        },
        "analysisNotes": analysis.get("analysis_notes"),
    })
