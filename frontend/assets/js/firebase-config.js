/* ══════════════════════════════════════════════════════════
   ZITLAS — Firebase Configuration
   ──────────────────────────────────────────────────────────

   SETUP STEPS:
   1. Go to https://console.firebase.google.com
   2. Create a project (or use an existing one)
   3. Project Settings → General → "Your apps" → Add Web App
   4. Copy the firebaseConfig object values below
   5. Authentication → Sign-in method → Enable Google
   6. Firestore Database → Create database → Start in test mode
   7. Add your domain to Authentication → Settings → Authorized domains

   FIRESTORE SECURITY RULES (paste in Firestore → Rules):
   ──────────────────────────────────────────────────────────
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
       }
     }
   }
   ══════════════════════════════════════════════════════════ */

'use strict';

const FIREBASE_CONFIG = {
  apiKey:            "REPLACE_WITH_YOUR_API_KEY",
  authDomain:        "REPLACE_WITH_YOUR_PROJECT_ID.firebaseapp.com",
  projectId:         "REPLACE_WITH_YOUR_PROJECT_ID",
  storageBucket:     "REPLACE_WITH_YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "REPLACE_WITH_YOUR_MESSAGING_SENDER_ID",
  appId:             "REPLACE_WITH_YOUR_APP_ID",
};

/* ── Initialize (guard against double-init on multi-page nav) ── */
if (!firebase.apps.length) {
  firebase.initializeApp(FIREBASE_CONFIG);
}

/* ── Global singletons used across all pages ── */
var ZitlasAuth = firebase.auth();
var ZitlasDB   = firebase.firestore();

/* ── Persist login across tabs + page reloads ── */
ZitlasAuth.setPersistence(firebase.auth.Auth.Persistence.LOCAL);
