"""
ZITLAS — Expert Certificate Verification (backend/services/certificate_verification.py)

Runs an uploaded document through Gemini's vision model to decide, in one
pass:
  1. Is this actually a professional coaching/fitness certification? (reject
     selfies, IDs, screenshots, random photos, blank pages immediately)
  2. If yes — OCR the certificate fields (name, org, cert number, dates)
  3. Visual authenticity assessment (logos, signature, QR/stamp, tampering,
     blur, cropped text, missing issuer) → a 0-100 confidence score

IMPORTANT — HONEST LIMITATION: this is an LLM vision model's visual judgment,
not forensic document authentication (no ELA/noise-pattern/metadata
analysis). It catches obviously-wrong uploads and clearly doctored images
reliably; it cannot certify with certainty that a well-made forgery is
genuine. That's exactly why the >=95% threshold auto-passes only the most
confident cases and everything else routes to human admin review.
"""

from __future__ import annotations

import json
import re

from services import gemini_service

AUTO_VERIFY_THRESHOLD = 95

CERT_VERIFICATION_PROMPT = """You are a strict document verification AI for ZITLAS, a fitness coaching platform. You are examining an image a fitness/wellness expert uploaded, claiming it is their professional coaching certification.

STEP 1 — CLASSIFY
Decide if this image is ACTUALLY a professional certification/certificate document — e.g. a personal trainer certification (ACE, NASM, ISSA), a nutrition/dietetics certification, a yoga teacher certification, a sports science/physiotherapy degree, or a strength & conditioning certification.

REJECT (is_certificate = false) if the image is any of: a selfie or personal photo, a random/nature/food image, a screenshot of something else, a government ID (Aadhaar, PAN card, driving license, passport), a gym photo, a blank or irrelevant page, or anything that is clearly not a formal certification document.

STEP 2 — IF (AND ONLY IF) is_certificate IS TRUE, EXTRACT:
- coach_name: the name of the person the certificate was issued to
- certificate_name: the title of the certification (e.g. "ACE Certified Personal Trainer")
- issuing_organization: the organization that issued it
- certificate_number: the ID/certificate number printed on it, if any
- issued_date: the issue date exactly as printed, if visible
- expiry_date: the expiry date exactly as printed, if visible, else null

STEP 3 — AUTHENTICITY ANALYSIS (only if is_certificate is true)
Visually assess the document and report what you can see:
- has_official_logo: an organization logo/emblem is visible
- has_signature: a signature is visible
- has_qr_code: a QR code is visible
- has_stamp_or_seal: an official stamp or embossed seal is visible
- signs_of_tampering: inconsistent fonts, misaligned text, visible editing artifacts, mismatched backgrounds, or anything suggesting digital alteration
- is_blurry: the text is hard to read due to blur/low resolution
- has_cropped_text: text is cut off at an edge, suggesting a cropped screenshot rather than a full document
- missing_issuer: no organization/issuer name is visible anywhere

Then give verification_confidence, an integer 0-100, reflecting how confident you are this is a genuine, complete, unaltered certification document (100 = fully confident genuine and complete; 0 = certainly fake, tampered, or unreadable). Be conservative — only score 95+ when the document looks fully legitimate with no red flags at all.

Respond with ONLY this JSON object, no other text:
{
  "is_certificate": true or false,
  "rejection_reason": "one short sentence if is_certificate is false, else null",
  "coach_name": "string or null",
  "certificate_name": "string or null",
  "issuing_organization": "string or null",
  "certificate_number": "string or null",
  "issued_date": "string or null",
  "expiry_date": "string or null",
  "has_official_logo": true or false,
  "has_signature": true or false,
  "has_qr_code": true or false,
  "has_stamp_or_seal": true or false,
  "signs_of_tampering": true or false,
  "is_blurry": true or false,
  "has_cropped_text": true or false,
  "missing_issuer": true or false,
  "verification_confidence": 0-100,
  "analysis_notes": "one or two sentence summary of your assessment"
}"""


def _extract_json(text: str) -> dict | None:
    try:
        return json.loads(text.strip())
    except (json.JSONDecodeError, ValueError):
        pass
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group())
        except (json.JSONDecodeError, ValueError):
            pass
    return None


async def verify_certificate_image(image_bytes: bytes, mime_type: str) -> dict:
    """
    Returns the parsed analysis dict (see CERT_VERIFICATION_PROMPT's JSON
    shape). Raises ValueError if the AI response couldn't be parsed as JSON.
    """
    result = await gemini_service.analyze_image(image_bytes, mime_type, CERT_VERIFICATION_PROMPT)
    parsed = _extract_json(result["reply"])
    if not parsed:
        raise ValueError("Verification AI returned an unreadable response")
    return parsed


def compute_status(analysis: dict) -> tuple[str, int]:
    """(verificationStatus, verificationScore) from the raw analysis dict."""
    score = int(analysis.get("verification_confidence") or 0)
    score = max(0, min(100, score))
    tampered = bool(analysis.get("signs_of_tampering"))
    status = "verified" if (score >= AUTO_VERIFY_THRESHOLD and not tampered) else "pending_review"
    return status, score
