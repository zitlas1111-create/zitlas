/*!
 * ZITLAS — Streak service (frontend/assets/js/streak-service.js)
 *
 * Day-goal streak logic. localStorage is the always-available source of
 * truth ("works offline"); Firestore users/{uid} gets a merge-synced copy
 * ({ currentStreak, longestStreak }) whenever a session is available.
 *
 * State (localStorage 'zitlas_activity_streak'):
 *   { currentStreak, longestStreak, lastGoalDate }   dates are "YYYY-MM-DD"
 *
 * Rules:
 *   goal completed today, yesterday also completed  -> streak + 1
 *   goal completed today after a gap                -> streak = 1
 *   a day ends without the goal                     -> streak = 0
 */
(function (win) {
  'use strict';

  var KEY = 'zitlas_activity_streak';

  function localDateStr(d) {
    d = d || new Date();
    return d.getFullYear() + '-' +
      String(d.getMonth() + 1).padStart(2, '0') + '-' +
      String(d.getDate()).padStart(2, '0');
  }

  function prevDateStr(dateStr) {
    var d = new Date(dateStr + 'T12:00:00'); /* noon avoids DST edge cases */
    d.setDate(d.getDate() - 1);
    return localDateStr(d);
  }

  function load() {
    try {
      var s = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (s && typeof s.currentStreak === 'number') return s;
    } catch (_) {}
    return { currentStreak: 0, longestStreak: 0, lastGoalDate: null };
  }

  function save(state) {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (_) {}
    _syncUserDoc(state);
  }

  function _syncUserDoc(state) {
    try {
      if (typeof ZitlasDB === 'undefined' || typeof ZitlasAuth === 'undefined' || !ZitlasAuth.currentUser) return;
      ZitlasDB.collection('users').doc(ZitlasAuth.currentUser.uid).set({
        currentStreak: state.currentStreak,
        longestStreak: state.longestStreak,
        lastGoalDate:  state.lastGoalDate || null,
      }, { merge: true }).catch(function (e) {
        console.warn('[STREAK] Firestore sync failed (will retry next sync):', e && e.code);
      });
    } catch (_) {}
  }

  /* ══════════════════════════════════════════
     CROSS-DEVICE SYNC
     This was write-only before: a fresh device never pulled down an
     existing streak, so the SAME account showed 0 on one phone and 12 on
     another. Hydrate once on login, then stay live via onSnapshot — same
     users/{uid} doc login.js/activity-service.js/cloud-sync.js already
     share, each merging only their own fields.
  ══════════════════════════════════════════ */
  var _subscribers = [];
  function onSync(cb) { if (typeof cb === 'function') _subscribers.push(cb); }
  function _notify() {
    _subscribers.forEach(function (fn) {
      try { fn(); } catch (e) { console.error('[STREAK] subscriber threw', e); }
    });
  }

  function _mergeRemote(data) {
    if (!data || typeof data.currentStreak !== 'number') return false;
    var local = load();
    var merged = {
      currentStreak: data.currentStreak,
      longestStreak: Math.max(data.longestStreak || 0, local.longestStreak || 0),
      lastGoalDate:  data.lastGoalDate || local.lastGoalDate || null,
    };
    var changed = JSON.stringify(merged) !== JSON.stringify(local);
    if (changed) { try { localStorage.setItem(KEY, JSON.stringify(merged)); } catch (_) {} }
    return changed;
  }

  var _attachedFor = null;
  function _initCloudSync() {
    if (typeof ZitlasAuth === 'undefined') return;
    ZitlasAuth.onAuthStateChanged(function (user) {
      if (!user || typeof ZitlasDB === 'undefined' || _attachedFor === user.uid) return;
      _attachedFor = user.uid;
      var uid = user.uid;
      ZitlasDB.collection('users').doc(uid).get().then(function (snap) {
        if (snap.exists && _mergeRemote(snap.data())) _notify();
      }).catch(function (e) { console.warn('[STREAK] hydrate failed', e); });

      ZitlasDB.collection('users').doc(uid).onSnapshot(function (snap) {
        if (snap.exists && _mergeRemote(snap.data())) _notify();
      }, function (e) { console.warn('[STREAK] realtime error', e); });
    });
  }
  _initCloudSync();

  /* A day whose goal was never met has ended — streak breaks.
     No-op if the goal was met that same day (lastGoalDate covers it). */
  function recordMissedDay(dateStr) {
    var s = load();
    if (s.lastGoalDate === dateStr) return s; /* actually completed — not a miss */
    if (s.currentStreak !== 0) {
      console.log('[STREAK] missed', dateStr, '— streak reset from', s.currentStreak);
      s.currentStreak = 0;
      save(s);
    }
    return s;
  }

  /* Goal completed on dateStr (normally today). Idempotent per day. */
  function updateStreak(dateStr) {
    dateStr = dateStr || localDateStr();
    var s = load();
    if (s.lastGoalDate === dateStr) return s; /* already counted today */
    s.currentStreak = (s.lastGoalDate === prevDateStr(dateStr)) ? s.currentStreak + 1 : 1;
    s.lastGoalDate  = dateStr;
    if (s.currentStreak > s.longestStreak) s.longestStreak = s.currentStreak;
    console.log('[STREAK] goal met', dateStr, '— streak now', s.currentStreak,
      '(longest', s.longestStreak + ')');
    save(s);
    return s;
  }

  /* Read with gap correction: if the last completed day is neither today
     nor yesterday, days were missed while the app was closed. */
  function getStreak() {
    var s = load();
    var today = localDateStr();
    if (s.currentStreak > 0 && s.lastGoalDate !== today && s.lastGoalDate !== prevDateStr(today)) {
      s.currentStreak = 0;
      save(s);
    }
    return { currentStreak: s.currentStreak, longestStreak: s.longestStreak, lastGoalDate: s.lastGoalDate };
  }

  win.ZitlasStreak = {
    updateStreak:    updateStreak,
    recordMissedDay: recordMissedDay,
    getStreak:       getStreak,
    onSync:          onSync,
    _localDateStr:   localDateStr,
    _prevDateStr:    prevDateStr,
  };
  /* Bare global alias (spec-required name) */
  win.updateStreak = updateStreak;
})(window);
