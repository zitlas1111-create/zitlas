/*!
 * ZITLAS — Athlete review synchronizer (assets/js/review-sync.js)
 *
 * THE missing link between the expert completing a review and the athlete
 * actually seeing it. Before this module, the only Firestore→device sync
 * for review_requests lived inside cprofile.js — meaning the athlete had
 * to open that specific expert's PROFILE page for the completed review to
 * reach their device at all. Opening the Diet page directly (the natural
 * place to look for your diet) read only the stale localStorage cache and
 * kept showing the original AI plan.
 *
 * Runs on the Diet page and Dashboard (any page that includes it):
 *   onSnapshot review_requests.where(userId == me)
 *     -> merge every doc into expert_plan_reviews  (the cache diet.js reads)
 *     -> maintain the zitlas_review_request anchor (which request is ACTIVE
 *        — the same anchor diet.js's getCompletedPlanReview() matches on,
 *        so the banner can never show a different expert's stale review)
 *     -> notification on accept/complete (deduped via localStorage flags,
 *        because cprofile.js's own listener may fire for the same event
 *        in another tab)
 *     -> dispatch "zitlas-review-updated" so an OPEN diet page re-renders
 *        live (localStorage 'storage' events never fire in the writing tab)
 *
 * Deliberately does NOT auto-apply plans — the diet page's banner/Accept
 * flow owns that, so the athlete always consciously accepts changes.
 */
(function (win) {
  'use strict';

  var REVIEWS_KEY = 'expert_plan_reviews';
  var ANCHOR_KEY  = 'zitlas_review_request';

  function safeJSON(key, fallback) {
    try { var v = JSON.parse(localStorage.getItem(key) || 'null'); return v == null ? fallback : v; }
    catch (_) { return fallback; }
  }
  function myUid() {
    if (typeof ZitlasAuth !== 'undefined' && ZitlasAuth.currentUser) return ZitlasAuth.currentUser.uid;
    var fb = safeJSON('zitlas_firebase_user', null);
    if (fb && fb.uid) return fb.uid;
    return localStorage.getItem('zitlas_athlete_id') || null;
  }
  function isCompleted(status) { return status === 'completed' || status === 'review_completed'; }
  function isLive(status) {
    /* statuses that still represent an ACTIVE request lifecycle */
    return status === 'pending' || status === 'in_progress' || status === 'expert_reviewing' ||
           isCompleted(status);
  }

  /* One notification per (review, milestone) across ALL tabs/pages —
     cprofile.js's listener uses the same flags. */
  function notifyOnce(reviewId, milestone, fn) {
    var flag = 'zitlas_review_note_' + reviewId + '_' + milestone;
    if (localStorage.getItem(flag)) return;
    try { localStorage.setItem(flag, new Date().toISOString()); } catch (_) {}
    fn();
  }

  /* Keep the active-request anchor honest:
     - anchor's doc synced & live        -> refresh its status/expert fields
     - anchor's doc synced & superseded  -> re-point at the newest live one
     - anchor's doc NOT in the snapshot  -> leave the anchor ALONE (it may
       be an in-flight write; re-pointing here could resurrect an older
       expert's review — the exact wrong-expert bug class)
     - no anchor at all                  -> adopt the newest live request
       (heals the paid request flow, which historically never wrote the
       anchor, AND makes requests made on another device work here) */
  function reconcileAnchor(docs) {
    var anchor = safeJSON(ANCHOR_KEY, null);
    var byId = {};
    docs.forEach(function (d) { byId[d.id] = d; });

    if (anchor && anchor.id) {
      var d = byId[anchor.id];
      if (!d) return; /* not in this snapshot — never second-guess it */
      if (isLive(d.status)) {
        var updated = Object.assign({}, anchor, {
          status: d.status, expertId: d.expertId || anchor.expertId,
        });
        if (JSON.stringify(updated) !== JSON.stringify(anchor)) {
          try { localStorage.setItem(ANCHOR_KEY, JSON.stringify(updated)); } catch (_) {}
        }
        return;
      }
      /* superseded/cancelled — fall through to adopt a replacement */
    }

    /* No usable anchor — adopt the newest live, not-yet-accepted request */
    var live = docs.filter(function (d) {
      return d.id && isLive(d.status) && !d.athleteAccepted &&
             (d.reviewType || d.planReviewType || 'diet') !== undefined;
    }).sort(function (a, b) {
      return String(b.submittedAt || b.createdAt || '') < String(a.submittedAt || a.createdAt || '') ? -1 : 1;
    });
    if (live.length) {
      var top = live[0];
      try {
        localStorage.setItem(ANCHOR_KEY, JSON.stringify({
          id: top.id, expertId: top.expertId, planId: top.planId || null, status: top.status,
        }));
        console.log('[REVIEW SYNC] anchor set from Firestore →', top.id, '(' + (top.expertName || top.expertId) + ')');
      } catch (_) {}
    }
  }

  function attach() {
    if (win.__zitlasReviewSyncAttached) return;
    if (typeof ZitlasDB === 'undefined') return;
    var uid = myUid();
    if (!uid) return;
    win.__zitlasReviewSyncAttached = true;

    console.log('[REVIEW SYNC] listening: review_requests.where(userId ==', uid + ')');
    ZitlasDB.collection('review_requests')
      .where('userId', '==', uid)
      .onSnapshot(function (snapshot) {
        var docs = snapshot.docs.map(function (d) { return d.data(); }).filter(function (d) { return d && d.id; });
        if (!docs.length) return;

        var all = safeJSON(REVIEWS_KEY, []);
        if (!Array.isArray(all)) all = [];
        var changed = false;

        docs.forEach(function (data) {
          var idx = all.findIndex(function (r) { return r.id === data.id; });
          var prev = idx !== -1 ? (all[idx].status || '') : '';
          var next = data.status || '';

          /* Merge Firestore over the local copy — Firestore is canonical
             for expert-authored fields (reviewedDietPlan, status, names);
             athleteAccepted is LOCAL-only progress and must survive. */
          var merged = Object.assign({}, idx !== -1 ? all[idx] : {}, data);
          if (idx !== -1 && all[idx].athleteAccepted) merged.athleteAccepted = true;
          var mergedStr = JSON.stringify(merged);
          if (idx === -1) { all.push(merged); changed = true; }
          else if (JSON.stringify(all[idx]) !== mergedStr) { all[idx] = merged; changed = true; }

          /* Milestone notifications (deduped across tabs/pages) */
          if (typeof ZitlasNotify !== 'undefined') {
            if (!isCompleted(prev) && isCompleted(next)) {
              notifyOnce(data.id, 'completed', function () {
                ZitlasNotify.send(uid, {
                  title: '⭐ ' + (data.expertName || 'Expert') + ' completed your review',
                  message: 'Open your ' + ((data.reviewType || 'diet') === 'workout' ? 'Training' : 'Diet') +
                           ' page to see and accept the changes.',
                  category: 'review', type: 'review_completed', priority: 'high',
                  action: (data.reviewType === 'workout') ? 'training' : 'diet',
                  expertId: data.expertId,
                });
              });
            } else if (prev === 'pending' && (next === 'in_progress' || next === 'expert_reviewing')) {
              notifyOnce(data.id, 'accepted', function () {
                ZitlasNotify.send(uid, {
                  title: '👨‍⚕️ ' + (data.expertName || 'Expert') + ' accepted your review request',
                  message: 'They’re now reviewing your ' + (data.reviewType || 'plan') + '.',
                  category: 'review', type: 'review_accepted',
                  action: 'expert_profile', actionId: data.expertId,
                  expertId: data.expertId,
                });
              });
            }
          }
        });

        if (changed) {
          try { localStorage.setItem(REVIEWS_KEY, JSON.stringify(all)); } catch (_) {}
        }
        reconcileAnchor(docs);
        if (changed) {
          console.log('[REVIEW SYNC]', docs.length, 'doc(s) merged — notifying page');
          try { win.dispatchEvent(new CustomEvent('zitlas-review-updated')); } catch (_) {}
        }
      }, function (e) { console.warn('[REVIEW SYNC] listener error', e); });
  }

  /* Auth may settle after DOM — try now, on auth change, and once delayed */
  function init() {
    attach();
    if (typeof ZitlasAuth !== 'undefined') {
      ZitlasAuth.onAuthStateChanged(function () { attach(); });
    }
    setTimeout(attach, 3000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  win.ZitlasReviewSync = { attach: attach };
})(window);
