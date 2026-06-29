/* ══════════════════════════════════════════════════════════
   ZITLAS — Firebase Configuration
   Firebase project: zitlas-b8677 (shared with ZITLAS Hiring)
   SDK: Firebase v10 compat (same API surface as v8)

   Firestore security rules required in Firebase Console:
   ──────────────────────────────────────────────────────
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

var FIREBASE_CONFIG = {
  apiKey:            "AIzaSyAR4Q0Ldur2Y2N8iHwsAmPS4V2cWCvf_pg",
  authDomain:        "zitlas-b8677.firebaseapp.com",
  projectId:         "zitlas-b8677",
  storageBucket:     "zitlas-b8677.firebasestorage.app",
  messagingSenderId: "203730393646",
  appId:             "1:203730393646:web:f1f4776d8b0d1134bf1dbf",
  measurementId:     "G-MK3CYXXS8Q"
};

/* Guard against double-init on multi-page navigation */
if (!firebase.apps.length) {
  firebase.initializeApp(FIREBASE_CONFIG);
}

/* Global singletons — used across login.js, profile.js, dashboard.js */
var ZitlasAuth = firebase.auth();
var ZitlasDB   = firebase.firestore();

/* Persist login across tabs and page reloads */
ZitlasAuth.setPersistence(firebase.auth.Auth.Persistence.LOCAL);
