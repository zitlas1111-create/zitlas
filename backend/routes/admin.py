"""
ZITLAS — Admin-only privileged operations (backend/routes/admin.py)

Certificate verification and expert approval used to be CLIENT writes gated
only by a client-writable users/{uid}.role field (FIRESTORE_SECURITY_AUDIT.md
V3/V4 — trivially spoofable). They now run here, behind require_admin (custom
claim or ZITLAS_ADMIN_UIDS allowlist), writing via the Admin SDK (which
bypasses Security Rules), so:

  - expert_certificates.verificationStatus,
  - experts/{uid}.verification / .verified / .approved,
  - and the Firebase Auth `expert` custom claim

can ONLY change through an authenticated admin. The admin UI
(assets/js/certificate-manager.js, pages/admin/admin-review.js) is preserved —
it just calls these endpoints instead of writing Firestore directly.

Faithful port of the old certificate-manager.js recomputeVerifiedFlag(): the
expert is "verified" iff they have >=1 certificate with
verificationStatus=='verified'; experts/{uid}.verification is the single object
every badge surface reads.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from services import firestore_service, identity_service
from services.auth_service import require_admin, verify_firebase_token

router = APIRouter()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _db():
    db = firestore_service.get_client()
    if db is None:
        reason = firestore_service.config_error() or "unknown"
        raise HTTPException(status_code=503, detail=f"admin_service_unavailable: {reason}")
    return db


class CertActionBody(BaseModel):
    certId: str
    reason: str | None = None  # required for reject


class ExpertApproveBody(BaseModel):
    expertId: str
    approved: bool = True


class ExpertDeactivateBody(BaseModel):
    expertId: str


class RecomputeBody(BaseModel):
    expertId: str


def _recompute_verified(db, expert_id: str) -> dict:
    """Mirror of certificate-manager.js recomputeVerifiedFlag — recompute the
    expert's badge state from their certificates and persist it. Returns the
    verification object written."""
    certs = db.collection("expert_certificates").where("expertId", "==", expert_id).stream()
    verified = []
    for c in certs:
        d = c.to_dict() or {}
        if d.get("verificationStatus") == "verified":
            verified.append(d)
    is_verified = len(verified) > 0
    verified_at = None
    if is_verified:
        stamps = sorted(
            [c.get("reviewedAt") or c.get("uploadedAt") for c in verified if (c.get("reviewedAt") or c.get("uploadedAt"))]
        )
        verified_at = stamps[0] if stamps else None
    verification = {
        "isVerified": is_verified,
        "verificationLevel": "professional" if is_verified else None,
        "verifiedAt": verified_at,
        "verifiedCertificates": len(verified),
    }
    db.collection("experts").document(expert_id).set(
        {"verification": verification, "verified": is_verified}, merge=True
    )
    return verification


@router.post("/certificates/approve")
async def approve_certificate(body: CertActionBody, admin: dict = Depends(require_admin)):
    db = _db()
    cert_ref = db.collection("expert_certificates").document(body.certId)
    snap = cert_ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="certificate_not_found")
    expert_id = (snap.to_dict() or {}).get("expertId")
    if not expert_id:
        raise HTTPException(status_code=400, detail="certificate_missing_expertId")

    cert_ref.update({
        "verificationStatus": "verified",
        "reviewedBy": admin["uid"], "reviewedAt": _now_iso(), "rejectionReason": None,
    })
    verification = _recompute_verified(db, expert_id)
    # Grant the rules-level expert claim (best-effort; see identity_service).
    claim_set = identity_service.grant_expert(expert_id) if verification["isVerified"] else False

    print(f"[ADMIN] cert approved certId={body.certId} expert={expert_id} claim_set={claim_set}")
    return {"success": True, "verification": verification,
            "claimSet": claim_set,
            "note": None if claim_set else "expert must re-login (or call getIdToken(true)) for the claim to take effect"}


@router.post("/certificates/reject")
async def reject_certificate(body: CertActionBody, admin: dict = Depends(require_admin)):
    if not body.reason:
        raise HTTPException(status_code=400, detail="reason_required")
    db = _db()
    cert_ref = db.collection("expert_certificates").document(body.certId)
    snap = cert_ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="certificate_not_found")
    expert_id = (snap.to_dict() or {}).get("expertId")

    cert_ref.update({
        "verificationStatus": "rejected",
        "reviewedBy": admin["uid"], "reviewedAt": _now_iso(), "rejectionReason": body.reason,
    })
    verification = _recompute_verified(db, expert_id) if expert_id else {"isVerified": False}
    # If this leaves the expert with zero verified certs, drop the claim.
    if expert_id and not verification.get("isVerified"):
        identity_service.revoke_expert(expert_id)

    print(f"[ADMIN] cert rejected certId={body.certId} expert={expert_id} reason={body.reason}")
    return {"success": True, "verification": verification}


@router.post("/experts/deactivate")
async def deactivate_expert(body: ExpertDeactivateBody, caller: dict = Depends(verify_firebase_token)):
    """Expert account/profile OFFBOARDING (was a set of privileged client
    Firestore writes — expert-dashboard.js delete flow — now denied by rules).

    AUTHORIZATION: the authenticated expert may deactivate their OWN profile;
    an admin may deactivate anyone's. Server-side (Admin SDK), it:
      * deletes experts/{uid} (the marketplace profile),
      * downgrades users/{uid}: strips 'expert'/'expert_pending' from roles[]
        and sets expert_status='none' (NEVER deletes the users doc — the same
        uid may hold athlete data),
      * revokes the `expert` custom claim.
    It deliberately does NOT delete the Firebase Auth account, nor referential/
    audit data (expert_reviews, expert_certificates, chat_rooms,
    personal_coaching) — those reference the uid and are preserved."""
    target = body.expertId
    if caller["uid"] != target and not caller.get("admin"):
        raise HTTPException(status_code=403, detail="not_authorized")

    db = _db()
    result = {"expertProfileDeleted": False, "userDowngraded": False, "claimRevoked": False}

    # 1. Remove the marketplace profile doc (if present).
    exp_ref = db.collection("experts").document(target)
    if exp_ref.get().exists:
        exp_ref.delete()
        result["expertProfileDeleted"] = True

    # 2. Downgrade the users doc without destroying athlete data.
    user_ref = db.collection("users").document(target)
    snap = user_ref.get()
    if snap.exists:
        d = snap.to_dict() or {}
        patch = {"expert_status": "none"}
        if isinstance(d.get("roles"), list):
            patch["roles"] = [r for r in d["roles"] if r not in ("expert", "expert_pending")]
        elif d.get("role") == "expert":
            patch["role"] = "athlete"   # downgrade, never delete
        user_ref.set(patch, merge=True)
        result["userDowngraded"] = True

    # 3. Revoke the rules-level expert claim.
    result["claimRevoked"] = identity_service.revoke_expert(target)

    print(f"[ADMIN] expert deactivated target={target} by={caller['uid']} result={result}")
    return {"success": True, **result,
            "note": "Firebase Auth account and audit data (reviews, certs, chats) preserved"}


@router.post("/experts/recompute-verification")
async def recompute_verification(body: RecomputeBody, admin: dict = Depends(require_admin)):
    """Admin maintenance: recompute experts/{uid}.verification/.verified from
    trusted certificate data server-side (replaces the client-side
    recomputeVerifiedFlag write that Security Rules now deny). Also syncs the
    expert claim to match the recomputed verified state."""
    db = _db()
    verification = _recompute_verified(db, body.expertId)
    if verification.get("isVerified"):
        identity_service.grant_expert(body.expertId)
    else:
        identity_service.revoke_expert(body.expertId)
    print(f"[ADMIN] recompute-verification expert={body.expertId} verified={verification.get('isVerified')}")
    return {"success": True, "verification": verification}


@router.post("/grant-admin")
async def grant_admin(body: ExpertApproveBody, admin: dict = Depends(require_admin)):
    """One-time bootstrap: set the `admin` custom claim on a uid so their ID
    token carries admin=true (needed for the admin cert-listing Security Rule).
    Callable by an existing admin — the FIRST admin is bootstrapped via the
    ZITLAS_ADMIN_UIDS env allowlist (auth_service), which makes require_admin
    pass without a claim; this endpoint then persists the claim so it survives
    independent of the env var. Reuses ExpertApproveBody.expertId as the target
    uid. The target must re-login (or call getIdToken(true)) for it to apply."""
    target = body.expertId
    ok = identity_service.grant_admin(target) if body.approved \
        else identity_service.revoke_admin(target)
    print(f"[ADMIN] grant-admin target={target} approved={body.approved} claim_set={ok}")
    return {"success": True, "claimSet": ok,
            "note": "target must re-login for the admin claim to take effect"}


@router.post("/experts/approve")
async def approve_expert(body: ExpertApproveBody, admin: dict = Depends(require_admin)):
    """Flip experts/{uid}.approved and (on approve) grant the expert claim.
    Certificate approval already grants the claim; this exists for direct
    expert-account approval independent of certificates."""
    db = _db()
    db.collection("experts").document(body.expertId).set(
        {"approved": bool(body.approved), "approvedBy": admin["uid"], "approvedAt": _now_iso()},
        merge=True,
    )
    claim_set = identity_service.grant_expert(body.expertId) if body.approved else identity_service.revoke_expert(body.expertId)
    print(f"[ADMIN] expert approve={body.approved} expert={body.expertId} claim_set={claim_set}")
    return {"success": True, "approved": bool(body.approved), "claimSet": claim_set}
