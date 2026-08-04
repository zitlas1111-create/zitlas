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

---

# Zino Voice — Phase 1 (infrastructure)

## ⚠️ BLOCKER: the ElevenLabs account is on a FREE plan

Verified against the live API with the configured key:

```
POST /v1/text-to-speech/SGbOfpm28edC83pZ9iGb -> 402 payment_required
"Free users cannot use library voices via the API. Please upgrade your
 subscription to use this voice."
```

This is NOT specific to Zino's voice ID — premade voices (Aria, Rachel) return
the identical 402. **No voice can be synthesized via the API on this plan.**
It is a billing state, not a code defect; the integration is correct and starts
working the moment the plan is upgraded, with no code change.

Because a voice screen with no voice is useless, the app falls back to the
DEVICE speech engine (`flutter_tts`) so Talk with Zino genuinely works today.
`VoiceService.lastSource` reports which was used and the call screen labels it
honestly ("Zino's voice" vs "Device voice") rather than implying premium audio
it isn't delivering.

STT is unaffected — it runs on Groq Whisper using the existing `GROQ_API_KEY`
(verified: auth accepted, only a deliberately-invalid payload rejected).

## Architecture — ElevenLabs is a speaker, not a brain

`/api/voice/chat` calls the SAME `groq_service.chat(system_override=
ZINO_COMPANION_SYSTEM)` the text chat uses, then hands the resulting sentence
to ElevenLabs. No intelligence moved to a voice vendor and ElevenLabs Agents
are deliberately not used. The only thing voice adds to the prompt is a
language instruction plus spoken-output guidance (no emoji/markdown, 1-3
sentences) — appended, never edited into the existing persona, so
`/api/ai/zino-chat` and the website are untouched.

**Verified end to end:** a Hinglish request returned *"Hey Atharva! Aaj ka din
bhi ek naya mauka hai to crush those goals. Keep going, champ!"* with
`voice_available: false` — real Hinglish from the real brain, text delivered
despite the TTS outage. The existing `/api/ai/zino-chat` was re-tested in the
same session and still answers in its original emoji-rich English.

## Secrets

`ELEVENLABS_API_KEY` and `GROQ_API_KEY` exist only in `backend/.env`. Flutter's
entire vocabulary is three HTTP calls to ZITLAS's own server. The voice ID is
env-configurable (`ELEVENLABS_VOICE_ID`, defaulting to `SGbOfpm28edC83pZ9iGb`),
so changing Zino's voice is a deployment change rather than a code patch.

## Backend endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/voice/health` | config visibility — reports whether a key EXISTS, never its value |
| `POST /api/voice/tts` | text → `audio/mpeg` |
| `POST /api/voice/stt` | multipart audio → transcript (Groq Whisper) |
| `POST /api/voice/chat` | text → reply + base64 audio in ONE round trip |

`/chat` bundles reply and audio deliberately: two sequential calls would
serialize two round trips into the athlete's perceived latency on a live call.
If synthesis fails, `audio_base64` is null but `reply` still returns — a voice
outage never costs the athlete their answer.

## Language

Three options (English / Hindi / **Hinglish, recommended**), asked ONCE on
first use and stored **account-level** at `users/{uid}.voiceLanguage` — same
reasoning as `zinoTourCompleted`: it's a fact about the person, not the phone,
so a reinstall or a second device doesn't re-ask, and a shared handset can't
leak one athlete's choice to another. A FAILED read is reported as
`known: false` and distinguished from "never chose", so an offline moment can't
overwrite a real preference. Changeable later in Profile and from the call
screen.

Whisper gets `hi` as its hint for Hinglish — there is no ISO code for
code-switched speech, and hinting Hindi transcribes the Hindi words correctly
while passing English through.

## Privacy

Recorded audio goes to a temp file, is uploaded for transcription, and is
**deleted immediately**. ZITLAS never retains a copy of the athlete's speech.
Clips under 1 KB are discarded client-side as silence rather than uploaded.

## Files

**New (backend):** `services/voice_service.py`, `routes/voice.py`.
**New (Flutter):** `core/voice/voice_language.dart`, `voice_service.dart`,
`voice_language_store.dart`, `voice_recorder.dart`;
`features/zino/voice/zino_call_controller.dart`,
`voice/presentation/zino_call_screen.dart`, `voice_language_sheet.dart`;
`test/voice_test.dart`.
**Modified:** `backend/main.py`, `backend/.env` (+`ELEVENLABS_VOICE_ID`),
`core/network/api_client.dart` (+`postMultipartBytes`, `postForBytes`),
`app/router.dart` (`/zino/call`), `AndroidManifest.xml` (`RECORD_AUDIO`),
`zino_screen.dart` (call entry point), `profile_screen.dart` (language row),
`pubspec.yaml`.

## Validation

- `flutter analyze` — 15 info lints, all pre-existing style conventions. **No warnings or errors.**
- `flutter test` — **252/252 passed** (222 before, **+30 new**).
- `flutter build apk --debug` — **succeeded**.
- Backend E2E via `TestClient`: health 200, tts 503 (correct given the 402),
  chat 200 with real Hinglish + graceful degradation.
- Existing `/api/ai/zino-chat` re-verified: unchanged.
- **Real-device test — NOT PERFORMED.** No Android device connected, so the
  microphone, permission prompt, audio playback, and background/resume
  behaviour are untested on hardware.

## Ready for Phase 2

Yes, with two caveats: the ElevenLabs plan must be upgraded for the premium
voice, and the on-device checks above still need a connected phone. The
assessment conversation, goal/diet/workout generation are deliberately absent —
`ZinoCallController` runs mic → transcript → existing brain → speech and
nothing more.

---

# Expert review completion — duplicate-completion fix

## Root cause: TWO unguarded re-entry windows, not one

Both come from the same mistake — relying on a widget's disabled state to
prevent a second tap. `EdActionButton` does null `onPressed` when `busy`, but
that only takes effect on the NEXT frame, so a fast double-tap is already
through.

**A. `_confirmComplete` opened its dialog BEFORE claiming the busy flag.**
`_busy` was only set inside `_run`, i.e. *after* the confirmation dialog was
answered. A double-tap therefore opened two dialogs; confirming both ran two
completions — two Firestore writes and two success toasts.

**B. "Review & Send" had a busy flag that nothing ever set.**
The button rendered `busy: busy`, but the edit path called
`widget.onEditPlan(r)` directly and never added the review to `_busy`. A
double-tap pushed the plan editor **twice**. Saving on the top copy popped it
and revealed the identical second copy — which is exactly what "the completion
screen showed twice" looks like from the outside.

## Automatic chat navigation — not reproduced

I traced every `ExpertChatScreen` push: all three call sites (`_openReviewChat`,
`_openCoachingChat`, `_openRoom`) are wired to explicit user-tapped buttons, and
neither editor nor the completion path navigates anywhere except a plain pop
back to the dashboard. **There is no code path from completing a review to
Chat**, so I could not reproduce that symptom and cannot claim to have "fixed"
it. The most likely explanation is symptom B: with two editors stacked, the
screen behind the popped one is not where the expert expected to land. The
navigation is now explicit and commented so it can't drift.

One thing I checked and ruled out rather than assumed: the editors were pushed
with `Navigator.push` but popped with GoRouter's `context.pop()`. That mismatch
*looks* like a bug, but `GoRouterDelegate.pop()` resolves to the root navigator
here, so it was popping the right route. I still changed it to
`Navigator.of(context).pop()` for consistency with the push.

## Fixes

1. **`_claim(id)` / `_release(id)`** — a synchronous re-entry guard checked at
   the TOP of every review action, before any `await`. This is what actually
   closes the double-tap window; the button's disabled state is now just the
   visual half.
2. **`_confirmComplete`** claims before showing the dialog, and re-checks the
   live status afterwards (completed on another device while the dialog was
   open → says so once, writes nothing).
3. **`_openEditor`** claims for the editor's whole lifetime.
   `onEditPlan` is now `Future<void> Function(...)` and
   `_openReviewEditor` returns the push future, so the guard spans until the
   editor closes.
4. **`_save` in both editors** re-checks `_saving` before doing anything.
5. **`ExpertRepository._completeOnce`** — every completion path
   (`completeReview`, `submitDietReview`, `submitWorkoutReview`) now runs in a
   transaction that re-reads the review and **no-ops when it is already
   `review_completed`**. This is the last line of defence behind the UI: a
   retry after a timeout, a resumed app, or a second device can never produce a
   second completion. The athlete notification only fires when the call is the
   one that actually performed the write.

## Data guarantees

One atomic write per completion, carrying status + reviewed plan + change
history + expert id/name + notes + `reviewedAt`/`completedAt`. A duplicate call
cannot overwrite `completedAt`, cannot rewrite the completing expert, cannot
clobber a plan the athlete may already have accepted, and cannot re-notify.
`athleteAccepted` is deliberately untouched — that belongs to the athlete's own
accept action.

## Files changed

`presentation/sections/reviews_section.dart` (claim/release guard, both
paths), `presentation/screens/expert_dashboard_screen.dart` (editor push
returns its future), `data/expert_repository.dart` (`_completeOnce`
transaction on all three completion paths),
`presentation/screens/review_diet_editor_screen.dart` +
`review_workout_editor_screen.dart` (save guard, matching pop),
`test/expert_review_completion_test.dart` (new).

## Validation

- `flutter analyze` — 15 info lints, all pre-existing conventions. **No warnings or errors.**
- `flutter test` — **264/264 passed** (252 before, **+12 new**).
- `flutter build apk --debug` — **succeeded**.
- **Discrimination proof**: a throwaway test replicating the OLD plain-`update()`
  path was run and confirmed it DID clobber `completedAt` and `expertName` —
  so the new tests genuinely catch the regression rather than passing vacuously.
- **Real-device test — NOT PERFORMED.** No Android device connected, so the
  physical double-tap, slow-network, and app-resumed-mid-completion cases are
  covered by unit tests only.

---

# Phase — Zino Smart Notification System

## What was built

Eight fixed daily reminders delivered by the Android AlarmManager, so they fire
with the app closed, minimised or the screen locked. Nothing of ours needs to be
running.

| Time | Slot | Category | Copy source |
|------|------|----------|-------------|
| 07:30 | Morning motivation | motivation | 365 quotes, one per day of the year |
| 09:00 | Breakfast | meals | 52 messages |
| 13:00 | Lunch | meals | 51 messages |
| 17:00 | Snack | meals | 51 messages |
| 18:00 | Step progress | steps | Generated from the day's REAL step count |
| 19:00 | Workout | workout | 20 messages, suppressed if already trained |
| 20:30 | Dinner | meals | 51 messages |
| 22:00 | Night wind-down | motivation | 30 messages |

## Design decisions worth knowing

**Rotation is day-of-year, not random.** A notification handed to AlarmManager
hours ahead must display the text it was scheduled with; a random pick at
schedule time and another at display time would disagree. Day-indexing also
makes "never the same message two days running" provable — consecutive days are
always different list positions — rather than hoped for.

**The two contextual slots carry placeholder text in the schedule and are
rewritten at fire time.** A schedule fixed hours earlier cannot know whether the
goal was met. `runStepReminder()` reads the real step total and either
encourages with actual numbers ("6,200 of 8,000 — 1,800 to go") or celebrates;
`runWorkoutReminder()` sends *nothing at all* if the session is already done.
Telling someone to finish steps they already finished is what gets an app muted.

**Preferences are stored as the DISABLED set**, so a category added in a future
release defaults ON without a migration. Device-scoped, not account-scoped —
"don't buzz this phone" is a property of the handset.

**`USE_EXACT_ALARM` is deliberately NOT declared.** It is auto-granted, but Play
restricts it to apps whose core function is an alarm clock, timer or calendar; a
fitness app that declares it fails policy review. `SCHEDULE_EXACT_ALARM` is
requested at runtime instead, and the scheduler falls back to
`inexactAllowWhileIdle` when it isn't held — a reminder inside a window beats no
reminder at all. Profile → Notifications surfaces an opt-in "Allow precise
timing" card only when the grant is missing.

**The permission ask happens after the Zino tour, not at launch.** Android shows
its POST_NOTIFICATIONS dialog exactly once per install; spending it cold is the
fastest route to a permanent "Don't allow". A new user who has just seen what
Zino does understands what the reminders are for.

## Files added

`lib/core/notifications/zino_messages.dart` (365 quotes + 205 slot messages),
`zino_notification_scheduler.dart`, `notification_preferences.dart`,
`zino_contextual_reminders.dart`, `notification_onboarding.dart`,
`presentation/notification_consent_sheet.dart`,
`lib/features/profile/presentation/screens/notification_settings_screen.dart`,
`test/notification_test.dart`, `test/notification_onboarding_test.dart`.

Modified: `AndroidManifest.xml` (boot receiver, `RECEIVE_BOOT_COMPLETED`,
`SCHEDULE_EXACT_ALARM`), `lib/main.dart` (reschedule on every launch),
`lib/core/widgets/app_shell.dart` (one-time ask), `lib/app/router.dart` +
Profile row (`/profile/notifications`).

## Validation

- `flutter analyze lib/ test/` — 21 issues, **all info-level**. No warnings or errors.
- `flutter test` — **351/351 passed** (+32 new across the two notification suites).
- `flutter build apk --debug` — **succeeded**.
- **Real device (OnePlus, Android 15):**
  - All 8 slots confirmed queued in the OS AlarmManager via `dumpsys alarm`, at
    exactly 07:30 / 09:00 / 13:00 / 17:00 / 18:00 / 19:00 / 20:30 / 22:00,
    targeting `ScheduledNotificationReceiver`.
  - Inexact fallback confirmed working: after removing `USE_EXACT_ALARM` the
    alarms re-registered as windowed (`window=+1h`) instead of throwing.
  - Fresh-install permission state confirmed (`granted=false` after uninstall);
    the "already granted" onboarding branch confirmed writing
    `flutter.zitlas_notification_prompted=true` and rescheduling.
  - `am force-stop` cancels the alarms — this is documented Android behaviour
    for an explicit user stop, not a defect. Reopening the app restores them.
  - **Post-reboot verification INCOMPLETE.** The device was rebooted with 8
    alarms queued, but Android disables Wireless Debugging across a reboot, so
    the post-boot alarm queue could not be read. The boot receiver is declared
    and the permission granted; the check itself is still owed.

---

# Phase — Step Tracking Persistence (critical bug fix)

## Root causes found

Four separate defects, all reproduced before being fixed.

**1. The daily total inflated on every read.** `computeSensorDelta`'s normal
branch left `baselineCumulative` at the START of the day while
`_applySensorReading` overwrote `stepsAtBaseline` with the running total. The
two halves of the baseline then described different instants, so each refresh
re-measured the whole day and added it to a figure that already contained it. A
4,000-step day reported 9,000 after four reads. Proven with a throwaway test
before the fix; that test is now `step_persistence_test.dart`.

**2. The counter froze for the rest of the day.** Same root cause. The
plausibility cap is sized per INTERVAL (5 steps/second since the last read),
but the delta being compared against it was measured from the start of the day.
After a couple of hours of walking, every subsequent read looked implausible,
was rejected, and the count stuck.

**3. "Enable step tracking" reappeared on a working, granted device.** Two
causes. `refresh()` mapped ANY unreadable source to `permissionDenied` without
checking whether a permission was actually missing — and TYPE_STEP_COUNTER is
an on-change sensor that legitimately reports nothing on a stationary phone.
Separately, `AccountGuard`'s purge list did not preserve the step keys, so
every sign-out deleted `zitlas_step_tracking_enabled` and the sensor baseline.
The OS grant survived; ZITLAS's memory of it did not.

**4. Yesterday could not be viewed.** Nothing ever read Health Connect for a
past day, and there was no history screen. Local history only ever contained
days the app happened to be open for.

## Fixes

| Fix | Where |
|-----|-------|
| Baseline re-anchors on every read; origin and total always describe the same instant | `step_sensor_baseline.dart`, `step_tracking_service.dart` |
| Service persists exactly the baseline the math produced | `step_tracking_service.dart` |
| `StepSource.cached` replays today's stored total when a read comes back empty | `step_tracking_service.dart` |
| `StepUnavailableReason.noReadingYet` — a waiting state, never an Enable button | `step_tracking_service.dart`, `activity_card.dart` |
| `ensureTrackingActive()` resumes silently whenever the OS grant is already held | `step_tracking_service.dart`, `dashboard_controller.dart` |
| Step/permission/baseline keys preserved across sign-out | `account_guard.dart` |
| Native local-midnight capture (AlarmManager + BroadcastReceiver, no Flutter engine) | `StepDayBoundary.kt` (new), `AndroidManifest.xml` |
| Boundary folded into both days on next launch, consume-once | `step_tracking_service.dart` |
| Health Connect backfill of the last 30 days | `step_tracking_service.dart` |
| Local history hydrated from synced day docs (survives reinstall/new device) | `step_tracking_service.dart`, `dashboard_controller.dart` |
| Streaks computed from real recorded days and persisted | `step_history.dart`, `dashboard_controller.dart`, `dashboard_repository.dart` |
| Step History screen (Today / Yesterday / 7 / 30 days) | `step_history_screen.dart` (new) |
| Distance / calories / active time from real height+weight | `step_metrics.dart` (new) |

## How midnight rollover works

`StepDayBoundaryReceiver` is armed by AlarmManager for 00:00:05 local, re-armed
on every fire, on every app launch, and on BOOT_COMPLETED. It is plain Kotlin —
no Flutter engine, no foreground service — so it costs nothing until it fires
and lands on time regardless of whether ZITLAS is running.

It reads TYPE_STEP_COUNTER once and writes `{dayKey, cumulative, bootTimeMillis}`
into the same SharedPreferences file Dart uses. On the next launch,
`_settleCapturedBoundary()` uses that one number twice: yesterday's closing
total is `stepsAtBaseline + (boundary - baselineCumulative)`, and today's origin
is anchored at `boundary` with a zeroed total. That is what recovers the steps
walked between the last time the app was open and midnight — they are otherwise
unrecoverable, because the hardware counter has no timestamps.

Guards: the boundary is consumed once (replaying it would re-anchor and lose a
day), it is ignored if the baseline belongs to a different day or a different
boot, and it can never REDUCE a day already recorded higher.

Health Connect needs none of this — its records are timestamped, so a completed
day is totalled retrospectively by `backfillFromHealthConnect()`.

## How reboot recovery works

`StepBootReceiver` re-arms the midnight capture on `BOOT_COMPLETED` /
`MY_PACKAGE_REPLACED` / `QUICKBOOT_POWERON`. The step COUNT itself needs no
recovery: Health Connect records are written by their own providers, and the
hardware counter accumulates in silicon. A reboot mid-day is detected by the
boot timestamp travelling with each reading, so the counter restarting at 0 is
re-anchored rather than subtracted (which would emit a large negative delta).

## Permissions are requested once

`ensureTrackingActive()` runs on every step refresh. If the local flag says
"not enabled" but Android still reports the grant — Health Connect via a real
aggregate probe, or ACTIVITY_RECOGNITION via `checkSelfPermission` — tracking
turns itself back on with no dialog. It never prompts and never launches a
permission sheet; only an explicit tap on "Enable" does that. Combined with the
`AccountGuard` fix, a grant given once survives sign-out, cache purge and
reinstall.

## Validation

- `flutter analyze lib/ test/` — 21 issues, **all info-level**. No warnings or errors.
- `flutter test` — **389/389 passed** (351 before, **+38 new**).
- `flutter build apk --debug` — **succeeded**.
- **Discrimination proof**: the inflation and freeze tests were written against
  the OLD code first and observed to FAIL (4,000 steps reported as 9,000; a
  10-second follow-up read frozen at the previous total) before the fix landed.
- **Real device (OnePlus, Android 15):**
  - `[STEPS] backfilled 2 day(s) from Health Connect` — 2026-08-01 (1,739) and
    2026-07-31 (2,465) recovered into local history. Yesterday is now viewable.
  - `[STEPS] no fresh reading — replaying stored 43` — the stationary-sensor
    path replays the real total instead of showing an Enable prompt.
  - Midnight alarm confirmed queued via `dumpsys alarm` for
    `StepDayBoundaryReceiver` at 00:00:05, alongside the 8 notification alarms.
  - Receiver confirmed FIRING WITH THE APP CLOSED (temporary 60-second alarm,
    reverted afterwards): `ZitlasSteps: midnight boundary fired`, then
    `step counter unreadable, no boundary written` — correct, because
    `ACTIVITY_RECOGNITION: granted=false` on this account (it uses Health
    Connect). The receiver wrote nothing rather than guessing.
  - **Not verified on device:** the sensor-only midnight capture writing a real
    boundary value (this account has no ACTIVITY_RECOGNITION grant, so the
    sensor path is inactive), and post-reboot re-arming (Android disables
    Wireless Debugging across a reboot). Both are covered by unit tests only.

---

# Phase — Wallet (critical fix)

## Root cause

**The Wallet was never migrated.** `/wallet` routed to `PaymentsScreen`, which
returned `PlaceholderScreen(title: 'Wallet', subtitle: 'Wallet balance,
top-up, transaction history. See features/payments.')` — a Phase-1 stub. The
Dashboard's balance chip read the real figure from `users/{uid}.wallet` and
navigated to it, so tapping a live ₹4,97,622 balance opened an empty page with
a wrench icon. Nothing was throwing; there was simply no wallet module.

Nothing else in the chain was broken. The audit traced UI → controller →
repository → API client → FastAPI → Firestore and found the backend
(`routes/payment.py`, `routes/coaching.py`) correct and complete.

## Data model (from the website + Security Rules, not invented)

`users/{uid}.wallet` = `{balance, reserved, total_added, total_spent,
transactions[]}`, each entry `{id, type, amount, description, date}`.

Two constraints drove the design:

1. **The client may never write the wallet.** `firestore.rules` enforces
   `createOmits(['wallet'])` / `updateKeeps(['wallet'])`. Money moves only via
   `POST /api/payment/verify` (credit, after an HMAC check) and
   `POST /api/payment/charge` (debit), both transactional. So there is no
   `credit()`/`debit()` in the repository, and the balance on screen only ever
   changes because the server changed it.
2. **`wallet_transactions` is unreadable by any client**
   (`allow read, write: if false`). That collection is the internal audit log,
   not the athlete's statement. The statement is the `transactions` array on
   the wallet — exactly what `components/wallet.js` renders.

## "Automatically create the wallet document if missing" — deliberately not done

The task asks for this; Security Rules forbid it, and they are right to. A
client that writes its own wallet is a client asserting its own balance. A
missing `wallet` field is a normal state for a new account (the backend writes
it on the first credit), so it is modelled as `Wallet.empty` with
`exists: false` and renders as a real ₹0 empty state. **It never crashes and
never blocks the screen** — which is what the requirement was actually
protecting against. `test/wallet_test.dart` asserts the app performs no write.

## Files

**New:** `models/wallet.dart`, `data/wallet_repository.dart`,
`data/razorpay_checkout.dart`, `wallet_controller.dart`,
`presentation/screens/wallet_screen.dart`,
`presentation/screens/transaction_history_screen.dart`,
`presentation/widgets/wallet_transaction_row.dart`,
`presentation/widgets/add_funds_sheet.dart`, `test/wallet_test.dart`,
`test/wallet_screen_test.dart`.
**Deleted:** `presentation/screens/payments_screen.dart` (the placeholder).
**Modified:** `lib/app/router.dart`, `pubspec.yaml` (+`razorpay_flutter`).

## Behaviour

- **Live balance** via a Firestore snapshot listener — a top-up completed on
  the website, or a coaching charge accepted by an expert, appears without a
  refresh.
- **Available, not raw balance,** is the headline figure; `reserved` (locked by
  an open coaching request) is called out separately. Showing reserved money as
  spendable is how an athlete reaches a checkout that declines them.
- **Direction comes from the transaction TYPE, never the amount's sign** — the
  backend stores positive amounts in both directions, so keying off the number
  renders every debit as money in.
- **Real top-ups.** `razorpay_flutter` opens the native sheet with a `key_id`
  issued per-order by the server; no key is compiled into the app, and a
  payment is worth nothing until `/verify` checks its HMAC. Nothing is credited
  locally.
- **States:** spinner → content, a ₹0 empty state, and an error state with a
  retry that re-subscribes. No raw exception can reach the UI: a Dart `Error`
  always maps to a generic message (a bug found by test — `StateError`'s
  "Bad state: …" text was leaking through the length check).

## Balance = credits − debits

`Wallet.ledgerBalance` computes it, and `ledgerDisagrees` flags a divergence.
The app **reports** a mismatch (debug log) and keeps displaying the SERVER
balance — that is what the backend will actually spend against, and a
client-recomputed figure would offer money that isn't there.

**This found a real discrepancy in production data** on the test account:
stored balance ₹4,97,622 vs credits (₹5,00,840) − debits (₹3,208) = ₹4,97,632
— a **₹10 gap**. All three current backend balance writes append a matching
ledger entry, so this predates the backend-only wallet (`wallet.js`'s own
comments describe the client-side `attemptCharge`/`deduct` writes it "just
moved away from"). Not fixable from the app, and it must not be: flagged here
for a backend reconciliation.

## Validation

- `flutter analyze lib/ test/` — 23 issues, **all info-level**. No warnings or errors.
- `flutter test` — **437/437 passed** (389 before, **+48 new**).
- `flutter build apk --debug` — **succeeded**.
- **Real device (OnePlus, Android 15):** wallet opened against the live
  account — `[WALLET] fetch uid=D4Ms… exists=true balance=497622.0 reserved=0.0
  available=497622.0 transactions=11`. Screenshot confirms ₹4,97,622 (correct
  `en-IN` grouping), Added ₹5,00,840 / Spent ₹3,208 / Balance ₹4,97,622, and
  three real transactions with correct signs, descriptions and timestamps.
- **Not verified on device:** a live Razorpay payment end-to-end (it would
  charge real money), and the history/add-funds screens visually — both are
  covered by widget tests instead.

---

# Phase — Personal Coach Assignment (Phase 1)

## Root cause: the request never reached the expert

`firestore.rules` granted the expert a read on `personal_coach_requests` via
`resource.data.coachId`. **That field has never existed on this collection** —
`coachId` lives only on `personal_coaching` (the relationship). Requests have
always identified the expert as `expertId`.

So no document ever satisfied the expert's half of the condition, and the
expert dashboard's `where('expertId', '==', uid)` listener — the same query the
website runs at `expert-dashboard.js:1400` — was rejected outright. A coaching
request reached Firestore correctly and then reached nobody. This affected web
and mobile equally.

There was no rules test for the collection at all, which is why it survived.

## Architecture used — no new collections, no parallel implementation

| Concern | Where it already lived |
|---|---|
| Request | `personal_coach_requests/{PCR_…}` — backend-written |
| **Assignment** | `personal_coaching/{athleteUid}` — backend-written |
| Notifications | `notifications/{id}` via `coaching_service.notify()` |
| Routes | `POST /api/coaching/request \| accept \| reject \| withdraw` |

**`coach_assignments` was NOT created.** The task allows it only "if the
assignment collection does not exist" — it does. `personal_coaching/{athleteUid}`
is the assignment, and keying it by the athlete is what makes "no duplicate
assignments" true by construction: there is physically no room for a second
row, and `/accept` rejects a competing coach with
`athlete_has_other_active_coach`.

**`assignedCoachId` / `coachStatus` on the user doc, and `activeClientCount` /
`assignedUsers` on the expert doc, were NOT added.** They would be copies of
data that already has one owner, and copies drift. `activeClientCount` is
derived live from `personal_coaching where coachId == uid`, which cannot
disagree with the list it sits above.

## What was actually missing, and what was built

1. **The rules bug above.** One line: `coachId` → `expertId`. Deployed.
2. **The expert was never notified.** `/request` notified only the athlete;
   the expert learned about a request by happening to have their dashboard
   open. Added a "New Personal Coaching Request" notification, sent after the
   transaction commits so it can never advertise a request that rolled back.
3. **The expert had no profile to judge on.** Rules correctly stop an expert
   reading `users/{athleteId}` until they are the ACTIVE coach — a pending
   request must not hand over the whole profile. So the backend now copies a
   deliberate subset (`photo, gender, age, heightCm, weightKg, bmi, goalType`)
   onto the request. BMI is computed from real height/weight rather than the
   `calculations` block, which only refreshes on an Assessment re-run. Every
   field is null when unset — an expert acting on an invented weight is worse
   than one who can see the field is blank.
4. **No "My Personal Coach" card.** Added, fed by a LIVE listener on
   `personal_coaching/{uid}`, so an acceptance appears on the athlete's
   dashboard without a refresh. Photo + verified badge from `experts/{coachId}`
   (public, signed-in-readable). Message opens the existing chat room via the
   same `chat_<athleteId>_<expertId>` id the rest of the app uses; Call is
   present but says Phase 7 rather than silently doing nothing.
5. **No coaching counts.** Added Athletes / Pending / Accepted / Declined to
   the coaching section, derived from the streams already held.
6. **Unretryable failures said "try again".** `/request` returns specific
   refusals (`open_request_exists`, `active_coaching_exists`,
   `expert_not_found`, `insufficient_balance`); each now gets the sentence that
   explains what to do next.

## Files

**Backend:** `routes/coaching.py` (expert notification, `_athlete_profile_summary`,
`updatedAt`), `tests/test_coaching.py` (+7).
**Rules:** `firestore.rules`, `tests/firestore-rules/rules.test.js` (+8 — the
collection had zero coverage).
**Flutter — new:** `dashboard/models/assigned_coach.dart`,
`dashboard/presentation/widgets/my_coach_card.dart`, `test/coach_assignment_test.dart`.
**Flutter — modified:** `dashboard_repository.dart` (`watchAssignedCoach`),
`dashboard_controller.dart` (live listener), `dashboard_screen.dart`,
`expert_models.dart` (`CoachingAthleteProfile`), `coaching_section.dart`
(profile facts + summary), `expert_dashboard_controller.dart`
(`declinedCoaching`), `experts_repository.dart` (`CoachingRequestException`),
`personal_coaching_sheet.dart`.

## Persistence

The assignment is one Firestore document. Nothing about it is stored on the
handset, so logout, login, app restart and phone restart are not special cases
— the listener re-attaches and reads the same doc. Duplicate prevention is
structural (doc id = athlete uid) plus the transactional guards in `/request`
(`open_request_exists`) and `/accept`.

## Validation

- `flutter analyze lib/ test/` — 23 issues, **all info-level**.
- `flutter test` — **456/456 passed** (437 before, **+19 new**).
- Backend `pytest` — **35 passed**, +7 new all passing. 5 pre-existing failures
  in `test_coaching.py` are unrelated to this work: they assert ₹499 prices
  while `PLATFORM_CHARGES_FREE=true` zeroes every amount (confirmed identical
  on a clean checkout via `git stash`). Not touched — out of scope.
- `flutter build apk --debug` — succeeded, installed.
- **Deployed:** `firebase deploy --only firestore:rules` → "released rules
  firestore.rules to cloud.firestore". Backend pushed to `main` (f9f5487) for
  Render; `https://zitlas.com/api/system/trial-mode` responds 200.
- **NOT verified end-to-end on device.** That needs two real accounts (an
  athlete and the expert they request) driven through the UI. Everything up to
  it is proven: rules deployed, backend live, app installs and runs with zero
  permission errors, and the request→accept→assignment→notification chain is
  covered by unit tests on both sides.
- The 8 new rules tests **could not be executed** — the emulator needs Java,
  which isn't installed here. They are written against the deployed rule.

## Phase 2 depends on

`personal_coaching/{athleteUid}` with `status: 'active'` and a live
`endDateTs`. `isActiveCoachOf(athleteId)` in `firestore.rules` already gates
`coaching_plans`, `users/{uid}` reads and chat on exactly that, so expert diet
and workout editing can build on it directly.

---

# Phase 2 — Personal Coach Plan Management (partial)

## Architecture: reused, not rebuilt

The website already implements this phase in
`frontend/components/coaching-workspace.js` (2,164 lines). Its data model is
the contract, and this work adopts it field-for-field so a plan written on the
phone opens on the web and vice versa:

```
coaching_plans/{athleteUid}
  diet:    { planId, days:[ {day, meals:[ {id, name, time,
             options:[{name, calories, protein, notes}] } ]} ] }
  dietSelections: { '<day>:<mealId>': optionIndex }
  training: { planId, days:[...] }
  dietVersion / trainingVersion, dietUpdatedAt / trainingUpdatedAt
coaching_plans/{athleteUid}/versions/{id}   — snapshot per save
```

**No new collections. No duplicate plans.** The key design point — and the
whole of "AI never overwrites coach modifications" — is that the coach plan
lives in its OWN document. `users/{uid}.dietPlan` (the AI plan) is never
written by any of this code, so regenerating one cannot touch the other. A
test asserts exactly that.

## Delivered

**Data spine** — `coaching/models/coach_diet_plan.dart`,
`coaching/models/coach_plan_version.dart`,
`coaching/data/coaching_plan_repository.dart`:
- Publish diet/training, each versioned independently.
- **Every publish snapshots to `versions/`.** A rollback is saved FORWARD as a
  new revision rather than rewinding, so the revision being replaced stays
  visible and nothing is ever deleted.
- **Athlete notified** on every publish, in the exact `notifications` doc shape
  `ZitlasNotify.send()` writes, so it renders identically on both platforms.
- **`planId` fail-closed stamp.** A plan authored against a goal the athlete
  has since reset retires itself instead of continuing to prescribe.

**Athlete side** — the coach's plan now appears on the Diet screen via a LIVE
listener (`coach_diet_card.dart`), above the AI plan rather than replacing it.
Options render as a real choice; the athlete's pick writes `dietSelections`.

**Protein variety (Step 3)** — `coaching/models/protein_variety.dart`
classifies dishes into 10 sources by name and reports per-source meal counts,
flagging a week that leans on one source (>50% of protein meals, or fewer than
3 sources) with concrete alternatives. Counts MEALS, not options: three chicken
options at lunch is one chicken meal, because the athlete eats one.

**Security (Step 10)** — `coaching_plans` already gated reads/writes on
`isActiveCoachOf`, so an unassigned expert was never able to reach an athlete.
But the ATHLETE had blanket write, which let them rewrite their own coach's
prescription and show it back as the coach's. Tightened to: coach authors;
athlete may change only `dietSelections` (plus deleting the legacy
`athleteContext` pair that `coaching-reset.js` clears on a Goal Reset — traced
from every athlete-side write on the website before restricting). Deployed.

## Bugs found and fixed

**Hard casts threw on the real production document.** `dietVersion` and
selection indices are written by the website too, and JS stores numbers as
strings. `(x as num?)` took the whole coach plan down with
`type 'String' is not a subtype of type 'num?'`. Now coerced through the
codebase's own `asNum`. Caught on device, not by the unit tests — five
regression tests added.

**"Paneer Bhurji" was classified as an egg dish.** `bhurji` is a preparation
(a scramble), not an ingredient, and Paneer Bhurji is one of the commonest
vegetarian breakfasts in India. It miscounted a paneer meal AND made a
vegetarian week look like it contained egg.

## NOT delivered — still open for the rest of Phase 2

Stated plainly, because these are the larger half of the spec:

- **The coach-side editors in Flutter.** A coach can currently author plans
  only through the website's coaching workspace. The data layer, versioning,
  notifications and security they need are done and tested; the editor UI
  (meal/option/macro editing, food-dataset search, budget warning, workout
  sets/reps/rest) is not built.
- **The rich athlete profile (Step 1).** `athlete_profile_screen.dart` is
  still the thin read-only summary — diet preferences, lifestyle, fitness
  block, private coach notes are not there.
- **The athlete-facing change history (Step 9).** Versions are recorded and
  readable; nothing renders them yet.

## Validation

- `flutter analyze lib/ test/` — 23 issues, **all info-level**.
- `flutter test` — **495/495 passed** (485 before, **+39 new** in
  `test/coach_plan_test.dart`).
- `tests/firestore-rules/rules.test.js` — **+11** for `coaching_plans`.
  NOT EXECUTED: the emulator needs Java, which isn't installed here.
- `flutter build apk --debug` — succeeded, installed.
- Rules deployed (`firebase deploy --only firestore:rules`, compiled clean).
- **Real device, real Firestore:**
  `[COACH PLAN] D4Ms… diet=7d v4 training=false v0` — an existing production
  coach plan (7 days, version 4) read successfully, and
  `[DIET] coach plan retired — authored for plan_1784204757943, live plan is
  plan_1785567755379` — the fail-closed guard firing on real data, correctly
  retiring a plan written for a goal this athlete has since reset.

---

# Phase 2B — Coach Workspace (diet half complete)

Builds on Phase 2A's spine. No new collections, no second repository, no
second coaching model — `CoachingPlanRepository`, `CoachDietPlan`,
`coaching_plans/{athleteUid}` and its `versions/` subcollection are reused
exactly as they were.

## Delivered

**The coach diet editor** (`coaching/presentation/screens/coach_diet_editor_screen.dart`)
— add / rename / delete / duplicate / reorder meals, set meal times, copy a
whole day onto another, and per-food: add from the dataset, replace, edit
(calories / protein / carbs / fat / note), delete.

Edits are a LOCAL DRAFT until Publish. The athlete holds a live listener, so a
half-built week would otherwise stream to them meal by meal; the draft means
the coach decides exactly when the athlete sees anything. A test asserts
nothing reaches Firestore before Publish.

**Food search reuses `showFoodSearchSheet`** against the real 4,520-food
database. `GET /api/diet/foods/search` now also returns `budgetCategory`,
`dietSuitable` and `allergens` — the compliance checks below are impossible
without them, and they were simply not in the response.

**Compliance engine** (`coaching/models/plan_compliance.dart`) — checks every
food against the athlete's own recorded profile: allergies (matched against
BOTH the dataset's allergen tags and the food name, because the athlete types
free text and the tagging is not exhaustive), diet type, never-eaten, disliked,
budget tier. Warns, never blocks — a coach can have a clinical reason to
prescribe something the athlete dislikes, and an editor that refuses to save is
one that gets worked around.

**Athlete preferences are permanently on screen** while the week is written,
never behind a tap. A coach who has to go looking for an allergy is a coach who
will sometimes not look.

**Protein variety panel** — per-source meal counts with bars, the >50% warning,
and named alternatives.

**Rich athlete profile** (`expert_dashboard/presentation/widgets/athlete_profile_sections.dart`)
— identity/body/goal, food preferences, lifestyle, fitness, assessment. Every
value reads a field that genuinely exists on `users/{athleteId}`; anything the
athlete never provided renders "Not recorded" rather than a plausible number.

**Private coach notes** at `experts/{coachId}/athlete_notes/{athleteId}` —
under the COACH. `coaching_plans/{athleteUid}` is athlete-readable, so a note
kept there would be visible to the person it is about. New rule grants the
subcollection to its owner alone (`experts/{uid}` itself is world-readable to
signed-in users; a subcollection does not inherit that).

**Version history + rollback sheet** over Phase 2A's `versions/`.

## On budget: there is no rupee cost in ZITLAS

The spec asks for "₹250/day vs ₹212/day". **The 4,520-food dataset has no price
field** — only `budgetCategory` (Low/Medium/High) and `budget_tier_detailed`
(Budget/Standard/Premium/Luxury) — and the athlete's intake records a TIER
(Economy/Standard/Premium), not an amount. A rupee figure would have to be
invented, and a coach shown a fabricated "₹212/day" would trust it.

So budget intelligence reports the real signal: how many of the week's foods
sit above the tier the athlete said they could afford, as a count and a
percentage, with saving still allowed. If real prices are wanted, the dataset
needs a cost column first.

## Bugs found

**The "no food profile recorded" message was unreachable.** `mealsPerDay`
defaults to 3, so the preferences strip always had at least one chip and the
empty-state branch could never render — an athlete who recorded nothing showed
"🍽 3 meals/day" as though it were their answer. Now gated on the athlete
having actually answered something.

## NOT delivered

- **The coach workout editor** (Step 7). The data layer (`saveTraining`,
  versioning, notification) is done and tested from Phase 2A; the editor UI is
  not built. `exercise_editor_sheet.dart` exists to reuse.
- **The athlete-facing change history** (Step 10) — versions are recorded and
  the coach can browse/restore them; the athlete-side "Eggs → Paneer" diff view
  is not built.
- Meal timings / water goal / wake-bed times / workout adherence / body fat in
  the profile: **ZITLAS does not collect these anywhere**, so they are shown as
  "Not recorded" rather than fabricated.

## Validation

- `flutter analyze lib/ test/` — 22 issues, **all info-level**.
- `flutter test` — **528/528 passed** (495 before, **+33 new** across
  `plan_compliance_test.dart` and `coach_workspace_test.dart`).
- Rules deployed (compiled clean).
- `flutter build apk --debug` — **succeeded**.
- **Device install NOT completed this round** — the phone dropped off wireless
  ADB mid-build and did not return. The previous build of this work was
  verified on-device; this one is not.

---

# Phase 3 — Meal Snap, Coach Review & Compliance (partial)

## Architecture: the website already had this

`frontend/pages/diet/diet.js` (~2160-2600) implements the whole flow. Its
contract is adopted field-for-field, so a meal snapped on the phone appears in
the website's coaching workspace and vice versa. **No new collections.**

`meal_checkins/{checkinId}`:
```
checkinId, athleteId, athleteName, coachId, day, mealType, mealName,
imageUrl, timestamp, status: 'pending'|'reviewed',
reaction, score, comment, reviewedAt, reviewedBy,
estimatedCalories/Protein/Carbs/Fat, foodRecognition, confidenceScore
```
Reactions are the website's own five: `perfect | great | good |
needs_improvement | not_recommended`.

## Upload — Firebase Storage, with the site's existing fallback

`assets/js/chat-attachments.js` already does compress → **Firebase Storage** →
`POST /api/chat/upload` fallback. `MealPhotoUploader` mirrors it exactly,
uploading to `meal_checkins/{uid}/{ts}_{rand}.jpg` in the same bucket
certificates use. The fallback is the point: an athlete photographing lunch
must not lose it because a bucket rule changed.

Nutrition estimation reuses `POST /api/meal/estimate-nutrition`, which already
existed and already documented the `meal_checkins` fields it populates. It runs
IN PARALLEL with the upload and is allowed to fail — its fields stay null,
meaning "not estimated", never "zero".

## The active-coach gate

Meal Snap renders **nothing at all** without a live `personal_coaching`
relationship — not a disabled button. The gate is re-checked at send time too,
because a relationship can lapse while the camera is open.

## Compliance — honest about gaps

A meal nobody photographed is **UNKNOWN, not a failure**, and is reported
separately. A photo the coach hasn't opened is **the coach's backlog, not the
athlete's non-compliance** — quality rate is null until something is rated
rather than 0%. One meal slot counts once however many photos were taken, so a
keen athlete can't score over 100%. Expected meals come from the athlete's own
profile, not a constant.

Insights name the meal and the count that produced them, and nothing fires from
a single data point — one skipped breakfast is a Tuesday, not a pattern.
Protein is only commented on where the vision model actually estimated it.

## Files

**New:** `coaching/data/meal_photo_uploader.dart`,
`coaching/data/meal_checkin_repository.dart`,
`coaching/models/meal_checkin.dart`, `coaching/models/meal_compliance.dart`,
`coaching/presentation/screens/meal_review_screen.dart`,
`diet/presentation/widgets/meal_snap_button.dart`,
`test/meal_checkin_test.dart`, `storage.rules`.
**Modified:** `diet_controller.dart` (relationship + check-in listeners, submit),
`diet_screen.dart`, `diet_meal_card.dart` (a `footer` slot — the card still
knows nothing about coaching), `athlete_profile_screen.dart`, `pubspec.yaml`
(+`firebase_storage`, +`flutter_image_compress`).

## storage.rules — WRITTEN, NOT DEPLOYED

No `storage.rules` existed in this repo, so the live bucket runs whatever the
Firebase console was last set to — not visible from here. Deploying replaces
those rules, and a missing path would instantly break live certificate uploads
or chat images. All four production paths were traced from real upload code
(`certificates/`, `chat_uploads/`, `meal_checkins/`, `meal_snaps/`) and are
covered, but **this needs checking against the live bucket before deploy.**

Worth stating plainly: a Storage download URL carries its own token and works
for anyone holding it, whatever these rules say. Meal photos stay confidential
because the URL only ever appears inside a `meal_checkins` document, which
`firestore.rules` already restricts to the athlete and their coach.

## NOT delivered

- **The daily 12:00 AM step/compliance summary to the coach** (Steps 9-10). The
  notification scheduler and step archiving both exist; the job that composes
  and sends the summary does not.
- **The athlete's meal-history screen** (Step 6). Check-ins render inline on
  each meal card with rating and comment; there is no separate history view.
- Meal reminders (Step 14) already exist from the notification phase and were
  not touched.

## Validation

- `flutter analyze lib/ test/` — 22 issues, **all info-level**.
- `flutter test` — **554/554 passed** (528 before, **+26 new**).
- `flutter build apk --debug` — succeeded; installed and launched on the
  OnePlus with **no crashes and no errors** in logcat.
- **The Snap → review → notify loop is NOT device-verified.** It needs two real
  accounts (an athlete with an active coach, and that coach), and the signed-in
  test account has no active coaching relationship — so the button correctly
  renders nothing, which is itself the gate working, but the loop is unproven
  on a device.
