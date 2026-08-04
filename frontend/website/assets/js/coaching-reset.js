/*!
 * ZITLAS — Shared Personal Coaching + Expert Review cleanup
 * (assets/js/coaching-reset.js)
 *
 * Single source of truth for "retire all coach/review state," called from
 * every trigger business rules require: Reset Goal (both the Dashboard's
 * button AND the Diet page's own button — these used to diverge, the root
 * cause of one bug class), End/Cancel Personal Coaching, and generating a
 * fresh AI plan / retaking the assessment (both funnel through
 * ai-coach.js's saveToLocalStorage()).
 *
 * THE SUBTLE PART this fixes: clearing localStorage alone is NOT durable
 * against assets/js/review-sync.js's live Firestore onSnapshot listener.
 * That listener treats "no local anchor" as "adopt the newest live review
 * from Firestore" (see its reconcileAnchor()) — so a moment after clearing
 * expert_plan_reviews / zitlas_review_request, the very next snapshot fire
 * silently repopulates them, because clearing localStorage never touched
 * the review_requests DOCS themselves, which review-sync.js is still
 * live-watching. This module marks every review the device currently
 * knows about as no longer "live" (status: 'dismissed') directly in
 * Firestore, so review-sync.js's own isLive() check correctly excludes it
 * — the actual fix, not a symptom suppression that a live listener would
 * just undo again.
 */
(function (win) {
  'use strict';

  var LOCAL_KEYS = [
    'zitlas_expert_review', 'zitlas_plan_versions', 'zitlas_review_request',
    'expert_plan_reviews', 'expert_review', 'expert_diet_override', 'reviewed_diet_plan',
    'modifiedBy', 'expertApproval', 'review_request',
    'expertDiet', 'expertOverride', 'dietOverride', 'reviewStatus',
    'expertReviewedPlan', 'approvedPlan', 'expertWorkoutOverride',
  ];

  function safeJSON(key, fallback) {
    try { var v = JSON.parse(localStorage.getItem(key) || 'null'); return v == null ? fallback : v; }
    catch (_) { return fallback; }
  }
  function myUid() {
    if (typeof ZitlasAuth !== 'undefined' && ZitlasAuth.currentUser) return ZitlasAuth.currentUser.uid;
    var fb = safeJSON('zitlas_firebase_user', null);
    return (fb && fb.uid) || localStorage.getItem('zitlas_athlete_id') || null;
  }

  /* Dismisses every LIVE review_requests doc for this user — by Firestore
     QUERY, not just the ids this device happens to have cached. The old
     ids-from-localStorage approach had a fatal gap: after localStorage was
     already cleared (a previous reset, another device's reset, a fresh
     login), there were no ids to dismiss — the still-live Firestore docs
     survived, and review-sync.js's "no local anchor → adopt newest live
     review" path resurrected them onto the device. Query-based dismissal
     retires them at the SOURCE, regardless of local cache state. The
     locally-cached ids are still included as a supplement for legacy docs
     that may predate the userId field. */
  var _LIVE_REVIEW_STATUSES = ['pending', 'in_progress', 'expert_reviewing', 'completed', 'review_completed'];
  function _dismissLiveReviewsInFirestore() {
    if (typeof ZitlasDB === 'undefined') return Promise.resolve();
    var now = new Date().toISOString();
    var ids = {};
    var anchor = safeJSON('zitlas_review_request', null);
    if (anchor && anchor.id) ids[anchor.id] = true;
    (safeJSON('expert_plan_reviews', []) || []).forEach(function (r) { if (r && r.id) ids[r.id] = true; });

    function dismissDoc(id) {
      return ZitlasDB.collection('review_requests').doc(id)
        .update({ status: 'dismissed', dismissedAt: now })
        .catch(function (e) { console.warn('[COACHING RESET] could not dismiss review_requests/' + id, e); });
    }

    var uid = myUid();
    var queryPromise = !uid ? Promise.resolve() :
      ZitlasDB.collection('review_requests').where('userId', '==', uid).get()
        .then(function (snap) {
          var live = [];
          snap.forEach(function (doc) {
            var d = doc.data() || {};
            if (_LIVE_REVIEW_STATUSES.indexOf(d.status) !== -1) { live.push(doc.id); delete ids[doc.id]; }
            else delete ids[doc.id]; /* already terminal — no write needed */
          });
          console.log('[COACHING RESET] dismissing', live.length, 'live review doc(s) by query');
          return Promise.all(live.map(dismissDoc));
        })
        .catch(function (e) { console.warn('[COACHING RESET] review query failed — falling back to cached ids', e); });

    return queryPromise.then(function () {
      var rest = Object.keys(ids);
      if (!rest.length) return;
      return Promise.all(rest.map(dismissDoc));
    });
  }

  /* Retires personal_coaching/{uid} to a status neither diet.js's
     _pcShowsCoachPlan() nor ZitlasCoachingGate treats as show-worthy.
     NEVER deletes — coaching history, ratings, chat, wallet transactions
     must survive a reset; only this specific relationship's "am I still
     the active coach" signal is retired. */
  function _retireCoachingRelationship(newStatus) {
    if (typeof ZitlasDB === 'undefined') return Promise.resolve();
    var uid = myUid();
    if (!uid) return Promise.resolve();
    var relRef = ZitlasDB.collection('personal_coaching').doc(uid);
    return relRef.get().then(function (snap) {
      if (!snap.exists) return;
      var prior = snap.data() || {};
      if (prior.status === newStatus) return;
      var patch = { status: newStatus, priorStatus: prior.status || null };
      patch[newStatus + 'At'] = new Date().toISOString();
      return relRef.update(patch);
    }).catch(function (e) { console.warn('[COACHING RESET] relationship retire failed (non-blocking)', e); });
  }

  /* Wipes the athlete context previously published into
     coaching_plans/{uid} (assessment, medical conditions, AI plans, goal).
     Without this, a coach opening the workspace after the athlete's Goal
     Reset still sees the PREVIOUS goal's data — e.g. medical conditions
     the athlete never reported on their new assessment. The coach-authored
     diet/training plans on the same doc are deliberately left untouched
     (history). Fresh context is re-published automatically by cprofile.js/
     diet.js the next time a coaching relationship is active. */
  function _clearPublishedContext() {
    if (typeof ZitlasDB === 'undefined' || typeof firebase === 'undefined') return Promise.resolve();
    var uid = myUid();
    if (!uid) return Promise.resolve();
    return ZitlasDB.collection('coaching_plans').doc(uid).update({
      athleteContext: firebase.firestore.FieldValue.delete(),
      athleteContextUpdatedAt: firebase.firestore.FieldValue.delete(),
    }).catch(function (e) {
      /* Missing doc = nothing published = nothing stale. Non-blocking. */
      if (!(e && e.code === 'not-found')) console.warn('[COACHING RESET] context clear failed (non-blocking)', e);
    });
  }

  function clearLocalReviewKeys() {
    LOCAL_KEYS.forEach(function (k) { localStorage.removeItem(k); });
  }

  /* opts.relationshipStatus — pass 'reset' from Reset Goal / retake
     assessment flows so personal_coaching/{uid} is retired too (omit this
     from End Coaching's own call — cprofile.js already sets 'ended'
     itself; calling this with no relationshipStatus there just adds the
     review-dismissal half without racing that separate write). */
  function clearAll(opts) {
    opts = opts || {};
    var dismissPromise = _dismissLiveReviewsInFirestore();
    clearLocalReviewKeys();
    var relationshipPromise = opts.relationshipStatus
      ? _retireCoachingRelationship(opts.relationshipStatus)
      : Promise.resolve();
    /* Goal Reset flows (relationshipStatus set) also wipe the published
       athlete context so the coach can never see the previous goal's
       assessment/medical data. */
    var contextPromise = opts.relationshipStatus
      ? _clearPublishedContext()
      : Promise.resolve();
    /* A true Goal Reset also clears the users/{uid} cloud mirror of every
       goal-scoped field (goal, assessment, plans, calculations, planId…).
       Without this, cloud-sync's hydrateOnLoad() RESTORED everything the
       reset had just deleted from localStorage on the very next page load
       — the root cause of "I reset my goal 7 times and old data keeps
       coming back". */
    var cloudPromise = (opts.relationshipStatus === 'reset' && typeof ZitlasCloudSync !== 'undefined')
      ? ZitlasCloudSync.clearGoalData()
      : Promise.resolve();
    console.log('[COACHING RESET] cleared local review keys' +
      (opts.relationshipStatus ? ' + retiring relationship to "' + opts.relationshipStatus + '" + clearing published context + cloud goal data' : ''));
    return Promise.all([dismissPromise, relationshipPromise, contextPromise, cloudPromise]);
  }

  win.ZitlasCoachingReset = { clearAll: clearAll, clearLocalReviewKeys: clearLocalReviewKeys };
})(window);
