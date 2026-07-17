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

print(f"[TRIAL CONFIG] CLIENT_TRIAL_MODE = {CLIENT_TRIAL_MODE}"
      f"{' (from env)' if _env else ''} — coach payments "
      f"{'DISABLED (free trial)' if CLIENT_TRIAL_MODE else 'ACTIVE'}")
