"""
ZITLAS — Firestore Admin access (backend/services/firestore_service.py)

The Personal Coaching escrow flow (routes/coaching.py) is the first feature
in this backend that needs to read/write Firestore server-side — every
other route is deliberately Firestore-free (see routes/certificates.py's
docstring). Wallet reservations must be enforced where the caller can't
spoof the check, which means the balance/reservation math has to live here,
not in client JS.

Uses google-cloud-firestore directly (not the firebase-admin package,
which this codebase avoids everywhere else — see push_service.py) with the
same service-account credential source as FCM push.

Without FIREBASE_SERVICE_ACCOUNT_JSON/_FILE configured, get_client()
returns None — callers in routes/coaching.py must fail closed (503), unlike
push's silent no-op, because a coaching request that "succeeds" without
actually reserving money would be a real financial bug.
"""

from __future__ import annotations

from google.cloud import firestore

from services.google_credentials import last_error, load_credentials

_PROJECT_ID = "zitlas-b8677"
_SCOPE = "https://www.googleapis.com/auth/datastore"

_client: firestore.Client | None = None
_attempted = False


def get_client() -> firestore.Client | None:
    """Lazy-load and cache the Firestore Admin client. Returns None (and
    logs why) when unconfigured."""
    global _client, _attempted
    if _client is not None:
        return _client
    if _attempted:
        return None
    _attempted = True

    creds = load_credentials([_SCOPE])
    if creds is None:
        return None

    _client = firestore.Client(project=_PROJECT_ID, credentials=creds)
    return _client


def is_configured() -> bool:
    return get_client() is not None


def config_error() -> str | None:
    return last_error([_SCOPE])
