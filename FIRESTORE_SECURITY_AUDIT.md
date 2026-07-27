# ZITLAS — Firestore Security Audit & Proposed Production Rules

**Status:** DRAFT FOR REVIEW — nothing deployed, no application code changed, no `firestore.rules` file committed.
**Date:** 2026‑07‑27
**Current rules in Console (Test Mode):** `allow read, write: if request.time < timestamp.date(2026, 7, 29);` → expires **2026‑07‑29**.
**Firebase project id:** `zitlas-b8677` (from `backend/services/firestore_service.py`).

---

## 0. Method & the single most important architectural fact

I grepped the entire repository for every Firestore access pattern (`collection(`, `doc(`, `get/getDocs`, `set/add/update/delete`, `onSnapshot`, `where`, `runTransaction`, `firebase.firestore`, `firebase_admin`, `google.cloud.firestore`) across:

- **Frontend** — vanilla JS Web SDK (compat v10.7.1), ~40 files under `frontend/`.
- **Backend** — Python, `backend/routes/*.py` + `backend/services/*.py`.
- **Mobile** — `zitlas/android` is a **Capacitor/WebView wrapper around the same `frontend/`**, *not* Flutter. There is **no separate Dart/Flutter Firestore client** — the phone app runs the exact same JS and is governed by the same rules. (Confirmed: no `.dart` Firestore code exists.)

### The fact that shapes every rule below

**The backend uses the Google Cloud Firestore *server* SDK with a service‑account credential (`firestore_service.py` → `google.cloud.firestore.Client`), NOT the client Web SDK.** Server‑SDK access **completely bypasses Security Rules.**

Consequences:

1. Every backend write — `razorpay_orders`, `wallet_transactions`, `personal_coaching`, `personal_coach_requests`, escrow reservations, membership activation, coach‑request lifecycle — **is unaffected by whatever we put in the rules.** We can lock those collections to *deny‑all for clients* and the backend keeps working.
2. Therefore the rules only need to describe **what the browser/WebView client is allowed to do.** Anywhere the client currently does something privileged (mint wallet balance, verify certificates, elevate its own role) that *should* be a backend responsibility, the correct fix is to **move that write to the backend** rather than to weaken the rule.

There is **no `firestore.rules`, `firebase.json`, or `firestore.indexes.json`** anywhere in the repo, and **no service‑account JSON** is committed (loaded from `FIREBASE_SERVICE_ACCOUNT_JSON`/`_FILE` env at runtime). So the rules currently live *only* in the Console, in Test Mode.

---

## 1. Complete Firestore usage audit

### 1a. Collection inventory (19 top‑level + subcollections)

The "known list" you supplied had 12 collections. The audit found **7 more top‑level collections** and **8 subcollections** you didn't list. Newly discovered are marked ⚠️**NEW**.

| Collection | Doc ID pattern | Ownership fields | Read (client) | Create (client) | Update (client) | Delete (client) | Frontend source | Backend (Admin) |
|---|---|---|---|---|---|---|---|---|
| **users** ⚠️NEW | `{uid}` (Auth UID) | doc id = owner; `role`, `wallet`, `membership` | Owner; **also the athlete's active coach & (today) any expert running a charge** | Owner at signup | Owner (profile, goal, cloud‑sync) | — | `login.js`, `cloud-sync.js`, `payment-service.js`, `streak-service.js`, `push-notifications.js`, `zino.js`, `activity-service.js` | ✅ `coaching.py`, `payment.py`, `coaching_service.py` write `wallet`/`membership`/reserved |
| `users/{uid}/activity/{date}` ⚠️NEW (sub) | `{YYYY-MM-DD}` | path `{uid}` | Owner + active coach | Owner | Owner | — | `activity-service.js`, `dashboard.js`, `day.js`, `coaching-workspace.js` | — |
| `users/{uid}/weight_log/{date}` ⚠️NEW (sub) | `{YYYY-MM-DD}` | path `{uid}` | Owner + active coach | Owner | Owner | — | `dashboard.js`, `coaching-workspace.js` | — |
| **experts** | `{uid}` (expert Auth UID) | doc id = owner; `verified`, `approved`, `rating` | **Public‑ish** (marketplace, badges) | Owner at signup | Owner (profile) — ⚠️ incl. `verified/approved` today | — | `login.js`, `coaches.js`, `dietitian.js`, `pricing.js`, `verified-badge.js`, `expert-dashboard.js`, `cprofile.js`, `certificate-manager.js` | — |
| **expert_certificates** | `{certId}` | `expertId` | Owner expert + **admin** | Owner expert (upload) | ⚠️ **"admin" (client‑gated) sets `verificationStatus`** | Owner expert | `certificate-manager.js`, `admin-review.js`, `cert-audit.html`, `cprofile.js`, `expert-dashboard.js` | — |
| **expert_reviews** ⚠️NEW | `{reviewRequestId}` | authored by expert | Athlete (their plan review) + expert | Reviewing expert | Reviewing expert | — | `expert-review.js` | — |
| **review_requests** | auto/`RR_*` | `userId` = `athleteId`, `expertId`, `status`, `planId` | Athlete (`where userId==me`) + expert (`where expertId==me`) | Athlete | Athlete (dismiss) + expert (status/notes) | — | `diet.js`, `cprofile.js`, `expert-review.js`, `expert-dashboard.js`, `modify-diet.js`, `modify-workout.js`, `review-sync.js`, `coaching-reset.js`, `pending-requests-bar.js` | — |
| **personal_coach_requests** | `{requestId}` | `athleteId`, `coachId`, `status` | Athlete + coach | ✅ **Backend only** (`coaching.py`) | ✅ Backend only | — | read: `cprofile.js`, `expert-dashboard.js`, `pending-requests-bar.js` | ✅ `coaching.py`, `coaching_sweep.py` |
| **personal_coaching** | `{athleteUid}` | doc id = athlete; `coachId`, `status`, `endDateTs` (Timestamp) | Athlete (id==me) + coach (`coachId==me`) | ✅ Backend only (accept) | Athlete may retire **`status` only** (`coaching-reset.js`); backend does everything else | ✅ Backend only | read: many; write: `coaching-reset.js` (status), `zino.js`, `health-status.js`, `diet.js`, `day.js`, `weekly-plan.js`, `expert-review-promo.js` | ✅ `coaching.py`, `coaching_sweep.py` |
| **coaching_plans** | `{athleteUid}` | doc id = athlete | Athlete + active coach | Coach (workspace) | Coach (plan) + athlete (`dietSelections` only) | `coaching-reset.js` clears `athleteContext` field | `coaching-workspace.js`, `diet.js`, `weekly-plan.js`, `coaching-reset.js` | — |
| `coaching_plans/{athleteUid}/versions/{vid}` ⚠️NEW (sub) | auto | path athlete | Coach + athlete | Coach | — | — | `coaching-workspace.js` | — |
| **coaching_meal_requests** | `CMR_*` | `athleteId`, `coachId`, `status` | Athlete + coach | Athlete + coach | Coach (answer, 3 options) | — | `diet.js`, `coaching-workspace.js` | — |
| **meal_checkins** | `MC_*`/auto | `athleteId`, `coachId`, `status` | Athlete + coach | Athlete (photo) | Coach (rate/score/comment) | — | `diet.js`, `coaching-workspace.js`, `dashboard.js` | — |
| **workout_checkins** ⚠️NEW | auto | `athleteId`, `coachId`, `status` | Athlete + coach | Athlete | Coach (review) | — | `day.js`, `coaching-workspace.js` | — |
| **meal_snap_logs** ⚠️NEW | `meal_snap_logs/{uid}/{date}/{autoId}` | path `{uid}` | Owner (AI‑only personal log) | Owner | Owner | Owner | `diet.js` | — |
| **weekly_reviews** ⚠️NEW | `{athleteId}_{weekStart}` | `athleteId`, `coachId` | Athlete + coach | Coach | Coach | — | `coaching-workspace.js` | — |
| **health_alerts** ⚠️NEW | `{alertId}` | `athleteId`, `coachId` | Athlete + coach | Athlete | Coach | — | `health-status.js` | — |
| **chat_rooms** | `chat_{athleteId}_{coachId}` | `participants[]`, `athleteId`, `expertId` | Participants | Participant | Participant (lastMessage etc.) | — | `cprofile.js`, `expert-dashboard.js`, `diet.js`, `health-status.js`, `coaching-workspace.js` | — |
| `chat_rooms/{id}/messages/{msgId}` (sub) | `{msg.id}` | parent participants | Participants | Participant (sender) | — | — | same as above | — |
| `chat_rooms/{id}/calls/{callId}` ⚠️NEW (sub) | `call_*` | `callerId`, `calleeId` | Participants | Caller | Both (status/offer/answer) | — | `webrtc-call.js`, `call-ui.js` | — |
| `.../calls/{callId}/callerCandidates` ⚠️NEW (sub) | auto | parent call | Participants | Caller | — | — | `webrtc-call.js` | — |
| `.../calls/{callId}/calleeCandidates` ⚠️NEW (sub) | auto | parent call | Participants | Callee | — | — | `webrtc-call.js` | — |
| **notifications** | `{notificationId}` | `userId` = recipient | Recipient (`where userId==me`) | **Any authed** (cross‑user by design; no sender field) | Recipient (`isRead`) | Recipient | `notification-center.js` | ✅ `coaching_service.py` |
| **coaching_notifications** | auto | `athleteId`/`coachId`/recipient | Recipient (toast watcher) | Athlete & coach both | — | consumer deletes | `diet.js`, `day.js`, `coaching-workspace.js`, `health-status.js` | ✅ `coaching_service.py` |
| **wallet_transactions** | `txn_*` | `userId` | (audit record) | ⚠️ **Client today** (`attemptCharge`, `creditWallet`) + backend | — | — | `payment-service.js` | ✅ `payment.py`, `coaching.py` |
| **razorpay_orders** | `order_*` | `userId` | — | ✅ **Backend only** | ✅ Backend only | — | none | ✅ `payment.py` |

### 1b. UID / identity usage

- **Firebase Auth UID is the backbone.** `users/{uid}` and `experts/{uid}` are keyed by Auth UID. `personal_coaching/{athleteUid}`, `coaching_plans/{athleteUid}`, `meal_snap_logs/{uid}/…` embed the UID in the *path*. Relationship collections carry `athleteId`/`coachId`(`expertId`) *fields* equal to Auth UIDs.
- **`chat_rooms` doc id encodes both parties**: `chat_{athleteId}_{coachId}`, plus a `participants: [athleteUid, expertUid]` array — ideal for a rules membership check.
- **Roles today are a plain field** (`users.role` / `users.roles[]` / `experts.role`), written by the client at signup and read by the client to gate expert/admin UI. **Rules must not trust this field for privilege** (see §2).

### 1c. Where genuinely public/unauthenticated access is required

- **`experts`**: the coaches marketplace (`coaches.js`), pricing (`pricing.js`), dietitian list (`dietitian.js`) and the verified badge (`verified-badge.js`) read expert profiles. These pages are reachable by a logged‑in user browsing coaches. **They do not require *unauthenticated* access** — every entry point is behind login (guest/"Skip for Now" was removed in a prior task). So `experts` should be **read: signed‑in**, not world‑readable. No other collection needs public read. **Nothing** needs public write.

---

## 2. Current security vulnerabilities (Test Mode)

While `allow read, write: if request.time < …` is live, **every document in the project is world‑readable and world‑writable by anyone with the public Firebase web config** (which ships in `firebase-config.js` in client JS — it is *designed* to be public; it is not a secret). Concretely:

| # | Severity | Vulnerability | Mechanism | Impact |
|---|---|---|---|---|
| V1 | 🔴 Critical | **Total open access** | Test Mode `if true` (date‑gated) | Anyone can dump or overwrite the entire DB: all users' PII, plans, chats, wallet balances, payment records. |
| V2 | 🔴 Critical | **Wallet self‑crediting** | `wallet` lives in `users/{uid}.wallet`; `payment-service.creditWallet()`/`attemptCharge()` write it **client‑side** in a `runTransaction`. `cloud-sync.js` FIELD_MAP also maps `wallet`. | A user calls `ZitlasPayment.creditWallet({userId:myUid, amount:99999})` from the console (or writes `users/{uid}.wallet.balance` directly) and has unlimited free balance — **no Razorpay payment required.** |
| V3 | 🔴 Critical | **Privilege escalation to expert/admin** | `users/{uid}.role`/`roles[]` and `experts/{uid}` are client‑written; expert AND admin UI gate on these client‑controlled fields (`admin-review.js isAdmin()` reads `users.role=='admin'`). | Any user sets their own `role:'admin'`/`role:'expert'` → gains the admin certificate‑review console and expert dashboard. |
| V4 | 🔴 Critical | **Verified‑expert / certificate spoofing** | Client "admin" action sets `expert_certificates.verificationStatus='verified'`; the badge (`verified-badge.js`) trusts it. Combined with V3, self‑approval. | A fake account presents as a **ZITLAS‑verified** coach to real athletes. |
| V5 | 🟠 High | **Cross‑user PII harvesting** | Any client can read any `users/{uid}` (assessments, medical conditions, goals, location, wallet), all `chat_rooms/*/messages`, all `review_requests`, all `meal_checkins`. | Mass scrape of health data & private chats. |
| V6 | 🟠 High | **Payment/order data exposure & tampering** | `razorpay_orders`, `wallet_transactions` world‑read/write. | Read others' order/payment ids; forge transaction audit records. |
| V7 | 🟠 High | **Escrow tampering** | `personal_coaching`/`personal_coach_requests` world‑writable; a client could set `status:'active'`, rewrite `coachId`, or extend `endDateTs`. | Free/forged coaching relationships, bypassing the paid escrow flow. |
| V8 | 🟡 Medium | **Notification/chat spoofing & message injection** | Any client can create `notifications`/`coaching_notifications` for any `userId`, or write messages into any `chat_rooms/*/messages`. | Phishing notifications; injecting messages into others' conversations. |
| V9 | 🟡 Medium | **Fake plan reviews / requests** | `review_requests`, `expert_reviews` world‑writable. | Forge "expert approved" states on plans. |

---

## 3. Proposed authorization model

**Principles:** default‑deny; identity (Auth UID) is the primary authorization key; role‑privileged surfaces (expert/admin) move to **custom claims**; all money/escrow/verification fields become **backend‑authoritative** (Admin SDK, which bypasses rules).

### 3.1 Identity & roles

- **Ownership = UID match**, either `request.auth.uid == {uid path segment}` or `== resource.data.<ownerField>`. This alone covers ~80% of collections and needs no role at all.
- **Expert / admin privilege via custom claims**, set by the backend after real verification, read in rules as `request.auth.token.expert == true` / `request.auth.token.admin == true`. Rules must **not** derive privilege from the client‑writable `users.role`. *(Backend work required — see §6.)*
- **Active‑coach relationship** is derived by a rule helper that `get()`s `personal_coaching/{athleteId}` and checks `coachId == uid && status=='active' && request.time < endDateTs`.

### 3.2 Field‑level protections on self‑writable docs

- `users/{uid}`: owner may write their own doc **except** `role`, `roles`, `wallet`, `membership`, `expert_status` (backend‑only). This preserves profile/goal/cloud‑sync writes while closing V2/V3.
- `experts/{uid}`: owner may write profile fields **except** `verified`, `approved`, `verificationStatus`, `rating`, `reviews`, `role` (backend/admin‑only). Closes V4.
- `personal_coaching/{athleteUid}`: athlete may change **only `status`** (+ its timestamp) and only to a terminal value (`reset`/`ended`); everything else backend‑only. Closes V7 while keeping Goal‑Reset working.

### 3.3 Money is backend‑only, always

`wallet_transactions` and `razorpay_orders` = **client deny‑all** (backend writes via Admin SDK). `users/{uid}.wallet` and `.membership` = **backend‑only fields**. The client never mutates balance again.

---

## 4. Proposed `firestore.rules` (v2)

> Not written to disk as `firestore.rules` yet — this is the review copy. Assumes custom claims `expert`/`admin` exist (see §6). Rules that reference `endDateTs` guard for its presence so legacy docs don't hard‑fail.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ── Helpers ──────────────────────────────────────────────
    function signedIn()      { return request.auth != null; }
    function isUser(uid)      { return signedIn() && request.auth.uid == uid; }
    function isExpert()       { return signedIn() && request.auth.token.expert == true; }
    function isAdmin()        { return signedIn() && request.auth.token.admin == true; }

    // Only these fields differ between existing and incoming doc?
    function onlyChanged(fields) {
      return request.resource.data.diff(resource.data).affectedKeys().hasOnly(fields);
    }
    // Incoming create/update does NOT touch any protected field
    function notWriting(fields) {
      return !request.resource.data.diff(
               resource != null ? resource.data : {}
             ).affectedKeys().hasAny(fields);
    }

    // Active paid coaching relationship athlete<->me
    function rel(athleteId) {
      return get(/databases/$(database)/documents/personal_coaching/$(athleteId)).data;
    }
    function isActiveCoachOf(athleteId) {
      return signedIn()
        && exists(/databases/$(database)/documents/personal_coaching/$(athleteId))
        && rel(athleteId).coachId == request.auth.uid
        && rel(athleteId).status == 'active'
        && ('endDateTs' in rel(athleteId))
        && request.time < rel(athleteId).endDateTs;
    }
    // chat_rooms membership (participants array carries both UIDs)
    function isChatParticipant(roomId) {
      return signedIn()
        && request.auth.uid in get(/databases/$(database)/documents/chat_rooms/$(roomId)).data.participants;
    }

    // ── users/{uid} + subcollections ─────────────────────────
    match /users/{uid} {
      allow read:   if isUser(uid) || isActiveCoachOf(uid);
      // Create own doc at signup, but never seed privileged fields.
      allow create: if isUser(uid)
                    && notWriting(['wallet','membership','role','roles','expert_status'])
                    // allow role only as a benign self-label, never 'admin'
                    && (!('role' in request.resource.data) || request.resource.data.role in ['athlete','expert']);
      // Update own profile/goal/cloud-sync data, but not money/role/membership.
      allow update: if isUser(uid)
                    && notWriting(['wallet','membership','role','roles','expert_status']);
      allow delete: if false;

      match /activity/{date} {
        allow read:  if isUser(uid) || isActiveCoachOf(uid);
        allow write: if isUser(uid);
      }
      match /weight_log/{date} {
        allow read:  if isUser(uid) || isActiveCoachOf(uid);
        allow write: if isUser(uid);
      }
    }

    // ── experts/{uid} — signed-in readable, self profile writes only ──
    match /experts/{uid} {
      allow read:   if signedIn();
      allow create: if isUser(uid)
                    && notWriting(['verified','approved','verificationStatus','rating','reviews','role']);
      allow update: if isUser(uid)
                    && notWriting(['verified','approved','verificationStatus','rating','reviews','role']);
      allow delete: if false;
    }

    // ── expert_certificates — expert owns; only admin sets status ──
    match /expert_certificates/{certId} {
      allow read:   if isAdmin()
                    || (signedIn() && resource.data.expertId == request.auth.uid)
                    // athletes viewing a coach's *verified* certs on cprofile
                    || (signedIn() && resource.data.verificationStatus == 'verified');
      allow create: if signedIn()
                    && request.resource.data.expertId == request.auth.uid
                    && request.resource.data.verificationStatus in ['pending_review', 'pending'];
      allow update: if isAdmin()
                    || (signedIn() && resource.data.expertId == request.auth.uid
                        && notWriting(['verificationStatus','verificationScore','rejectionReason']));
      allow delete: if signedIn() && resource.data.expertId == request.auth.uid;
    }

    // ── review_requests — athlete owner + assigned expert ──
    match /review_requests/{id} {
      function athlete() { return resource.data.userId; }
      allow read:   if signedIn()
                    && (request.auth.uid == resource.data.userId
                        || request.auth.uid == resource.data.expertId);
      allow create: if signedIn()
                    && request.resource.data.userId == request.auth.uid;
      allow update: if signedIn()
                    && (request.auth.uid == resource.data.userId       // athlete: dismiss
                        || request.auth.uid == resource.data.expertId); // expert: status/notes
      allow delete: if false;
    }

    // ── expert_reviews — authored by reviewing expert, read by its athlete ──
    match /expert_reviews/{id} {
      allow read:   if signedIn();     // packet is fetched by the owning athlete + expert; tighten with athleteId if present
      allow create,
            update: if isExpert();
      allow delete: if false;
    }

    // ── personal_coaching/{athleteUid} — escrow, backend-authoritative ──
    match /personal_coaching/{athleteUid} {
      allow read:   if isUser(athleteUid)
                    || (signedIn() && resource.data.coachId == request.auth.uid);
      // Athlete may ONLY retire the relationship (status + its timestamp).
      allow update: if isUser(athleteUid)
                    && onlyChanged(['status','priorStatus','resetAt','endedAt'])
                    && request.resource.data.status in ['reset','ended'];
      allow create, delete: if false;   // backend (Admin SDK) only
    }

    // ── personal_coach_requests — backend-only writes ──
    match /personal_coach_requests/{reqId} {
      allow read:   if signedIn()
                    && (resource.data.athleteId == request.auth.uid
                        || resource.data.coachId  == request.auth.uid);
      allow write:  if false;           // backend (Admin SDK) only
    }

    // ── coaching_plans/{athleteUid} (+ versions) ──
    match /coaching_plans/{athleteUid} {
      allow read:   if isUser(athleteUid) || isActiveCoachOf(athleteUid);
      // athlete may write dietSelections; coach writes the plan
      allow create,
            update: if isUser(athleteUid) || isActiveCoachOf(athleteUid);
      allow delete: if false;
      match /versions/{vid} {
        allow read:  if isUser(athleteUid) || isActiveCoachOf(athleteUid);
        allow write: if isActiveCoachOf(athleteUid);
      }
    }

    // ── coaching_meal_requests / meal_checkins / workout_checkins / health_alerts ──
    // Same shape: athleteId owner + coachId participant.
    match /coaching_meal_requests/{id} {
      allow read:   if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow create: if signedIn() && request.resource.data.athleteId in [request.auth.uid, resource == null ? request.auth.uid : resource.data.athleteId]
                    && (request.resource.data.athleteId == request.auth.uid || request.resource.data.coachId == request.auth.uid);
      allow update: if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow delete: if false;
    }
    match /meal_checkins/{id} {
      allow read:   if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow create: if signedIn() && request.resource.data.athleteId == request.auth.uid;
      allow update: if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow delete: if false;
    }
    match /workout_checkins/{id} {
      allow read:   if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow create: if signedIn() && request.resource.data.athleteId == request.auth.uid;
      allow update: if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow delete: if false;
    }
    match /health_alerts/{id} {
      allow read:   if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow create: if signedIn() && request.resource.data.athleteId == request.auth.uid;
      allow update: if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow delete: if false;
    }

    // ── weekly_reviews/{athleteId_weekStart} ──
    match /weekly_reviews/{id} {
      allow read:   if signedIn() && (resource.data.athleteId == request.auth.uid || resource.data.coachId == request.auth.uid);
      allow create,
            update: if signedIn() && request.resource.data.coachId == request.auth.uid;
      allow delete: if false;
    }

    // ── meal_snap_logs/{uid}/{date}/{logId} — personal AI log ──
    match /meal_snap_logs/{uid}/{date}/{logId} {
      allow read, write: if isUser(uid);
    }

    // ── chat_rooms + messages + calls (participant-gated) ──
    match /chat_rooms/{roomId} {
      allow read:   if signedIn() && request.auth.uid in resource.data.participants;
      allow create: if signedIn() && request.auth.uid in request.resource.data.participants;
      allow update: if signedIn() && request.auth.uid in resource.data.participants;
      allow delete: if false;

      match /messages/{msgId} {
        allow read:   if isChatParticipant(roomId);
        allow create: if isChatParticipant(roomId)
                      && request.resource.data.senderId == request.auth.uid;
        allow update, delete: if false;
      }
      match /calls/{callId} {
        allow read:   if isChatParticipant(roomId);
        allow create: if isChatParticipant(roomId);
        allow update: if isChatParticipant(roomId);
        allow delete: if false;
        match /{candidateSet}/{candId} {   // callerCandidates | calleeCandidates
          allow read:   if isChatParticipant(roomId);
          allow create: if isChatParticipant(roomId);
          allow delete: if false;
        }
      }
    }

    // ── notifications — recipient-only read, mark-read only update ──
    match /notifications/{id} {
      allow read:   if signedIn() && resource.data.userId == request.auth.uid;
      allow create: if signedIn()
                    && request.resource.data.userId is string
                    && request.resource.data.isRead == false;   // cross-user by design; see §6 to move server-side
      allow update: if signedIn() && resource.data.userId == request.auth.uid
                    && onlyChanged(['isRead']);
      allow delete: if signedIn() && resource.data.userId == request.auth.uid;
    }

    // ── coaching_notifications — toast; recipient consumes ──
    match /coaching_notifications/{id} {
      allow read:   if signedIn()
                    && (resource.data.athleteId == request.auth.uid
                        || resource.data.coachId == request.auth.uid
                        || resource.data.recipientId == request.auth.uid);
      allow create: if signedIn();       // both parties emit; see §6
      allow delete: if signedIn()
                    && (resource.data.athleteId == request.auth.uid
                        || resource.data.coachId == request.auth.uid
                        || resource.data.recipientId == request.auth.uid);
      allow update: if false;
    }

    // ── MONEY — client deny-all (backend Admin SDK bypasses) ──
    match /wallet_transactions/{id} { allow read, write: if false; }
    match /razorpay_orders/{id}     { allow read, write: if false; }

    // ── Default deny for anything unlisted ──
    match /{document=**} { allow read, write: if false; }
  }
}
```

---

## 5. Frontend queries/writes that will FAIL under these rules

These are the intended breakages (they represent today's vulnerabilities) — each needs a code change (see §6) **before** the rules go live, or that feature breaks:

| # | File / call | What breaks | Why | Fix |
|---|---|---|---|---|
| B1 | `payment-service.js` `attemptCharge()` — reads **the athlete's** `users/{uid}` on the **expert's** device | Read denied (expert is not the athlete's active coach in a *review* flow) | `users` read is owner/active‑coach only | Move charge to backend (`/api/payment/charge`) — already the right home; Admin SDK reads freely. Currently ₹0 so dormant. |
| B2 | `payment-service.js` `creditWallet()` / `attemptCharge()` write `users/{uid}.wallet` + `wallet_transactions` | Write denied | `wallet` is protected; `wallet_transactions` deny‑all | Recharge already goes through `/api/payment/verify` (backend). Remove/retire client `creditWallet`; move the debit into backend. |
| B3 | `cloud-sync.js` FIELD_MAP includes `wallet`, `membership` | `save('wallet'/'membership')` denied | protected fields | Make cloud‑sync treat `wallet`/`membership` as **read‑only (hydrate only)**; never `save()` them. |
| B4 | `admin-review.js` / `certificate-manager.js` admin action sets `expert_certificates.verificationStatus` | Denied unless `token.admin` | verification is admin‑claim‑only now | Grant admin custom claim to real admins; OR move approval to a backend endpoint. |
| B5 | `login.js` expert signup writes `experts/{uid}` with `verified/approved` and `users/{uid}.role:'expert'` | `verified/approved` write denied (fields protected); `role:'expert'` create still allowed | those fields are backend/admin‑only | Have signup write only profile fields; backend sets `approved/verified` + the `expert` custom claim after review. |
| B6 | `chat_rooms/*/messages` create where message lacks `senderId==uid` | Denied | message create requires `senderId==auth.uid` | Ensure every message write sets `senderId = current uid` (cprofile.js sets `senderId` to a *type* string `'athlete'`/`'expert'`, **not the UID** — must change to the UID). |
| B7 | `notifications` read via `where('userId','==',uid)` | ✅ Works (matches rule) | — | none |
| B8 | Any expert dashboard `review_requests` `where('expertId','==',uid)` | ✅ Works | rule allows expert read on own | none |
| B9 | Coach reading `users/{athleteUid}/activity`, `weight_log`, `coaching_plans` | ✅ Works **iff** an active `personal_coaching` row exists with `endDateTs` in the future | `isActiveCoachOf` | verify all live coaching rows have `endDateTs` (created since the escrow change); backfill legacy rows if any. |
| B10 | `expert_reviews` read by athlete | ✅ Works (signed‑in) but broader than ideal | no `athleteId` field on the doc today | add `athleteId`/`userId` to `expert_reviews` docs to tighten to participants. |

> **Collection‑group / listing note:** Firestore evaluates rules **per document**, and a `where(...)` query must be *provably* satisfiable by the rule or the whole query is rejected. The queries above are all equality filters on the exact ownership field the rule checks (`userId==me`, `expertId==me`, `athleteId==me`), so they pass. Any query that tries to read a collection **without** an ownership filter (e.g. an unfiltered `experts` list is fine since read=signed‑in; an unfiltered `review_requests` list would be **rejected**) must keep its `where` clause.

---

## 6. Changes required BEFORE deployment

**Backend / infrastructure**
1. **Custom claims.** Add a backend routine (Admin SDK `set_custom_user_claims`) to set `{expert:true}` when an expert is approved and `{admin:true}` for admin accounts. Rules in §4 depend on these. *(Firebase Admin claims, not the `users.role` field.)*
2. **Move the wallet debit server‑side.** Port `attemptCharge()`'s balance‑check‑and‑debit into a backend endpoint (mirror `/api/payment/verify`). Recharge is already server‑verified; this closes V2 fully. Low risk today because platform charges are ₹0.
3. **Certificate approval + expert approval server‑side.** Replace the client "admin" writes to `expert_certificates.verificationStatus` and `experts.verified/approved` with backend endpoints (admin‑claim‑gated), which also set the `expert` claim.

**Frontend**
4. **cloud-sync:** stop `save()`‑ing `wallet`/`membership` (hydrate‑only).
5. **Chat messages:** set `senderId = current Auth UID` on every `messages` write (today `cprofile.js` stores the *type* `'athlete'`/`'expert'`). Rule B6.
6. **`expert_reviews`:** add `athleteId` (a.k.a `userId`) to each doc so its read rule can be tightened from "signed‑in" to "participant".
7. Confirm no page issues an **unfiltered** list against an owner‑scoped collection (must always carry the `where(ownerField==uid)` filter).

**Data**
8. **Backfill `endDateTs`** on any pre‑escrow `personal_coaching` docs still in `status:'active'` (otherwise `isActiveCoachOf` fails closed and the coach loses access). New docs already have it (`coaching.py:354`).
9. Confirm every live `chat_rooms` doc has a `participants` array (older docs may predate it — the rule keys off it).

**Sequencing**
10. Deploy rules to a **staging** project (or the emulator) first; run §7; only then publish to `zitlas-b8677`, ideally right after shipping the code changes above so no feature regresses at the cutover.

---

## 7. Testing plan (Firebase Emulator + Rules Playground)

**A. Local emulator (authoritative, automatable)**
1. `firebase init emulators` (Firestore emulator) — no code in repo yet; add `firebase.json` + this `firestore.rules` in a throwaway branch.
2. Write `@firebase/rules-unit-testing` specs (Node). Minimum matrix:

| Scenario | Expect |
|---|---|
| Anonymous read `users/other` | ❌ deny |
| Athlete A read own `users/A` | ✅ allow |
| Athlete A read `users/B` | ❌ deny |
| Athlete A set `users/A.wallet.balance=99999` | ❌ deny (V2) |
| Athlete A set `users/A.role='admin'` | ❌ deny (V3) |
| Athlete A update `users/A.name` | ✅ allow |
| Non‑admin set `expert_certificates.verificationStatus='verified'` | ❌ deny (V4) |
| Admin‑claim set same | ✅ allow |
| Coach (active, endDateTs future) read athlete `coaching_plans`/`activity` | ✅ allow (B9) |
| Coach (expired/`endDateTs` past) read same | ❌ deny |
| Random expert read unrelated athlete `users`/`meal_checkins` | ❌ deny (V5) |
| Athlete set `personal_coaching/A.status='active'` | ❌ deny (V7) |
| Athlete set `personal_coaching/A.status='reset'` (only field) | ✅ allow |
| Non‑participant read `chat_rooms/chat_A_C/messages` | ❌ deny (V5/V8) |
| Participant create message with `senderId==self` | ✅ allow |
| Participant create message with `senderId!=self` | ❌ deny (B6) |
| Any client read/write `razorpay_orders`/`wallet_transactions` | ❌ deny (V6) |
| Recipient read own `notifications`; non‑recipient read | ✅ / ❌ |

3. Run against the **emulator seeded with a realistic doc set** (one athlete, one coach, one active + one expired `personal_coaching`, chat room, certs).

**B. Rules Playground (Console, quick sanity)** — spot‑check the highest‑risk paths (V2/V3/V4/V7) with a simulated auth UID and a custom‑claim toggle before publishing.

**C. Staged rollout** — publish to a staging Firebase project, run the app end‑to‑end (signup → assessment → plan → request review → coach accept via backend → chat/call → wallet recharge), watch the Firestore "Rules" monitoring tab for `PERMISSION_DENIED`, fix, then promote to `zitlas-b8677`.

---

## 8. Open questions for you before we finalize

1. **Admin identity:** who are the admin UIDs, and are you OK moving admin/expert gating to **custom claims** (recommended) vs. keeping the `users.role` field (not safe to trust in rules)?
2. **Charge‑on‑expert‑device:** OK to move `attemptCharge` to the backend? (It's the clean fix for B1/B2; dormant today because charges are ₹0.)
3. **`expert_reviews`/`coaching_notifications` sender fields:** OK to add `athleteId`/`recipientId` so those reads can be tightened from "any signed‑in" to "participant only"?
4. Any collection you *intend* to be genuinely public (unauthenticated), e.g. a marketing coach directory? Today none needs it.

Nothing here is deployed. On your go‑ahead I can (a) create `firebase.json` + `firestore.rules` in the repo, (b) write the emulator test suite, and/or (c) draft the backend custom‑claims + charge/approval endpoints.
