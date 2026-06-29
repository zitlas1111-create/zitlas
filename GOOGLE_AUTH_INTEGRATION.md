# Google Auth Integration
Firebase project: zitlas-b8677 (shared with ZITLAS Hiring Platform)

---

## Firebase Files Discovered in Hiring Platform

| File | Contents |
|------|----------|
| `zitlas_hiring/frontend/login.html` | Inline `<script type="module">` — only Firebase file in entire hiring repo |
| (no separate firebase-config.js) | Config is embedded in login.html lines 171–179 |

**What hiring platform uses:**
- `firebase-app.js` v10.14.1 (modular)
- `firebase-auth.js` v10.14.1 (GoogleAuthProvider, signInWithPopup)
- **No Firestore** — user data flows through backend API (`/api/auth/google-login`)

---

## Firebase Config (copied from hiring platform)

```js
{
  apiKey:            "AIzaSyAR4Q0Ldur2Y2N8iHwsAmPS4V2cWCvf_pg",
  authDomain:        "zitlas-b8677.firebaseapp.com",
  projectId:         "zitlas-b8677",
  storageBucket:     "zitlas-b8677.firebasestorage.app",
  messagingSenderId: "203730393646",
  appId:             "1:203730393646:web:f1f4776d8b0d1134bf1dbf",
  measurementId:     "G-MK3CYXXS8Q"
}
```

**SDK used in main app:** Firebase v10.7.1 compat (`firebase-app-compat.js`) — same API surface as v8, works without module bundler.

---

## Firestore Collections Used

### `users/{uid}`

**New document schema (created on first Google sign-in):**
```js
{
  uid:           string,   // Firebase UID
  name:          string,   // Google displayName
  email:         string,   // Google email
  photo:         string|null,  // Google photoURL
  roles:         string[],  // ["athlete"] or ["athlete","expert_pending"]
  expert_status: string,   // "none" | "pending" | "approved"
  created_at:    Timestamp,
  last_login:    Timestamp  // updated on every return visit
}
```

**On return visit — only these fields are updated:**
```js
{ name, photo, last_login }
// roles and expert_status are NEVER overwritten
```

**Legacy schema** (existing docs before this update) uses `role: string` — the app handles both schemas via fallback logic.

---

## localStorage Keys Written by Auth Flow

| Key | Value | When |
|-----|-------|------|
| `zitlas_user` | `{ uid, name, email, photo, provider: "google" }` | On every successful Google sign-in |
| `loggedIn` | `"true"` | On every successful Google sign-in |
| `zitlas_user_role` | `"athlete"` or `"expert"` | On every successful Google sign-in |
| `zitlas_token` | `"firebase_<uid>"` | On every successful Google sign-in |
| `zitlas_firebase_user` | `{ uid, name, email, photo, role }` | On every successful Google sign-in (backward compat) |
| `zitlas_expert_id` | Expert slug (e.g. `"ramesh"`) | Only when role is "expert" |
| `zitlas_expert_applied` | Email | When expert application is submitted |

---

## User Flow

### New User — Google Sign-In
1. User clicks "Continue with Google"
2. `signInWithPopup(ZitlasAuth, provider)` fires — Google account picker
3. Firestore check: `users/{uid}` — does not exist
4. Role-selection modal appears (Athlete / Expert)
5. User picks role → Firestore `users/{uid}.set(...)` with `roles` + `expert_status`
6. `syncFirebaseUser(user, role)` — writes `zitlas_user`, `loggedIn`, `zitlas_user_role`
7. If athlete → overlay → dashboard
8. If expert → "Application Under Review" panel (status: pending)

### Returning User — Google Sign-In
1. `signInWithPopup` fires
2. Firestore check: `users/{uid}` — exists
3. Read `roles[]` and `expert_status` to determine resolved role
4. Update `name`, `photo`, `last_login` in Firestore (roles/expert_status untouched)
5. `syncFirebaseUser(user, resolvedRole)`
6. Navigate to dashboard or expert-dashboard

### Fast Startup Redirect (Phase 8)
- Runs synchronously at top of `login.js` before Firebase fires
- If `loggedIn === "true"` AND `zitlas_user` exists → immediate redirect
- No network call needed — sub-millisecond vs 500–2000ms for Firebase

### Persist Login
- Firebase `setPersistence(LOCAL)` keeps the Firebase session alive across browser restarts
- localStorage `loggedIn` flag provides instant redirect on the login page
- Both work in tandem: Firebase is authoritative, localStorage is the fast path

---

## Expert Approval Flow

```
User signs up as "Expert"
  ↓
Firestore: roles: ["athlete","expert_pending"], expert_status: "pending"
  ↓
"Application Under Review" shown in login modal
  ↓
Admin manually updates Firestore:
  roles: ["athlete","expert"] and expert_status: "approved"
  ↓
Next time user signs in via Google:
  - Firestore check reads roles.includes("expert") === true
  - resolvedRole = "expert"
  - redirect → expert-dashboard.html
```

**The same Google account works in both apps:**
- Hiring platform: manages application workflow, approval
- Main ZITLAS app: reads `expert_status` from same Firestore project to grant access

---

## Files Modified

| File | Changes |
|------|---------|
| `frontend/assets/js/firebase-config.js` | Replaced placeholder config with real values from hiring platform |
| `frontend/pages/login/login.js` | (1) Phase 8 fast startup redirect; (2) `syncFirebaseUser` writes `zitlas_user`+`loggedIn`; (3) `onAuthStateChanged` handles new roles[]/expert_status schema; (4) Google sign-in existing user handles new schema; (5) New user Firestore `.set()` uses roles[]+expert_status schema |
| `frontend/pages/dashboard/dashboard.html` | Added `id="greetingName"` to greeting h1; cleared hardcoded "Arjun" |
| `frontend/pages/dashboard/dashboard.js` | `initGreeting` populates user first name from `zitlas_user`; `getUserInitials` reads `zitlas_user`; `loadFirebaseUserProfile` reads `zitlas_user` first |
| `frontend/pages/profile/profile.js` | `loadAthleteProfile` reads `zitlas_user` for name/photo; avatar accepts http URLs (Google photos); logout clears `loggedIn` |
| `frontend/pages/profile/personal-info/personal-info.js` | `loadFormData` pre-populates name/email from `zitlas_user` if local form is empty; photo area shows Google profile photo |

---

## Firestore Security Rules

Paste these into Firebase Console → Firestore → Rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## Testing Checklist

### Google Sign-In — New Athlete
- [ ] Click "Continue with Google" on login page
- [ ] Google account picker appears
- [ ] Role selection modal appears with user's name/photo
- [ ] Select "Athlete" → click Continue
- [ ] Dashboard loads
- [ ] Greeting shows "Good [time], [FirstName]! 👋"
- [ ] Profile page shows Google name and photo
- [ ] Personal Info page pre-fills name and email
- [ ] `localStorage.getItem('zitlas_user')` → `{uid, name, email, photo, provider: "google"}`
- [ ] `localStorage.getItem('loggedIn')` → `"true"`
- [ ] `localStorage.getItem('zitlas_user_role')` → `"athlete"`
- [ ] Firestore `users/{uid}` → `{roles: ["athlete"], expert_status: "none", ...}`

### Google Sign-In — Returning User
- [ ] Sign out then sign back in with same Google account
- [ ] Role modal does NOT appear
- [ ] Redirect goes directly to dashboard (no role selection)
- [ ] Firestore doc has updated `last_login` timestamp
- [ ] `name` and `photo` updated in Firestore

### Fast Startup Redirect (Phase 8)
- [ ] After first sign-in, navigate to `login.html`
- [ ] Redirect happens immediately without waiting for Firebase
- [ ] No login form briefly visible

### Expert Application
- [ ] Select "Expert" in role modal
- [ ] "Application Under Review" panel shows
- [ ] `localStorage.getItem('zitlas_expert_applied')` → email
- [ ] Firestore `users/{uid}` → `{roles: ["athlete","expert_pending"], expert_status: "pending"}`
- [ ] Click "Continue as Athlete" → goes to dashboard as athlete guest

### Expert Approval (manual Firestore update)
- [ ] In Firebase Console, update user doc:
  - `roles: ["athlete","expert"]`
  - `expert_status: "approved"`
- [ ] Sign out, sign back in with Google
- [ ] Redirect goes to `expert-dashboard.html`
- [ ] `localStorage.getItem('zitlas_user_role')` → `"expert"`

### Logout (Phase 9)
- [ ] Profile page → Logout → confirm
- [ ] Firebase `signOut()` called
- [ ] `localStorage.getItem('loggedIn')` → null
- [ ] `localStorage.getItem('zitlas_user')` → null
- [ ] `localStorage.getItem('zitlas_user_role')` → null
- [ ] Redirect to login page

### Profile Population (Phase 7)
- [ ] After Google sign-in, open Personal Information page
- [ ] Full name field pre-filled with Google name
- [ ] Email field pre-filled with Google email
- [ ] Profile photo shows Google account photo
- [ ] User can edit and save — manual values take priority over Google data

---

## Potential Issues / Known Limitations

| Issue | Details |
|-------|---------|
| Firestore rules must be configured | Default rules block all reads — paste rules above into Firebase Console |
| Google popup blocked | Some browsers block popups — user sees error toast, must allow popups for this domain |
| Expert approval is manual | Admin must update Firestore directly; no admin UI yet |
| `photo.startsWith('http')` check | Google photo URLs start with `https://` — handled; URL must be on CORS-friendly host |
| Old Firestore docs use `role` field | Backward compat: `syncFirebaseUser` reads `data.role` as fallback |
| Expert accounts (`ramesh@zitlas.com` etc.) | Still work via email/password login — not affected by this change |
