# FINAL PRODUCTION AUDIT
Generated: 2026-06-29

---

## Demo Data Found

| File | Variable / Line | What it Contains |
|------|-----------------|------------------|
| `frontend/pages/dashboard/dashboard.js:11` | `MOCK_CHATS` | 5 fake chat entries (Priya Sharma, Arjun Patil, Neha Kulkarni, Rohan Deshmukh, Amit Desai) rendered into `#dashChatsList` for every user |
| `frontend/pages/dashboard/dashboard.js:1098` | `window.zitlasSteps` seed | Hardcoded `today_steps: 6162`, `calories_burned: 204`, `distance_km: 4.5` shown until Health Connect connects |
| `frontend/pages/diet/diet.js:29` | `MOCK_NUTRITIONISTS` | 3 fake nutritionists (Dr. Priya Sharma, Rahul Mehta, Nisha Patel) used as fallback when `zitlas_nutritionists` localStorage key is empty |
| `frontend/components/wallet.js:41` | `COUPONS` | 4 placeholder coupon codes (WELCOME100, FIT50, ZITLASPRO, HEALTHIFY) displayed in the wallet panel — not redeemable |
| `frontend/pages/profile/membership/membership.js:205` | `alert()` | `alert('Payment integration coming soon.\nThis is a demo upgrade.')` — browser-native blocking alert on upgrade |

---

## Hardcoded Users

| Name | Files | Risk |
|------|-------|------|
| `Arjun Patil` | `profile.html:59`, `dashboard.html:23`, `dashboard.html:125`, `dashboard.js:13` (MOCK_CHATS) | Wrong name displays to real users before JS overrides it (FOUC) |
| `Arjun Nair` | `cprofile.js:56`, `coaches.js:87`, `diet.js:1216`, `expert-dashboard.js:33`, `expert-profile.js:33` | Real expert profile — not demo data; intentional |
| `Ramesh Patil` | `cprofile.js:261`, `coaches.js:89`, `dietitian.js:26`, `expert-dashboard.js:83`, `login.js:222` | Real expert profile — not demo data; intentional |
| `Priya Sharma / Neha Kulkarni / Rohan Deshmukh / Amit Desai` | `dashboard.js:11–17` (MOCK_CHATS) | Completely fake — no real accounts |

---

## Hardcoded Reviews (Fake Social Proof)

| Location | Reviewer Name | On Which Expert |
|----------|---------------|-----------------|
| `cprofile.js:44` | Arjun Mehta | Rahul (nutritionist) |
| `cprofile.js:84` | Karan Mehta | Arjun Nair |
| `cprofile.js:89` | Riya Sharma | Arjun Nair |
| `cprofile.js:290` | Arjun Patil | Ramesh Patil |
| `cprofile.js:293` | Priya Desai | Ramesh Patil |
| (all remaining COACH_DB entries) | Various hardcoded names | All 10 expert profiles |

These render on the public coach profile pages as if they are real verified reviews.

---

## Seeded LocalStorage Keys

| Key | File | What is Written |
|-----|------|-----------------|
| `zitlas_token` | `login.js:253`, `dashboard.js:611,639` | `demo_<timestamp>` or `expert_<timestamp>` or `firebase_<uid>` |
| `zitlas_expert_profile` | `expert-profile.js:201` | Seeded from `EXPERT_DEFAULTS` on first load for known expert IDs |
| `zitlas_wallet` | `wallet.js:34` | Written on every add/deduct; starts at `{ balance: 0 }` — no fake balance |

---

## Debug Artifacts

| File | Line | Issue |
|------|------|-------|
| `diet.js:249` | `console.trace("[WRITE zitlas_diet_plan]", storage)` | Verbose stack trace in production |
| `ai-coach.js:2038` | `console.trace("[WRITE zitlas_diet_plan]", ...)` | Verbose stack trace in production |
| `cprofile.js:1770` | `console.trace("[WRITE zitlas_diet_plan]", storage)` | Verbose stack trace in production |
| `login.js:480` | `console.trace('Redirect executed')` | Stack trace leak |
| `dashboard.js:20,22,32` | Multiple `console.log` inside `renderChats` | Debug noise |

---

## Default Profile Images

| File | Location | Issue |
|------|----------|-------|
| `dashboard.html:22` | `<img src="../../assets/arjun.png" id="headerAvatar">` | Hardcoded Arjun Patil avatar in header — visible before JS loads |
| `dashboard.html:124` | `<img src="../../assets/arjun.png" id="goalPlayerImg">` | Hardcoded Arjun Patil in goal panel — visible before JS loads |
| `profile.html:44` | `src="../../assets/images/arjun.png"` | Same issue on profile page |
| `dashboard.js:710` | `makeFallbackSVG('AP', ...)` | Initials hardcoded as 'AP' (Arjun Patil) |
| `dashboard.js:715` | `makeFallbackSVG('AP', ...)` | Same |

---

## Fake Content

### Chats
`MOCK_CHATS` in `dashboard.js` — 5 fake conversations rendered into the dashboard chat section.  
No UI element hides them behind a data check. Every new user sees fake chat history.

### Reviews
Fake reviews hardcoded in all `COACH_DB` entries in `cprofile.js`. Displayed as verified user feedback on coach profile pages.

### Notifications
No fake notification objects found. The notification bell shows `'No new notifications'` toast — acceptable.

### Step Counter / Fitness Metrics
`window.zitlasSteps` seed in `dashboard.js` sets `today_steps: 6162` before Health Connect data loads. New users see fake progress ring filled to 61%.

### Wallet Coupons
`COUPONS` array in `wallet.js` contains 4 unredeemable placeholder coupon codes shown in the wallet panel to all users.

### Plans
No auto-seeded plans found. Diet/workout plans are only written when the user completes the AI assessment — correct.

---

## Production Risks

| Risk | Severity | File |
|------|----------|------|
| `MOCK_CHATS` rendered to all users regardless of auth state | **HIGH** | `dashboard.js` |
| Fake step count (6162) visible before Health Connect loads | **HIGH** | `dashboard.js` |
| Fake reviews on coach profiles — misleading social proof | **HIGH** | `cprofile.js` |
| `arjun.png` shows for ~100ms before JS overrides it (FOUC) | **MEDIUM** | `dashboard.html`, `profile.html` |
| `console.trace` in diet save path — stack dump in browser console | **MEDIUM** | `diet.js`, `ai-coach.js`, `cprofile.js` |
| `alert()` on Premium upgrade — blocks page, non-dismissible on some mobile browsers | **MEDIUM** | `membership.js` |
| MOCK_NUTRITIONISTS rendered when API data absent | **MEDIUM** | `diet.js` |
| Wallet coupon codes are fake / non-functional | **LOW** | `wallet.js` |
| `demo_` prefix in fallback auth token value | **LOW** | `login.js`, `dashboard.js` |
