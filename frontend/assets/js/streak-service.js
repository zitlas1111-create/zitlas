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
      }, { merge: true }).catch(function (e) {
        console.warn('[STREAK] Firestore sync failed (will retry next sync):', e && e.code);
      });
    } catch (_) {}
  }

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
    _localDateStr:   localDateStr,
    _prevDateStr:    prevDateStr,
  };
  /* Bare global alias (spec-required name) */
  win.updateStreak = updateStreak;
})(window);
