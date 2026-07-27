"""
ZITLAS — Pre-deploy Firestore backfill / compatibility scanner
==============================================================

Finds (and optionally backfills) existing production documents that would
become INACCESSIBLE or misbehave once the production Security Rules
(../../firestore.rules) go live. Rules key off specific ownership/relationship
fields; any legacy doc missing them fails closed (denied), which for a coach
means losing access to an athlete, or for a chat means participants can't read
their own room.

SAFETY CONTRACT
  * DRY RUN by default — no writes unless --apply is passed.
  * --apply additionally requires typing the confirmation phrase.
  * NEVER deletes a document. Only adds/patches missing fields with values
    DERIVED from data already in the document (never fabricated identities).
  * Reports every document needing attention; a doc it cannot safely repair
    (missing identity that can't be derived) is REPORTED, never guessed.

Uses the same Admin client as the backend (services.firestore_service), so it
needs FIREBASE_SERVICE_ACCOUNT_JSON / _FILE in the environment. Run from
backend/:  python -m scripts.firestore_backfill            (dry run)
           python -m scripts.firestore_backfill --apply    (writes, with prompt)

Checks (mirrors the rule dependencies):
  personal_coaching : active rows must have endDateTs (Timestamp). Derivable
                      from the existing `endDate` ISO string.
  chat_rooms        : must have participants[]. Derivable from athleteId+
                      expertId, or from the doc id `chat_<athlete>_<coach>`.
  review_requests   : must have userId (athlete) + expertId. NOT derivable if
                      absent → report only.
  expert_reviews    : must have athleteId + expertId. Report only if absent.
  notifications     : must have userId. Report only.
  coaching_notifications : must have athleteId|coachId|recipientId. Report only.
  users / experts   : sanity counts; report docs carrying legacy privileged
                      fields is informational only (rules ignore them).
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone

# Allow running as `python -m scripts.firestore_backfill` from backend/.
sys.path.insert(0, ".")

from google.cloud import firestore  # noqa: E402
from services import firestore_service  # noqa: E402

CONFIRM_PHRASE = "APPLY ZITLAS BACKFILL"


def _client():
    db = firestore_service.get_client()
    if db is None:
        print("[BACKFILL] Firestore Admin NOT configured: "
              f"{firestore_service.config_error()}")
        print("[BACKFILL] set FIREBASE_SERVICE_ACCOUNT_JSON / _FILE and retry.")
        sys.exit(2)
    return db


def _parse_iso(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except Exception:
        return None


def scan(db, apply: bool):
    report = {"needs_fix": 0, "fixed": 0, "unfixable": 0, "checked": 0}

    def note(unfixable=False):
        report["needs_fix"] += 1
        if unfixable:
            report["unfixable"] += 1

    def did_fix():
        report["fixed"] += 1

    # ── personal_coaching: active rows need endDateTs (Timestamp) ──
    print("\n== personal_coaching ==")
    for doc in db.collection("personal_coaching").stream():
        report["checked"] += 1
        d = doc.to_dict() or {}
        if d.get("status") == "active" and not d.get("endDateTs"):
            end_dt = _parse_iso(d.get("endDate"))
            if end_dt:
                print(f"  FIXABLE {doc.id}: active, missing endDateTs — derive from endDate={d.get('endDate')}")
                note()
                if apply:
                    doc.reference.set({"endDateTs": end_dt}, merge=True)
                    did_fix()
            else:
                print(f"  UNFIXABLE {doc.id}: active, missing endDateTs AND endDate — coach will lose access; "
                      f"set an endDateTs manually (Timestamp).")
                note(unfixable=True)

    # ── chat_rooms: need participants[] ──
    print("\n== chat_rooms ==")
    for doc in db.collection("chat_rooms").stream():
        report["checked"] += 1
        d = doc.to_dict() or {}
        parts = d.get("participants")
        if isinstance(parts, list) and len(parts) >= 2:
            continue
        derived = None
        if d.get("athleteId") and d.get("expertId"):
            derived = [d["athleteId"], d["expertId"]]
        elif doc.id.startswith("chat_") and doc.id.count("_") >= 2:
            bits = doc.id.split("_")
            if len(bits) >= 3 and bits[1] and bits[2]:
                derived = [bits[1], bits[2]]
        if derived:
            print(f"  FIXABLE {doc.id}: missing participants — derive {derived}")
            note()
            if apply:
                doc.reference.set({"participants": derived}, merge=True)
                did_fix()
        else:
            print(f"  UNFIXABLE {doc.id}: missing participants and cannot derive — report only")
            note(unfixable=True)

    # ── report-only ownership checks ──
    def report_only(coll, required_any, label):
        print(f"\n== {coll} (report-only) ==")
        missing = 0
        for doc in db.collection(coll).stream():
            report["checked"] += 1
            d = doc.to_dict() or {}
            if not any(d.get(f) for f in required_any):
                missing += 1
                print(f"  MISSING {label} {coll}/{doc.id}: has none of {required_any} — will be inaccessible")
                note(unfixable=True)
        if missing == 0:
            print(f"  OK — every {coll} doc has {label}")

    report_only("review_requests", ["userId", "athleteId"], "athlete owner (userId)")
    report_only("expert_reviews", ["athleteId"], "athleteId")
    report_only("notifications", ["userId"], "recipient (userId)")
    report_only("coaching_notifications", ["athleteId", "coachId", "recipientId"], "a recipient field")

    # ── informational sanity counts ──
    print("\n== users / experts (informational) ==")
    users = list(db.collection("users").stream())
    experts = list(db.collection("experts").stream())
    legacy_role_admin = sum(1 for u in users if (u.to_dict() or {}).get("role") == "admin")
    print(f"  users={len(users)} experts={len(experts)} "
          f"(users with legacy role=='admin': {legacy_role_admin} — rules ignore this; "
          f"admin now comes from the custom claim / ZITLAS_ADMIN_UIDS)")

    return report


def main():
    ap = argparse.ArgumentParser(description="ZITLAS Firestore pre-deploy backfill scanner")
    ap.add_argument("--apply", action="store_true",
                    help="Actually write fixes (default: dry run, no writes)")
    args = ap.parse_args()

    print("ZITLAS Firestore backfill —", "APPLY MODE" if args.apply else "DRY RUN (no writes)")
    print("Time:", datetime.now(timezone.utc).isoformat())

    if args.apply:
        print(f"\n!! APPLY MODE will write to PRODUCTION Firestore. Type exactly:  {CONFIRM_PHRASE}")
        try:
            typed = input("> ").strip()
        except EOFError:
            typed = ""
        if typed != CONFIRM_PHRASE:
            print("Confirmation mismatch — aborting without any writes.")
            sys.exit(1)

    db = _client()
    report = scan(db, apply=args.apply)

    print("\n================ SUMMARY ================")
    print(f"  documents checked : {report['checked']}")
    print(f"  needing attention : {report['needs_fix']}")
    print(f"  auto-fixable      : {report['needs_fix'] - report['unfixable']}")
    print(f"  fixed (this run)  : {report['fixed']}")
    print(f"  UNFIXABLE (manual): {report['unfixable']}")
    if not args.apply and report["needs_fix"]:
        print("\n  Dry run only — re-run with --apply to write the auto-fixable ones.")
    print("  NOTE: no document was ever deleted by this script.")


if __name__ == "__main__":
    main()
