/*
 * ZITLAS — Firestore Security Rules tests (Firebase Emulator)
 * =========================================================
 * Exercises ../../firestore.rules against the Firestore emulator using
 * @firebase/rules-unit-testing. Covers the matrix mandated by the pre-deploy
 * plan (Phase 3): unauthenticated denial, per-user isolation, role/wallet/
 * admin/verified tamper denial, chat participant gating, coach relationship
 * gating, notification recipient access, payment/order tamper denial, and a
 * sanity check that legitimate existing frontend queries still pass.
 *
 * RUN (requires Java + Firebase CLI — NOT available in the dev box where these
 * were written, so they have NOT been executed here; see README.md):
 *   npm install
 *   npm test            # firebase emulators:exec ... mocha
 *
 * Seed data below mirrors the real doc shapes found in the audit:
 *   athleteA / athleteB / coachC (active coach of A) / coachD (unrelated) / admin
 */

const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'zitlas-b8677';
const A = 'athleteA';
const B = 'athleteB';
const C = 'coachC';       // active coach of A
const D = 'coachD';       // unrelated expert
const ADMIN = 'adminU';

let testEnv;

const future = new Date(Date.now() + 30 * 24 * 3600 * 1000);
const past = new Date(Date.now() - 24 * 3600 * 1000);

// Authenticated contexts (admin carries the custom claim).
const asA = () => testEnv.authenticatedContext(A).firestore();
const asB = () => testEnv.authenticatedContext(B).firestore();
const asC = () => testEnv.authenticatedContext(C).firestore();
const asD = () => testEnv.authenticatedContext(D).firestore();
const asAdmin = () => testEnv.authenticatedContext(ADMIN, { admin: true }).firestore();
const anon = () => testEnv.unauthenticatedContext().firestore();

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => { await testEnv.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  // Seed with rules DISABLED (admin context) to set up realistic state.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${A}`).set({ uid: A, role: 'athlete', name: 'A', wallet: { balance: 500 } });
    await db.doc(`users/${B}`).set({ uid: B, role: 'athlete', name: 'B', wallet: { balance: 10 } });
    await db.doc(`experts/${C}`).set({ uid: C, role: 'expert', verified: true, approved: true });
    await db.doc(`experts/${D}`).set({ uid: D, role: 'expert', verified: false });
    // Active coaching: C coaches A, unexpired.
    await db.doc(`personal_coaching/${A}`).set({
      athleteId: A, coachId: C, status: 'active', endDateTs: future,
    });
    await db.doc(`coaching_plans/${A}`).set({ athleteId: A, dietSelections: {} });
    await db.doc(`users/${A}/activity/2026-07-27`).set({ steps: 100 });
    await db.doc(`chat_rooms/chat_${A}_${C}`).set({
      participants: [A, C], athleteId: A, expertId: C, lastMessage: 'hi',
    });
    await db.doc(`chat_rooms/chat_${A}_${C}/messages/m1`).set({ senderId: A, text: 'hi' });
    await db.doc(`review_requests/rr1`).set({ userId: A, athleteId: A, expertId: C, status: 'pending' });
    await db.doc(`meal_checkins/mc1`).set({ athleteId: A, coachId: C, status: 'pending' });
    await db.doc(`workout_checkins/wc1`).set({ athleteId: A, coachId: C, status: 'pending' });
    await db.doc(`coaching_meal_requests/cmr1`).set({ athleteId: A, coachId: C, status: 'pending' });
    await db.doc(`expert_reviews/rr1`).set({ reviewId: 'rr1', athleteId: A, expertId: C, status: 'APPROVED' });
    await db.doc(`coaching_notifications/cn1`).set({ athleteId: A, coachId: C, title: 'toast' });
    await db.doc(`notifications/n1`).set({ notificationId: 'n1', userId: A, isRead: false, title: 't' });
    await db.doc(`expert_certificates/cert1`).set({ certId: 'cert1', expertId: C, verificationStatus: 'pending_review' });
    // WebRTC call signaling under the A<->C chat room.
    await db.doc(`chat_rooms/chat_${A}_${C}/calls/call1`).set({ callerId: A, calleeId: C, status: 'ringing' });
    await db.doc(`chat_rooms/chat_${A}_${C}/calls/call1/callerCandidates/ic1`).set({ candidate: 'x' });
    await db.doc(`chat_rooms/chat_${A}_${C}/calls/call1/calleeCandidates/ic2`).set({ candidate: 'y' });
    await db.doc(`wallet_transactions/txn1`).set({ userId: A, amount: 5 });
    await db.doc(`razorpay_orders/order1`).set({ uid: A, amountPaise: 100 });
  });
});

describe('unauthenticated', () => {
  it('cannot read any user', async () => {
    await assertFails(anon().doc(`users/${A}`).get());
  });
  it('cannot write any user', async () => {
    await assertFails(anon().doc(`users/${A}`).set({ hacked: true }));
  });
});

describe('users — ownership & privilege', () => {
  it('athlete reads own doc', async () => {
    await assertSucceeds(asA().doc(`users/${A}`).get());
  });
  it('athlete CANNOT read another athlete', async () => {
    await assertFails(asA().doc(`users/${B}`).get());
  });
  it('athlete CANNOT change wallet balance', async () => {
    await assertFails(asA().doc(`users/${A}`).set({ wallet: { balance: 999999 } }, { merge: true }));
  });
  it('athlete CANNOT change role (self-promote)', async () => {
    await assertFails(asA().doc(`users/${A}`).update({ role: 'admin' }));
  });
  it('athlete CANNOT make self expert via role change', async () => {
    await assertFails(asA().doc(`users/${A}`).update({ role: 'expert' }));
  });
  it('athlete CAN update benign profile fields', async () => {
    await assertSucceeds(asA().doc(`users/${A}`).update({ name: 'A2', photo: 'x' }));
  });
  it('active coach CAN read athlete user doc', async () => {
    await assertSucceeds(asC().doc(`users/${A}`).get());
  });
  it('unrelated expert CANNOT read athlete user doc', async () => {
    await assertFails(asD().doc(`users/${A}`).get());
  });
});

describe('users — signup create (Google role-select flow)', () => {
  const N = 'newUser';
  const asN = () => testEnv.authenticatedContext(N).firestore();
  it('CAN create own doc with athlete + expert_pending roles + expert_status pending', async () => {
    await assertSucceeds(asN().doc(`users/${N}`).set({
      uid: N, name: 'New', email: 'n@x.com',
      roles: ['athlete', 'expert_pending'], expert_status: 'pending',
    }));
  });
  it('CAN create a plain athlete doc', async () => {
    await assertSucceeds(asN().doc(`users/${N}`).set({ uid: N, role: 'athlete' }));
  });
  it('CANNOT seed roles containing admin at signup', async () => {
    await assertFails(asN().doc(`users/${N}`).set({ uid: N, roles: ['athlete', 'admin'] }));
  });
  it('CANNOT seed wallet at signup', async () => {
    await assertFails(asN().doc(`users/${N}`).set({ uid: N, role: 'athlete', wallet: { balance: 500 } }));
  });
  it('CANNOT seed expert_status=approved at signup', async () => {
    await assertFails(asN().doc(`users/${N}`).set({ uid: N, expert_status: 'approved' }));
  });
  it('CANNOT create a doc for a different uid', async () => {
    await assertFails(asN().doc(`users/someoneElse`).set({ uid: 'someoneElse', role: 'athlete' }));
  });
});

describe('experts — verified/approved tamper', () => {
  it('self CANNOT set verified=true', async () => {
    await assertFails(asD().doc(`experts/${D}`).update({ verified: true }));
  });
  it('self CANNOT set approved=true', async () => {
    await assertFails(asD().doc(`experts/${D}`).update({ approved: true }));
  });
  it('self CAN update profile fields', async () => {
    await assertSucceeds(asD().doc(`experts/${D}`).update({ speciality: 'Nutrition' }));
  });
  it('anyone signed-in can read experts (marketplace)', async () => {
    await assertSucceeds(asA().doc(`experts/${C}`).get());
  });
});

describe('expert_certificates — verification tamper', () => {
  it('non-admin owner CANNOT self-verify a certificate', async () => {
    await assertFails(asC().doc(`expert_certificates/cert1`).update({ verificationStatus: 'verified' }));
  });
  it('admin CAN read pending certs (admin listing)', async () => {
    await assertSucceeds(asAdmin().doc(`expert_certificates/cert1`).get());
  });
  it('owner CAN upload a pending certificate', async () => {
    await assertSucceeds(asD().doc(`expert_certificates/cert2`).set({
      certId: 'cert2', expertId: D, verificationStatus: 'pending_review',
    }));
  });
  it('cannot upload a certificate pre-marked verified', async () => {
    await assertFails(asD().doc(`expert_certificates/cert3`).set({
      certId: 'cert3', expertId: D, verificationStatus: 'verified',
    }));
  });
  it('owner CAN delete own certificate', async () => {
    await assertSucceeds(asC().doc(`expert_certificates/cert1`).delete());
  });
  it('non-owner non-admin CANNOT delete a certificate', async () => {
    await assertFails(asD().doc(`expert_certificates/cert1`).delete());
  });
  it('admin CAN delete any certificate (cert-audit cleanup)', async () => {
    await assertSucceeds(asAdmin().doc(`expert_certificates/cert1`).delete());
  });
});

describe('personal_coaching — escrow tamper', () => {
  it('athlete CANNOT self-activate a relationship', async () => {
    await assertFails(asA().doc(`personal_coaching/${A}`).update({ status: 'active' }));
  });
  it('athlete CAN retire (reset) their own relationship', async () => {
    await assertSucceeds(asA().doc(`personal_coaching/${A}`).update({ status: 'reset', resetAt: 'now' }));
  });
  it('athlete CANNOT create a coaching relationship', async () => {
    await assertFails(asB().doc(`personal_coaching/${B}`).set({ athleteId: B, coachId: C, status: 'active' }));
  });
});

describe('coaching data — coach relationship gating', () => {
  it('active coach CAN read athlete coaching_plans', async () => {
    await assertSucceeds(asC().doc(`coaching_plans/${A}`).get());
  });
  it('active coach CAN read athlete activity', async () => {
    await assertSucceeds(asC().doc(`users/${A}/activity/2026-07-27`).get());
  });
  it('unrelated expert CANNOT read athlete coaching_plans', async () => {
    await assertFails(asD().doc(`coaching_plans/${A}`).get());
  });
  it('unrelated expert CANNOT read athlete meal_checkins', async () => {
    await assertFails(asD().doc(`meal_checkins/mc1`).get());
  });
  it('assigned coach CAN review a meal checkin', async () => {
    await assertSucceeds(asC().doc(`meal_checkins/mc1`).update({ score: 8, status: 'reviewed' }));
  });
});

describe('chat — participant gating', () => {
  it('participant CAN read the chat room', async () => {
    await assertSucceeds(asA().doc(`chat_rooms/chat_${A}_${C}`).get());
  });
  it('non-participant CANNOT read the chat room', async () => {
    await assertFails(asB().doc(`chat_rooms/chat_${A}_${C}`).get());
  });
  it('participant CAN read messages', async () => {
    await assertSucceeds(asC().doc(`chat_rooms/chat_${A}_${C}/messages/m1`).get());
  });
  it('non-participant CANNOT read messages', async () => {
    await assertFails(asB().doc(`chat_rooms/chat_${A}_${C}/messages/m1`).get());
  });
  it('participant CAN send a message stamped with own uid', async () => {
    await assertSucceeds(asA().doc(`chat_rooms/chat_${A}_${C}/messages/m2`).set({ senderId: A, text: 'hey' }));
  });
  it('participant CANNOT forge a message from the other party', async () => {
    await assertFails(asA().doc(`chat_rooms/chat_${A}_${C}/messages/m3`).set({ senderId: C, text: 'spoof' }));
  });
});

describe('review_requests — owner/expert', () => {
  it('athlete owner CAN read own request', async () => {
    await assertSucceeds(asA().doc(`review_requests/rr1`).get());
  });
  it('assigned expert CAN read the request', async () => {
    await assertSucceeds(asC().doc(`review_requests/rr1`).get());
  });
  it('unrelated user CANNOT read the request', async () => {
    await assertFails(asB().doc(`review_requests/rr1`).get());
  });
  it('athlete CAN create a request for themselves', async () => {
    await assertSucceeds(asA().doc(`review_requests/rr2`).set({ userId: A, athleteId: A, expertId: D, status: 'pending' }));
  });
  it('athlete CANNOT create a request as another user', async () => {
    await assertFails(asA().doc(`review_requests/rr3`).set({ userId: B, expertId: D, status: 'pending' }));
  });
  it('athlete CAN update workflow status (e.g. dismiss) on own request', async () => {
    await assertSucceeds(asA().doc(`review_requests/rr1`).update({ status: 'dismissed' }));
  });
  it('client CANNOT forge paymentStatus=paid on a review (payment-state lock)', async () => {
    await assertFails(asA().doc(`review_requests/rr1`).update({ paymentStatus: 'paid' }));
    await assertFails(asC().doc(`review_requests/rr1`).update({ paymentStatus: 'paid' }));
  });
  it('client CANNOT forge walletTransactionId on a review', async () => {
    await assertFails(asA().doc(`review_requests/rr1`).update({ walletTransactionId: 'txn_fake' }));
  });
  it('client CANNOT create a review pre-marked paid', async () => {
    await assertFails(asA().doc(`review_requests/rrPaid`).set({ userId: A, expertId: C, status: 'pending', paymentStatus: 'paid' }));
  });
  it('client CAN create a review as unpaid', async () => {
    await assertSucceeds(asA().doc(`review_requests/rrUnpaid`).set({ userId: A, expertId: C, status: 'pending', paymentStatus: 'unpaid' }));
  });
});

describe('notifications — recipient access', () => {
  it('recipient CAN read own notification', async () => {
    await assertSucceeds(asA().doc(`notifications/n1`).get());
  });
  it('non-recipient CANNOT read the notification', async () => {
    await assertFails(asB().doc(`notifications/n1`).get());
  });
  it('recipient CAN mark own notification read', async () => {
    await assertSucceeds(asA().doc(`notifications/n1`).update({ isRead: true }));
  });
  it('recipient CANNOT rewrite arbitrary fields', async () => {
    await assertFails(asA().doc(`notifications/n1`).update({ title: 'changed' }));
  });
});

describe('users — membership tamper', () => {
  it('athlete CANNOT self-activate premium membership', async () => {
    await assertFails(asA().doc(`users/${A}`).set(
      { membership: { plan: 'premium', active: true } }, { merge: true }));
  });
});

describe('expert_reviews — participant access', () => {
  it('athlete of the review CAN read it', async () => {
    await assertSucceeds(asA().doc(`expert_reviews/rr1`).get());
  });
  it('authoring expert CAN read it', async () => {
    await assertSucceeds(asC().doc(`expert_reviews/rr1`).get());
  });
  it('unrelated user CANNOT read it', async () => {
    await assertFails(asB().doc(`expert_reviews/rr1`).get());
  });
  it('only the expert (expertId==uid) can author a review', async () => {
    await assertSucceeds(asC().doc(`expert_reviews/rr9`).set({ reviewId: 'rr9', athleteId: A, expertId: C }));
    await assertFails(asA().doc(`expert_reviews/rr8`).set({ reviewId: 'rr8', athleteId: A, expertId: C }));
  });
});

describe('coaching_notifications — recipient access', () => {
  it('athlete recipient CAN read', async () => {
    await assertSucceeds(asA().doc(`coaching_notifications/cn1`).get());
  });
  it('coach recipient CAN read', async () => {
    await assertSucceeds(asC().doc(`coaching_notifications/cn1`).get());
  });
  it('unrelated user CANNOT read', async () => {
    await assertFails(asB().doc(`coaching_notifications/cn1`).get());
  });
});

describe('workout_checkins & coaching_meal_requests — participant', () => {
  it('coach CAN read athlete workout checkin', async () => {
    await assertSucceeds(asC().doc(`workout_checkins/wc1`).get());
  });
  it('unrelated expert CANNOT read workout checkin', async () => {
    await assertFails(asD().doc(`workout_checkins/wc1`).get());
  });
  it('athlete CAN create own workout checkin', async () => {
    await assertSucceeds(asA().doc(`workout_checkins/wc2`).set({ athleteId: A, coachId: C, status: 'pending' }));
  });
  it('coach CAN read a coaching_meal_request', async () => {
    await assertSucceeds(asC().doc(`coaching_meal_requests/cmr1`).get());
  });
  it('unrelated expert CANNOT read a coaching_meal_request', async () => {
    await assertFails(asD().doc(`coaching_meal_requests/cmr1`).get());
  });
});

describe('WebRTC calls — participant gating (calls + candidates)', () => {
  it('participant CAN read the call doc', async () => {
    await assertSucceeds(asC().doc(`chat_rooms/chat_${A}_${C}/calls/call1`).get());
  });
  it('non-participant CANNOT read the call doc', async () => {
    await assertFails(asB().doc(`chat_rooms/chat_${A}_${C}/calls/call1`).get());
  });
  it('participant CAN create a call', async () => {
    await assertSucceeds(asA().doc(`chat_rooms/chat_${A}_${C}/calls/call2`).set({ callerId: A, calleeId: C, status: 'ringing' }));
  });
  it('participant CAN read callerCandidates', async () => {
    await assertSucceeds(asC().doc(`chat_rooms/chat_${A}_${C}/calls/call1/callerCandidates/ic1`).get());
  });
  it('participant CAN add calleeCandidates', async () => {
    await assertSucceeds(asC().doc(`chat_rooms/chat_${A}_${C}/calls/call1/calleeCandidates/ic9`).set({ candidate: 'z' }));
  });
  it('non-participant CANNOT read callerCandidates', async () => {
    await assertFails(asB().doc(`chat_rooms/chat_${A}_${C}/calls/call1/callerCandidates/ic1`).get());
  });
  it('non-participant CANNOT write calleeCandidates', async () => {
    await assertFails(asB().doc(`chat_rooms/chat_${A}_${C}/calls/call1/calleeCandidates/hack`).set({ candidate: 'h' }));
  });
});

describe('QUERY authorization (collection queries, not just doc reads)', () => {
  it('athlete CANNOT list the whole users collection', async () => {
    await assertFails(asA().collection('users').get());
  });
  it('athlete CANNOT query another athlete\'s review_requests', async () => {
    // Query filtered to someone else's ownership field → rejected by rules.
    await assertFails(asB().collection('review_requests').where('userId', '==', A).get());
  });
  it('athlete CANNOT list all notifications (unfiltered)', async () => {
    await assertFails(asA().collection('notifications').get());
  });
  it('expert CANNOT list all review_requests (unfiltered)', async () => {
    await assertFails(asC().collection('review_requests').get());
  });
  it('coach CAN query own coaching_meal_requests (coachId==me)', async () => {
    await assertSucceeds(asC().collection('coaching_meal_requests').where('coachId', '==', C).get());
  });
  it('athlete CANNOT list all wallet_transactions', async () => {
    await assertFails(asA().collection('wallet_transactions').where('userId', '==', A).get());
  });
});

describe('money — tamper denial', () => {
  it('client CANNOT read wallet_transactions', async () => {
    await assertFails(asA().doc(`wallet_transactions/txn1`).get());
  });
  it('client CANNOT write wallet_transactions', async () => {
    await assertFails(asA().doc(`wallet_transactions/txnX`).set({ userId: A, amount: 9999 }));
  });
  it('client CANNOT read razorpay_orders', async () => {
    await assertFails(asA().doc(`razorpay_orders/order1`).get());
  });
  it('client CANNOT forge a razorpay_order paid', async () => {
    await assertFails(asA().doc(`razorpay_orders/order1`).update({ status: 'paid' }));
  });
});

describe('legitimate existing frontend queries still work', () => {
  it('expert dashboard: review_requests where expertId==me', async () => {
    await assertSucceeds(asC().collection('review_requests').where('expertId', '==', C).get());
  });
  it('notification center: notifications where userId==me', async () => {
    await assertSucceeds(asA().collection('notifications').where('userId', '==', A).get());
  });
  it('admin: pending certificates listing', async () => {
    await assertSucceeds(asAdmin().collection('expert_certificates').where('verificationStatus', '==', 'pending_review').get());
  });
  it('athlete: own meal_snap_logs subcollection', async () => {
    await assertSucceeds(asA().doc(`meal_snap_logs/${A}/2026-07-27/log1`).set({ day: 'Mon', mealType: 'lunch' }));
  });
});

describe('coach relationship EXPIRY', () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      // Flip C's relationship to expired.
      await ctx.firestore().doc(`personal_coaching/${A}`).set(
        { athleteId: A, coachId: C, status: 'active', endDateTs: past }, { merge: true });
    });
  });
  it('EXPIRED coach can no longer read athlete coaching_plans', async () => {
    await assertFails(asC().doc(`coaching_plans/${A}`).get());
  });
});
