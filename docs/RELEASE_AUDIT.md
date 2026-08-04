# ZITLAS_FULL — Production Release Audit

**Date:** 2026-08-04
**Verdict:** ❌ NOT READY FOR PRODUCTION — 2 critical blockers, both requiring
account access this audit does not have. Backend + Website + Android are
green; **iOS is not releasable.**

---

## Verification actually performed

Nothing below is inferred. Each line was executed.

| Check | Method | Result |
|---|---|---|
| Backend route table | `GET /openapi.json` on a live server | **64 routes** |
| Every GET endpoint | live HTTP | **all 200**, 0 failures |
| Every POST/PATCH endpoint | live HTTP with `{}` | **0× 404, 0× 500** |
| Auth enforcement | live HTTP, unauthenticated | admin/payment/coaching/meal/review-apply all **401** |
| Website asset graph | 320 `src`/`href`/`url()` refs resolved against disk | **0 genuinely broken** |
| Flutter asset graph | 16 Dart refs + 6 pubspec decls | **all resolve** |
| Python syntax | `ast.parse` over every file | **0 errors** |
| `flutter analyze` | whole project | **0 errors, 0 warnings** (21 info lints) |
| `flutter test` | whole suite | **567 / 567 passed** |
| `flutter build apk --debug` | Gradle | **succeeded**, exit 0 |
| Secret scan | client code, 6 patterns | **0 server secrets leaked** |
| Storage path coverage | traced every upload call site | **4/4 paths covered by rules** |
| Composite index need | every multi-`where`/`orderBy` query | **none required** |
| Production reachability | `https://zitlas.com` | **live** |

---

## 1. Issues found

### 🔴 CRITICAL — release blockers

**C1 — iOS: `GoogleService-Info.plist` is missing. Firebase is dead on iOS.**

`firebase_bootstrap.dart` calls `Firebase.initializeApp()` with **no**
`FirebaseOptions`, so it relies entirely on the native config file per
platform. Android has `android/app/google-services.json` ✅. iOS has **no**
`ios/Runner/GoogleService-Info.plist`, and there is no `firebase_options.dart`
fallback anywhere in `lib/`.

Consequence: an iOS build compiles, then fails Firebase init at runtime and
degrades to `AuthStatus.firebaseUnavailable` — **no login, no Firestore, no
messaging**. Every feature is gated behind auth, so the iOS app is unusable.

The source comment at `firebase_bootstrap.dart:11` already concedes this:
*"iOS would read `ios/Runner/GoogleService-Info.plist` the same way once
that's added."*

*Cannot be fixed from here* — the file contains project-specific identifiers
that must be downloaded from the Firebase console after registering an iOS app
(bundle id `com.zitlas.app`) in project `zitlas-b8677`. Fabricating it would
produce a file that fails in a harder-to-diagnose way.

**C2 — Production is running the OLD backend. Voice and Food Search 404 in production.**

Live probes against `https://zitlas.com`:

| Endpoint | Production | This repo |
|---|---|---|
| `/api/ai/health` | 200 | 200 |
| `/api/rag/status` | 200 (678 chunks) | 200 |
| `/api/voice/health` | **404** | 200 |
| `/api/diet/foods/search` | **404** | 200 |

Those are exactly the routes unique to the merged backend (`voice.py`,
`swap.py`, `diet.py`'s food search). The deployed service predates the
consolidation. **Shipping the Flutter app before redeploying the backend gives
users a broken Zino Voice and a broken expert Food Search**, because the app
calls both.

*Cannot be fixed from here* — requires a Render deploy.

### 🟠 HIGH

**H1 — `storage.rules` could never be deployed.** ✅ **FIXED.**
The file existed and is well-written (default-deny, 10 MB cap, content-type
allowlist, owner-only writes), but `firebase.json` had **no `storage` block**,
so `firebase deploy` ignored it entirely and the live bucket has been running
whatever was last set by hand in the console. Wired up — see §2.

**H2 — Feature parity is not 100%.** 15 gaps remain (6 website-missing, 9
Flutter-missing), fully evidenced in `docs/CONSOLIDATION.md` §6. Three have
hard infrastructure blockers (WebRTC needs a TURN server; PDF certificate
upload needs the banned `file_picker`). This audit did not close them — doing
so is days of feature work, not release hardening.

### 🟡 MEDIUM

**M1 — Demo login modal mints a fake token.** `dashboard.js:807/835` writes
`zitlas_token = 'demo_' + Date.now()` after a 1.1 s fake delay, with
`/* TODO: real API call */` where the request should be.
**Mitigated, not exploitable for data:** `init()` (dashboard.js:2023)
redirects unauthenticated users to the real login page before the modal can be
reached, and all data access is Firestore-enforced server-side. The weak
`isLoggedIn()` gate (any truthy localStorage value passes) grants **UI access
only** — no document is readable without real Firebase Auth. Left in place:
removing it is UI surgery, and this phase's mandate was not to change UI.

**M2 — `zitlas://` deep link is dead.** `login.js` hands off to the app via
`zitlas://login`, but the scheme is registered in **neither**
`AndroidManifest.xml` **nor** `Info.plist`. The redirect always times out and
silently falls through.

**M3 — `config/app-config.js` is dead.** Not loaded by any HTML page.
`PAYMENT_ENABLED:false` / `CHAT_ENABLED:false` therefore gate **nothing** —
verified: payments and chat are live and unaffected. `IS_DEMO_MODE` is read in
`diet.js` but always `undefined`, so mock-nutritionist fallbacks correctly
resolve to `[]` in production.

### 🟢 LOW

- **L1** 21 `info`-level Dart lints (`use_build_context_synchronously`,
  `prefer_initializing_formals`). Harmless, pre-existing.
- **L2** Website PNGs unoptimised — 12.9 MB across 9 files
  (`verification.png` 2.1 MB, `zino_intro.png` 2.3 MB). Recompression saves
  several MB with zero code change.
- **L3** Logo treatment mismatch between site (grey halo, light theme) and app
  (black-keyed). Needs one properly-keyed transparent master.
- **L4** `ios/Podfile` absent — auto-generated on first macOS build, not a
  real blocker.
- **L5** `/api/ai/coach-start|coach-chat|coach-finalize` return **200 on an
  empty body** rather than 422. Lax input validation, no crash.

---

## 2. Files modified in this phase

| File | Change | Risk |
|---|---|---|
| `firebase.json` | Added `"storage": { "rules": "storage.rules" }` | Config only — no app logic touched |

That is the complete list. **No application logic, UI, API, route, business
rule, auth, payment, coaching, Zino, Meal Snap, wallet or notification code was
modified in this phase**, in keeping with RULE #1.

⚠️ **Consequence of the fix you must know before deploying:** a bare
`firebase deploy` will now push `storage.rules` to the live bucket and
**replace** whatever is currently set there. The rules cover all four paths the
code actually uses — `certificates/`, `chat_uploads/`, `meal_checkins/`,
`meal_snaps/` (each traced to its call site) — and deny everything else. If
anything was uploaded to a path outside those four by an older build, it will
stop being writable. Deploy storage rules deliberately:
`firebase deploy --only storage`.

---

## 3. Optimizations performed

None. Every performance idea identified (image recompression L2, the
deterministic swap engine migration W2) changes bytes users receive or UI
behaviour, which this phase's constraints excluded. They are recorded rather
than silently applied.

---

## 4. Intentionally left unchanged

| Thing | Why |
|---|---|
| CORS `allow_origins` = localhost only | **Correct for the real topology.** The website is served same-origin by FastAPI, and native iOS/Android do not enforce CORS. Widening it would be a security regression for no gain. Only a separately-hosted Flutter **Web** build would need a change. |
| `firestore.indexes.json` (empty) | Verified no composite index is required — the only multi-filter queries are two equality clauses (`notification-center.js`) and a same-field range (`coaching-workspace.js:1448`), neither of which needs one. The live site proves it. ⚠️ Deploying `--only firestore:indexes` may prompt to delete indexes created by hand in the console. |
| Firebase Web/Android API keys in client code | Public by design; they identify, they don't authorize. Security rests on the rules, which were audited. |
| The 5 duplicated cross-platform PNGs | Source assets both builds need; Flutter cannot bundle from outside its package root. |
| Demo login modal (M1) | Unreachable behind the auth guard; removing it is UI surgery. |
| Dead endpoints | **None found.** All 64 routes are reachable and all are called by at least one client, except the documented parity gaps. Nothing was removed. |

---

## 5. Deployment instructions

**Order matters — the backend must go first, or the mobile release ships broken.**

**1 · Backend + website (fixes C2)**
```bash
git push origin main          # Render auto-deploys from render.yaml
```
`rootDir: backend` · `runtime: python` · `pip install -r requirements.txt` ·
`uvicorn main:app --host 0.0.0.0 --port $PORT` — all verified.

Set in the Render dashboard (never commit these):
```
GROQ_API_KEY  GROQ_API_KEY_DIET  GEMINI_API_KEY  OPENROUTER_API_KEY
ELEVENLABS_API_KEY  ELEVENLABS_VOICE_ID
RAZORPAY_KEY_ID  RAZORPAY_KEY_SECRET
SUPPORT_EMAIL  SUPPORT_EMAIL_PASSWORD
FIREBASE_SERVICE_ACCOUNT_JSON     # without it /api/coaching/* returns 503
DISABLE_KB_PREWARM=true           # recommended on the free tier
```

Verify the deploy actually took:
```bash
curl https://zitlas.com/api/voice/health          # must be 200, not 404
curl "https://zitlas.com/api/diet/foods/search?q=paneer&limit=1"
```

**2 · Firebase**
```bash
firebase deploy --only firestore:rules
firebase deploy --only storage        # read the warning in §2 first
```

**3 · Android**
```bash
cd mobile && flutter build appbundle --release
```

**4 · iOS — BLOCKED until C1 is resolved**
```bash
# On macOS, after adding ios/Runner/GoogleService-Info.plist:
cd mobile && flutter build ipa --release
```

---

## 6. Recommended commit message

```
Consolidate zitlas + zitlas_mobile into ZITLAS_FULL; wire storage rules

Merge the two repositories into a single production tree. The mobile
backend was verified a strict superset of the website backend (0 files
unique to the website side; every website-only line traced to a
reformatted equivalent still present), so it becomes the one backend
serving both clients.

Adopting the mobile firestore.rules also repairs two live defects that
affected both platforms: End Coaching was rejected with permission-denied
because `endedBy`/`reason` were missing from the changedOnly allowlist,
and the expert dashboard's request listener matched on `coachId`, a field
personal_coach_requests has never carried (the backend writes `expertId`).

Wire storage.rules into firebase.json — the file existed but had no
binding, so `firebase deploy` had always ignored it.

Repository: 937.2 MB -> 113.9 MB (-88%), 47,705 -> 1,165 files.
zitlas's 129-commit history is an ancestor of this repo's 150, so no
history was lost.

Verified: 64/64 backend routes reachable (0x 404, 0x 500), auth enforced
on every privileged route, flutter analyze clean, 567/567 tests pass,
flutter build apk succeeds.

Known blockers, unresolved: ios/Runner/GoogleService-Info.plist is absent
(Firebase cannot initialise on iOS) and production still runs the
pre-merge backend. See docs/RELEASE_AUDIT.md.
```

---

## 7. Final verdict

# ❌ NOT READY FOR PRODUCTION

**Ready to ship now:** Backend ✅ · Website ✅ · Android ✅
**Blocked:** iOS ❌

Two blockers stand between this repo and a full release, and **neither is a
code defect I could fix** — both need account access this audit does not have:

1. **C1** — add `ios/Runner/GoogleService-Info.plist` from the Firebase
   console. Until then the iOS app has no auth and no data.
2. **C2** — redeploy the backend to Render. Until then Zino Voice and expert
   Food Search 404 in production.

Do both, re-run the two `curl` checks in §5, and the verdict flips to
✅ **READY**. Everything else on the release checklist verified green.
