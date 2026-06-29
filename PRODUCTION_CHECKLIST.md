# PRODUCTION CHECKLIST
Generated: 2026-06-29

---

## ✅ Files Cleaned

| File | Change |
|------|--------|
| `frontend/pages/dashboard/dashboard.js` | Removed `MOCK_CHATS` array; `renderChats()` now reads `zitlas_chats` from localStorage and shows empty state for new users |
| `frontend/pages/dashboard/dashboard.js` | Step counter seed changed from `{ today_steps: 6162, ... }` to zeros |
| `frontend/pages/dashboard/dashboard.js` | `initImageFallbacks()` now reads real user initials from localStorage instead of hardcoded `'AP'` |
| `frontend/pages/dashboard/dashboard.html` | Removed `arjun.png` from `#headerAvatar` and `#goalPlayerImg` |
| `frontend/pages/profile/profile.html` | Removed `arjun.png` from `#avatarImg`; removed `Arjun Patil` from `<h1>` |
| `frontend/pages/coaches/cprofile.js` | Cleared all 10 `reviews: [...]` arrays in `COACH_DB` — now `reviews: []` |
| `frontend/pages/coaches/cprofile.js` | Removed `console.trace("[WRITE zitlas_diet_plan]", ...)` |
| `frontend/pages/diet/diet.js` | Removed `console.trace("[WRITE zitlas_diet_plan]", ...)` |
| `frontend/pages/diet/diet.js` | `MOCK_NUTRITIONISTS` fallback now gated behind `IS_DEMO_MODE`; shows empty state in production |
| `frontend/pages/dashboard/ai-coach/ai-coach.js` | Removed `console.trace("[WRITE zitlas_diet_plan]", ...)` |
| `frontend/pages/login/login.js` | Removed `console.trace('Redirect executed')` |
| `frontend/pages/profile/membership/membership.js` | Replaced `alert()` with `showToast()` on upgrade |
| `frontend/pages/dashboard/dashboard.css` | Added `.dash-chat-empty` styles for the no-conversations state |

---

## ✅ Demo Data Removed

- [x] `MOCK_CHATS` (5 fake conversations on dashboard)
- [x] Hardcoded step count `6162` and `calories_burned: 204`
- [x] `arjun.png` in all 3 locations
- [x] `Arjun Patil` hardcoded name in profile.html
- [x] All 20 fake reviews across 10 expert profiles in COACH_DB
- [x] All `console.trace` debug calls (4 removed)
- [x] `alert()` blocking popup on membership upgrade
- [x] `MOCK_NUTRITIONISTS` as automatic fallback (now gated behind IS_DEMO_MODE)

---

## ⚠️ Remaining Hardcoded Values (Intentional / Low Risk)

| Item | Location | Status |
|------|----------|--------|
| `EXPERT_DEFAULTS` for 10 experts | `expert-profile.js` | Required — seeds expert dashboard profile on first login |
| `EXPERT_DB` with 10 expert records | `expert-dashboard.js` | Required — these are the real expert profiles |
| `COACH_DB` with 10 coach records | `cprofile.js` | Required — real coach profiles, reviews now empty |
| `EXPERT_ACCOUNTS` dict | `login.js` | Required — email-to-id mapping for expert login |
| `demo_` prefix on fallback auth token | `login.js:253`, `dashboard.js:611` | Low risk — cosmetic; only used when Firebase not configured |
| `demo_google_` token on Google button | `dashboard.js:639` | Medium risk — Google auth button does not call real OAuth; replace when Google Sign-In is wired |
| Wallet coupon codes (WELCOME100, etc.) | `wallet.js:41` | Low risk — shown as reference codes; no redemption backend |
| `MOCK_NUTRITIONISTS` array definition | `diet.js` | Kept but fully gated behind `IS_DEMO_MODE=false` |

---

## 🧪 Manual Testing Steps

### New User Flow (Critical Path)

1. Clear all localStorage (`localStorage.clear()` in browser console)
2. Open `dashboard.html`
   - [ ] Header avatar shows initials SVG or blank — NOT `arjun.png`
   - [ ] Goal panel player image is blank — NOT `arjun.png`
   - [ ] Step counter ring shows 0 steps, 0 calories, 0 km
   - [ ] Chat section shows "No conversations yet" empty state — NOT fake Priya Sharma / Arjun Patil chats

3. Open `profile.html`
   - [ ] Name shows blank — NOT "Arjun Patil"
   - [ ] Avatar shows blank or initials — NOT `arjun.png`
   - [ ] Role badge shows "Basic Member" (no membership saved → defaults to basic)
   - [ ] Membership card subtitle shows "Current Plan: Basic"

4. Open `coaches/cprofile.html?id=ramesh`
   - [ ] "What Athletes Say" section is empty — NOT "Arjun Patil" fake review

5. Open `profile/membership/membership.html`
   - [ ] Click "Upgrade to Premium"
   - [ ] Toast appears — NOT browser `alert()` popup
   - [ ] Plan updates in UI

6. Open `diet.html` as athlete
   - [ ] Meal swap "Book Nutritionist" modal shows empty state or real data — NOT Dr. Priya Sharma / fake nutritionists

### Returning User (After Assessment)

7. Complete the AI assessment flow
   - [ ] Step counter still shows 0 until Health Connect connects
   - [ ] Diet plan renders from real AI output
   - [ ] Workout plan renders from real AI output

### Expert Login

8. Login as `ramesh@zitlas.com` / `expert123`
   - [ ] Dashboard shows pending reviews from `expert_plan_reviews` — NOT fake data
   - [ ] Stats (`statPending`, `statClients`, `statEarnings`) reflect real review count

---

## 🔴 Potential Risks

| Risk | Severity | Action Required |
|------|----------|-----------------|
| Google Sign-In button sets `demo_google_` token instead of real OAuth | **HIGH** | Wire real Google OAuth (`/api/auth/google`) before production |
| `MOCK_NUTRITIONISTS` still defined (just gated) — future developers could re-enable | **LOW** | Remove entirely once real nutritionist API is connected |
| Wallet coupon codes show in UI but cannot be redeemed | **LOW** | Remove coupon codes or wire redemption API |
| `EXPERT_ACCOUNTS` dict in login.js contains known expert email/password pattern | **MEDIUM** | Move to server-side auth when real expert accounts are provisioned |
| `expert-profile.js` auto-seeds `zitlas_expert_profile` on first load from `EXPERT_DEFAULTS` | **LOW** | Acceptable for now; experts edit their own profile after first login |
| Coach profile stats (sessions, clients, success rate) are hardcoded in `COACH_DB` | **MEDIUM** | Will need real data from backend API in a future release |

---

## 📁 New Files Created

| File | Purpose |
|------|---------|
| `frontend/config/app-config.js` | Central feature flags; `IS_DEMO_MODE = false` |
| `FINAL_PRODUCTION_AUDIT.md` | Complete demo data inventory |
| `PRODUCTION_CHECKLIST.md` | This file |
