/*!
 * ZITLAS — Cross-Device Cloud Sync (assets/js/cloud-sync.js)
 *
 * ROOT CAUSE THIS FIXES: goal, assessment/SWOT/calculations, diet plan,
 * workout plan, personal info (name/photo/age/height/weight/etc.), and
 * wallet balance were 100% localStorage — a second device logged into the
 * SAME Firebase account had none of it. Personal Coaching, chat, reviews,
 * notifications, meal check-ins, and certificates were ALREADY correctly
 * Firestore-backed before this file existed and are untouched.
 *
 * STRATEGY: a cache-through mirror, not a rewrite of every read/write call
 * site. Firestore users/{uid} becomes the source of truth for the fields
 * below; localStorage keeps the exact same keys every existing page
 * already reads, so diet.js/weekly-plan.js/dashboard.js/etc. work
 * unmodified once their init is gated behind hydrateOnLoad() and they
 * re-render on the 'zitlas:cloud-sync' event. New/changed data always
 * goes through save() below, which writes localStorage AND Firestore
 * together — so the writing tab updates instantly and every other device
 * gets it the moment its onSnapshot fires.
 *
 * Deliberately NOT synced (matches the spec's own carve-out): theme,
 * tutorial-completion flags, last-opened-tab, and raw device step-counter
 * data (activity-service.js) — a phone's pedometer reading is legitimately
 * device-specific, unlike a user-entered goal or an AI-generated plan.
 *
 * Fields already owned by login.js/streak-service.js/activity-service.js
 * (name, photo, role, roles, expert_status, createdAt, last_login,
 * currentStreak, longestStreak, dailyStepGoal, lastSyncDate) are never
 * touched here — everything below lives under distinct top-level field
 * names on the same users/{uid} doc to avoid any collision.
 */
(function (win) {
  'use strict';

  var FIELD_MAP = {
    goal:         'zitlas_goal',
    assessment:   'zitlas_assessment',
    survey:       'zitlas_survey',
    calculations: 'zitlas_calculations',
    swot:         'zitlas_swot',
    dietPlan:     'zitlas_diet_plan',
    workoutPlan:  'zitlas_workout_plan',
    roadmap:      'zitlas_roadmap',
    precautions:  'zitlas_precautions',
    personalInfo: 'zitlas_personal_info',
    wallet:       'zitlas_wallet',
    location:     'zitlas_location', /* Geo-Aware Food Intelligence — optional */
    planMeta:     null, /* virtual — see planGeneratedAt/planId below */
  };
  /* Small standalone string/number fields that don't warrant a whole
     localStorage JSON blob of their own. */
  var SCALAR_FIELD_MAP = {
    planGeneratedAt: 'zitlas_plan_generated_at',
    planId:          'zitlas_plan_id',
  };

  function db() { return (typeof ZitlasDB !== 'undefined') ? ZitlasDB : null; }
  function myUid() {
    if (typeof ZitlasAuth !== 'undefined' && ZitlasAuth.currentUser) return ZitlasAuth.currentUser.uid;
    try {
      var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || 'null');
      if (fb && fb.uid) return fb.uid;
    } catch (_) {}
    return null;
  }

  /* personalInfo can carry a base64 profile photo, which is device-local
     on purpose (Firestore documents cap out at 1 MiB — a proper fix needs
     Storage-hosted URLs like the chat/certificate uploads already use).
     Callers that write personalInfo strip `photo` before syncing to the
     cloud, so applying a cloud copy must MERGE on top of the existing
     local object instead of overwriting it, or the local photo would be
     wiped out the next time this device hydrates. */
  var MERGE_ON_APPLY = { personalInfo: true };

  function _applyField(cloudKey, lsKey, cloudValue) {
    if (MERGE_ON_APPLY[cloudKey]) {
      var existing = {};
      try { existing = JSON.parse(localStorage.getItem(lsKey) || '{}') || {}; } catch (_) {}
      var merged = Object.assign({}, existing, cloudValue);
      var mergedStr = JSON.stringify(merged);
      var changed = JSON.stringify(existing) !== mergedStr;
      if (changed) localStorage.setItem(lsKey, mergedStr);
      return changed;
    }
    var newStr = JSON.stringify(cloudValue);
    var changed = localStorage.getItem(lsKey) !== newStr;
    if (changed) localStorage.setItem(lsKey, newStr);
    return changed;
  }

  var _hydratedFor = null;
  var _realtimeAttachedFor = null;

  /* One-shot fetch, resolved BEFORE a page's own init() reads localStorage,
     so the very first render already has this device's latest cloud data
     instead of flashing stale/empty local state. */
  /* Multiple independent modules on the same page (wallet.js + the page's
     own boot()) each call this — memoize the in-flight/completed promise
     per uid so that only ONE Firestore read happens per page load. */
  var _hydratePromise = null;
  var _hydratePromiseFor = null;
  function hydrateOnLoad(uid) {
    uid = uid || myUid();
    var d = db();
    if (!uid || !d) return Promise.resolve(false);
    if (_hydratePromiseFor === uid && _hydratePromise) return _hydratePromise;
    _hydratePromiseFor = uid;
    _hydratePromise = d.collection('users').doc(uid).get().then(function (snap) {
      if (!snap.exists) return false;
      _applySnapshot(snap.data());
      _hydratedFor = uid;
      return true;
    }).catch(function (e) {
      console.warn('[CLOUD SYNC] hydrate failed — continuing with local cache', e);
      return false;
    });
    return _hydratePromise;
  }

  function _applySnapshot(data) {
    Object.keys(FIELD_MAP).forEach(function (cloudKey) {
      var lsKey = FIELD_MAP[cloudKey];
      if (!lsKey || data[cloudKey] === undefined) return;
      try { _applyField(cloudKey, lsKey, data[cloudKey]); } catch (_) {}
    });
    Object.keys(SCALAR_FIELD_MAP).forEach(function (cloudKey) {
      var lsKey = SCALAR_FIELD_MAP[cloudKey];
      if (data[cloudKey] === undefined || data[cloudKey] === null) return;
      try { localStorage.setItem(lsKey, String(data[cloudKey])); } catch (_) {}
    });
  }

  /* Realtime — call once per page. Fires `cb()` (with no args) whenever
     THIS device's local cache actually changed, so the page can re-run
     its own render function. Deliberately skips re-render on the very
     first snapshot when it matches what hydrateOnLoad() already applied,
     to avoid a redundant double-render on page open. */
  /* Independent modules on the SAME page (wallet.js, dashboard.js,
     notification-center.js, etc.) each call attachRealtime() with their
     own callback — only ONE underlying Firestore listener is ever opened
     per uid per page; every registered callback fires off that single
     snapshot. */
  var _subscribers = [];
  function attachRealtime(uid, cb) {
    uid = uid || myUid();
    var d = db();
    if (!uid || !d) return function () {};
    if (typeof cb === 'function') _subscribers.push(cb);
    if (_realtimeAttachedFor === uid) return function () {};
    _realtimeAttachedFor = uid;

    return d.collection('users').doc(uid).onSnapshot(function (snap) {
      if (!snap.exists) return;
      var data = snap.data();
      var changed = false;
      Object.keys(FIELD_MAP).forEach(function (cloudKey) {
        var lsKey = FIELD_MAP[cloudKey];
        if (!lsKey || data[cloudKey] === undefined) return;
        if (_applyField(cloudKey, lsKey, data[cloudKey])) changed = true;
      });
      if (changed) {
        console.log('[CLOUD SYNC] remote change applied —', _subscribers.length, 'subscriber(s) re-rendering');
        try { win.dispatchEvent(new CustomEvent('zitlas:cloud-sync')); } catch (_) {}
        _subscribers.forEach(function (fn) {
          try { fn(); } catch (e) { console.error('[CLOUD SYNC] subscriber threw', e); }
        });
      }
    }, function (e) { console.warn('[CLOUD SYNC] realtime listener error', e); });
  }

  /* The ONE function every feature should call instead of a bare
     localStorage.setItem for anything in FIELD_MAP/SCALAR_FIELD_MAP.
     Writes local first (so the calling tab is instant), then Firestore. */
  function save(cloudKey, value) {
    var lsKey = FIELD_MAP[cloudKey] || SCALAR_FIELD_MAP[cloudKey];
    if (lsKey) {
      try {
        localStorage.setItem(lsKey, typeof value === 'string' && SCALAR_FIELD_MAP[cloudKey]
          ? value : JSON.stringify(value));
      } catch (_) {}
    }
    var d = db();
    var uid = myUid();
    if (!d || !uid) return Promise.resolve();
    var patch = {};
    patch[cloudKey] = value;
    patch[cloudKey + 'UpdatedAt'] = new Date().toISOString();
    return d.collection('users').doc(uid).set(patch, { merge: true })
      .catch(function (e) { console.warn('[CLOUD SYNC] save failed for', cloudKey, e); });
  }

  /* Cloud-only write — skips the local mirror entirely. For callers (like
     the personal-info form) that already persist their own localStorage
     copy with fields (e.g. a photo) deliberately excluded from the cloud
     copy; letting save() touch localStorage here would immediately
     overwrite that fuller local object with the stripped-down one. */
  function saveCloudOnly(cloudKey, value) {
    var d = db();
    var uid = myUid();
    if (!d || !uid) return Promise.resolve();
    var patch = {};
    patch[cloudKey] = value;
    patch[cloudKey + 'UpdatedAt'] = new Date().toISOString();
    return d.collection('users').doc(uid).set(patch, { merge: true })
      .catch(function (e) { console.warn('[CLOUD SYNC] saveCloudOnly failed for', cloudKey, e); });
  }

  /* Like save(), but for writing several fields in ONE network round-trip —
     used right after AI plan generation, which touches 5-7 fields at once. */
  function saveBulk(fields) {
    Object.keys(fields).forEach(function (cloudKey) {
      var lsKey = FIELD_MAP[cloudKey] || SCALAR_FIELD_MAP[cloudKey];
      if (!lsKey) return;
      var value = fields[cloudKey];
      try {
        localStorage.setItem(lsKey, typeof value === 'string' && SCALAR_FIELD_MAP[cloudKey]
          ? value : JSON.stringify(value));
      } catch (_) {}
    });
    var d = db();
    var uid = myUid();
    if (!d || !uid) return Promise.resolve();
    var patch = {};
    var now = new Date().toISOString();
    Object.keys(fields).forEach(function (cloudKey) {
      patch[cloudKey] = fields[cloudKey];
      patch[cloudKey + 'UpdatedAt'] = now;
    });
    return d.collection('users').doc(uid).set(patch, { merge: true })
      .catch(function (e) { console.warn('[CLOUD SYNC] saveBulk failed', e); });
  }

  /* Convenience: hydrate then boot the page's normal init, then attach
     realtime pointed at the same init function so it just re-runs on any
     remote change. Falls back to calling initFn immediately (local-only)
     when there's no session yet — never blocks a logged-out/guest page. */
  function bootWithSync(initFn) {
    if (typeof ZitlasAuth === 'undefined') { initFn(); return; }
    ZitlasAuth.onAuthStateChanged(function (user) {
      if (!user) { initFn(); return; }
      hydrateOnLoad(user.uid).then(function () {
        initFn();
        attachRealtime(user.uid, initFn);
      });
    });
  }

  win.ZitlasCloudSync = {
    hydrateOnLoad: hydrateOnLoad,
    attachRealtime: attachRealtime,
    save: save,
    saveCloudOnly: saveCloudOnly,
    saveBulk: saveBulk,
    bootWithSync: bootWithSync,
    myUid: myUid,
  };
})(window);
