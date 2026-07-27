# ZITLAS Firestore Security Rules — Emulator Tests

Tests `../../firestore.rules` against the Firestore emulator using
`@firebase/rules-unit-testing`.

## ⚠️ Not yet executed

These tests were **written but not run** in the environment where they were
authored: the Firestore emulator is a **Java** process driven by the **Firebase
CLI**, and neither Java nor `firebase-tools` is installed there
(`java -version` → not found; `firebase --version` → not found). They must be
run on a machine that has both before deployment.

## Prerequisites

- Node.js 18+ (dev box has v22 ✓)
- Java JDK 11+ (`java -version`) — **required by the emulator**
- Firebase CLI: `npm i -g firebase-tools`

## Run

```bash
cd tests/firestore-rules
npm install
npm test
```

`npm test` runs:

```
firebase emulators:exec --only firestore,auth --project zitlas-b8677 "mocha rules.test.js --timeout 20000"
```

`emulators:exec` boots the emulator, runs mocha against it, and shuts it down.
It reads `../../firebase.json` for the emulator ports (Firestore 8080, Auth 9099).

## Coverage (matrix from the pre-deploy plan)

- unauthenticated read/write denied
- athlete reads/writes own data; cannot read another athlete
- athlete cannot change role / wallet balance / become admin / mark verified
- expert cannot self-verify a certificate; admin can list pending
- escrow: athlete cannot self-activate coaching; can only retire it
- coach-relationship gating (active coach reads athlete data; unrelated + expired denied)
- chat participant gating + sender-id spoof denial
- notification recipient access + mark-read-only
- payment/order + wallet_transaction tamper denied
- legitimate existing frontend queries (expert dashboard, notification center,
  admin cert listing, personal meal-snap logs) still succeed
