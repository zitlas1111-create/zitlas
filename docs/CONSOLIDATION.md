# ZITLAS_FULL — Consolidation Record & Feature-Parity Register

**Date:** 2026-08-04
**Result:** `zitlas` and `zitlas_mobile` no longer exist. `ZITLAS_FULL` is the only repository.

---

## 1. How the merge was decided

Nothing was copied blind and nothing was overwritten on a guess. Every
duplicated file was compared by MD5 before a winner was chosen.

### Backend — `zitlas_mobile` won outright

An 81-vs-84 file hash diff (excluding caches) produced:

| Result | Count | Detail |
|---|---|---|
| Only in website backend | **0** | — |
| Only in mobile backend | **3** | `routes/swap.py`, `routes/voice.py`, `services/voice_service.py` |
| Different content | 12 | mobile larger in **every** case |

Each of the 12 differing files was line-diffed. Only two had any
website-only lines at all (`food_engine.py` 20, `groq_service.py` 7), and
every one of those was a *reformatted* version of code still present in the
mobile file — verified by grepping the mobile copies for each symbol
(`by_id`, `_W_GOAL`, `_base_dish_name`, `max_prep_minutes`,
`_apply_engine_swap`, `build_region_boost`, `rag_service`). All present.

**Conclusion: the mobile backend is a strict superset. Zero features lost.**
It became `backend/` verbatim.

### Website — the `zitlas_mobile` copy won

Both projects carried a 116-file `frontend/`. They differed in exactly
**two** files:

- `assets/logo.png` — mobile carried the newer green mark
- `pages/login/login.js` — mobile added the app deep-link handoff

Mobile's copy became `frontend/website/`.

### `firestore.rules` — mobile won, and this fixes a live bug

The mobile rules are a superset that repairs two defects affecting **both**
platforms:

1. **End Coaching never worked, on either client.** Both `cprofile.js:4252`
   and `ExpertsRepository.endCoaching` write `endedBy` and `reason`, but the
   old `changedOnly([...])` allowlist omitted both fields, so every attempt
   was rejected with `permission-denied`. The adopted rules
   (`firestore.rules:176`) include them.
2. **The expert dashboard's coaching-request listener was rejected outright.**
   The old rule matched on `coachId`, a field `personal_coach_requests`
   documents have never had — the backend writes `expertId`
   (`routes/coaching.py:229`). New requests therefore never reached the
   expert. Fixed at `firestore.rules:192`.

Adopting the merged rules file fixes both on web and mobile at once. **This
is the one behavioural fix delivered by the consolidation itself.**

### Everything else

`firebase.json`, `firestore.indexes.json`, `render.yaml`, `.firebaserc`,
`package.json`, `CLAUDE.md`, `PROJECT_CONTEXT.md`, `food_dataset/` (10 files)
and `food_profiles/` (20 files) were **byte-identical** in both projects.
One copy kept, no merge required.

`tests/firestore-rules/rules.test.js` — mobile's (30,012 B) supersedes the
website's (20,901 B); same file, more cases.

---

## 2. What was deleted, and why it was safe

| Deleted | Size | Justification |
|---|---:|---|
| `zitlas/zitlas/` (recursive self-copy) | 302.1 MB | 431/431 files byte-identical to its parent. Pure accident. |
| `zitlas/tests/firestore-rules/node_modules/` | 290.0 MB | npm-restorable |
| `zitlas/node_modules/` | 21.7 MB | npm-restorable |
| `zitlas/.git/` | 89.9 MB | **Verified redundant** — see below |
| `zitlas/android/` (Capacitor wrapper) | 6.6 MB | Superseded by the real Flutter app. Contained no keystore and no `google-services.json`. |
| `zitlas/backend`, `zitlas/frontend`, `zitlas/docs`, root `*.md` | ~42 MB | Proven subsets/duplicates above |
| `food_dataset/*.pre_v2_backup.json`, `*.pre_v3_backup.json` | 15.5 MB | Regenerable by re-running `enrich_food_dataset_v2.py` / `_v3.py`. The untouched 4,500-food source and the runtime enriched file both kept. |
| `__pycache__/`, `.pytest_cache/`, `.idea/`, `*.iml`, `*.log` | ~0.3 MB | Generated |

### Git history was **not** lost

`zitlas`'s HEAD (`8bb4203`, 129 commits) was confirmed to be a **direct
ancestor** of the retained repository's HEAD (`a81c62a`, 150 commits) via
`git merge-base --is-ancestor`. `zitlas_mobile` was forked from `zitlas`, so
the retained `.git` already contains every commit the deleted one had.
Deleting it discarded a duplicate, not history.

---

## 3. Size

| | Files | Size |
|---|---:|---:|
| Before — `zitlas` | 46,443 | 782.8 MB |
| Before — `zitlas_mobile` | 1,262 | 154.4 MB |
| **Before — combined** | **47,705** | **937.2 MB** |
| After — source only | 686 | 68.7 MB |
| After — retained git history | 479 | 45.2 MB |
| **After — `ZITLAS_FULL` total** | **1,165** | **113.9 MB** |
| **Reduction** | **−46,540 (−97.6%)** | **−823.3 MB (−87.8%)** |

Breakdown of the 68.7 MB of source:

| | Files | Size |
|---|---:|---:|
| `backend/` | 100 | 24.3 MB (18.4 MB of it the FAISS index) |
| `frontend/website/` | 116 | 16.0 MB (12.9 MB of it unoptimised PNGs) |
| `food_dataset/` | 8 | 15.3 MB |
| `mobile/` | 416 | 12.4 MB |
| `tests/`, `docs/`, `food_profiles/`, root configs | 46 | 0.7 MB |

Measured after `flutter clean`; excludes `mobile/build/`,
`mobile/.dart_tool/` and `mobile/android/.gradle/`, all of which are build
output regenerated on demand and now gitignored.

---

## 4. Paths changed by the move

Only one code path broke, and it was fixed:

```diff
# backend/main.py
- FRONTEND_DIR = BASE_DIR.parent / "frontend"
+ FRONTEND_DIR = BASE_DIR.parent / "frontend" / "website"
```

Every other path reference was audited and still resolves: the
`Path(__file__).parent.parent` roots in `enrich_food_dataset*.py`,
`generate_food_profiles.py`, `food_engine.py`, `chat.py`, `kb_manager.py`,
`rag_service.py`, `workout_engine.py` and `offline_fallback.py` all point at
`backend/` or the repo root, neither of which moved.

**Served URLs did not change.** The backend mounts `frontend/website/` at
`/`, so the site's root-relative links (`/assets/…`, `/pages/…`) are
untouched. `render.yaml` needed no edit (`rootDir: backend`).

---

## 5. Validation performed

| Check | Result |
|---|---|
| `python -m ast` over all 143 backend files | **0 syntax errors** |
| `from main import app` | **OK** — 68 API routes registered |
| `FRONTEND_DIR` resolves & contains `pages/login/login.html` | **OK** |
| Live server: 7 website assets (HTML/CSS/JS/PNG/component) | **200** |
| Live server: 9 API endpoints incl. `/api/voice/health`, `/api/rag/status` | **200** |
| `GET /api/diet/foods/search?q=paneer` | **200** — 125 real matches |
| `GET /api/rag/status` | **ready:true**, 678 chunks indexed |
| `flutter analyze` | **0 errors, 0 warnings** (21 pre-existing `info` lints) |
| `flutter test` | **567 / 567 passed** |
| `flutter build apk --debug` | **succeeded** — `app-debug.apk`, 173.2 MB, exit 0 |

Food-search and RAG were exercised specifically because they read from
`food_dataset/` and `backend/vector_store/` — the two paths most at risk
from the restructure. Both returned real data.

---

## 6. Feature-parity register

Derived by enumerating all 68 backend endpoints and cross-referencing every
caller in `frontend/website/**` and `mobile/lib/**`, then reconciling against
`docs/MIGRATION_INVENTORY.md`.

### 6.1 At parity on both platforms

Authentication · Google login · role picker · assessment (all 3 question
sets) · dashboard · goals & goal reset · diet plan · meal swap · workout /
weekly plan / day detail · expert marketplace · expert profile · personal
coaching request/accept/reject/withdraw · **end coaching** (fixed above) ·
coach diet & workout editors · meal check-ins · meal compliance · plan
compliance · expert reviews inbox · review editors · chat (text) ·
notifications + FCM + scheduler + consent · step tracking · wallet ·
add funds · transaction history · Razorpay order creation · membership ·
profile · personal info · help & support · certificates (view/status) ·
verified-expert flag · daily score · streaks · Zino chat · Zino tour ·
meal snap.

### 6.2 Present on Flutter, missing on the website

| # | Feature | Evidence | Effort | Blocker |
|---|---|---|---|---|
| W1 | **Zino Voice** (TTS/STT/voice chat) | `/api/voice/*` — 4 Dart callers, **0** website callers. `core/voice/`, `zino_call_screen.dart`, `voice_language_sheet.dart` | Large | None — backend is live and configured (`tts_configured:true`) |
| W2 | **Deterministic swap engine** | Website still calls the 10-12 s LLM `/api/ai/swap-meal`; Flutter uses `/api/diet/swap` (sub-10 ms, no hallucinated nutrition claims) | Medium | Not a URL swap — the new route returns **5 ranked options**, the old returns **1**. Needs a swap-sheet rework. |
| W3 | **Expert food search** | `/api/diet/foods/search` — 1 Dart caller (`food_search_sheet.dart`), 0 website. The expert plan editor can't search the food DB. | Medium | None |
| W4 | **Protein variety panel** | `protein_variety_panel.dart` + `protein_variety.dart`; no website equivalent | Small | None |
| W5 | **Coach plan version history** | `plan_history_sheet.dart` + `coach_plan_version.dart`; no website equivalent | Small | None |
| W6 | **Step history screen** | `step_history_screen.dart` (17 KB); website has capture but no history view | Medium | None |

### 6.3 Present on the website, missing on Flutter

| # | Feature | Evidence | Effort | Blocker |
|---|---|---|---|---|
| M1 | **Admin console** | `admin-review.html`, `cert-audit.html`, 4 `/api/admin/*` callers vs 1 in Dart | Large | *Recommend leaving web-only* — back-office tooling rarely belongs in an athlete app |
| M2 | **Certificate upload** | Expert uploads certificates on web only | Medium | **Partial** — `file_picker` is banned in this project (it broke the Android build), so **PDF** certificates can't be picked. Image certificates are unblocked: `image_picker` + `firebase_storage` are both in `pubspec.yaml` and already used by `meal_photo_uploader.dart`. |
| M3 | **WebRTC voice/video calls** | `webrtc-call.js`, `call-ui.js` | Large | **Hard** — needs a native WebRTC dep, and no TURN server is configured even for web (STUN-only) |
| M4 | **Chat image attachments** | `chat-attachments.js`; Flutter chat is text-only | Medium | **None** — the upload pipeline already exists (`image_picker` + `firebase_storage`, proven by Meal Snap). Only the chat UI is missing. |
| M9 | **Membership upgrade checkout** | `membership_screen.dart:205` tells the user to *"upgrade from the ZITLAS website for now"* | Small | **None** — `razorpay_flutter: ^1.4.5` **is** integrated and working for Wallet top-ups (`razorpay_checkout.dart` → `wallet_screen.dart`). Membership simply never got wired to it. The in-file comment at `membership_screen.dart:16` claiming the SDK isn't integrated is stale. |
| M5 | **Hindi localisation** | `i18n.js` retranslates ~150 strings across the site; Flutter is English-only (`language_modal.dart` persists the choice but doesn't retranslate) | Large | None, but cross-cutting — touches every one of the ~230 Dart files |
| M6 | **Full verified-badge component** | `verified-badge.js` has levels/tooltip/sheet; Flutter uses a plain boolean | Small | None |
| M7 | **Expert pricing editor page** | `pricing.html`; Flutter edits the fee via Edit Profile only | Small | None |
| M8 | **Profile photo upload (expert)** | Web stores a base64 dataURL on the Firestore doc | Small | Worth replacing with real Storage uploads rather than porting the anti-pattern |

### 6.4 Cross-platform integration defects found

| # | Issue | Detail |
|---|---|---|
| X1 | **App deep-link is dead** | `login.js` redirects to `zitlas://login` to hand off to the app, but **no `zitlas` URL scheme is registered** in `mobile/android/app/src/main/AndroidManifest.xml` or `mobile/ios/Runner/Info.plist`. The redirect silently times out and falls through to the website every time. Fix: register the scheme on both platforms and add a deep-link route. |
| X2 | **`docs/MIGRATION_INVENTORY.md` is stale in places** | It is an excellent phase-by-phase record, but several "deferred" items were built in later phases and never struck through — it still lists Meal Snap, step capture, the Assessment wizard, the Wallet panel and the Razorpay SDK as missing when all five now exist in `lib/`. **Treat the code as authoritative, not that document.** Every entry in §6 above was derived from the source and the 68-endpoint call graph, then reconciled against the doc — not the other way round. |

---

## 7. Known non-duplicates (deliberately kept twice)

Five images are byte-identical between `frontend/website/assets/` and
`mobile/assets/images/` — `homebg.png`, `loginbg.png`, `zino.png`,
`zino_done.png`, `zino_intro.png` (9.35 MB total). **They were not
deduplicated on purpose:** Flutter cannot bundle assets from outside its
package root, and the website has no build step to copy them in. Collapsing
them would require introducing a build step to one side or the other. Every
asset in both trees was confirmed to be referenced by code.

---

## 8. Remaining TODOs

1. **Logo treatment mismatch.** The website and the app now show the same
   green ZITLAS mark, but in different treatments: the website's copy has a
   grey halo, Flutter's is keyed on solid black. Neither drops cleanly into
   the other — the **website is light-themed** (`--bg-primary: #F4F7ED`), so
   Flutter's black-backed PNG would paint a black box on a cream header, and
   the transparent `logo_icon.png` has a white "Z" that would vanish. This
   needs one properly keyed, transparent, dark-"Z" master exported for the
   light site. **Not changed** — swapping blind would visibly break the site.
2. Work the §6.2 / §6.3 register in the order you choose. **Highest
   value-per-hour first:** M9 (membership checkout — the SDK is already
   integrated and shipping for Wallet), W4, W5, M6, M7, then X1. W1 (Zino
   Voice on web) and M5 (Hindi localisation) are the two large ones.
3. Fix X1 (deep link) — small and self-contained.
4. Decide whether `backend/vector_store/` (18.4 MB of FAISS index) stays
   tracked. It is currently committed so a fresh deploy has working RAG on
   the first request; the alternative is running `python prebuild_indexes.py`
   at deploy time. A commented-out ignore rule is already in `.gitignore`.
5. Website images are unoptimised (`verification.png` 2.1 MB,
   `zino_intro.png` 2.3 MB, `zino_done.png` 2.3 MB, `chat.png` 1.6 MB).
   Recompression would cut several MB with no code change.

---

## 9. Deployment

**Backend + website — one Render service, one deployment.**

```
render.yaml → rootDir: backend
              pip install -r requirements.txt
              uvicorn main:app --host 0.0.0.0 --port $PORT
```

The website is served by that same FastAPI process from `frontend/website/`.
There is no second host and no static deploy step. Required environment
variables (`backend/.env` locally, Render dashboard in production):

```
GROQ_API_KEY  GROQ_API_KEY_DIET  GEMINI_API_KEY  OPENROUTER_API_KEY
ELEVENLABS_API_KEY  ELEVENLABS_VOICE_ID
RAZORPAY_KEY_ID  RAZORPAY_KEY_SECRET
SUPPORT_EMAIL  SUPPORT_EMAIL_PASSWORD
FIREBASE_SERVICE_ACCOUNT_JSON     # else /api/coaching/* returns 503
DISABLE_KB_PREWARM=true           # recommended on Render free tier
```

**Firebase — one project, one rule set.**

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

**Mobile.**

```bash
cd mobile
flutter build appbundle --release     # Play Store
flutter build ipa --release           # App Store
```

The app targets the same Render backend; its base URL lives in
`mobile/lib/core/config/env.dart`. There is no mobile-specific backend and
no second Firebase project.
