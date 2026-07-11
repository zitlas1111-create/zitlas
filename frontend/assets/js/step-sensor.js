/*!
 * ZITLAS — Hardware step-sensor fallback (frontend/assets/js/step-sensor.js)
 *
 * Only active when Health Connect is NOT the data source (not installed /
 * permission denied). Health Connect always wins: activity-sync.js calls
 * setEnabled(false) whenever an HC read succeeds, so the two sources can
 * never double-count the same day.
 *
 * How background counting works WITHOUT a service: TYPE_STEP_COUNTER is a
 * hardware counter that accumulates steps-since-boot on the sensor chip,
 * with the app dead, screen locked, or phone in pocket. We persist a
 * baseline and compute "today's steps" as (cumulative - baseline) whenever
 * the app is next opened or resumed — the same approach Google Fit uses.
 * While the app is in the FOREGROUND we additionally subscribe to live
 * sensor events so the dashboard number moves in real time.
 *
 * localStorage: zitlas_step_sensor_state
 *   { date, lastCumulative, lastTs, enabled }
 *
 * Anti-cheat (sensor path only — Health Connect data is already filtered
 * by the OS): a delta is capped by elapsed time — nobody takes more than
 * ~5 steps/second sustained. Readings above the cap are REJECTED (baseline
 * still advances so the jump is never counted later either). Counter
 * resets (reboot) are detected as cumulative < lastCumulative.
 */
(function (win) {
  'use strict';

  var STATE_KEY = 'zitlas_step_sensor_state';
  var MAX_STEPS_PER_SEC = 5;      /* fast run — anything above is not walking */
  var DELIVERY_GRACE    = 30;     /* sensor events arrive batched; allow slack */
  var SYNC_THROTTLE_MS  = 60000;  /* Firestore write at most once a minute */

  var _enabled  = true;   /* activity-sync flips this off when HC works */
  var _watching = false;
  var _lastFsSync = 0;

  function _plugin() {
    return (win.Capacitor && win.Capacitor.Plugins && win.Capacitor.Plugins.StepSensor) || null;
  }

  function _todayStr() {
    return win.ZitlasStreak ? win.ZitlasStreak._localDateStr() : new Date().toISOString().slice(0, 10);
  }

  function _loadState() {
    try { return JSON.parse(localStorage.getItem(STATE_KEY) || 'null'); } catch (_) { return null; }
  }
  function _saveState(s) {
    try { localStorage.setItem(STATE_KEY, JSON.stringify(s)); } catch (_) {}
  }

  /* ── Pure baseline math (exported for unit tests) ──
     Takes the persisted state + a fresh cumulative reading, returns the
     new state and how many steps to ADD to today's total. Handles:
       - first-ever reading      -> baseline only, add 0
       - normal delta            -> add (cumulative - lastCumulative)
       - reboot (counter reset)  -> counter restarted from 0; the new
                                    cumulative IS the post-reboot delta
       - day change              -> steps before the first reading of the
                                    new day belong to yesterday; baseline
                                    moves, add 0 for the boundary reading
       - implausible jump        -> rejected, baseline advances            */
  function computeDelta(state, cumulative, nowMs, todayStr) {
    if (cumulative == null || cumulative < 0) {
      return { state: state || { date: todayStr, lastCumulative: null, lastTs: nowMs }, added: 0, rejected: false };
    }
    if (!state || state.lastCumulative == null) {
      return {
        state: { date: todayStr, lastCumulative: cumulative, lastTs: nowMs },
        added: 0, rejected: false,
      };
    }

    var raw;
    if (cumulative < state.lastCumulative) {
      /* Counter reset (device rebooted): everything on the new counter
         happened after our last reading. */
      raw = cumulative;
    } else {
      raw = cumulative - state.lastCumulative;
    }

    var dayChanged = state.date !== todayStr;
    var newState = { date: todayStr, lastCumulative: cumulative, lastTs: nowMs };

    if (dayChanged) {
      /* Steps in `raw` straddle midnight and mostly belong to yesterday
         (which the rollover already archived) — don't credit them to the
         new day. The baseline advance above is the reset. */
      return { state: newState, added: 0, rejected: false };
    }

    var elapsedSec = Math.max(0, (nowMs - (state.lastTs || nowMs)) / 1000);
    var maxPlausible = Math.round(elapsedSec * MAX_STEPS_PER_SEC) + DELIVERY_GRACE;
    if (raw > maxPlausible) {
      return { state: newState, added: 0, rejected: true };
    }
    return { state: newState, added: raw, rejected: false };
  }

  /* ── Apply a cumulative reading to today's model ── */
  function _applyReading(cumulative) {
    if (!_enabled || !win.ZitlasActivity) return;
    var res = computeDelta(_loadState(), cumulative, Date.now(), _todayStr());
    _saveState(res.state);
    if (res.rejected) {
      console.warn('[STEP SENSOR] implausible jump rejected');
      return;
    }
    if (res.added > 0) {
      var syncFs = (Date.now() - _lastFsSync) > SYNC_THROTTLE_MS;
      if (syncFs) _lastFsSync = Date.now();
      var model = win.ZitlasActivity.addSensorSteps(res.added, syncFs);
      try {
        win.dispatchEvent(new CustomEvent('zitlas-activity-updated', { detail: model }));
      } catch (_) {}
    }
  }

  /* ── Public API ── */

  function setEnabled(on) {
    _enabled = !!on;
    if (!_enabled) stopLiveWatch();
  }

  function isNativeAvailable() {
    var p = _plugin();
    if (!p) return Promise.resolve({ available: false, permissionGranted: false });
    return p.isAvailable().catch(function () { return { available: false, permissionGranted: false }; });
  }

  function requestPermission() {
    var p = _plugin();
    if (!p) return Promise.resolve({ granted: false });
    return p.requestPermission().catch(function () { return { granted: false }; });
  }

  /* One-shot catch-up read — called on every sync pass (app open / resume).
     This is what makes locked-screen / minimized / rebooted steps appear
     the moment the user comes back. */
  function syncFromSensor() {
    var p = _plugin();
    if (!p || !_enabled) return Promise.resolve(false);
    return p.readCumulative().then(function (r) {
      if (!r || !r.available || r.granted === false) return false;
      _applyReading(typeof r.cumulative === 'number' ? r.cumulative : -1);
      return true;
    }).catch(function (e) {
      console.warn('[STEP SENSOR] read failed', e);
      return false;
    });
  }

  /* Foreground live updates — every hardware event moves the dashboard. */
  function startLiveWatch() {
    var p = _plugin();
    if (!p || !_enabled || _watching) return;
    p.addListener('step', function (ev) {
      if (ev && typeof ev.cumulative === 'number') _applyReading(ev.cumulative);
    });
    p.startWatch().then(function (r) {
      _watching = !!(r && r.watching);
      if (_watching) console.log('[STEP SENSOR] live watch active');
    }).catch(function () {});
  }

  function stopLiveWatch() {
    var p = _plugin();
    if (!p || !_watching) return;
    _watching = false;
    p.stopWatch().catch(function () {});
  }

  win.ZitlasStepSensor = {
    computeDelta:      computeDelta,   /* exported for unit tests */
    setEnabled:        setEnabled,
    isNativeAvailable: isNativeAvailable,
    requestPermission: requestPermission,
    syncFromSensor:    syncFromSensor,
    startLiveWatch:    startLiveWatch,
    stopLiveWatch:     stopLiveWatch,
  };
})(window);
