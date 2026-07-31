# ZITLAS Web → Flutter Migration Inventory

Snapshot date: 2026-07-29. Read-only audit of the existing web app (`backend/`, `frontend/` in this same repository — see note below) against the new Flutter app under `lib/`.

> **Repo layout note:** the task brief assumed a separate `zitlas` source project and an empty `zitlas_mobile` target. In reality there is no separate `zitlas` folder on disk (only zip/backup copies) — the source web app already lives inside *this* repository as `backend/` + `frontend/` (confirmed by `PROJECT_CONTEXT.md`, which documents that exact folder structure). `flutter create .` had already been run in-place, uncommitted, adding `lib/`, `android/`, `ios/`, etc. on top of the existing project. That scaffold step also deleted the previous Capacitor Android project (`android/app/src/main/java/com/zitlas/app/{MainActivity.java, health/HealthConnectManager.kt, health/HealthConnectPlugin.java, health/StepSensorPlugin.java}`, splash/launcher assets, `capacitor.settings.gradle`, etc.) — none of this is committed, so it's fully recoverable from git history (`git show HEAD:android/...`) if the native Health Connect/step-sensor plugin logic needs to be ported into a future Flutter platform channel. Nothing was deleted or restored during this session; this document treats `backend/`+`frontend/` as the authoritative source and `lib/` as the migration target.

## 1. Backend (unchanged — Flutter consumes it as-is)

`backend/main.py` mounts these routers (see `backend/routes/*.py`); full per-endpoint detail below. No backend code is modified by this migration.

CORS currently allows only `http://127.0.0.1:8000` / `http://localhost:8000` — **must be revisited** once the Flutter app talks to a deployed backend origin (native HTTP calls aren't subject to CORS, but Flutter Web would be).

Response shape is **not** uniform: three patterns are in use (`{"success": true, ...}`, raw Pydantic/domain object, or an ad hoc dict). The Flutter API client must use per-endpoint response models, not one generic envelope parser.

| Router file | Prefix | Status | Auth |
|---|---|---|---|
| `auth.py` | `/api/auth` | Stub only (`/health`). Real auth is 100% client-side Firebase Auth. | — |
| `player.py` | `/api/user` | Stub only (`/health`). | — |
| `diet.py` | `/api/diet` | Stub only (`/health`) — real diet logic lives under `/api/ai/*`. | — |
| `ai.py` | `/api/ai` | **Primary AI surface**, 21 endpoints (chat, zino-chat, swot, training-plan, diet-plan, goal-plan, elite-weekly-plan, coach-recommend, mental/physical/nutrition questions+assessment, nutrition-weekly-plan, swap-meal, coach-start/chat/finalize). | None |
| `assessment.py` | `/api/assessment` | `/analyze` (instant calc, no LLM), `/generate-plan` (full 3-brain pipeline: assessment → RAG → LLM diet+workout → precautions). | None |
| `rag.py` | `/api/rag` | `/query`, `/status`. No frontend caller found — likely internal-only (invoked from within `/api/ai/*`/`/api/assessment/*` handlers). | None |
| `chat.py` | `/api/chat` | `/upload` (multipart image, ephemeral local disk fallback for chat attachments). | None |
| `meal_ai.py` | `/api/meal` | `/estimate-nutrition` (meal-photo vision AI, cost-gated). | **Firebase token** |
| `certificates.py` | `/api/certificates` | `/verify` (AI cert OCR/verification; does not persist the file). | None |
| `review.py` | `/api/review` | Legacy **in-memory, non-persistent** review request store (`submit`, `expert/{id}`, `{id}`, `{id}/status`, `{id}/approve`). Data lost on every restart; no caller-identity check. | None |
| `review_apply.py` | `/api/review` (same prefix) | `/apply` — server-authoritative write of an approved expert plan onto `users/{uid}.dietPlan`/`.workoutPlan`, with a planId "apply-gate". | **Firebase token** |
| `support.py` | `/api/support` | `/contact` (SMTP email to support inbox). | None |
| `system.py` | `/api/system` | `/trial-mode`, `/kb-status`, `/test-push` (FCM test send). | None |
| `admin.py` | `/api/admin` | Certificate approve/reject, expert deactivate/approve/recompute-verification, grant-admin. | **Firebase token + admin claim** |
| `coaching.py` | `/api/coaching` | Personal Coaching escrow: `/request` (reserve), `/accept`, `/withdraw`, `/reject`. Atomic Firestore transactions. | **Firebase token** |
| `payment.py` | `/api/payment` | Razorpay wallet top-up (`/create-order`,`/verify`), Premium membership (`/membership/create-order`,`/membership/verify`, ₹149/mo or ₹999/yr, server-priced), generic escrow-style `/charge` for reviews/coaching-meal-requests. | **Firebase token** |

Payments/subscriptions summary: wallet top-up (Razorpay) + the one true subscription (Premium membership) + a generic `/payment/charge` used for pay-per-service (expert review, coaching meal request) + coaching's own request/accept/withdraw/reject escrow flow. `GET /api/system/trial-mode` tells the client whether charges are currently waived platform-wide.

## 2. Frontend page → Flutter feature map

Legend: **API** = backend calls, **FS** = Firestore collections, **LS** = localStorage keys (become local-cache/model concerns in Flutter, not literal SharedPreferences string keys).

| Web page(s) | Flutter target (`lib/features/...`) | Notes |
|---|---|---|
| `pages/login/login.{html,js,css}` | `features/auth` | Firebase email/password + Google sign-in, password reset, role picker (athlete/expert) for new Google users. **No anonymous/guest auth** — removed intentionally on web. |
| `pages/dashboard/dashboard.*` | `features/dashboard` | Home hub: chats, activity ring, goal card, health-status card, expert-review promo, notifications entry. Has dead demo-login code (`/api/auth/login`, `/api/auth/google` calls are commented-out TODOs) — do not port as if live. |
| `pages/dashboard/ai-coach/ai-coach.*` | `features/assessment` (+ `features/ai_coach` for the Zino-branded parts) | 11-step onboarding wizard → `POST /api/assessment/generate-plan`. Full-screen flow, no bottom nav. |
| `pages/dashboard/weekly-plan/weekly-plan.*`, `pages/dashboard/training/day.*` | `features/workout` | Read-only render of the AI/expert/coach plan; 3-source priority chain: `zitlas_expert_review` (legacy) → `zitlas_roadmap` → `zitlas_workout_plan`. Live Firestore `personal_coaching/{uid}`, `coaching_plans/{uid}` subscriptions. |
| `pages/diet/diet.*` | `features/diet` | Largest/most complex page. The "authoritative pattern" schema (`originalDietPlan`/`currentDietPlan`/`expertModifications`) — see §3 of `CLAUDE.md`. Meal swap, AI photo nutrition estimate, review-request flow, Personal Coaching diet mode, version history. |
| `pages/coaches/coaches.*`, `pages/dietitian/dietitian.*` | `features/experts` | Expert marketplace listings from Firestore `experts` (approved-only), search/sort/filter. |
| `pages/coaches/cprofile.*` | `features/experts` (profile) + `features/coaching` + `features/chat` | Athlete-facing expert profile: booking, chat (text/image/voice call), Personal Coaching request/withdraw, wallet payments, `_buildDietStorageFromReview`/`_buildWorkoutStorageFromReview` (athlete "accept" half of the modification pattern). |
| `pages/coaches/expert-review.*` | `features/reviews` | Athlete's detail/diff view for one expert review request. |
| `pages/experts/expert-dashboard.*` | `features/expert_dashboard` | Expert control room: review queue, coaching accept/reject, editable diet/workout builder, chat/calls, cert upload, admin-only deactivate. Only non-IIFE JS file on web — flag for the port, not a pattern to keep. |
| `pages/experts/modify-diet.*`, `modify-workout.*` | `features/expert_dashboard` (sub-flow) | Standalone expert plan editors, `POST /api/review/apply`. |
| `pages/experts/pricing.*` | `features/expert_dashboard` (settings) | Expert's own service pricing; edits are **not retroactive** to in-flight requests (price is snapshotted). |
| `pages/profile/profile.*` | `features/profile` | Account hub/menu. |
| `pages/profile/personal-info/*` | `features/profile` (edit) | Name/age/height/weight, unit conversion, per-user theme preference. |
| `pages/profile/membership/membership.*` | `features/membership` | Plan tiers + weekly usage limits, Razorpay membership purchase. |
| `pages/profile/help-support/*` | `features/profile` (support) or standalone `features/support` | `POST /api/support/contact`. |
| `pages/notifications/notifications.*` | `features/notifications` | Deliberately generic renderer over Firestore `notifications` — no hardcoded type switch. Keep that design in Flutter. |
| `pages/admin/admin-review.*`, `pages/admin/cert-audit.html` | *(not in scope for mobile — ops-only, unreachable from any in-app nav on web too)* | Admin tooling; can stay web-only unless requested otherwise. |
| `components/navbar.js` | `core/widgets` (`AppShell` bottom nav) | 5 tabs: Home/Diet/Training/Experts/Profile. Also owns "hide navbar while any modal is open" logic — reimplement via route-level `Scaffold` control in Flutter, not a MutationObserver equivalent. |
| `components/wallet.js` | `features/payments` | Wallet balance + locked/reserved amount, top-up via Razorpay order/verify. |
| `components/coaching-workspace.js` | `features/coaching` | Shared full-screen workspace for both athlete and coach roles during an active Personal Coaching relationship. |
| `assets/js/zino.js` | `features/zino` | AI companion chat + onboarding spotlight tutorial; `POST /api/ai/zino-chat`. |
| `assets/js/health-connect.js`, `step-sensor.js`, `activity-service.js`, `streak-service.js`, `activity-sync.js`, `step-permissions.js`, `health-status.js`, `daily-score.js` | `features/health` | Step-counter system — **the most architecturally sensitive port**: requires reimplementing native Health Connect + hardware step-counter access as Flutter platform channels/plugins (the deleted Capacitor Java/Kotlin plugins are the reference implementation, recoverable from git history). Out of scope for this foundation pass. |
| `assets/js/cloud-sync.js` | `core/services` + per-feature repositories | Cache-through mirror making Firestore `users/{uid}` the source of truth while preserving today's "flat field" shape. |
| `assets/js/coaching-gate.js`, `coaching-reset.js`, `review-sync.js` | `features/coaching`, `features/reviews` | Cross-cutting state consistency helpers — canonical "is coaching active" check, reset-on-cancel cleanup, live review sync. Reimplement as repository/provider logic, not ad hoc per-screen checks. |
| `assets/js/expert-profile.js`, `expert-review-promo.js` | `features/experts`, `features/dashboard` | |
| `assets/js/certificate-manager.js`, `verified-badge.js` | `features/expert_dashboard`, `features/experts` | Cert upload → AI verify (backend) → Storage upload (client) → admin approve (backend, sets custom claim). |
| `assets/js/payment-service.js` | `features/payments` | Central charge engine; `attemptCharge()` wraps `/api/payment/charge` with a client-side Firestore transaction for idempotency. |
| `assets/js/pending-requests-bar.js` | `features/experts` (shared widget) | Floating pending-status bar. |
| `assets/js/push-notifications.js`, `notification-center.js` | `features/notifications` | FCM token → `users/{uid}.pushTokens` (arrayUnion); separate in-app `notifications` Firestore feed (not the same thing as a push). |
| `assets/js/chat-attachments.js`, `webrtc-call.js`, `call-ui.js` | `features/chat` | Image attachments (Storage direct-upload, backend fallback), WebRTC voice call signaled entirely over Firestore (STUN-only, no TURN configured — note for mobile network reliability). |
| `assets/js/i18n.js` | `core/config` (localization) | Inline translation table, no network. Consider Flutter's `intl`/ARB pipeline instead of a hand-rolled table. |
| `assets/js/geo-location.js` | `features/dashboard` or `features/health` | One-time optional location permission prompt for "Geo-Aware Food Intelligence". |
| `frontend/config/app-config.js` | **Do not port** | Orphaned — never `<script>`-included by any page on web; the one consumer (`diet.js`) always sees it as undefined. Dead code. |

## 3. Firebase / Firestore (shared project — no new Firebase project)

**Project:** `zitlas-b8677` ("shared with ZITLAS Hiring"). SDK on web: Firebase JS v10.7.1 compat. Flutter already depends on `firebase_core ^4.12.1`, `firebase_auth ^6.5.6`, `cloud_firestore ^6.7.1`, `firebase_messaging ^16.4.3`.

**Web config** (from `frontend/assets/js/firebase-config.js` — reference values only, **not usable as-is for Android/iOS**, see §4):
```
apiKey:            AIzaSyAR4Q0Ldur2Y2N8iHwsAmPS4V2cWCvf_pg
authDomain:        zitlas-b8677.firebaseapp.com
projectId:         zitlas-b8677
storageBucket:      zitlas-b8677.firebasestorage.app
messagingSenderId: 203730393646
appId (web):       1:203730393646:web:f1f4776d8b0d1134bf1dbf
measurementId:     G-MK3CYXXS8Q
```

**Auth methods to reimplement:** email/password (sign up + sign in + `fetchSignInMethodsForEmail` pre-check), Google Sign-In, password reset email. No anonymous auth. Role picker on first Google sign-in (athlete vs. expert) when no `users/{uid}` doc and no matching `experts` doc exists.

**Client-side account isolation (must have a Flutter equivalent):** the web app purges all user-scoped local cache whenever the signed-in uid differs from the last cached "owner" uid — this closed a real cross-account data-leak bug. Flutter's local cache layer needs the same per-uid purge-on-switch guard from day one of auth being wired up.

**Firestore collection map** (path → purpose → security model):

| Collection | Purpose | Access model |
|---|---|---|
| `users/{uid}` (+`activity/{date}`, `weight_log/{date}` subcollections) | Profile, cloud-synced app state (goal/assessment/diet/workout/roadmap/personalInfo), streaks, push tokens. `wallet`/`membership`/`role`/`roles`/`expert_status` are backend-only fields even though they live on this doc. | Owner-only, except `activity`/`weight_log` also readable by an active coach. |
| `experts/{uid}` | Public expert profile + `pricing` map. `verified`/`approved`/`verification*` are backend-only. | Signed-in read; owner create/update (trust fields locked). |
| `expert_certificates/{certId}` | Cert upload + AI verification result. Verdict fields backend-only. | Owner or admin. |
| `review_requests/{id}`, `expert_reviews/{id}` | Paid single-review workflow + its finalized content. `paymentStatus`/`walletTransactionId` backend-only. | Athlete (`userId`) or `expertId`. |
| `personal_coaching/{athleteUid}` | Active paid coaching relationship (escrow). Create/delete backend-only. | Athlete or `coachId`. |
| `personal_coach_requests/{id}` | Pre-payment coaching request step. Backend write-only. | Athlete or coach read. |
| `coaching_plans/{athleteUid}` (+`versions/{id}`) | Coach-authored plan content + version history. | Athlete owner or active coach; `versions` write is coach-only. |
| `coaching_meal_requests`, `meal_checkins`, `workout_checkins`, `weekly_reviews`, `health_alerts`, `coaching_notifications` | Day-to-day coaching workflow artifacts. | Participant (athlete/coach) gated. |
| `meal_snap_logs/{uid}/{date}/{logId}` | Personal AI meal-photo log. | Owner only. |
| `chat_rooms/{id}` (+`messages`, `calls`, `calls/{id}/callerCandidates`,`calleeCandidates`) | 1:1 chat + WebRTC call signaling. Room id = `chat_<athleteId>_<coachId>`. | `participants[]`-gated; messages/calls create+read only, no update/delete. |
| `notifications/{id}` | In-app notification feed (distinct from FCM push; no fan-out Cloud Function exists yet). | Recipient-only read; cross-user create allowed but constrained. |
| `wallet_transactions/{id}`, `razorpay_orders/{id}` | Money ledger. | **Deny-all for clients** — Admin SDK only. |

`firestore.indexes.json` is currently **empty** — any new compound `where`+`orderBy` query introduced in Flutter will likely need a new composite index.

**Storage** (`zitlas-b8677.firebasestorage.app`): chat images at `{prefix}/{uid}/{ts}_{rand}.jpg` (client-compressed, with a `/api/chat/upload` backend fallback), expert certificates at `certificates/{expertId}/{id}.{ext}`. Storage rules are flagged in-source as **currently world-readable/writable** — tighten as part of this migration, don't just mirror them. Note: profile photos are stored as base64 inline in Firestore (`users/{uid}.personalInfo.photo`, capped ~180KB), not Storage — an anti-pattern worth fixing in Flutter (use real Storage uploads) rather than copying.

**FCM:** token stored at `users/{uid}.pushTokens` (`arrayUnion`, multi-device). `frontend/firebase-messaging-sw.js` is web-only and has no Flutter equivalent; `firebase_messaging` package's Android/iOS notification handling replaces it directly.

**No Firebase Cloud Functions exist** — everything privileged goes through the FastAPI backend using the Admin SDK. Flutter therefore needs two data-access paths, same as web: direct Firestore client SDK (rules-gated) for everything in the table above, and REST calls to the existing FastAPI backend for privileged operations (coaching escrow, payments, admin, review-apply, meal photo AI).

## 4. Firebase Android/iOS registration — required, not yet done

No `google-services.json` or `GoogleService-Info.plist` exists in this repo. The web `appId` above **cannot** be reused for native apps — Android/iOS each need their own app registered under the `zitlas-b8677` project with their own platform-specific `appId`. Per the task's instruction not to fabricate these values, here is exactly what's needed before Firebase will initialize on-device:

1. Register an Android app on `zitlas-b8677` in the Firebase console (or via `flutterfire configure --project=zitlas-b8677`) with package name **`com.zitlas.app`** (updated in this session — see §5) → download `google-services.json` → place at `android/app/google-services.json`.
2. Register an iOS app on the same project with bundle id **`com.zitlas.app`** (updated in this session to match Android, since no iOS app previously existed) → download `GoogleService-Info.plist` → place at `ios/Runner/GoogleService-Info.plist`.
3. Either run `flutterfire configure` (generates `lib/firebase_options.dart` automatically, recommended) or wire the two files manually per `firebase_core`'s standard Android/iOS setup (Gradle `google-services` plugin + `GoogleService-Info.plist` added to the Xcode project).
4. `lib/core/config/firebase_bootstrap.dart` (added this session) is ready to call `Firebase.initializeApp()` once step 3 is done — it is **not called from `main.dart` yet** on purpose, so `flutter analyze`/`flutter test` stay green without a real config present.

This app was explicitly told **not** to run `flutterfire configure` or invent config values — that remains a manual step for whoever holds Firebase console access.

## 5. Changes made to `android/`/`ios/` this session

User-confirmed decision: Android application ID changed from Flutter's default `com.example.zitlas_mobile` to **`com.zitlas.app`** (matching the original Capacitor Android app, for Play Store/Firebase continuity) — `android/app/build.gradle.kts` (`namespace`, `applicationId`), `AndroidManifest.xml` (`android:label` → "ZITLAS"), and the Kotlin package moved to `android/app/src/main/kotlin/com/zitlas/app/MainActivity.kt`. iOS bundle id changed from Flutter's auto-generated `com.zitlas.zitlasMobile` to `com.zitlas.app` for platform consistency (no prior iOS app existed to preserve). No other native code was touched; the deleted Capacitor plugin sources remain recoverable from git history for the future Health Connect/step-sensor port.

## 6. Explicitly out of scope for this pass

Per the task brief, this pass covers audit + inventory + architecture + app shell/theme/routing/service foundation only. Not implemented yet: real Firebase Auth wiring, any screen's real business logic beyond a placeholder, the native health/step-sensor platform channel, payments/Razorpay integration, WebRTC calling, and Firebase project registration (§4).

---

# Phase 4 — Expert Dashboard migration

Source of truth: `frontend/pages/experts/expert-dashboard.{html,css,js}` (627 / 2880 / 5227 lines), plus the shared modules it loads (`certificate-manager.js`, `payment-service.js`, `notification-center.js`, `coaching-gate.js`).

## 4.1 Section-by-section parity

| Website section | Flutter | Data source | Status |
|---|---|---|---|
| `.ed-header` (avatar, name, role, online dot, bell, logout) | `_ExpertHeader` | `experts/{uid}` live + `notifications` unread count live | **Migrated** |
| `.ed-profile-card` (name/role/rating/reviews/fee/experience) | `_ProfileCard` | `experts/{uid}` live | **Migrated** |
| `.ed-stats-grid` (4 tiles) | `_StatsGrid` | derived from `review_requests` + `chat_rooms` + `experts.fee` | **Migrated** (see §4.3) |
| Quick Actions (2 buttons) | `_QuickButton` ×2 | — (section navigation) | **Migrated** |
| My Athletes | `_AthleteTile` | `personal_coaching where coachId==uid` live | **Migrated** |
| Reviews Inbox + 3 tabs + badges | `ExpertReviewsSection` | `review_requests where expertId==uid` live | **Migrated** |
| Review accept (wallet charge) | `acceptReview` | `POST /api/payment/charge` then status → `in_progress` | **Migrated** |
| Review reject (+ bundled sibling) | `rejectReview` | `review_requests` update ×2 | **Migrated** |
| Review complete | `completeReview` | `review_requests` update | **Migrated** |
| Personal Coaching + 3 tabs + badges | `ExpertCoachingSection` | `personal_coach_requests where expertId==uid` live | **Migrated** (blocked at runtime, §4.4) |
| Coaching accept / decline | `respondToCoaching` | `POST /api/coaching/accept` \| `/reject` w/ ID token | **Migrated** |
| Client Chats list | `ExpertChatsSection` | `chat_rooms where participants array-contains uid` live | **Migrated** |
| Chat thread + send | `ExpertChatScreen` | `chat_rooms/{id}/messages` live; room-merge + `doc(id).set()` | **Migrated** |
| Chat read-only lock when coaching ended | `isChatReadOnly` | `personal_coaching.status == 'ended'` | **Migrated** |
| My Profile (full card, stats, fees) | `ExpertProfileSection` | `experts/{uid}` live | **Migrated** |
| Edit Profile modal | `showEditProfileSheet` | merge-write to `experts/{uid}` (editable fields only) | **Migrated** |
| Certificates list | `_CertificatesCard` | `expert_certificates where expertId==uid` live | **Migrated (read)** |
| Certificate upload | — | `POST /api/certificates/verify` + Firebase Storage | **Deferred** (§4.2) |
| Pricing & Services card | `_PricingCard` | — | **Card migrated**, editor deferred (§4.2) |
| Logout (header + profile) | `performSignOut` | shared with athlete side | **Migrated** |
| Delete Account (2-step) | `_DeleteAccountButton` | `POST /api/admin/experts/deactivate` | **Migrated** |
| `.ed-navbar` 5 tabs + badges | `_ExpertNavBar` | live counts | **Migrated** |

## 4.2 Deliberately deferred (with reason)

- **Certificate upload** — needs multi-format file picking including **PDF**. `file_picker` is excluded from this project by standing instruction (it broke the Android build), and `image_picker` cannot select PDFs. Viewing/status is migrated; uploading stays on the web portal.
- **Pricing editor** (`pricing.html`) — a separate page, not dashboard content. The dashboard-facing card is reproduced; the review fee itself is editable via Edit Profile.
- **Plan editors** (`modify-diet.html` 695 ln, `modify-workout.html` 409 ln) — separate full pages with their own diff/merge schemas; a phase of their own. Accept/chat/complete all work without them.
- **Coaching Workspace** (`coaching-workspace.js`, 2164 ln) — a shared athlete+coach surface, not expert-dashboard-specific. "Open" on My Athletes falls back to the chat thread, which is exactly the website's own documented fallback when the workspace module is unavailable (ED:110).
- **WebRTC voice calls** (`webrtc-call.js` + `call-ui.js`) — needs a native WebRTC dependency; STUN-only with no TURN server configured even on web.
- **Chat image attachments** — depends on the same upload pipeline as certificates.
- **Profile photo upload** in Edit Profile — the website stores it as an inline base64 dataURL on the Firestore doc (capped at ~900 KB, ED:2740), an anti-pattern worth replacing with real Storage uploads rather than porting as-is.

## 4.3 Behaviour corrections vs. the website (deliberate, documented)

1. **`#statMessages` is dead on the website** — hardcoded `0` at ED:326 and never recomputed, so the tile permanently reads "No new messages right now." Rather than reproduce a broken counter, the tile shows **Active Chats** from the live `chat_rooms` listener. Same position, same icon, real data.
2. **Two competing stat writers.** The website computes `statClients`/`statEarnings` twice with different rules — `updateDashboardStats` (ED:863, from Firestore) vs `renderInbox` (ED:4560, from a `localStorage` cache) — and whichever runs last wins. Flutter uses the Firestore-derived definitions only, since Firestore is authoritative and the localStorage mirror is a web-only offline cache.
3. **No `localStorage` mirror.** The website funnels Firestore snapshots through `localStorage['expert_plan_reviews']` / `['zitlas_chats']` and renders from the cache. Flutter renders directly from the live snapshots — same data, one less layer that can go stale.

## 4.4 Pre-existing defect found (NOT fixed — rules are out of scope)

`personal_coach_requests` documents are written by the backend with **`expertId`** (`backend/routes/coaching.py:229`) and contain no `coachId` field. But `firestore.rules:163-166` grants read access on:

```
resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid
```

An expert's query is `.where('expertId', '==', uid)` (ED:1399 on web, `watchCoachingRequests` in Flutter). Firestore rejects a query it cannot prove is authorized, so this listener returns **permission-denied** — on the website too. The expert's Coaching tab cannot load its requests for anyone.

**Fix required (one line, Firebase console or `firestore.rules`):** add `|| resource.data.expertId == request.auth.uid` to that read rule. Until then the Flutter Coaching tab shows an explicit "server configuration issue — contact support" state instead of a misleading network error, and every other section keeps working (per-listener error isolation).

# Phase 3A (re-audit) — Athlete Dashboard COMPLETE parity pass

Source of truth: `frontend/pages/dashboard/dashboard.{html,css,js}` (453 / 2279 / 2173 lines) plus its full dependency tree — 20 shared JS modules totalling 6,873 lines. ~11,800 lines audited.

**Source-path note:** `C:\Users\Atharva\Desktop\zitlas` does not exist. The newest website source is `zitlas_mobile/frontend` (diet.js Jul 27) — `zitlas_BACKUP_27_JUL` holds an older copy (diet.js Jul 18), `zitlas_GIT_CLEAN` has no frontend at all.

## 3A.1 Parity matrix

| Website feature | Source | Data source | Flutter | Status |
|---|---|---|---|---|
| Header avatar → profile | `applyProfileImages()` | `personalInfo.photo` → `users.photo` | `DashboardHeader` | **COMPLETE** |
| Header logo | dashboard.html:48 | asset | `Image.asset(logo.png)` | **COMPLETE** |
| Notification bell + unread dot | `initNotifBell()` | `notifications where userId==uid && isRead==false` (live) | `DashboardHeader` | **COMPLETE** |
| Wallet balance button | `wallet.js buildButton()` | `users/{uid}.wallet` (`balance - reserved`) | `_WalletButton` → `/wallet` | **COMPLETE** (this pass) |
| Time-based greeting + first name | `initGreeting()` | `personalInfo.fullName` | `GreetingSection` | **COMPLETE** |
| Goal card: title/ring/pct/current/target/days-left/dates | `renderGoalCard()` | `users/{uid}.goal` (live) | `GoalCard` | **COMPLETE** |
| Goal-card player avatar panel | `applyProfileImages()` | same photo chain, initials fallback | `_GoalPlayerPanel` | **COMPLETE** (this pass) |
| Set Goal modal (5 type pills, 5 validation rules) | `initSetGoalModal()` | writes `users/{uid}.goal` | `set_goal_sheet.dart` | **COMPLETE** |
| Reset Goal modal + full data clear | `initResetGoalModal()` | `GOAL_SCOPED_FIELDS` → null | `reset_goal_dialog.dart` | **COMPLETE** |
| Expert review promo | `expert-review-promo.js` | plan existence + coaching status | `ExpertReviewPromoCard` | **COMPLETE** |
| **Health Status / Recovery Mode card** | `health-status.js` (634 ln) | `shared_preferences` + activity day doc | `HealthStatusCard` | **COMPLETE** (this pass) |
| — 7 statuses, 15 symptoms, 11 body parts | `STATUSES/SYMPTOMS/BODY_PARTS` | — | `health_status.dart` | **COMPLETE** |
| — deterministic adjustment engine (safety gate + 6 branches) | `computeAdjustments()` | rule-based, no LLM | `computeHealthAdjustments()` | **COMPLETE** |
| — coach alert (3 writes) | `alertCoach()` | `health_alerts`, `coaching_notifications`, `chat_rooms/{id}/messages` | `sendHealthAlert()` | **COMPLETE** |
| — self notification | `notifySelf()` | `notifications` | `sendSelfNotification()` | **COMPLETE** |
| — recovery timeline + tally | `renderCard()` | `zitlas_health_history` | `_Timeline` | **COMPLETE** |
| — clear status chip | `hsClearStatusChip` | removes override only | `clearHealthStatus()` | **COMPLETE** |
| SWOT widget (4 quadrants, score chips, archetype pill) | `renderSwotWidget()` | `users/{uid}.swot` (live) | `SwotWidgetCard` | **COMPLETE** |
| Activity ring + count-up + 3 stats | `renderStepCounterCard()` | `users/{uid}/activity/{date}` | `ActivityCard` | **COMPLETE** |
| — weekly Mon–Sun strip | `getWeeklySummary()` | 7-day activity docs | `_WeekStrip` | **COMPLETE** (this pass) |
| — adaptive goal suggestion + 1-tap apply | `getAdaptiveGoalSuggestion()` | 7-day avg vs `dailyStepGoal` | `_AdaptiveGoalLine` | **COMPLETE** (this pass) |
| — Recovery Mode line + rest-day copy | `getEffectiveGoal()` | `goalEffective`/`recoveryMode` on day doc | `ActivityCard` | **COMPLETE** (this pass) |
| — 4 status messages incl. "exceeded by X" | `getStatusMessage()` | — | `activityStatusMessage()` | **COMPLETE** (this pass) |
| — streak badge | `d.streak_days` | `users/{uid}.currentStreak` | `ActivityCard` | **COMPLETE** |
| Daily Score (overall + 5 chips, hidden when no data) | `renderDailyScoreCard()` | activity + `meal_checkins` | `DailyScoreCard` | **COMPLETE** |
| Wellness: water +250/+500, sleep, weight + delta | `renderWellnessCard()` | activity doc + `weight_log` | `WellnessCard` | **COMPLETE** |
| Today's Training card | `renderTrainingWidget()` | `users/{uid}.workoutPlan` | `TrainingWidgetCard` | **COMPLETE** |
| Recent Chats + empty state | `renderChats()` | `chat_rooms` | `RecentChatsCard` | **COMPLETE** |
| Quick Stats (4 cards) | `initStatCountUp()` | **hardcoded `7/5/3/4.50` on the website** | `QuickStatsRow` | **COMPLETE** (faithful) |
| Zino AI assistant launcher | `zino.js` `#znFab` | — | `_ZinoFab` → `/zino` | **COMPLETE** (this pass) |
| Bottom nav (5 tabs) | `navbar.js` | — | `StatefulShellRoute` | **COMPLETE** |

## 3A.2 Confirmed DEAD on the website — deliberately not reproduced

Verified by grepping `dashboard.html` for each selector the handler binds to (all return 0 matches), and by checking `init()`'s call list:

- **Weekly Plan modal** — `#weeklyPlanModal` exists in the HTML but `openWeeklyPlanModal()` is **never called**; `initWeeklyPlanModal()` wires the button to `window.location.href = './weekly-plan/weekly-plan.html'` instead. The Flutter button navigates to `/training`, matching the real behavior.
- **Roadmap** (`renderRoadmap`, `renderProfileFallbackRoadmap`, `selectRoadmapDay`, `renderDayTraining`, `initRoadmapCards`) — `.roadmap-card` / `#roadmapScroll` / `.roadmap-scroll` absent; `renderRoadmap()` is not in `init()`.
- **Task cards** (`initTaskCardClick`) — `.task-card` absent. It also calls `openTrainingModal()`, which **is never defined anywhere** — it would throw if ever reached.
- **`initViewButtons`** — `#viewRoadmapBtn` / `#viewAllTraining` absent.
- **`initStreakPulse`** — `.streak-card` absent.
- **Login modal** — a demo stub: the submit handler has `/* TODO: real API call */` and just writes `localStorage['zitlas_token'] = 'demo_' + Date.now()`. Flutter's router already guards `/dashboard` behind real Firebase auth, so this modal has no native equivalent by design.

## 3A.3 Behaviour notes (deliberate, documented)

1. **Quick Stats are hardcoded on the website** — `7 / 5 / 3 / 4.50` are literals in both `dashboard.html` and `initStatCountUp()`; no data source is ever read. Reproduced verbatim rather than silently "fixing" them, since the instruction is exact parity with the real site. Flagged here so it's a conscious product decision, not an oversight.
2. **Health status persistence uses `shared_preferences`, not Firestore.** The website stores `zitlas_health_today` / `zitlas_health_history` in `localStorage` only — there is no Firestore collection for health status (only `health_alerts` when a coach is active). `shared_preferences` is the faithful native equivalent; inventing a Firestore collection would have been a schema change.
3. **Weekly strip / adaptive goal read Firestore, not a local 90-day cache.** The website's `localStorage` history is a mirror of the day docs it already writes via `_syncDayToFirestore`. Flutter reads the authoritative `users/{uid}/activity/{date}` records directly — same data, one less layer.

## 3A.4 Still deferred (with reason)

- **Native step capture** (Health Connect + hardware `TYPE_STEP_COUNTER`) — the Capacitor plugins were deleted when this repo became a Flutter project; needs a Flutter platform channel or a Health Connect package. Everything the dashboard *renders* from the day doc is at parity; only the on-device writer is missing, so steps stay at whatever the web app last synced.
- **Zino conversation UI** — the launcher is wired to the existing `/zino` route; the assistant screen itself is its own migration phase.
- **Wallet panel internals** — button + `/wallet` route wired; the top-up/transaction panel (941 ln, Razorpay checkout) is its own phase.

# Phase 5 — Diet migration

Source of truth: `frontend/pages/diet/diet.{html,css,js}`, plus `ai-coach.js` (plan generation/save), `cprofile.js` (`_buildDietStorageFromReview`/accept flow), `expert-dashboard.js` (review unwrap logic), `experts/modify-diet.js` (expert editor's wrapper shape), `backend/routes/assessment.py` (`generate-plan` response shape) and `backend/routes/ai.py` (`swap-meal`). Cross-checked against `CLAUDE.md`'s "Diet Modification System" section, which documents this as the authoritative pattern for all expert-modification features.

## 5.1 Section-by-section parity

| Website behavior | Flutter | Data source | Status |
|---|---|---|---|
| `loadDietStorage()` / `isNewDietSchema()` migration | `DietStorage.isNewSchema`, `DietStorage.fromLegacyFlatPlan` | `users/{uid}.dietPlan` live | **Migrated** |
| `validateDietStorage()` planId fail-closed check | `DietController._validateAndMaybeAdopt` | `users/{uid}.planId` live | **Migrated** |
| `_recoverFromMaster()` | `DietController._recoverFromMaster` | `users/{uid}.dietPlanMaster` (one-time, only on invalid/absent `dietPlan`) | **Migrated** |
| `buildEffectivePlan()` | `DietStorage.buildEffectivePlan()` | in-memory, over `currentDietPlan` + `expertModifications` | **Migrated** |
| Day selector + today auto-select | `DietDaySelector` / `DietController._maybeAutoSelectDay` | — | **Migrated** |
| Plan header (name, targets, key rules) | `DietPlanHeaderCard` | `users/{uid}.calculations` live | **Migrated** |
| Meal card (foods/time/macros/expert badge) | `DietMealCard` | effective plan | **Migrated** |
| `callSwapMealApi()` | `DietRepository.swapMeal` | `POST /api/ai/swap-meal` (existing endpoint, unchanged) | **Migrated** |
| `applySwappedMeal()` | `DietController.acceptSwap` | writes `users/{uid}.dietPlan`; clears that meal's `expertModifications` entry | **Migrated** |
| `submitVerifyRequest()` | `DietController.requestReview` / `DietRepository.submitReviewRequest` | `review_requests` (`reviewType: 'diet'`) — same collection & shape the Expert Dashboard Reviews Inbox reads | **Migrated** |
| `getCompletedPlanReview()` / `planIdMismatch` guard | `DietController.pendingAcceptableReview` | `review_requests where userId==uid && reviewType=='diet'` live | **Migrated** |
| `showExpertReviewBanner()` + "what changed" | `DietExpertReviewBanner` | `mealChangeHistory` on the review doc | **Migrated** (simplified — see §5.2) |
| `acceptExpertPlan()` / `_buildDietStorageFromReview()` | `DietController.acceptExpertReview` | history + `_edited`-flag scan fallback, exactly mirrored | **Migrated** |
| Expert picker for review requests | `DietRequestReviewSheet` | `experts where approved==true` (live collection, not the `zitlas_nutritionists` cache) | **Migrated** (real source, see §5.2) |
| Empty state ("No Plan Yet") | `DietEmptyState` | — → routes to `/assessment` | **Migrated**, target still a placeholder (see §5.4) |

## 5.2 Deliberate scope decisions (with reason)

- **Expert picker sourced from the live `experts` collection**, not the website's `zitlas_nutritionists` `localStorage` cache. That cache is only populated by browsing the Experts marketplace page, which is itself still a placeholder in this app; reading the same authoritative collection the marketplace would populate from is more robust, not a simplification or an invented feature.
- **"What changed" summary is a flat expandable list** built from `mealChangeHistory` (day/meal/new foods/reason), not the website's full original-vs-expert day-by-day comparison view. Same underlying data, simpler presentation — a full diff view can be added without any schema change.
- **Personal Coaching diet mode is deferred entirely** (coach-plan overlay, meal check-ins, "Ask Coach") — it depends on the Coaching Workspace, already deferred in Phase 4 (§4.2).
- **Dead website code not reproduced**: `renderStaticFallback`, `fetchWeeklyPlan`, `loadNearbyNutritionists`/`renderNutritionistsOnly`, `zitlas_plan_versions`-based version history — confirmed unreachable/unpopulated in the audited source.
- **Expert's `modify-diet.html` editor UI is out of scope** — this phase is athlete-facing; the editor was already excluded from the Expert Dashboard phase (§4.2, "Plan editors").
- **Snap Meal (AI photo nutrition logging)** — deferred. It's a standalone camera-capture + `/api/meal/estimate-nutrition` + `meal_snap_logs` feature, not part of the Diet plan/persistence/expert-review pipeline this phase covers; would need its own audit of the capture UX and Storage upload path.

## 5.3 Persistence guarantee (verified)

`DietController` only ever *reads* `users/{uid}` and `review_requests` on init/rebuild — a plan is never generated or reconstructed from scratch by opening the screen, restarting the app, navigating away and back, or a widget/controller rebuild (a fresh `DietController` just re-subscribes to the same live doc and re-derives the same state). The only writes are: (1) accepting a meal swap, (2) accepting an expert review, (3) one-time `planId` stamping of an unstamped legacy plan (adopt), and (4) discarding a plan that fails the `planId` fail-closed check (stale). None of these are triggered by navigation or rebuilds — only by an explicit athlete action or a genuine goal-identity mismatch.

## 5.4 Known limitation — not a regression

The empty-state CTA and the review-request flow's "no plan" path both route to `/assessment`, which is **still the Phase-1 placeholder screen** (`AssessmentScreen` → `PlaceholderScreen`). The 11-step assessment wizard that calls `POST /api/assessment/generate-plan` was never in scope for this phase — the Diet task's own constraints were about not building a *second* AI-generation system inside the Diet feature, not about building the wizard itself. An athlete with no existing plan can see the Diet screen's empty state correctly, but cannot yet generate a plan from within the app until the Assessment phase is built.

## 5.5 Validation

- `flutter analyze` — no issues found (feature-scoped and whole-project).
- `flutter test` — all tests passed (no Diet-specific widget tests were added; existing suite covers app boot/login only, same as every prior phase).
- `flutter build apk --debug` — build succeeded.

# Phase 6 — Training migration

Source of truth: `frontend/pages/dashboard/weekly-plan/weekly-plan.{html,css,js}` (102/1024/1074 ln) and `frontend/pages/dashboard/training/day.{html,css,js}` (286/1099/1154 ln), plus `assets/js/verified-badge.js` (252 ln), `assets/js/coaching-gate.js` (43 ln), and the shared modules already audited in Phases 3A/5 (`cloud-sync.js`, `payment-service.js`, `notification-center.js`). ~3,900 lines of page-specific JS/CSS audited, plus the shared-module cross-check.

**Source-path note (same as Phases 3A/5):** `C:\Users\Atharva\Desktop\zitlas` does not exist; `zitlas_mobile/frontend` is the newest, authoritative copy (confirmed again this phase).

**Bottom-nav mapping confirmed via `navbar.js`:** the "Training" tab's `file` is `dashboard/weekly-plan/weekly-plan.html`, not `training/day.html` — the day page is a sub-page reached only by tapping a day card (no bottom nav of its own; `day.html` doesn't even load `navbar.js`). Flutter mirrors this: `/training` is the Weekly Plan screen (the real shell-tab destination); the day detail is pushed via `Navigator.push` from a day card tap, reusing the same live `WorkoutController` instance rather than a second `go_router` route.

## 6.1 Confirmed dead code — NOT reproduced (with evidence)

Before writing any UI, I grepped the entire frontend AND backend for every writer of the two schemas these pages read:

- **`zitlas_roadmap` (the "sport plan" schema and its full 10-section day template — Warmup/Activation/Primary+Secondary Skill/Match Simulation/Mental Conditioning/Recovery/Stretching/Hydration/Weekly Review)** — grepped every `.js` file for `setItem('zitlas_roadmap'`: only 2 hits, both in `cloud-sync.js`'s field-map declaration and `diet.js`'s key-clearing list — **never written**. `ai-coach.js` (the only plan-generation code) never produces it. Backend's `roadmap` references (`routes/ai.py`'s `/api/ai/elite-weekly-plan`, `services/groq_service.py`'s `generate_elite_weekly_plan`) are a *diet* nutrition-roadmap endpoint with **zero frontend callers** (grepped for `elite-weekly-plan` — no hits) — unrelated to training and also dead. `weekly-plan.js`'s `renderDay`/`renderWeeklyReview`(roadmap)/`renderProfileFallbackRoadmap`/`selectRoadmapDay` and `day.js`'s entire `renderDay()` + 10 section renderers are therefore unreachable in production. **Not built.**
- **Legacy `zitlas_expert_review` branch** (`er.status === 'APPROVED'`) in both `loadPlan()`/`loadPlanWithSource()` — same precedent as the Diet feature (Phase 5), which already determined this schema is superseded by the wrapper+`workoutModifications` system. Not reproduced here either, for consistency.
- **CASE 1 flat-schema recovery migration** (`_migrateWorkoutPlanFromReview`, `_getCompletedWorkoutReview`) — a one-time data-repair path for accounts whose `workoutPlan` predates the wrapper schema. Since every new plan is written in wrapper form (`fromAiPlan`), this is a dwindling edge case, not a distinct user-facing feature; deferred, documented here rather than silently dropped.

## 6.2 A real, load-bearing behavior difference from Diet (not a bug)

**Training has NO "Accept Expert Changes" button anywhere in `weekly-plan.js` or `day.js`.** Both files auto-apply the newest `workoutChangeHistory` the moment it exists for the current `planId` — no status filter, no `athleteAccepted` check (`getLatestWorkoutReview()`). The explicit accept action lives on a *different* page (`cprofile.js`'s `_buildWorkoutStorageFromReview`), out of scope for "Training." `WorkoutController._maybeAutoSyncReview()` reproduces this exactly: it rebuilds and persists `workoutModifications` from the latest matching review automatically, with no accept UI on the Training screens. Building an accept button here — even though Diet has one — would be inventing a control the real Training page doesn't have.

## 6.3 Parity matrix

| Website feature | Source | Data source | Flutter | Status |
|---|---|---|---|---|
| `loadPlan()`/`loadPlanWithSource()` schema detection + migration | `WorkoutStorage.isNewSchema`/`fromLegacyFlatPlan` | `users/{uid}.workoutPlan` live | **Migrated** |
| Goal-identity (`planId`) fail-closed gate | `WorkoutController._validateAndMaybeAdopt` | `users/{uid}.planId` live | **Migrated** |
| Auto-apply newest expert review (no accept button) | `WorkoutController._maybeAutoSyncReview` | `review_requests` (`reviewType:'workout'`) live | **Migrated** (see §6.2) |
| `buildEffectiveWorkoutPlan()` | `WorkoutStorage.buildEffectivePlan()` | in-memory | **Migrated** |
| Personal Coaching training override (`initCoachTrainingMode`) | `WorkoutController._coachOverrideActive` | `personal_coaching/{uid}` + `coaching_plans/{uid}` live | **Migrated** |
| Coach banner (active/ended copy) | `WorkoutCoachBanner` | — | **Migrated** (verified-badge integration deferred, see §6.4) |
| Hero (role badge, title, goal/ambition tags, 3 stats) | `WorkoutHero` | plan | **Migrated**; `dateRange`/"AI Enhanced" badge omitted — confirmed unreachable for this schema (§6.1-style dead-field check: no `date`/`aiEnhanced` anywhere in `backend/routes/assessment.py`'s response) |
| Context bar ("Your Plan Profile") | `WorkoutContextBar` | plan | **Migrated**, including the real duplicate Goal/Weekly-Focus rows (both derive from the same `plan_name` for this schema — reproduced, not "fixed") |
| Week Progress (bar, dots, current session) | `WorkoutWeekProgress` | plan | **Migrated**, including the real always-0%/no-"done"-dots behavior (`weekly_plan` days never carry a `date`, so the website's own completion check never fires either) |
| AI Analysis strip | — | `plan.analysis` | **Not built** — confirmed dead for this schema (§6.1 method); backend never emits `analysis` |
| 7-Day schedule (day cards, status badge, expert-modified badge, focus diff strikethrough, Primary line) | `WorkoutDayCard` | plan | **Migrated** |
| Weekly Review section | — | `plan.weeklyReview` | **Not built** — confirmed dead for this schema; `transformWorkoutPlan()` never sets it and `day.js`'s fitness path never calls `renderWeeklyReview()` |
| Day detail hero/time-breakdown/Fitness Session/exercises | `WorkoutDayScreen` | plan | **Migrated** |
| Expert-modified banner + note (day-level) | `WorkoutDayScreen` | `day._modified`/`_modifiedBy` | **Migrated** |
| Coach's Tip | `WorkoutDayScreen` | `day.daily_tip` | **Migrated** |
| Rest/Recovery day handling | `WorkoutDayScreen` | `day.isRest` | **Migrated** |
| Complete Workout | `WorkoutController.completeWorkout` | `users/{uid}/activity/{date}.workoutCompleted` (same doc `activity-service.js` owns) | **Migrated** |
| Send Workout to Coach (+ coaching-gate) | `WorkoutController.sendWorkoutToCoach` | `workout_checkins`, `coaching_notifications` | **Migrated** |
| Check-in status ("Sent"/"Reviewed · N/10" + comment) | `_WorkoutActions` | `workout_checkins` live | **Migrated** |
| 10-section sport template (Warmup…Hydration) | `day.js`'s `renderDay()` | `zitlas_roadmap` | **Confirmed dead, not built** (§6.1) |
| Empty state ("No Plan Found") | `WorkoutEmptyState` | — → `/assessment` | **Migrated**, exact website copy preserved verbatim (including its "AI Nutrition assessment" wording on the Training page) |

## 6.4 Deliberate scope decisions (with reason)

- **Verified-expert badge (`ZitlasBadge`) is not integrated** into the coach banner or expert-modified badges. No shared Flutter badge widget exists yet — the Expert Dashboard phase used a plain `verified` boolean without building the full `{isVerified, verificationLevel, verifiedAt}` badge/tooltip/bottom-sheet component `verified-badge.js` implements. Same simplification the Diet feature already made for its expert-review banner. The banner *text* and both status branches (active/ended) are otherwise exact.
- **CASE 1 flat-schema migration** deferred — see §6.1.

## 6.5 Validation

- `flutter analyze` — no issues found (whole project).
- `flutter test` — all tests passed.
- `flutter build apk --debug` — build succeeded.
- Confirmed old `zitlas` website directory does not exist and `zitlas_mobile/frontend` (read-only) was not modified.
- Confirmed no regression: `git status` shows changes only under `lib/features/workout/` and `docs/MIGRATION_INVENTORY.md` — Auth, Dashboard, Diet, router, and theme files are untouched.

# Phase 7 — Assessment migration

Source of truth: `frontend/pages/dashboard/ai-coach/ai-coach.{html,css,js}` (186/1325/2397 ln — the largest single page audited so far), cross-checked against `backend/services/assessment_service.py` (the calculation + SWOT engine) and `backend/routes/assessment.py` (`AssessmentInput`, `POST /generate-plan`).

**Source-path note (same as every prior phase):** `C:\Users\Atharva\Desktop\zitlas` does not exist; `zitlas_mobile/frontend` is the newest, authoritative, read-only copy — untouched this phase.

## 7.1 What this page actually is

`ai-coach.html`/`.js` is the full **11-step onboarding wizard**: Welcome → Goal Selection → Assessment questions → Processing → Fitness Snapshot → SWOT → **Diet Plan preview** → **Workout Plan preview** → Done. It is not a short form — it includes read-only previews of the freshly-generated Diet and Workout plans before the athlete ever reaches the dashboard. All 9 live screens (confirmed against the DOM: `s-welcome`, `s-goal`, `s-assess`, `s-processing`, `s-snapshot`, `s-swot`, `s-diet`, `s-workout`, `s-done`) are migrated.

**Two screens implied by a stale code comment do not exist**: the header comment lists "...Diet → Workout → **Sources** → **CTA** → Done", but there is no `#s-sources` div and no upsell-CTA screen anywhere in the actual HTML — the ₹149 expert-review upsell was explicitly removed from onboarding per the website's own comment ("no longer interrupts onboarding — offered later on the dashboard"). Confirmed dead, not reproduced.

## 7.2 Question flows — 3 distinct sets, exact parity

| Goal | Website source | Questions | Flutter |
|---|---|---|---|
| `lose_weight` / `muscle_gain` | `QUESTIONS` | 15 | `defaultQuestions` |
| `general_fitness` | `GF_QUESTIONS` | 14 | `generalFitnessQuestions` |
| `transformation` | `TF_QUESTIONS` | 13 | `transformationQuestions` |

Every prompt, hint, option label/value/icon, placeholder, and validation range (age 13–100, height 120–230cm, weight 25–250kg, sleep 2–14h) is transcribed verbatim in `lib/features/assessment/models/assessment_question.dart`. The shared `SUPPLEMENT_QUESTION` (10 options, `'none'` sentinel) appears in all three flows identically.

**Answer-storage asymmetry reproduced exactly**: the website's `q.parse()` is only ever invoked for `text`/`slider` question types — `options`-type answers (including `goal_duration_months` and `available_time` on the GF/TF flows) are stored as **raw strings** and only parsed to numbers later, inside `buildPayload()`. `AssessmentController.answerAndAdvance`/`submitTextAnswer` reproduce this exact division of responsibility rather than parsing eagerly everywhere.

## 7.3 Wheel pickers — native reinterpretation, same feature

The website's custom drag/scroll wheel (`createWheelPicker()`, ~260 lines of touch/mouse/wheel physics) is reproduced as a native `CupertinoPicker` (`WheelPickerField`) — same UX intent (scroll to pick a value from a range or discrete preset list: age, height, weight, goal weight, sleep hours, and the default flow's `available_time` presets `[5,10,15,20,25,30,45,60,75,90]`), not the raw JS physics. Height (cm↔ft/in) and weight/goal-weight (kg↔lbs) keep their unit-toggle pickers, with `cmToFt`/`cmToIn`/`ftInToCm`/`kgToLbs`/`lbsToKg` ported exactly (`lib/features/assessment/models/unit_conversions.dart`) — unit-tested for round-trip correctness (§7.8).

## 7.4 Calculation engine — server-side only, no second engine

**Every BMI/BMR/TDEE/calorie/protein/water/steps number is computed by `assessment_service.run_assessment()` and returned in the response.** Flutter never recomputes these — `AssessmentRepository.generatePlan()` posts the exact `AssessmentInput` payload and displays exactly what comes back. The SWOT engine (`generate_swot()`) is also fully server-side and rule-based (no LLM call) — same treatment.

One genuine, confirmed **client-side** computation exists and is ported exactly: the Snapshot screen's own `bmiInfo()` re-categorization (Underweight/Healthy Weight/Overweight/Obese Class I/Obese Class II+), which is **deliberately different** from the backend's own `bmi_category` field (Normal Weight/Obese Class III, etc.) — the website's Snapshot screen never reads `calculations.bmi_category` at all, it always uses its own local thresholds. Both are modeled (`AssessmentCalculations.bmiCategory` for completeness, `bmiInfo()` for what the Snapshot screen actually renders) — reproduced as two genuinely different category systems, not unified into one "more correct" version.

**A real backend/frontend validation-range mismatch, reproduced not fixed**: `AssessmentInput.age` validates `12–80` server-side, but the website's own question-level UI validates `13–100`. The question UI gate is what a user actually experiences, so that's what Flutter's `_ageValid()` reproduces; a value the website's own UI would accept (e.g. 90) can still 422 server-side — matching the real site's behavior exactly, not smoothed over.

## 7.5 Firestore persistence — same fields, no new schema

`AssessmentRepository.saveAssessmentResult()` is the Firestore half of `saveToLocalStorage()` + `ZitlasCloudSync.saveBulk()`, writing to the exact same `users/{uid}` fields already read by the Dashboard/Diet/Training features built in prior phases — no new collections, no new field names:

| Field | Shape | Reused from |
|---|---|---|
| `goal` | `{type, currentVal, targetVal, unit:'kg', startDate, endDate}` | `GoalModel` (Phase 3A) |
| `survey` | raw answers map | — |
| `calculations` | `AssessmentCalculations.toMap()` | — |
| `swot` | `{swot, scores, user_archetype, summary, priority_action}` | — |
| `assessment` | validated input echo | — |
| `dietPlan` | `DietStorage.fromAiPlan(...).toMap()` | **`DietStorage`** (Phase 5) |
| `workoutPlan` | `WorkoutStorage.fromAiPlan(...).toMap()` | **`WorkoutStorage`** (Phase 6) |
| `precautions`, `planGeneratedAt`, `planId`, `dietPlanMaster`, `workoutPlanMaster` | as-is | — |

Stamping a **fresh `planId`** here is what makes the Diet/Training features' existing fail-closed `planId` gates (built in Phases 5/6) automatically treat any prior expert review as stale on next load — no separate "clear expert review keys" step was needed the way the website's localStorage-based approach required.

**`data.sources` is confirmed local-only on the website** (`localStorage.setItem('zitlas_sources', ...)`, never included in `ZitlasCloudSync.saveBulk()`'s bulk object) and is never displayed in any screen of this wizard either — correctly not persisted to Firestore, matching the real site exactly.

## 7.6 Goal integration — a real, reproduced quirk

`GoalModel.goalNames`/`goalUnits` (built in Phase 3A from `dashboard.js`'s own `GOAL_NAMES`/`GOAL_UNITS` maps) only have entries for `'Weight Loss'` — the 3 newer goal-type strings this phase writes (`'Muscle Gain'`, `'Transformation'`, `'General Fitness'`) have **no entries in the website's own maps either**. The Dashboard Goal card therefore falls back to the raw type string and a generic `'Value'` unit (not `'kg'`) for those 3 goals on the real production website. `_buildGoalMap()` writes the exact same 4 raw type strings the website writes; `GoalModel` already has the correct fallback chain (built in Phase 3A, unmodified) — the quirk is reproduced automatically, not newly introduced.

## 7.7 Diet/Training integration

The Diet Plan preview (S7) and Workout Plan preview (S8) reuse the **exact same** `DietPlanContent`/`WorkoutPlanContent`/`DietDay`/`WorkoutDay`/`WorkoutExercise` models the real Diet and Training features (Phases 5/6) already consume — parsed straight from the `generate-plan` response, zero reshaping. `WorkoutPlanContent`/`WorkoutDay`/`WorkoutExercise` gained 4 new **additive, nullable** fields (`weekly_training_volume_sets`, `training_split`, `sets_volume_est`, `progression`) to support the muscle-gain/transformation-only preview fields the website's `renderWorkout()` shows — confirmed these fields are read **only** by this preview screen, never by the persisted `weekly-plan.js`/`day.js` Training pages, so this is a pure superset with no behavior change to the already-shipped Training feature (`flutter analyze`/`test` on `lib/features/workout` still clean after the change).

Because persistence happens via the SAME `DietStorage.fromAiPlan`/`WorkoutStorage.fromAiPlan` factories the Diet/Training controllers already use for validation, an athlete who completes Assessment and taps through to the dashboard sees the identical plan immediately in the Diet and Training tabs — same object, not a re-fetch of different data.

## 7.8 Deterministic calculation-parity tests

Added `test/assessment_calculations_test.dart` (9 cases, all passing) — since the calculation formulas themselves are server-side, these test the DISPLAY layer instead: `bmiInfo()` category boundaries (18.5/25/30/35, exact accent/badge per band), `thousands()` number formatting, a hand-computed weight-loss profile (28yo/90kg/175cm/sedentary/goal 75kg — BMR/TDEE/deficit/protein/weeks independently derived from the Python formulas) verifying the Snapshot card text and goal-date derivation match exactly, and the wheel-picker unit conversion round-trips. **This test suite caught a real bug before ship**: the TDEE/BMR values interpolated into several card `expand` strings were missing thousands-separator formatting (`"2231"` instead of `"2,231"`) — fixed in `snapshot_card.dart` (all 3 goal branches) as a direct result of writing the test, not found by inspection.

## 7.9 Existing-user / retake behavior — reproduced exactly, not invented

Audited `init()`'s actual logic: **the website itself has no "resume mid-assessment" or "already completed" detection** — `ai-coach.html` always starts at Welcome unless a `?view=swot`/`?view=workout` deep link is present (used only by the Dashboard's "View Full →" SWOT link and the Training empty-state CTA, both of which point elsewhere in this app, not into the wizard). The actual gate that stops an existing user from retaking is entirely in `dashboard.js`'s `goalActionBtn` handler, already built correctly in Phase 3A (routes to Set/Reset Goal sheets instead of `/assessment` once a goal exists). **No resume/deep-link logic was added here** — reproducing the website's own absence of one is the correct parity outcome, not a gap.

## 7.10 Loading / error / navigation states

- **Processing**: 8 fixed-cadence (800ms) progress steps run visually in parallel with the real `POST /generate-plan` call; the screen waits for **both** the minimum visual duration AND the real response before advancing (`Future.wait`-equivalent), exactly matching `callGeneratePlan()`'s `tryAdvance()` gate.
- **Generation failure**: `apiResult` stays null, the Snapshot screen shows the website's own exact fallback text ("Could not load data. Check your connection and retry.") — no fake numbers, matching `renderSnapshot(null)`.
- **Text validation**: inline error text per question, matching each `errMsg` verbatim; Continue is blocked until valid.
- **Multiselect**: "Please select at least one option" blocks Continue with zero selections, matching `qMsErr`.
- **Double-submission**: Continue buttons disable during their async operation (option-tap has a 320ms "chosen" animation delay before advancing, matching the website's `setTimeout`).
- **Android back**: routed through a `PopScope` that calls the same back handlers the in-app back button uses (Goal→Welcome, mid-question→previous question) — never pops the whole wizard/loses answers. No back navigation exists past Processing, matching the website (no back button rendered on those screens).

## 7.11 Account isolation

`AssessmentRepository`/`AssessmentController` take `uid` from `AuthState.profile` (the same Firebase-authenticated session every other feature uses) and write only to `users/{uid}`— no hardcoded IDs, no cross-account leakage possible; `ChangeNotifierProvider` is keyed by `uid` so switching accounts creates a fresh controller.

## 7.12 Validation

- `flutter analyze` — no issues found (whole project).
- `flutter test` — **10/10 passed** (9 new deterministic calculation-parity tests + the existing boot test).
- `flutter build apk --debug` — build succeeded.
- Confirmed old `zitlas` website directory does not exist; `zitlas_mobile/frontend` (read-only) was not modified.
- Confirmed no regression: `git status` shows changes only under `lib/features/assessment/`, `lib/features/workout/models/` (additive fields), `lib/core/network/api_client.dart` (additive optional `timeout` param), `pubspec.yaml` (new asset), `assets/images/zino.png` (copied from the real website source, not modified), `test/`, and `docs/MIGRATION_INVENTORY.md` — Auth, Dashboard, Diet, Training screens, and the router are otherwise untouched.

# Phase 7.1 — Physical-device connectivity fix (post-Assessment bug report)

Reported symptom: on a real handset, the "Your Fitness Snapshot" screen showed *"Could not load data. Check your connection and retry."* and "Your Diet Plan" showed *"Diet plan could not be loaded."*

## Misattribution corrected first

Both strings were reported as **Dashboard** cards. They are not — `grep` places both exclusively in `lib/features/assessment/`: `snapshot_view.dart` (wizard screen S5) and `diet_preview_view.dart` (S7). The Dashboard contains neither string. The screenshot showed the **Assessment wizard**, and both screens fell back for one shared reason: `apiResult == null`.

Consequently the reported "Diet CTA bug" (a card titled *Your Diet Plan* whose button reads *See Workout Plan →*) is **not a bug** — `ai-coach.html` S7 is titled `Your <span>Diet Plan</span>` and its `#btnDietNext` reads exactly `See Workout Plan →`, because the wizard's next step is the workout preview. Same for S5's `#btnSnapshotNext` = `View SWOT Analysis →`. Both already matched the website verbatim; nothing was changed.

## Root cause 1 (caused the visible failure)

`Env.apiBaseUrl` defaulted to `http://127.0.0.1:8000`. On a physical device that loopback address is **the phone itself**, so every FastAPI call failed at the transport layer. Firestore was unaffected (the Firebase SDK talks to Google directly, not through this base URL) — which is why login and every Firestore-backed screen kept working, disguising a pure connectivity fault as a data/parsing bug.

`flutter build apk --debug` passes no `--dart-define`, so the loopback default was baked into the installed APK.

Verified the correct target rather than guessing: the website calls same-origin relative `fetch('/api/...')` (FastAPI serves `frontend/` as static files), and `https://zitlas.com` responds `200` on `/api/system/trial-mode` with both `/api/assessment/generate-plan` and `/api/ai/swap-meal` returning `422` to an empty body (route present, validation rejected) — so the default is now `https://zitlas.com`, the same origin the website uses.

**Blast radius** (every `ApiClient` caller was broken on-device, not just Assessment): `assessment_repository` (`generate-plan`), `diet_repository` (`swap-meal`), `expert_repository` (`payment/charge`, coaching accept/reject, `admin/experts/deactivate`).

## Root cause 2 (latent — would have broken every release build)

`android/app/src/main/AndroidManifest.xml` declared **no** `INTERNET` permission. It only appeared in Flutter's generated `debug/` and `profile/` manifests (added for the hot-reload channel), so debug testing masked it entirely; a release build would have shipped with no network access at all — Firebase included. Added to the main manifest.

No cleartext exemption was added: production is HTTPS, and a blanket `usesCleartextTraffic` would weaken the release build for dev-only convenience. Pointing at a local server is documented as `--dart-define=API_BASE_URL=http://<LAN-IP>:8000` plus a host-scoped exemption if actually needed.

## Secondary defects fixed while in the code

1. **A successful plan was discarded on a Firestore write failure.** Generation and persistence shared one `try`, so a failed save nulled `apiResult` and showed "could not load data" — destroying a real generated plan and 15 answers. They are now settled separately: the plan renders, with a distinct dismissible warning and a save-only retry.
2. **"…and retry" offered no retry.** Added `retryGeneration()`, which reuses the collected answers so the questionnaire never has to be retaken, plus a `Try Again` button.
3. **Every failure produced the same generic message.** `ApiException` already classified transport/401/403/5xx; the controller discarded it. `submitErrorMessage` now distinguishes network vs expired session vs server error vs 422 validation vs malformed response — a real outage is no longer indistinguishable from a data problem.
4. **Non-JSON 2xx crashed the parser.** `ApiClient` now converts it to a `malformed response` `ApiException` (the typical captive-portal/proxy HTML case).
5. **Debug-only diagnostics** added to `ApiClient` and the Assessment controller: base URL, status, failure class, and a physical-device hint. Never logs the auth header, request body (biometrics), or response payload.

## Regression guard

`test/env_config_test.dart` fails the build if `Env.apiBaseUrl` ever again contains `127.0.0.1`, `localhost`, `0.0.0.0`, or `10.0.2.2` (the emulator-only host alias, equally unreachable from a handset), and asserts it composes to the same absolute path the website fetches.

## Validation

- `flutter analyze` — no issues (whole project).
- `flutter test` — **13/13 passed** (3 new connectivity-config tests + 10 existing).
- `flutter build apk --debug` — succeeded; `INTERNET` confirmed present in the merged manifest.
- Files changed: `lib/core/config/env.dart`, `lib/core/network/api_client.dart`, `lib/features/assessment/assessment_controller.dart`, `lib/features/assessment/presentation/widgets/snapshot_view.dart`, `android/app/src/main/AndroidManifest.xml`, `test/env_config_test.dart` (new). No website file touched; no Firebase config, package ID, Firestore rule, or schema changed.

# Phase 7.2 — LLM type-drift parsing fix (workout/diet models)

Runtime exception from the physical device:

```
[ASSESSMENT] generate-plan FAILED — _TypeError:
type 'String' is not a subtype of type 'num?' in type cast
  #0 new WorkoutExercise.fromMap (workout_exercise.dart:35:23)
  #1 new WorkoutDay.fromMap.<anonymous closure> (workout_day.dart:95:43)
```

## Root cause

`workout_exercise.dart:35` was `sets: m['sets'] as num?`. The LLM returned `sets` as a **String**.

I had typed that field from `backend/routes/assessment.py`'s JSON schema (`"sets": number`) — but **that schema is a prompt instruction to the LLM, not an enforced contract**. Nothing validates the model's reply before it reaches the client, so the documented type is aspirational. Production genuinely contains both shapes:

| Writer | `sets` value |
|---|---|
| Expert editor — `modify-workout.js:139` `sets: sets ? parseInt(sets) : 0` | `3` (int) |
| LLM obeying the prompt | `3` (int) |
| LLM not obeying | `"3"`, `"3-4"`, `"AMRAP"`, `"To failure"` |

**Why the website never broke:** every render site coerces on use and never does arithmetic on it — `String(ex.sets)` (day.js:472/549/1023), `String(ex.sets \|\| '')` (weekly-plan.js:538), `ex.sets + ' sets · '` (ai-coach.js:2064), and `sets: ex.sets \|\| null` passed straight through to `workout_checkins` (day.js:797). JavaScript's dynamic typing absorbed the variance silently. Dart's `as num?` does not.

So `sets`/`rest_seconds` are now `String?` — **display values**, matching what every consumer actually needs. Coercing them to `num` would have thrown on (or destroyed) legitimate production values like `"3-4"`.

## Not just line 35 — four distinct unsafe-cast bugs

Writing the regression tests first surfaced three more failures beyond the reported one, including one in the **opposite** direction:

| # | Field | Bad cast | Failure |
|---|---|---|---|
| 1 | `sets` | `as num?` | **the reported crash** — String → num? |
| 2 | `reps_or_duration` | `as String?` | int → String? (LLM emits bare `12`) |
| 3 | `exercises` | `as List?` | String → List? (non-list value) |
| 4 | `sets: 3.0` | — | rendered `"3.0"` instead of `"3"` |

## Fix: a shared coercion layer, not per-field patches

New `lib/core/util/json_coerce.dart`, governed by one rule: **tolerant of type, never invents data.** Anything genuinely uninformative returns `null`, so callers can still distinguish "absent" from "zero" — a fabricated `0` would be indistinguishable from a real measurement.

- `asDisplayString` — opaque display values; preserves semantic strings, renders `3.0` → `"3"` like JS `String()`.
- `asNum` / `asInt` — arithmetic-bearing fields; accepts numbers, clean numeric strings, and unit-suffixed forms (`"45 min"` → `45`, `"1,600 kcal"` → `1600`), mirroring the website's own `parseInt(String(x).replace(/[^0-9]/g,''))` in `weekly-plan.js`'s `totalMin` reduce.
- `asText` — captions that sometimes arrive as bare numbers.
- `asMapList` / `asStringList` / `asMap` — collection extraction that yields the valid subset rather than throwing, so one malformed exercise cannot discard an otherwise-good 7-day plan.
- `displayStringToJson` — writes numeric-looking display values back out **as numbers**, so reading `sets: 3` and re-saving never drifts the stored type to `"3"` for the expert dashboard.

Applied across the whole LLM-fed tree: `WorkoutExercise`, `WorkoutDay`, `WorkoutPlanContent`, `WorkoutStorage.buildEffectivePlan` (expert `newWorkout` snapshots), `CoachTrainingPlan` (coach free-text form input — same variance, different cause), `WorkoutReviewRequest`, and pre-emptively `DietMeal`, `DietPlanContent`, `DietStorage`.

**Deliberately left alone:** `AssessmentCalculations` / `DietCalculations`. Those come from `run_assessment()` — pure Python arithmetic returning `round()`ed numbers, never LLM output. No evidence of variance, so no change.

## Orchestration bug (the misleading error message)

The log said `generate-plan FAILED`, implying the assessment failed. It hadn't — the backend succeeded and returned valid `calculations`, `swot` and `diet_plan`. All four sections were parsed in **one expression**, so a single bad field inside the workout tree discarded the completed assessment, the targets and the SWOT with it.

`AssessmentResult.fromMap` now parses each section independently, mirroring the backend's own isolation (`routes/assessment.py:1347-1375` wraps the diet and workout LLM steps in separate `try/except` and can legitimately return either as `null`). A present-but-unparseable section is logged and degrades to absent — the athlete keeps everything else and the UI shows its real "could not be loaded" state. `calculations`/`swot` remain **required**, throwing a clear `FormatException` if missing, because their absence in a 200 is genuinely malformed rather than an expected outcome.

## Tests

**62 passing** (up from 13). Written **before** the fix and confirmed failing against the old code with the exact reported error:

- `test/workout_parsing_test.dart` (18) — the exact crashing shape, semantic values (`"3-4"`, `"AMRAP"`), int/string/double equivalence, null vs missing, the reverse `int → String?` case, non-list/junk `exercises`, lossless `toMap` round-trip, full 7-day response, all four array-key aliases.
- `test/diet_parsing_test.dart` — same defect class covered pre-emptively in `diet_plan`.
- `test/assessment_result_isolation_test.dart` — a bad workout tree no longer costs the assessment; backend-null plans are normal; missing `calculations`/`swot` is a hard, clearly-reported failure.
- `test/json_coerce_test.dart` — the coercion contract itself, including "never fabricate a 0".

## Validation

- `flutter analyze` — no issues (whole project).
- `flutter test` — **62/62 passed**.
- `flutter build apk --debug` — succeeded.
- Backend untouched: the website works against this exact data, so Flutter was made compatible with the existing contract rather than the contract changed. No Firebase config, package ID, Firestore rule, or stored user plan altered.

# Phase 8 — Athlete-side Expert System migration

## Scope

Full athlete-facing Expert marketplace/profile/review-request lifecycle, plus the minimum expert-side surfaces needed to close the loop (View Athlete Profile, Diet/Workout review editing). Audited read-only first: `frontend/pages/coaches/coaches.{html,js}`, `cprofile.{html,js}` (4691 lines — hero, CTAs, request-review sheet, personal-coaching sheet, withdraw flows, previous reviews, status state machine), `expert-review.js` (confirmed **legacy**, superseded by the `expertModifications`/`workoutModifications` schema — not built against), `certificate-manager.js`, `expert-profile.js` (confirmed expert-self-view-only, out of scope), and the backend Firestore contract via collection names grepped across all of the above.

## Firestore collections (no new ones)

`experts`, `expert_certificates`, `review_requests`, `personal_coach_requests`, `personal_coaching`, `chat_rooms`/`messages` — all pre-existing, all traced field-for-field from the website source above.

## What was built

**Models** — `lib/features/experts/models/expert_listing.dart`: `ExpertListing` (the athlete-visible `experts/{id}` shape, mirrors `_normalizeExpertToCoach()`) + `ExpertPricing` (the real `PRICING_DEFAULTS` merge, not a flattened single fee).

**Data layer** — `lib/features/experts/data/experts_repository.dart`: marketplace fetch (one-time `.get()`, matches `coaches.js` — no live listener, no localStorage fallback since Flutter never had that cache), review-request submission (`buildReviewRequestDocs()` extracted as a pure function — reproduces the "both" bundle: primary carries the full price, secondary carries ₹0 and mirrors `bundleId`/`siblingId`), transactional withdraw (only proceeds if still `pending` server-side, exactly like the website's `runTransaction`), personal-coaching request/withdraw/end, chat send/watch.

**Controllers** — `ExpertsController` (search/specialty-filter/sort, mirrors `getFiltered()`), `ExpertProfileController` (certificates/reviews/coaching streams + the fail-closed status whitelist, extracted as pure `latestReviewOfTypePure()`/`verifyButtonStatePure()`/`canSubmitNewReviewPure()` functions for testability).

**Screens** — `ExpertsScreen` (marketplace: search, specialty pills, sort, cards with the real 3-action layout), `ExpertProfileScreen` (hero, quick-info, CTAs, status banner with exact per-status copy, About, Certificates, Expertise, Track Record, Pricing, Reviews, Previous Reviews), `RequestReviewSheet` (service type → review type → live price → submit), `PersonalCoachingSheet` (2-step, "no payment now" copy), `ChatScreen` (athlete side, replacing the placeholder), `CoachingScreen` (athlete's active-relationship view + End Coaching, replacing the placeholder), `AthleteProfileScreen` (new — expert-side "View Athlete Profile", closes the gap where `_openAthlete()` used to just open chat), `ReviewDietEditorScreen`/`ReviewWorkoutEditorScreen` (new — expert-side plan editors mirroring `modify-diet.html`/`modify-workout.html`, writing `mealChangeHistory`/`workoutChangeHistory` back onto the same `review_requests` doc the athlete's existing `DietController.acceptExpertReview()`/`WorkoutController._maybeAutoSyncReview()` already consume).

**Model hardening** — audited every Expert-related model for the same unsafe-cast defect class fixed in Phase 7.2: replaced raw `as num?`/`as int?` casts with `json_coerce.dart` helpers in `expert_models.dart` (fee, sessionDuration, reviews, rating, totalPrice, price, verificationScore) and `diet_review_request.dart` (dayIndex, calories, protein). Added `_edited`/`_modifiedBy`/`_modifiedAt` write-back to `DietMeal.toMap()` and a `copyWith` to `WorkoutExercise` — both needed for the new editors to round-trip expert edits.

## Deliberately deferred (consistent with the Phase 4 Expert Dashboard precedent)

- **WebRTC voice calling** — no phone-dialer alternative exists in production (`webrtc-call.js`/`call-ui.js` grepped for `phoneNumber`/`tel:`/dialer: zero matches); calling needs a native WebRTC dependency, same deferral reasoning as Phase 4.
- **Chat image attachments** — text-only for now, same precedent.
- **Transformation gallery** — rendered from `expert.gallery` if present but no dedicated lightbox/upload flow.
- **`expert-review.js`'s legacy `zitlas_expert_review`/`APPROVED` flow** — confirmed superseded by the `expertModifications` schema (CLAUDE.md's own "authoritative pattern" designation); not reproduced, avoids building two parallel review-editing systems.

## Tests

**22 new** (84 total, up from 62): `test/expert_listing_test.dart` (pricing defaults/merge/tolerance, field-mapping fallback chains, verified-never-inferred, missing-field tolerance, string-typed rating/reviews). `test/expert_review_request_test.dart` (the fail-closed whitelist — unknown/withdrawn/superseded/declined/expired/cancelled all degrade to idle rather than sticking; active-over-terminal precedence; reviewType isolation; the `buildReviewRequestDocs()` payload shape including the "both" bundle).

## Validation

- `flutter analyze` — no errors (3 pre-existing-style info-level lints only).
- `flutter test` — **84/84 passed**.
- `flutter build apk --debug` — succeeded.
- Installed on a connected physical device (`adb install`); app launched clean (no `FATAL`/crash in logcat); manually verified the new Expert Profile screen against a real `experts` doc — rendered a real expert's custom pricing override (₹100 flat instead of the ₹49/59/99 defaults) and a genuine `review_completed` status banner ("Expert Reviewed") sourced from a real `review_requests` doc. Did not attempt the full 2-athlete/2-expert account-isolation matrix or all 5 flows end-to-end — this is the user's personal device with unrelated apps/data, and multi-account manual testing needs dedicated test accounts the session doesn't have.

# Phase 9 — Athlete Profile migration

## Scope

Full parity for the final athlete bottom-nav section: `frontend/pages/profile/profile.html`+`.js` (hub) and its three sub-pages — `personal-info/` (Edit Profile), `membership/` (Membership & Billing), `help-support/` (Contact Support) — plus the Language modal and Logout confirmation. Audited read-only first; no separate "zitlas" website source directory exists (confirmed again — only stale backup copies of this same repo under different names), so `zitlas_mobile/frontend` remained the canonical source.

## Key audit findings that shaped scope

- **Profile is a navigation hub, not a data dashboard.** No height/weight/BMI cards live on the hub itself — all editable fields live on the separate Personal Information page.
- **`.location-badge` is a hardcoded "Pune, India"** in the website's raw HTML, never overwritten by `profile.js` for any user. Reproduced exactly as a static string rather than "fixed" to be dynamic — a real, deliberate production quirk, not a bug to correct.
- **`.avatar-edit-btn` on the hub has no click handler at all** (grepped the whole frontend — confirmed dead/decorative on the website itself). Reproduced as non-interactive; the real photo picker lives only on the Personal Information page, exactly matching production.
- **No Change Password / notification-preferences UI exists anywhere in Profile** — grepped for "password"/"notification" across the whole `pages/profile` tree; the only "notification" hit was the shared `notification-center.js` script include, not a settings toggle. Neither was built, per the task's own "implement exactly what exists" instruction.
- **Email/phone are plain profile metadata**, not tied to Firebase Auth — `personal-info.js` writes them straight to `users/{uid}.personalInfo`, no `updateEmail()`/reauth flow, no phone-auth. Reproduced identically; no invented reauth workflow.
- **Editing height/weight does NOT recompute BMI/calculations** — it only updates `survey.height_cm`/`weight_kg` for the *next* Assessment run. `ProfileRepository.savePersonalInfo()` deliberately does the same, never touching `calculations`.
- **Membership is a real, backend-verified Razorpay flow** (`/api/payment/membership/create-order` → checkout → `/api/payment/membership/verify`, transactional, server-priced). No `razorpay_flutter`/native Razorpay SDK exists in this Flutter app yet (checked `pubspec.yaml`) — a genuine infrastructure gap, not a scope-avoidance call. The Upgrade button calls the real order-creation endpoint (validates auth/connectivity honestly) but cannot open a native checkout sheet yet; this is stated to the user rather than faked.
- **The website's own i18n system (`assets/js/i18n.js`, ~150 translated strings) is real and functional**, not decorative — but full app-wide localization is a cross-cutting concern spanning every already-built screen (Dashboard, Diet, Training, Experts...), not a Profile-specific feature. The Language modal is built with exact copy/options and persists the selection (`zitlas_language`, already device-scoped in `AccountGuard`), but does not yet retranslate the rest of the app — documented as a deliberate, separate-initiative scope boundary, same category as the Razorpay SDK gap.

## What was built

**Models** (`lib/features/profile/models/personal_info.dart`) — `PersonalInfo` (mirrors `zitlas_personal_info` field-for-field, `age` ported 1:1 from `computeAge()`'s DOB-boundary logic) and `Membership` (mirrors `getMembership()`'s premium-expiry-degradation rule exactly — an expired `premium_expiry_date` reads back as basic, driven only by the backend-written date, never a client flag).

**Data layer** (`lib/features/profile/data/profile_repository.dart`) — `users/{uid}.personalInfo`/`.membership`/`.survey` reads/writes (same doc every other feature already uses, no new collection), `POST /api/support/contact`, `POST /api/payment/membership/create-order`.

**Controller** (`lib/features/profile/profile_controller.dart`) — live `users/{uid}` listener driving avatar/name/AI-label/membership badge, with the exact website fallback chains (`personalInfo.fullName || account.name || auth.name`, same for photo).

**Screens** — `ProfileScreen` (hub, replacing the placeholder), `PersonalInfoScreen` (new — photo picker via `image_picker` compressed to a base64 JPEG under the same 180KB cap as web, all Basic Information + Body Metrics fields with cm/ft-in and kg/lbs toggles ported exactly), `MembershipScreen` (rewritten from placeholder — plan cards, billing toggle, full comparison table, honest Upgrade behavior), `HelpSupportScreen` (new — same 5 fields, same validation, screenshot UI present-but-not-transmitted matching web), `LanguageModal` (new).

**Logout** — already-correct infrastructure from the Auth phase (`performSignOut()` → Firebase sign-out → `AccountGuard.clearUserCache()` → `context.go('/login')`, replacing the auth route so Back can't reopen Profile) was reused as-is, just wired to the hub's confirmation dialog with the exact website copy ("Log Out?" / "You will be logged out of your ZITLAS account.").

## Tests

**10 new** (94 total, up from 84): `test/personal_info_test.dart` — full-doc parsing, missing/absent-doc tolerance, string-typed height/weight (legacy data), unparseable DOB, both sides of the `computeAge()` day-of-month boundary, and all four `Membership` expiry-degradation cases (active, expired, no-expiry-date, absent).

## Validation

- `flutter analyze` — no errors (4 pre-existing-style info-level lints only).
- `flutter test` — **94/94 passed**.
- `flutter build apk --debug` — succeeded; installed on the connected physical device.
- **Physical-device result:** launched clean, no crash in logcat. Navigated Home → Profile and confirmed the real hub renders live production data end-to-end — the signed-in athlete's actual uploaded photo, real name, "AI MUSCLE GAIN MEMBER" label correctly derived from their live `goal.type`, and a correctly-computed "Premium Member" badge from their real `membership` doc. The device then locked itself (PIN/biometric keyguard) mid-session; further on-device navigation (Personal Information, Membership, Help & Support, Logout) was **not** exercised live past that point since unlocking someone's personal phone without their credentials isn't something to attempt — those screens are validated by successful compilation, the model/logic test suite, and code-level tracing against the website source, not a live tap-through. Multi-account isolation (Athlete A/B swap) was not tested live for the same reason; the underlying `AccountGuard.clearUserCache()` mechanism is unchanged from the already-verified Auth phase.

# Phase 8 — Functional integration audit + advanced mobile features

## Audit method

Given the explicit instruction not to assume a feature works because its screen/button exists, this phase traced each subsystem to its REAL production data path (Firestore collection, backend endpoint, or client-side write) before touching Flutter code, then fixed what didn't match.

## Findings and fixes, by subsystem

**1. Personal Coaching — a real bug found and fixed.** The Phase 6 `submitCoachingRequest`/`withdrawCoachingRequest` wrote directly to `personal_coach_requests` client-side. Tracing `backend/routes/coaching.py` showed the real production flow is a **backend-only transactional escrow**: `POST /api/coaching/request` reserves the plan price out of the athlete's `wallet.reserved` inside a Firestore transaction, computes the price server-side from the expert's real pricing, sets `paymentStatus: 'reserved'`/`expiresAt` (48h), and fires the "Request Sent" notification — none of which a client write reproduces. `POST /api/coaching/withdraw` releases the same reservation transactionally. Fixed: both methods now call the real endpoints; the controller/sheet no longer pass a client-computed price/label (the backend is authoritative). Accept/reject were already correctly routed to `/api/coaching/accept|reject` in Phase 6 — only request/withdraw had the bug.

**2. Expert Diet/Training modification** — re-verified against `DietController.acceptExpertReview()`/`WorkoutController._maybeAutoSyncReview()` (built in Phase 6): `mealChangeHistory`/`workoutChangeHistory` on `review_requests` is the real, consumed contract; confirmed still correct, no changes needed.

**3. Call feature** — grepped the entire frontend for `phoneNumber`/`phone_number`/`tel:` again: zero matches. There is no phone number field anywhere in the `experts` schema or any UI. Confirmed (again) this is not a real production feature — not implemented, no fake number invented.

**4. Chat** — schema/screens already correct from Phase 6; added the one real gap: neither direction wrote to the in-app Notification Center on message send. Fixed: both `ExpertsRepository.sendMessage()` (athlete to expert) and `ExpertRepository.sendMessage()` (expert to athlete) now write a `notifications` doc matching `ZitlasNotify.send()`'s exact shape, non-blocking.

**5. Notifications — the most significant finding.** `notification-center.js`'s own header comment states outright that this is "FCM-READY" but that no Cloud Function exists yet to actually deliver a push. Confirmed by grep: `push_service.send_to_token()` (the only code that actually delivers an FCM push) is called from exactly one place — a manual test endpoint in `routes/system.py` — never from any real event. The ONLY real, currently-live notification system in production is the in-app Notification Center (`notifications` Firestore collection), populated by `coaching.py`'s backend `notify()` calls (coaching lifecycle) and various website JS files (chat, reviews, etc.).

   Given that, this phase built:
   - `NotificationsScreen` — real Firestore-backed list (was 100% placeholder), exact doc shape, category icons/priority, mark-read/mark-all-read, and `navigateForAction()`'s tap-routing table ported 1:1 to go_router.
   - `FcmService` — real native FCM token registration into `users/{uid}.pushTokens` (arrayUnion, multi-device-safe, matches web's schema exactly), contextual permission request (after login resolves, not at splash; snoozed 7 days on decline, never re-prompts once denied), token-refresh listener. This is real, forward-compatible infrastructure — not a claim that push-per-event already fires, since it doesn't yet anywhere in production.
   - `notify()`-equivalent writes added to chat send (both directions) and review completion (`submitDietReview`/`submitWorkoutReview`), closing the two highest-value gaps for the app's own new features.
   - Not done: wiring `push_service.send_to_token()` into real backend events (coaching, review, chat) — a legitimate backend feature the website itself doesn't have yet either, and too large a change to make safely in this pass. Documented here rather than faked.

**6. Location + Regional Diet personalization — built for real, using the existing production engine.** `backend/services/location_food_engine.py` already exists, is fully data-driven off the real food dataset's `state_of_origin`/region tags (not a hand-typed list), and is already wired into `/api/assessment/generate-plan` via `AssessmentInput.location: dict`. The gap was entirely on the Flutter side: `AssessmentController._buildPayload()` was sending an empty location dict hardcoded. Fixed:
   - `LocationService` (new) — one-time, low-accuracy position fetch (never continuous tracking) plus the same free Nominatim reverse-geocode call the website uses, so `state` resolves to a value `location_food_engine.resolve_state()` already recognizes.
   - `AssessmentController._resolveLocation()` — the OS's own permission dialog is the consent step; on denial/disabled-service/timeout, falls back to the athlete's own Personal Information city/state (real user-provided data, not invented) rather than blocking plan generation.
   - Persisted to `users/{uid}.location` (matches `zitlas_location`'s cloud-sync field) alongside the assessment result, so it survives for future regenerations without needing to re-ask.
   - Order of authority preserved: this only affects the payload sent to `generate-plan` for a NEW plan; it never touches an existing/Expert-reviewed plan, and a location change alone never triggers regeneration (no code path does that).
   - Android manifest: added `ACCESS_COARSE_LOCATION` and `POST_NOTIFICATIONS`.

## Files changed

- New: `lib/core/location/location_service.dart`, `lib/core/notifications/fcm_service.dart`, `lib/features/notifications/models/app_notification.dart`, `lib/features/notifications/data/notifications_repository.dart`, `test/location_and_notifications_test.dart`.
- Rewritten: `lib/features/notifications/presentation/screens/notifications_screen.dart` (placeholder to real).
- Modified: `lib/features/assessment/assessment_controller.dart`, `lib/features/assessment/data/assessment_repository.dart` (location capture + persistence), `lib/features/experts/data/experts_repository.dart` (coaching backend routing fix + chat notify), `lib/features/expert_dashboard/data/expert_repository.dart` (chat notify + review-completed notify), `lib/features/experts/expert_profile_controller.dart` + `personal_coaching_sheet.dart` (simplified to match the new request signature), `lib/app/app.dart` (FCM bootstrap on authentication), `android/app/src/main/AndroidManifest.xml` (2 new permissions), `pubspec.yaml` (`geolocator`).

## Tests

**9 new** (103 total, up from 94): `test/location_and_notifications_test.dart` — `ResolvedLocation`'s exact backend-facing field shape, the empty/no-op case, `hasRegion` boundary, round-trip, null tolerance; `AppNotification.fromMap`'s exact doc shape, unrecognized-category tolerance (never gates creation, matches web), Timestamp/ISO-string tolerance, missing-field tolerance.

## Validation

- `flutter analyze` — no errors (4 pre-existing-style info-level lints only).
- `flutter test` — **103/103 passed**.
- `flutter build apk --debug` — succeeded; installed on the connected physical device; launched clean, no crash in logcat.
- What was NOT live-tested on-device: multi-account chat/coaching/review isolation (no second test account credentials available this session), FCM token delivery end-to-end (no Cloud Function exists server-side to send a real push to verify against), notification tap-routing from a real push (same reason), location permission dialog interaction (requires interactive tapping through Android's OS-level dialog). These are honestly reported as unverified-live rather than claimed complete.

# Regional food personalization fix — availability gating (backend)

## Problem

The Phase 8 region "boost" (`location_food_engine.build_region_boost()`) only ever ADDED weight toward a user's own state — `preferred_categories` folded into a relaxable, non-exclusionary `_pipeline_ids()` stage, and `preferred_keywords` folded into the scoring-only `favorite_foods` bonus. Nothing ever EXCLUDED a food from an unrelated region. A Kerala dish like Appam (`region: "South"`, `state_of_origin: ["Kerala"]`, popularity/availability scores in the ordinary 54-65 range — not distinguishable from genuine Pan-India staples by score alone) could reach a Maharashtra user's plan purely because it passed every OTHER filter (diet/goal/budget/etc.) with nothing checking region at all.

## Fix — availability GATING, not just boost

`location_food_engine.py`: added `_STATE_TO_ZONE` (pure India-zonal-council geography — West/North/South/East/Central/Northeast, matching the dataset's own 6 `region` values exactly) and `compatible_regions(location)`, returning `{user's zone, "Pan-India"}` or `None` (fail-open) when unresolvable — deliberately independent of `build_region_boost()`, so a state with zero verified regional dishes still gets a correct zone-level gate.

`food_engine.py`: added a new `_region_eligible_ids()` stage — eligible = `state_of_origin` includes the user's exact state (bucket A) OR `region` is Pan-India/the user's zone (bucket B/C), PLUS an explicit override: any food whose name/category/region matches an entry in the athlete's own `favorite_foods` (bucket D allowed back in on request — "location personalizes by default, never prohibits"). Threaded through `_pipeline_ids`/`recommend`/`build_week_plan`/`_ranked_swap_pool`/`find_swap_alternatives`/`find_swap_combos`, positioned as the LAST (most relaxable) stage in the filter pipeline — so nutrition/goal/diet/budget/living/season all take priority over regional availability if they'd conflict, per the spec's stated priority order.

`groq_service._engine_query_context()`: computes `user_state`/`compatible_regions` once per request and returns them in `ctx`; both the LLM-grounded path (`generate_diet_plan`) and the deterministic fallback (`_engine_grounded_diet_plan`) call the SAME `engine.build_week_plan()`, so one fix covers both — foods are always engine-selected, never LLM-invented (the pre-existing "hallucination firewall"), so this is the actual enforcement point regardless of which path serves the request. Meal-swap (`find_swap_combos`) got the same wiring for consistency.

## Evidence

- **Why Appam could reach a Maharashtra user (before)**: confirmed via direct dataset inspection (`node` script) — Appam's `region: "South"`, `state_of_origin: ["Kerala"]`, and nothing in the pipeline ever checked either field for exclusion.
- **Maharashtra regression** (`test_regional_diet.py`, new): a full 7-day Maharashtra plan generated through the real `_engine_query_context` → `build_week_plan` path contains zero occurrences of "appam" across all slots/days by default; with an explicit `favorite_foods: ["appam"]` override, Appam becomes pipeline-eligible again (tested in isolation via `_pipeline_ids` directly, since `recommend()`'s top-N ranking has unrelated confounds like season-tag matching that would make a full-pipeline assertion flaky for one specific dish).
- **Generalization beyond Maharashtra**: Kerala excludes Misal Pav (Maharashtra-specific) by default; Punjab excludes Appam by default — same mechanism, reversed direction, not a `if state == 'Maharashtra'` special case.
- **Nutrition preserved**: sparse-coverage state test (Nagaland, non-vegetarian) still produces a non-empty, real meal for every slot across all 7 days — the region gate relaxes rather than starving the plan. All pre-existing `test_meal_quality.py`/`test_workout_engine.py` suites still pass unmodified.
- **No-location no-op preserved**: `user_state`/`compatible_regions` are both `None` with no location, and a plan still generates normally (identical to pre-fix behavior).

## Files changed

`backend/services/location_food_engine.py`, `backend/services/food_engine.py`, `backend/services/groq_service.py`, `backend/routes/assessment.py`, `backend/test_regional_diet.py` (8 new regression tests).

## Validation

- `backend/test_regional_diet.py` — **ALL PASSED** (8 new + all pre-existing).
- `backend/test_meal_quality.py` — **ALL PASSED** (unmodified, no regressions).
- `backend/test_workout_engine.py` — **PASSED** (unrelated engine, confirmed untouched).
- `flutter analyze` — no errors (backend-only change; Flutter untouched this pass).
- `flutter test` — **103/103 passed** (unchanged).

# Location permission + intelligent swap-meal UX (mobile)

## Why location permission wasn't appearing

The previous phase's `AssessmentController._resolveLocation()` DID call the real Geolocator permission API, but silently, buried inside the "Processing…" step with zero explanatory UI first — easy to miss, and it ran on every assessment rather than once. There was also no durable, user-confirmed region: raw GPS output was folded straight into that one request's payload and nothing was ever persisted as a stable preference. Swap Meal was worse: it read `assessment['location']`, a key Assessment never actually writes (location is persisted as its own top-level `location` field) — so that reference always resolved to nothing, and Swap Meal never carried region at all.

## Fix

**Canonical field**: `users/{uid}.preferredDietRegion` (a plain state-name string) — the ONE durable, user-confirmed preference, distinct from `users/{uid}.location` (the raw GPS/reverse-geocode snapshot, unchanged from the prior phase, used only to seed a suggestion). `DietRegionRepository` (new) owns read/write/watch. GPS or manual selection both write here identically; nothing else ever silently overwrites it — a temporary trip doesn't touch it, and no code path regenerates an existing Diet because location changed.

**Consent flow** (`core/location/presentation/location_setup_flow.dart`, new): triggered once from the Assessment screen (`didChangeDependencies` → checks Firestore directly for an existing `preferredDietRegion` before showing anything — Part N's "don't re-ask" rule) — explanation sheet ("Personalize your food recommendations…") → `[Allow Location]` (real `Geolocator.requestPermission()`, the actual Android runtime dialog) → detect → confirm sheet ("We detected: Maharashtra" / `[Use Maharashtra]` / `[Change Region]`), or `[Choose Region Manually]` straight into a searchable picker (`core/location/indian_states.dart` — the exact 33 states/UTs `location_food_engine._STATE_TO_ZONE` recognizes, not an invented list). Denial/disabled-service/timeout all fall through to the same manual picker rather than blocking anything.

**Reaching the backend**: `AssessmentController` now reads the persisted `preferredDietRegion` (never a fresh GPS call) and sends `{'state': region}` as `location` in the generate-plan payload; `DietController.requestMealSwap()` was fixed to do the same for `/api/ai/swap-meal`. Debug-mode logs added at every step per the spec's exact examples: `[REGION] permission = …`, `[REGION] detected state = …`, `[REGION] preferredDietRegion = …`, `[DIET] generating with region = …`, `[SWAP] requesting alternatives with region = …` — none log raw coordinates.

**Profile setting** (Part M): Personal Information now has a "Preferred Food Region" row with `Change`, reusing the same picker. Changing it only affects future generation/swaps — nothing here regenerates the current Diet.

**Swap Meal reason step (Part H)** — audited `frontend/pages/diet/diet.js`/`diet.html`'s REAL `#swapModal` first: it already has this exact feature, a 3-phase flow (choose reason → loading → suggestion), with 7 fixed reasons whose exact `data-reason` text the backend keyword-matches (`groq_service._build_reason_context`/`_diet_type_from_reason`). The previous Flutter sheet had a free-text box instead — replaced with the exact 7 website reasons/icons/copy (`kDietSwapReasons`), preserving the existing single-suggestion + Try Again + Accept flow (the website has no "list of multiple alternatives to pick from" — that was never real, so it wasn't invented here). Region gating for "Not available near me" already works via the region-availability engine fix from the previous phase (`find_swap_combos` already receives `user_state`/`compatible_regions` from `_engine_query_context`, unconditionally, for every swap) — no backend change needed here.

**Expert-review safety**: no code path in this phase touches `originalDietPlan`/`currentDietPlan`/`expertModifications`/review metadata — swap continues to update only the one targeted meal through `DietController.acceptSwap()`, unchanged.

## Files changed

New: `lib/core/location/indian_states.dart`, `lib/core/location/diet_region_repository.dart`, `lib/core/location/presentation/region_picker_sheet.dart`, `lib/core/location/presentation/location_setup_flow.dart`, `test/diet_region_and_swap_reasons_test.dart`.
Modified: `lib/features/assessment/assessment_controller.dart` (removed the silent GPS call; reads persisted region instead), `lib/features/assessment/data/assessment_repository.dart` (removed the now-dead `fetchManualRegion`), `lib/features/assessment/presentation/screens/assessment_screen.dart` (drives the one-time consent flow), `lib/features/diet/diet_controller.dart` (fixed the dead `assessment['location']` reference), `lib/features/diet/presentation/widgets/diet_meal_swap_sheet.dart` (rebuilt with the real 7-reason phase), `lib/features/profile/presentation/screens/personal_info_screen.dart` (Preferred Food Region row).

## Validation

- `flutter analyze` — no errors (6 pre-existing-style info-level lints only, 2 new `use_build_context_synchronously` infos in the consent-flow function).
- `flutter test` — **110/110 passed** (7 new).
- `flutter build apk --debug` — succeeded; installed and launched clean on the connected physical device.
- **Live on-device**: the swap-meal reason sheet was confirmed rendering with the exact 7 website reasons/icons/copy, and selecting a reason produced the real debug log `[SWAP] requesting alternatives with region = (none)` — honestly reflecting that this pre-existing test account has no confirmed region yet (it predates this phase). The full consent→detect→confirm flow and the Profile "Change" picker were not exercised live this pass — further on-device navigation was stopped after a stray tap landed on an unrelated app on the tester's personal phone, rather than continuing to poke around it. Both are covered by `flutter analyze`/the model-level test suite and direct code tracing against the real endpoints instead of a live tap-through.

# Swap Meal fix — "Could not get a suggestion" root cause

## Root cause (two real contract mismatches, found by reproducing against the live production backend, not by guessing)

Curl-reproducing `POST https://zitlas.com/api/ai/swap-meal` with a hand-built payload matching what Flutter *should* send returned a clean 200 with a real alternative in ~2s — proving the backend, the food dataset, and the region-gating pipeline were all healthy. The bug was entirely in what Flutter actually sent:

1. **`previous_suggestions` shape mismatch.** `SwapMealRequest.previous_suggestions` on the backend is `list[list[str]]` (a bare list of food-name strings per prior attempt). Flutter was sending its own `List<Map<String, dynamic>>` bookkeeping structure (the full `{name, foods, calories, protein_g, reason}` suggestion objects it keeps for "Try Again") straight through. FastAPI/Pydantic rejects a dict where a `list[str]` is expected — HTTP 422, with zero detail ever surfacing past `requestMealSwap()`'s broad `catch`.
2. **`meal_time` non-nullable.** `SwapMealRequest.meal_time: str = Field(default="")` — a plain `str`, not `Optional[str]`. Flutter's `DietController.requestMealSwap()` passed `meal.time` (`String?`) straight through; a plan entry with no time recorded serializes to JSON `null`, which Pydantic also rejects for a non-Optional `str` field — the same silent 422.

Both failures looked identical to the user: `requestMealSwap()`'s `catch (e) { swapError = e; return null; }` discarded the real `ApiException` (status 422, detail message) entirely, so the sheet could only ever say the one generic sentence — exactly the "no useful debug information" problem called out in the task.

## Fix

- `DietRepository.swapMeal()` now reshapes `previousSuggestions` to `List<List<String>>` (extracting `foods`) before sending, matching the real contract.
- `DietController.requestMealSwap()` sends `meal.time ?? ''` instead of the raw nullable value.
- Swap-meal's request timeout raised from the default 30s to 60s (matches `generate-plan`'s existing reasoning: a RAG retrieval + LLM call, with a Groq→Gemini→OpenRouter fallback chain, can occasionally run past 30s under provider load even though the common case is ~2s).
- Added a new `swapErrorCategory` (`NETWORK_ERROR | AUTH_ERROR | VALIDATION_ERROR | BACKEND_ERROR | AI_PROVIDER_ERROR | INVALID_RESPONSE`) plus debug-mode logging of the real `ApiException` status/message/body — the athlete-facing message is unchanged, but a debug build now prints exactly what failed and why instead of only the generic sentence.
- Deterministic dataset-only swap already never depended on the LLM being reachable — `routes/ai.py`'s `swap_meal()` falls back to `offline_fallback.meal_swap()` (same `FoodRecommendationEngine`, same dataset) on any provider exception, so a simple swap already survives an AI outage; this pass didn't need to change that.

## Evidence

- Direct curl reproduction against the real production endpoint, both with a "clean" payload and with the exact field values (title-case `fitness_goal`, `null` `disliked_foods`) the real app sends — both returned HTTP 200 with genuine dataset-sourced alternatives (Khichdi with Extra Ghee / Egg Pakora, real `food_id`s, real calories/protein).
- **Live on-device, post-fix**: a fresh app launch showed a real, previously-persisted successful swap (Breakfast's stored meal had already changed from "Protein Rich Khichdi" to "Egg Pakora" — proof `acceptSwap()`'s persistence path works end-to-end too, not just the suggestion step), and a subsequent swap request completed and rendered "Suggested swap: Egg Pakora (1 bowl (150 g)) · 202 kcal · 12.0g protein · Why this works: …" with working Try Again/Accept — the exact shape and content the production curl call also returned.
- Could not isolate, with 100% certainty, which of the two contract bugs was the specific trigger for the athlete's original report (both are real, independent 422 causes) — reported honestly as "two confirmed bugs, both fixed, pipeline now verified working end-to-end" rather than overclaiming a single isolated root cause.

## Files changed

`lib/features/diet/data/diet_repository.dart` (reshape + timeout), `lib/features/diet/diet_controller.dart` (null-safe meal_time, error classification + debug logging).

## Validation

- `flutter analyze` — no new errors.
- `flutter test` — **110/110 passed** (unchanged; this fix has no unit-testable pure-function surface without mocking the HTTP layer, so it's verified by the live reproduction above instead).

---

# Regional ranking fix — "Gujarati Dal" swapped for "Khaman Dhokla" (backend)

## Root cause

Region was gating (in/out) but never scoring. `_pipeline_ids()`'s `region` stage decides *admissibility* only — Pan-India + the user's own state + everything in the user's broad zone (`_STATE_TO_ZONE`: Maharashtra and Gujarat are BOTH zone `"West"`). Once inside that admitted pool, `_score()` had **no region term at all** — ranking was decided purely by goal/availability/budget/preference, on which two Gujarati snacks (Gujarati Dal, Khaman Dhokla) tie almost exactly. So a Maharashtra user's swap could land on any West-zone dish, including one from a different state's cuisine entirely.

A second, compounding data-quality bug: the existing state index was built from `state_of_origin`, which is **empty on 3,748 of 4,520 foods (83%)** — including "Gujarati Dal" itself (`state_of_origin: []`, despite `category: "Gujarati Foods"`). Dataset inspection found a separate field, `available_states`, that is **never empty** (0/4520) and is superset-consistent with `state_of_origin` everywhere both are populated (`"All"` for genuine Pan-India dishes, an explicit state list otherwise) — the correct, complete field to index on, not invented.

## Fix — region becomes a real, weighted scoring tier (not just a filter)

1. **`FoodRecommendationEngine.__init__`** (`food_engine.py`) — state indexing switched from `state_of_origin` to `available_states` (`self._effective_states: dict[id, frozenset[str]]`), so foods missing `state_of_origin` are no longer invisible to their real state's bucket.
2. **New `_region_component(food, user_state, compatible_regions, favorite_foods)`** — a 5-tier scorer, generic across every state (no per-state hardcoding):
   - `1.00` user's own state | `0.75` Pan-India | `0.50` explicit favorite-food override of another state's dish | `0.30` another state's dish merely sharing the user's broad zone (the Khaman Dhokla case) | `0.15` outside the zone entirely | `0.70` no location resolved (unchanged no-op).
3. **New weight `_W_REGION = 0.20`** folded into `_score()` — weights rebalanced to `GOAL .30 / MEDICAL .20 / REGION .20 / AVAIL .12 / BUDGET .08 / PREF .05 / VARIETY .05` (still sums to 1.0). Region is now the second-highest ranking-relevant weight, after goal.
4. **`_ranked_swap_pool()`** — was hardcoding `favorite_foods=[]` into its `_score()` call (silently disabling both `pref_component` and the new region override tier for every swap); now passes the real list through.
5. **`[REGION_RANK]`** debug print added to `_ranked_swap_pool()` — logs the top-5 candidates' region/state/tier/score whenever `user_state`/`compatible_regions` is set.
6. **Closed a known pre-existing gap**: `offline_fallback.py`'s `_engine_context()` never computed `user_state`/`compatible_regions` at all, so region gating AND the new scoring tier were silently skipped whenever a request fell back to the offline path (e.g. all AI providers down). Now threaded through `_engine_foods_for_slot()` and `meal_swap()`'s `find_swap_combos()` call, matching the online path.
7. **Debug logs added**: `[DIET_REGION]`/`[SWAP_REGION] backend received = <state>` in `routes/ai.py` (both `nutrition-weekly-plan` and `swap-meal`), `[REGION] resolved state = ...` in `groq_service._engine_query_context`, `[REGION] offline path resolved state = ...` in `offline_fallback.py`.

Serving/unit check (report item 11): confirmed **not a pipeline bug** — `format_food_line()` already sources `serving_size` from the *replacement* food's own dataset record, never inherited from the original meal. "Gujarati Dal (1 piece (50 g))" is that dish's own (admittedly odd, dal-as-"piece") dataset value — a pre-existing content quirk in that one field, unrelated to and untouched by this fix; not patched, per the "don't hand-patch individual foods" instruction.

## Evidence

**Direct score comparison** (Maharashtra user, `_score()` with identical goal/living/budget args):

| Food | available_states | region tier | region_component | final score |
|---|---|---|---|---|
| Misal Pav | `["Maharashtra"]` | preferred | 1.00 | **0.9561** |
| Poha | `["Maharashtra", "MP", "Gujarat", "Rajasthan", "Chhattisgarh"]` | preferred | 1.00 | **0.9702** |
| Khaman Dhokla | `["Gujarat"]` | other-state-same-zone | 0.30 | 0.5122 |
| Gujarati Dal | `["Gujarat"]` (state_of_origin was `[]`) | other-state-same-zone | 0.30 | 0.5335 |

**Swap reproduction** — `find_swap_combos(meal_slot="mid_morning", ..., exclude_names=["Gujarati Dal"], user_state="Maharashtra", compatible_regions={"West","Pan-India"})` → top result: `Curd (Dahi) (Full Fat)` (Pan-India, score 0.9235). Khaman Dhokla does not appear anywhere in the ranked top-30 pool.

**Initial 7-day generation, Maharashtra**: 61 total food items — **46 Maharashtra-compatible, 15 Pan-India/common, 0 other-region-specific**.

**Generalization across states** (`_region_component`, no per-state code): for a **Punjab** user, Khaman Dhokla (Gujarat) scores 0.30, not 1.00. For a **Tamil Nadu** user, Gujarati Dal scores 0.30. For a **West Bengal** user, Misal Pav (Maharashtra) scores 0.30. Each state's *own* foods (via `available_states`) score 1.00 for that state only.

**Explicit-preference override preserved**: Maharashtra + no explicit preference → Appam absent from the eligible pool entirely (unchanged from the earlier regional-gating fix). Maharashtra + `favorite_foods=["Appam"]` → Appam re-admitted, `region_component = 0.50` (opt-in tier, still ranked below Pan-India/local, never top-ranked by default).

## Files changed

`backend/services/food_engine.py` (state indexing on `available_states`, `_region_component`, `_W_REGION`, `_score`/`recommend`/`_ranked_swap_pool` wiring, `[REGION_RANK]` debug), `backend/services/offline_fallback.py` (region params threaded into the offline path — closes the known gap), `backend/services/groq_service.py` (`[REGION]`/`[DIET_REGION]`/`[SWAP_REGION]` debug logs), `backend/routes/ai.py` (`[DIET_REGION]`/`[SWAP_REGION] backend received` logs), `backend/test_regional_diet.py` (2 new regression tests: the exact reported bug, and generalization across Punjab/Tamil Nadu/West Bengal).

## Validation

- `python -m pytest backend/test_regional_diet.py` — **26/26 passed** (24 pre-existing + 2 new).
- `python -m pytest backend` (excluding an unrelated pre-existing `test_meal_quality.py` collection issue and unrelated pre-existing `tests/test_coaching.py` failures, both confirmed via `git stash` to predate this change) — **44/44 passed**, zero regressions from this fix.
- `flutter analyze` — same 6 pre-existing info-level lints, no new issues (no Flutter code changed this pass).
- `flutter test` — **110/110 passed**, unchanged.
- Backend: unchanged this pass (per the task's explicit instruction not to rebuild it) — verified read-only via direct curl calls against the deployed production API.

---

# Real step counter — Health Connect + hardware sensor (mobile)

## What existed before

The Activity card (`activity_card.dart`), its ring, the Mon–Sun strip, Recovery
Mode, the adaptive-goal suggestion, `ActivityDayModel`, and the
`users/{uid}/activity/{date}` read path were all already built and reading real
Firestore data. The card's own header comment named the gap precisely: on-device
step **capture** was the one deferred piece (the Capacitor
`HealthConnectPlugin.java`/`StepSensorPlugin.java` were dropped in the Flutter
migration). So this phase added a real source and wired it in — it did not
redesign the Dashboard.

## Architecture chosen, and why

**Hybrid, two sources, never summed** — the same design the website used:

1. **Health Connect** (source of truth when present + granted). Read ONLY via
   the platform's `AggregateRequest(StepsRecord.COUNT_TOTAL)`. This is the
   deduplication answer: HC can hold overlapping step records from several
   providers (phone, watch, Fit, an OEM health app), and its aggregate is the
   only thing that resolves them correctly. Summing `readRecords()` by hand is
   exactly how impossible counts happen.
2. **Hardware `TYPE_STEP_COUNTER`** (fallback). The chip counts in hardware
   while the process is dead and the screen is locked, at ~no battery cost —
   this is what makes background capture work without a foreground service.
   Critically, it is also the source that actually works on a stock phone where
   Health Connect is installed but *nothing is writing steps into it*, which is
   the common case.

`health` (pub.dev) was evaluated and **rejected**: every version ≥12 pins
`device_info_plus` → `win32 ^5.x`, which conflicts irreconcilably with the
project's existing `share_plus ^13.3.0` → `win32 ^6.0.1`. Rather than downgrade
a working feature's dependency over a Windows-only transitive conflict, the
Health Connect surface ZITLAS actually needs (one availability check, one
permission request, one aggregate query) is ~200 lines of Kotlin we own.

## Midnight-to-midnight

`startOfLocalDay(now)` = `DateTime(now.year, now.month, now.day)` — constructed
in the device's *current* local zone, so it stays correct across timezone
changes and DST. The window `[local 00:00, now)` is computed in Dart and passed
into the native aggregate; the boundary is never computed natively, so there is
exactly one definition of "today" in the codebase. `startOfNextLocalDay` adds to
the day *component* rather than a 24-hour `Duration`, because a DST day is 23 or
25 hours long. No 24h timer, no UTC, no since-launch arithmetic anywhere.

Day rollover needs no timer at all: the day key is re-derived on every read, and
milestone state stored under yesterday's key reads back as empty today.

**Device step history is never deleted** — "reset at midnight" means the UI
starts displaying a new calendar day. Health Connect records and the sensor's
since-boot counter are read-only to ZITLAS.

## Sensor baseline safety

The since-boot counter needs `current - baselineAtStartOfDay`, which is a
classic source of absurd numbers. Every failure mode is handled explicitly and
tested: reboot (detected via boot timestamp, with a 90s drift tolerance so
NTP correction isn't a phantom reboot — and steps already earned that day are
carried forward, not erased), new local day, counter decrease without a reboot,
and implausible spikes (capped at 5 steps/sec against elapsed time). First-ever
read credits **0**, never the whole since-boot total.

## Notification behaviour

Local (`flutter_local_notifications`), not FCM — a step milestone is a
device-side fact, and `FcmService`'s own note confirms no Cloud Function exists
to send one anyway. Milestones 25/50/75/100, **max once per calendar day**,
state persisted so a restart can't re-fire. When several become eligible at once
(steps arrive in batches), only the **highest** is announced and the leapfrogged
ones are marked notified so they can never fire retroactively — 100% therefore
always wins when newly crossed. Lowering the goal mid-day completes it once and
stays silent thereafter. A paused (0) goal never notifies. Notification
permission denial never stops counting.

## Android limitations (honest)

Background milestone delivery uses WorkManager, and is **best-effort by design**:
15 minutes is Android's hard periodic floor; Doze/App Standby stretch that to
hours when the screen is off; aggressive OEM battery management
(OnePlus/Oppo/Xiaomi/Samsung) can stop it entirely; force-stop halts it until
next open. **What is never compromised is the step COUNT** — both sources
accumulate independently of this app running, so a delayed background run delays
a *notification*, and the steps appear in full the moment ZITLAS reopens.

## Goal source

No new field. Existing chain, in priority order: `activity/{date}.goalEffective`
(Recovery Mode) → `users/{uid}.dailyStepGoal` (athlete's explicit goal) →
`calculations.daily_steps_goal` (what Assessment recommended, written by
`assessment_service.py:1322`) → 10,000. The third step is new resolution logic:
previously a missing `dailyStepGoal` fell straight to a hardcoded 10,000,
ignoring the Assessment's own recommendation.

## Files changed

**New:** `lib/core/steps/step_platform.dart`, `step_day.dart`,
`step_sensor_baseline.dart`, `step_notifications.dart`,
`step_tracking_service.dart`, `step_background_worker.dart`,
`presentation/step_consent_sheet.dart`;
`android/app/src/main/kotlin/com/zitlas/app/StepTrackerPlugin.kt`;
`test/step_counter_test.dart`, `test/step_tracking_service_test.dart`.

**Modified:** `MainActivity.kt` (→ `FlutterFragmentActivity`, needed for
`registerForActivityResult`), `AndroidManifest.xml` (HC READ_STEPS,
ACTIVITY_RECOGNITION, rationale activity + activity-alias, package queries),
`build.gradle.kts` (minSdk 24→26 for `connect-client`, desugaring, HC +
coroutines deps), `dashboard_controller.dart`, `dashboard_repository.dart`
(`saveDailySteps`), `activity_card.dart` (real data + unavailable states),
`dashboard_screen.dart` (resume/open refresh), `profile_screen.dart` (Step
Tracking row), `main.dart`, `pubspec.yaml`.

## Validation

- `flutter analyze` — 6 pre-existing info lints, **no new issues**.
- `flutter test` — **157/157 passed** (110 before, +47 new).
- `flutter build apk --debug` — **succeeded**.
- **Real-device acceptance test — NOT PERFORMED.** No Android device was
  connected to this machine at implementation time (`adb devices` empty,
  `flutter devices` showed only Windows/Chrome/Edge). The walk-with-phone-locked
  verification in requirement F/Y remains outstanding and must be run before
  this feature is considered shipped.

---

# Zino — AI fitness companion (mobile)

## What the website actually had (audited first, source of truth)

`frontend/assets/js/zino.js` (773 lines) holds three cooperating pieces:
`ZinoManager` (context + `POST /api/ai/zino-chat`), `FloatingAssistant` (the
FAB + chat overlay), and `TutorialEngine` (a first-run spotlight walkthrough).
The persona, provider chain, and safety rules live server-side in
`groq_service.ZINO_COMPANION_SYSTEM` + `routes/ai.py::zino_chat`.

The Flutter side was a **bare `PlaceholderScreen`** — the route existed, nothing
behind it.

## Parity achieved

| Website | Flutter |
|---|---|
| `ZinoManager.buildContext()` | `ZinoContextBuilder.build()` |
| `POST /api/ai/zino-chat` | `ZinoRepository.send()` — same endpoint, same payload |
| `unwrapReply()` | `unwrapZinoReply()` |
| `CHIPS` (9 quick actions) | `kZinoChips` — verbatim |
| `_PAGE_MAP` / `current_page` | `ZinoScreenContext` — purpose strings verbatim |
| `_history` (20-cap, per session) | `ZinoController` (20-cap, **per uid**) |
| `.zn-fab` on every page | `ZinoFab` in `AppShell` (all 5 tabs) |
| `.zn-bubble`, `.zn-typing`, input bar | `_Bubble`, `_TypingBubble`, `_InputBar` |

**No backend change.** The persona, RAG, provider fallback chain, and safety
rules were already correct and are shared with the live website — modifying
them would have changed the site's behaviour. No API key exists in the app.

## Context layer — relevant, not everything

Context is rebuilt fresh per message (never cached — live state must not go
stale), reads only the signed-in uid's own documents, and strips nulls before
sending. Bulky structures are summarized: the full 7-day plan is large, so only
**today's** meals/focus travel. SWOT sends the headline strength/weakness, not
four lists of paragraphs.

**Expert-aware:** reads `currentDietPlan`/`currentWorkoutPlan` FIRST — the plan
actually in force — so Zino describes what a human expert approved, never the
superseded AI original, and carries `isCoachManaged` + `expertName` so it can
say *"your expert adjusted today's plan"* instead of contradicting them.

**Region-aware:** prefers the canonical `preferredDietRegion` over the raw GPS
snapshot, so Zino reasons with the same value the diet/swap engine uses.

**Step-aware:** prefers the live on-device reading (freshest by definition),
falling back to today's synced day doc.

## Actions — the security model

Requirement: *"DO NOT allow raw LLM output to arbitrarily execute application
code."* The design goes further than filtering model output — **the model
cannot emit an action at all**:

- Actions are a fixed typed enum (`ZinoAction`); no string→route evaluation, no
  dynamic dispatch. A test asserts every route exists in `router.dart`.
- Intent is derived from the **athlete's own message** via a pure keyword
  function, never from the reply. A prompt-injected or hallucinated response
  therefore cannot trigger navigation.
- Every action is **navigation-only** to a screen already reachable from the
  nav bar. Nothing writes data, spends money, or changes a plan.
- Actions render as a chip the athlete taps — **that tap is the confirmation**.
- Anything destructive/costly is deliberately excluded. `swapMeal` opens the
  Diet screen where the real Swap Meal sheet (reason → alternatives → confirm)
  keeps its own flow; Zino never performs the swap.

This also keeps the backend persona honest — it explicitly promises never to
claim it took an action.

## Memory — three separate tiers

1. **Conversation history** — recent thread, uid-scoped local key, 20-cap,
   replayed for continuity ("my knees are sore" is still visible two turns
   later). Disposable.
2. **Durable profile data** — goal, assessment, medical conditions. Zino
   **reads only**; a casual remark can never rewrite a medical field.
3. **Live app state** — steps, plan, streak. Rebuilt every message, never stored.

**Cross-account isolation has two independent layers:** the history key embeds
the uid (`zitlas_zino_history_<uid>`), so a different athlete reads a different
bucket entirely; and `AccountGuard.clearExcept()` already purges it on logout
and account switch. Both are covered by tests.

## Failure handling

Failed sends keep the athlete's text visible and marked "Not delivered" (never
silently dropped, never a fabricated reply), expose a Retry, and are excluded
from persisted history — an undelivered turn has no reply to pair with.
Errors are classified internally (`NETWORK_ERROR`/`AI_PROVIDER_ERROR`/…) while
the athlete sees Zino-voiced copy, never a code.

## Files changed

**New:** `lib/features/zino/data/zino_context_builder.dart`,
`data/zino_repository.dart`, `models/zino_message.dart`, `models/zino_action.dart`,
`zino_controller.dart`, `presentation/widgets/zino_fab.dart`,
`test/zino_test.dart`.
**Rewritten:** `presentation/screens/zino_screen.dart` (was a placeholder).
**Modified:** `app/router.dart` (`?from=`/`?expertId=` params),
`core/widgets/app_shell.dart` (FAB on every tab),
`dashboard_screen.dart` (removed its local FAB — now global).

## Validation

- `flutter analyze` — 9 info lints, all `prefer_initializing_formals` matching
  the existing codebase convention. **No warnings or errors.**
- `flutter test` — **195/195 passed** (157 before, **+38 new**).
- `flutter build apk --debug` — **succeeded**.
- **Real-device test — NOT PERFORMED.** No Android device was connected
  (`adb devices` empty). The on-device checklist in the task (new/existing
  user, network loss, logout/login, long conversations) remains outstanding.

---

# Zino position (top-right) + first-run tour

## Position — a correction to the previous phase

The previous Zino phase placed the launcher as a bottom-right material FAB with
an orange gradient fill. **That was wrong.** `frontend/assets/css/zino.css:136`
defines it as:

```css
.zn-fab { position: fixed; top: calc(78px + env(safe-area-inset-top)); right: 16px;
          width: 52px; height: 52px; border: 2.5px solid #FF9900; background: #fff; }
```

TOP-RIGHT, white fill, orange border, carrying `zino.png`, with a `znPulse`
ring (`::after`, scale 0.9→1.35, 2.6s, infinite). All of that is now
reproduced: `ZinoFabOverlay` pins it via `SafeArea(bottom: false)` — the Flutter
equivalent of `env(safe-area-inset-top)` — so the 78px offset is measured below
the status bar/notch and clears the page header rather than colliding with it.
Mounted once in `AppShell`, so it is identical on all five tabs.

## Tour — ported from `TutorialEngine` (zino.js:270-574)

Titles and body copy are **verbatim**; this is an existing onboarding script,
not something to rewrite. Two adaptations, both deliberate:

* The website's three Expert-Profile stops (`request-review`, `hire-coach`,
  `chat`) are folded into the Experts stop. Reaching an expert profile requires
  picking a specific expert, and auto-navigating into an arbitrary one mid-tour
  is impossible on a fresh account with no experts loaded. Their content is
  preserved in the Experts stop copy.
* A `zino-here` stop is **added** (the task asked for it) to introduce Zino's
  own top-right location — the website never needed it, since its FAB is
  visible on every page from the first second.

Stops spotlight the REAL widgets via `GlobalKey`s attached at the use site with
`KeyedSubtree`, so no widget needs to know a tour exists. A stop whose target
isn't mounted is skipped — matching the website, where a `querySelector` miss
skips the stop. This matters because a genuinely new account has no diet plan,
no experts and no coach yet.

## New-user detection — the part that must not regress

**Canonical field: `users/{uid}.zinoTourCompleted`** — the SAME field
`markDone()` writes on the website. No duplicate field. Written as the STRING
`'true'` for cross-client compatibility; reads accept string or bool. An
athlete who toured on the website is therefore never re-toured in the app.

**Account-level, never install-level.** SharedPreferences is only a fast-path
cache of the authoritative Firestore value. This is what makes reinstall,
logout/login, and the Flutter migration itself non-events.

**Fail-closed.** If the Firestore check can't complete (offline,
permission-denied, timeout), `shouldAutoStart` returns **false**. Ported from
the website's `_confirmNeverToured()`, whose own comment gives the reasoning: a
returning athlete must never be re-toured, whereas a genuinely new one simply
gets the tour on the next launch. This single choice is also what prevents the
endless-onboarding loop a fail-open design would cause on a flaky connection.

**Skip == Finish**, exactly as on the website (`skip()` calls `finish()`).

**Replay** (`Profile → Take Zino Tour Again`) bypasses the new-user check and
does NOT clear `zinoTourCompleted` — replaying can never turn an existing
athlete back into a "new user".

**Tour ≠ Assessment.** Completing the tour writes only the tour field, and a
completed assessment does not suppress the tour. Both directions are tested.

## Files changed

**New:** `lib/features/zino/tour/zino_tour_stops.dart`, `zino_tour_store.dart`,
`zino_tour_controller.dart`, `zino_tour_overlay.dart`; `test/zino_tour_test.dart`.
**Rewritten:** `zino_fab.dart` (top-right position + website appearance),
`core/widgets/app_shell.dart` (tour host + FAB overlay).
**Modified:** `dashboard_screen.dart`, `diet_screen.dart`, `workout_screen.dart`,
`profile_screen.dart` (tour target keys + replay row); `pubspec.yaml`
(`zino_intro.png`/`zino_done.png` assets, `fake_cloud_firestore` dev dep).

## Validation

- `flutter analyze` — 11 info lints, all pre-existing style conventions
  (`prefer_initializing_formals` etc). **No warnings or errors.**
- `flutter test` — **222/222 passed** (195 before, **+27 new**), covering all
  10 enumerated cases including fail-closed offline behaviour.
- `flutter build apk --debug` — **succeeded**.
- **Real-device test — NOT PERFORMED.** No Android device connected.
