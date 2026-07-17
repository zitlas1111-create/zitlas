"""
ZITLAS — CLIENT TRIAL MODE (single global switch)
==================================================

THE one place to enable/disable the temporary client trial in which all
COACH-RELATED payments are free while the payment infrastructure stays
fully intact.

    CLIENT_TRIAL_MODE = True   -> coach services behave as already paid:
        - Personal Coaching / Complete Transformation escrow reserves ₹0
          and accept debits ₹0 (routes/coaching.py)
        - Expert Diet/Workout Review + Expert Chat charges become ₹0
          (frontend ZitlasPayment.attemptCharge reads this flag via
          GET /api/system/trial-mode)
        - No wallet checks, no low-balance popups, no Razorpay prompts
          for coach services

    CLIENT_TRIAL_MODE = False  -> every coach payment flow is live again,
        exactly as before. No other change is needed anywhere.

NOT affected by this flag (always live):
    - Premium Plan subscription/upgrades (₹149/month)
    - Wallet recharge (Razorpay)
    - All non-payment functionality

The frontend fetches this value from /api/system/trial-mode on page load
(cached in localStorage between loads), so flipping this constant and
redeploying the backend flips the ENTIRE system — no frontend edit needed.

Optional override without a code change: set the CLIENT_TRIAL_MODE
environment variable to "true"/"false" — it wins over the constant below.
"""

import os

_DEFAULT = True  # <— flip to False after the 10-day client trial

_env = os.getenv("CLIENT_TRIAL_MODE")
CLIENT_TRIAL_MODE: bool = (_env.strip().lower() in ("1", "true", "yes", "on")) if _env else _DEFAULT

# ══════════════════════════════════════════════════════════════════════
# PLATFORM MONETIZATION POLICY (permanent — NOT the temporary trial above)
# ══════════════════════════════════════════════════════════════════════
# PLATFORM_CHARGES_FREE = True  →  ALL platform/expert-service charges are
# ₹0 for EVERY user (basic and premium alike): diet/workout verification,
# expert reviews, expert chat, coaching requests, nutritionist requests.
# The ONLY payment in ZITLAS is the Premium Membership subscription
# (₹149/month or ₹999/year via routes/payment.py membership endpoints).
# Premium differentiates on priority handling, higher limits, and ad-free —
# never on access or fees. The whole payment infrastructure stays intact;
# flipping this to False re-enables per-service pricing with no other
# code change (same single-switch pattern as CLIENT_TRIAL_MODE).
_env_free = os.getenv("PLATFORM_CHARGES_FREE")
PLATFORM_CHARGES_FREE: bool = (
    _env_free.strip().lower() in ("1", "true", "yes", "on")
) if _env_free else True

print(f"[TRIAL CONFIG] CLIENT_TRIAL_MODE = {CLIENT_TRIAL_MODE}"
      f"{' (from env)' if _env else ''} — coach payments "
      f"{'DISABLED (free trial)' if CLIENT_TRIAL_MODE else 'ACTIVE'}")
print(f"[TRIAL CONFIG] PLATFORM_CHARGES_FREE = {PLATFORM_CHARGES_FREE}"
      f"{' (from env)' if _env_free else ''} — expert services are "
      f"{'FREE for everyone (subscription-only monetization)' if PLATFORM_CHARGES_FREE else 'individually priced'}")
