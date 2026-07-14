"""
ZITLAS — Shared Google service-account credential loader (backend/services/google_credentials.py)

Extracted from push_service.py's original _load_credentials() so both FCM
push and the coaching-escrow Firestore Admin access (services/firestore_service.py)
share one credential source instead of loading/parsing the service-account
JSON twice. Behavior is unchanged from the original: lazy-loaded, cached per
scope tuple, and a clean None (never a raised exception) when unconfigured —
callers treat that as "this capability is disabled".

Configuration (either one, same as before):
  FIREBASE_SERVICE_ACCOUNT_JSON  — the service-account JSON as an env string
  FIREBASE_SERVICE_ACCOUNT_FILE  — path to the service-account .json file
"""

from __future__ import annotations

import json
import os

_cache: dict[tuple[str, ...], object] = {}
_errors: dict[tuple[str, ...], str] = {}


def load_credentials(scopes: list[str]):
    """Lazy-load and cache service-account credentials for the given scopes.
    Returns None (and records why in last_error()) when unconfigured."""
    key = tuple(scopes)
    if key in _cache:
        return _cache[key]
    if key in _errors:
        return None

    print(f"[GOOGLE CREDENTIALS] loading credentials for scopes={scopes} ...")
    try:
        from google.oauth2 import service_account

        raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
        path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE")
        print(f"[GOOGLE CREDENTIALS] FIREBASE_SERVICE_ACCOUNT_JSON set={bool(raw)} "
              f"FIREBASE_SERVICE_ACCOUNT_FILE set={bool(path)}"
              + (f" (exists on disk={os.path.exists(path)})" if path else ""))
        if raw:
            info = json.loads(raw)
            creds = service_account.Credentials.from_service_account_info(info, scopes=scopes)
            print(f"[GOOGLE CREDENTIALS] loaded from FIREBASE_SERVICE_ACCOUNT_JSON — "
                  f"service_account_email={getattr(creds, 'service_account_email', '?')}")
        elif path and os.path.exists(path):
            creds = service_account.Credentials.from_service_account_file(path, scopes=scopes)
            print(f"[GOOGLE CREDENTIALS] loaded from FIREBASE_SERVICE_ACCOUNT_FILE — "
                  f"service_account_email={getattr(creds, 'service_account_email', '?')}")
        else:
            _errors[key] = ("No service-account credentials: set FIREBASE_SERVICE_ACCOUNT_JSON "
                             "(the JSON string) or FIREBASE_SERVICE_ACCOUNT_FILE (a path) in the environment.")
            print(f"[GOOGLE CREDENTIALS] disabled — {_errors[key]}")
            return None
    except Exception as e:  # bad JSON, wrong key type, import failure
        _errors[key] = f"{type(e).__name__}: {e}"
        print(f"[GOOGLE CREDENTIALS] disabled — {_errors[key]}")
        import traceback
        print(traceback.format_exc())
        return None

    _cache[key] = creds
    return creds


def last_error(scopes: list[str]) -> str | None:
    return _errors.get(tuple(scopes))
