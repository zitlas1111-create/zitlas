/*!
 * ZITLAS — Activity service (frontend/assets/js/activity-service.js)
 *
 * The daily-activity data model. A "day" runs midnight-to-midnight in the
 * DEVICE's local timezone (same convention as Google Fit).
 *
 * localStorage (always available — offline-first):
 *   zitlas_activity_today    { date, steps, distance, calories,
 *                              activeMinutes, goalCompleted }
 *   zitlas_activity_history  { "YYYY-MM-DD": <same shape> } (last 90 days)
 *   zitlas_daily_step_goal   number (default 10000)
 *   zitlas_activity_pending  ["YYYY-MM-DD", ...] dates awaiting Firestore
 *
 * Firestore (synced whenever a session exists; failures queue for retry):
 *   users/{uid}/activity/{date}  the archived day document
 *   users/{uid}                  { dailyStepGoal, lastSyncDate } (merge)
 *
 * Depends on: streak-service.js (must load first).
 */
(function (win) {
  'use strict';

  var TODAY_KEY   = 'zitlas_activity_today';
  var HISTORY_KEY = 'zitlas_activity_history';
  var GOAL_KEY    = 'zitlas_daily_step_goal';
  var PENDING_KEY = 'zitlas_activity_pending';
  var HISTORY_MAX_DAYS = 90;
  var DEFAULT_GOAL = 10000;

  function todayStr() { return win.ZitlasStreak._localDateStr(); }

  function _load(key, fallback) {
    try { return JSON.parse(localStorage.getItem(key) || 'null') || fallback; }
    catch (_) { return fallback; }
  }
  function _save(key, val) {
    try { localStorage.setItem(key, JSON.stringify(val)); } catch (_) {}
  }

  function _blankDay(date) {
    return { date: date, steps: 0, distance: 0, calories: 0, activeMinutes: 0, goalCompleted: false };
  }

  /* ── Daily goal ── */

  function getDailyGoal() {
    var g = parseInt(localStorage.getItem(GOAL_KEY), 10);
    return (g && g > 0) ? g : DEFAULT_GOAL;
  }

  function setDailyGoal(n) {
    n = parseInt(n, 10);
    if (!n || n <= 0) return getDailyGoal();
    try { localStorage.setItem(GOAL_KEY, String(n)); } catch (_) {}
    _mergeUserDoc({ dailyStepGoal: n });
    console.log('[ACTIVITY] daily step goal set to', n);
    return n;
  }

  /* ── Today model ── */

  function getToday() {
    var t = _load(TODAY_KEY, null);
    if (!t || t.date !== todayStr()) return _blankDay(todayStr());
    return t;
  }

  function getTodaySteps()         { return getToday().steps; }
  function getTodayDistance()      { return getToday().distance; }
  function getTodayCalories()      { return getToday().calories; }
  function getTodayActiveMinutes() { return getToday().activeMinutes; }

  /* Overwrite today's counters with fresh Health Connect aggregates.
     HC totals are authoritative for the day, so this is a set, not an add. */
  function setTodayFromHealth(data) {
    var t = getToday();
    t.steps         = Math.max(0, Math.round(data.steps || 0));
    t.distance      = +(+(data.distance_km || 0)).toFixed(2);
    t.calories      = Math.max(0, Math.round(data.calories || 0));
    t.activeMinutes = Math.max(0, Math.round(data.active_minutes || 0));
    var completed   = checkGoalCompletion(t.steps);
    if (completed && !t.goalCompleted) {
      t.goalCompleted = true;
      win.ZitlasStreak.updateStreak(t.date);
    }
    _save(TODAY_KEY, t);
    _syncDayToFirestore(t); /* live document for today — updated in place */
    return t;
  }

  function checkGoalCompletion(steps) {
    if (steps === undefined) steps = getTodaySteps();
    return steps >= getDailyGoal();
  }

  /* ── Midnight rollover — never lose historical data ──
     If the stored "today" belongs to an earlier date, archive it into
     history + Firestore, settle the streak for that day, and start fresh.
     Handles multi-day gaps (app closed for a week) in one pass. */
  function archiveYesterdayActivity() {
    var t = _load(TODAY_KEY, null);
    var today = todayStr();
    if (!t || !t.date || t.date === today) return false;

    console.log('[ACTIVITY] rolling over — archiving', t.date);
    var history = _load(HISTORY_KEY, {});
    history[t.date] = t;
    _trimHistory(history);
    _save(HISTORY_KEY, history);

    if (t.goalCompleted) win.ZitlasStreak.updateStreak(t.date);
    else                 win.ZitlasStreak.recordMissedDay(t.date);

    _syncDayToFirestore(t);
    _save(TODAY_KEY, _blankDay(today));
    return true;
  }

  function _trimHistory(history) {
    var dates = Object.keys(history).sort();
    while (dates.length > HISTORY_MAX_DAYS) {
      delete history[dates.shift()];
    }
  }

  /* ── Dashboard messages (spec) ── */
  function getStatusMessage() {
    var t = getToday(), goal = getDailyGoal();
    if (t.steps >= goal) {
      var over = t.steps - goal;
      return over > 0
        ? "🏆 Amazing! You've exceeded today's goal by " + over.toLocaleString() + ' steps.'
        : "🎉 Today's target completed!";
    }
    return '🚀 ' + (goal - t.steps).toLocaleString() + ' steps left today';
  }

  /* ── Weekly summary: Mon..Sun of the CURRENT week ──
     [{ day:'Mon', date, status:'done'|'missed'|'today'|'future' }, ...]
     Also the data the AI coach reads later ("5 of 7 days completed"). */
  function getWeeklySummary() {
    var history = _load(HISTORY_KEY, {});
    var t       = getToday();
    var today   = todayStr();
    var now     = new Date(today + 'T12:00:00');
    var monday  = new Date(now);
    monday.setDate(now.getDate() - ((now.getDay() + 6) % 7)); /* back to Monday */
    var names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    var out = [];
    for (var i = 0; i < 7; i++) {
      var d = new Date(monday);
      d.setDate(monday.getDate() + i);
      var ds  = win.ZitlasStreak._localDateStr(d);
      var rec = ds === today ? t : history[ds];
      var status;
      if (ds > today)                       status = 'future';
      else if (ds === today)                status = t.goalCompleted ? 'done' : 'today';
      else if (rec && rec.goalCompleted)    status = 'done';
      else                                  status = 'missed';
      out.push({ day: names[i], date: ds, status: status });
    }
    return out;
  }

  /* ── Firestore sync (offline-tolerant) ── */

  function _fsReady() {
    return typeof ZitlasDB !== 'undefined' && typeof ZitlasAuth !== 'undefined' && !!ZitlasAuth.currentUser;
  }

  function _mergeUserDoc(fields) {
    if (!_fsReady()) return;
    ZitlasDB.collection('users').doc(ZitlasAuth.currentUser.uid)
      .set(fields, { merge: true })
      .catch(function (e) { console.warn('[ACTIVITY] user doc merge failed:', e && e.code); });
  }

  function _syncDayToFirestore(record) {
    if (!_fsReady()) { _queuePending(record.date); return; }
    ZitlasDB.collection('users').doc(ZitlasAuth.currentUser.uid)
      .collection('activity').doc(record.date)
      .set({
        date:          record.date,
        steps:         record.steps,
        distance:      record.distance,
        calories:      record.calories,
        activeMinutes: record.activeMinutes,
        goalCompleted: record.goalCompleted,
      }, { merge: true })
      .then(function () {
        _unqueuePending(record.date);
        _mergeUserDoc({ lastSyncDate: todayStr() });
      })
      .catch(function (e) {
        console.warn('[ACTIVITY] Firestore day sync failed — queued for retry:', e && e.code);
        _queuePending(record.date);
      });
  }

  function _queuePending(date) {
    var q = _load(PENDING_KEY, []);
    if (q.indexOf(date) === -1) { q.push(date); _save(PENDING_KEY, q); }
  }

  function _unqueuePending(date) {
    var q = _load(PENDING_KEY, []);
    var i = q.indexOf(date);
    if (i !== -1) { q.splice(i, 1); _save(PENDING_KEY, q); }
  }

  /* Retry every queued day (called on each sync while online) */
  function flushPendingSync() {
    if (!_fsReady()) return;
    var q = _load(PENDING_KEY, []);
    if (!q.length) return;
    console.log('[ACTIVITY] flushing', q.length, 'pending day(s) to Firestore');
    var history = _load(HISTORY_KEY, {});
    var t = getToday();
    q.slice().forEach(function (date) {
      var rec = date === t.date ? t : history[date];
      if (rec) _syncDayToFirestore(rec);
      else _unqueuePending(date); /* no local record — nothing to send */
    });
  }

  win.ZitlasActivity = {
    todayStr:                 todayStr,
    getToday:                 getToday,
    getTodaySteps:            getTodaySteps,
    getTodayDistance:         getTodayDistance,
    getTodayCalories:         getTodayCalories,
    getTodayActiveMinutes:    getTodayActiveMinutes,
    setTodayFromHealth:       setTodayFromHealth,
    getDailyGoal:             getDailyGoal,
    setDailyGoal:             setDailyGoal,
    checkGoalCompletion:      checkGoalCompletion,
    archiveYesterdayActivity: archiveYesterdayActivity,
    getStatusMessage:         getStatusMessage,
    getWeeklySummary:         getWeeklySummary,
    flushPendingSync:         flushPendingSync,
  };

  /* Bare global aliases (spec-required names) */
  win.getTodaySteps            = getTodaySteps;
  win.getTodayDistance         = getTodayDistance;
  win.getTodayCalories         = getTodayCalories;
  win.getTodayActiveMinutes    = getTodayActiveMinutes;
  win.checkGoalCompletion      = checkGoalCompletion;
  win.archiveYesterdayActivity = archiveYesterdayActivity;
})(window);
