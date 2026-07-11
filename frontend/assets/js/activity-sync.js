/*!
 * ZITLAS — Activity sync orchestrator (frontend/assets/js/activity-sync.js)
 *
 * Ties the pipeline together:
 *   app opens / becomes visible / midnight passes
 *     -> archiveYesterdayActivity()          (never lose history)
 *     -> read Health Connect (native only)   (fresh aggregates)
 *     -> ZitlasActivity.setTodayFromHealth() (persist + goal + streak)
 *     -> flushPendingSync()                  (offline retry queue)
 *     -> "zitlas-activity-updated" event     (dashboard re-renders)
 *
 * In a plain browser Health Connect resolves { available:false } and the
 * pipeline still runs — the dashboard shows the last persisted values, the
 * midnight rollover still archives, streaks still settle.
 *
 * Depends on: health-connect.js, streak-service.js, activity-service.js.
 */
(function (win) {
  'use strict';

  var _midnightTimer = null;
  var _livePollTimer = null;
  var _hcIsSource    = false;   /* set by the last sync pass */
  var LIVE_POLL_MS   = 60000;   /* HC re-read cadence while visible — one
                                   aggregate query/min, negligible battery */

  function _emitUpdated(model) {
    try {
      win.dispatchEvent(new CustomEvent('zitlas-activity-updated', { detail: model }));
    } catch (_) {}
  }

  /* ── Step-pipeline diagnostics ──
     Probes every stage of the pipeline and returns one structured report.
     Run from the console anywhere: ZitlasStepDiagnostics().then(console.table)
     A summary block is also logged on every sync pass ([STEP DIAG]). */
  function runStepDiagnostics() {
    var cap = win.Capacitor && win.Capacitor.Plugins;
    var d = {
      timestamp:            new Date().toISOString(),
      runtime:              cap ? 'native (Capacitor app)' : 'browser website',
      capacitorPresent:     !!cap,
      hcPluginPresent:      !!(cap && cap.HealthConnect),
      sensorPluginPresent:  !!(cap && cap.StepSensor),
      hcAvailable:          null, hcStatus: null, hcGranted: null, hcSteps: null,
      sensorAvailable:      null, sensorPermission: null, sensorCumulative: null,
      permOnboardingState:  (function () {
        try { return JSON.parse(localStorage.getItem('zitlas_step_perm_state') || 'null'); } catch (_) { return null; }
      })(),
      persistedToday:       win.ZitlasActivity ? win.ZitlasActivity.getToday() : null,
      activeSource:         'none',
      verdict:              '',
    };

    var probes = [];
    if (d.hcPluginPresent) {
      probes.push(cap.HealthConnect.isAvailable().then(function (st) {
        d.hcAvailable = !!st.available; d.hcStatus = st.status;
        if (!st.available) return;
        return cap.HealthConnect.getTodayActivity().then(function (a) {
          if (a && a.available === false)        { d.hcAvailable = false; return; }
          if (a && a.permissionGranted === false) { d.hcGranted = false; return; }
          d.hcGranted = true;
          d.hcSteps = a ? a.today_steps : null;
        });
      }).catch(function (e) { d.hcStatus = 'probe error: ' + e; }));
    }
    if (d.sensorPluginPresent) {
      probes.push(cap.StepSensor.isAvailable().then(function (st) {
        d.sensorAvailable = !!st.available;
        d.sensorPermission = !!st.permissionGranted;
        if (!st.available || !st.permissionGranted) return;
        return cap.StepSensor.readCumulative().then(function (r) {
          d.sensorCumulative = r ? r.cumulative : null; /* raw OS steps-since-boot */
        });
      }).catch(function (e) { d.sensorAvailable = 'probe error: ' + e; }));
    }

    return Promise.all(probes).then(function () {
      if (d.hcGranted && d.hcSteps != null)                  d.activeSource = 'health_connect';
      else if (d.sensorAvailable === true && d.sensorPermission) d.activeSource = 'step_sensor';

      if (!d.capacitorPresent) {
        d.verdict = 'Running as a WEBSITE in a browser. Browsers have no step-counter ' +
          'API and cannot read Health Connect — real step data is only possible in the ' +
          'ZITLAS Android app (Capacitor APK). This is a platform limitation, not a bug.';
      } else if (d.activeSource === 'health_connect') {
        d.verdict = 'Health Connect is the active source (' + d.hcSteps + ' steps today from the OS).';
      } else if (d.activeSource === 'step_sensor') {
        d.verdict = 'Hardware step sensor is the active source (raw counter since boot: ' +
          d.sensorCumulative + '). Walk a few steps and re-run — the raw value must increase.';
      } else if (d.hcPluginPresent && d.hcAvailable && d.hcGranted === false) {
        d.verdict = 'Health Connect installed but PERMISSION DENIED — re-run the permission flow.';
      } else if (!d.sensorPluginPresent) {
        d.verdict = 'Native app detected but StepSensor plugin missing — this APK predates the ' +
          'step-sensor build. Rebuild the APK (npx cap sync android + Gradle build).';
      } else if (d.sensorAvailable === false) {
        d.verdict = 'Device reports NO hardware step counter and Health Connect is unavailable — ' +
          'this device cannot count steps.';
      } else if (d.sensorPermission === false) {
        d.verdict = 'Step sensor present but ACTIVITY_RECOGNITION permission not granted — ' +
          're-run the permission flow.';
      } else {
        d.verdict = 'No usable step source found.';
      }
      console.log('[STEP DIAG]', JSON.stringify(d, null, 2));
      win.__zitlasStepDiag = d;
      return d;
    });
  }

  /* Full sync pass. Resolves the up-to-date today model.
     Source selection: Health Connect is the source of truth whenever it
     answers; the hardware step sensor (step-sensor.js) only takes over
     when HC is absent/denied — never both, so a step can't count twice. */
  function syncTodayActivity() {
    var A = win.ZitlasActivity;
    if (!A) return Promise.resolve(null);

    var rolled = A.archiveYesterdayActivity();
    if (rolled) console.log('[SYNC] day rolled over at sync time');

    return win.ZitlasHealthConnect_read()
      .then(function (hc) {
        var model;
        if (hc && hc.available && hc.granted && !hc.error) {
          console.log('[SYNC] Health Connect data:', hc.steps, 'steps');
          _hcIsSource = true;
          if (win.ZitlasStepSensor) win.ZitlasStepSensor.setEnabled(false);
          model = A.setTodayFromHealth(hc);
          A.flushPendingSync();
          _emitUpdated(model);
          return model;
        }
        /* Browser / no permission / HC error — persisted model stands,
           then the hardware sensor path (native only) catches us up and
           starts live foreground counting. */
        console.log('[SYNC] Health Connect unavailable — sensor fallback/persisted data');
        _hcIsSource = false;
        model = A.getToday();
        A.flushPendingSync();
        _emitUpdated(model);
        if (win.ZitlasStepSensor) {
          win.ZitlasStepSensor.setEnabled(true);
          win.ZitlasStepSensor.syncFromSensor().then(function (used) {
            if (used && document.visibilityState === 'visible') {
              win.ZitlasStepSensor.startLiveWatch();
            }
          });
        }
        return model;
      });
  }

  /* ── Live updates while the app is on screen ──
     HC source: re-read the day aggregate every minute (steps taken with
     the phone in a pocket appear without any reload). Sensor source: the
     hardware event listener in step-sensor.js already pushes every step. */
  function _startLivePoll() {
    _stopLivePoll();
    if (!_hcIsSource || !win.Capacitor) return;
    _livePollTimer = setInterval(function () {
      if (document.visibilityState !== 'visible') return;
      syncTodayActivity();
    }, LIVE_POLL_MS);
  }
  function _stopLivePoll() {
    if (_livePollTimer) { clearInterval(_livePollTimer); _livePollTimer = null; }
  }

  /* Indirection so this file never throws if health-connect.js is missing */
  win.ZitlasHealthConnect_read = function () {
    if (win.ZitlasHealthConnect && win.ZitlasHealthConnect.readTodayActivity) {
      return win.ZitlasHealthConnect.readTodayActivity();
    }
    /* Legacy bridge (window.HealthConnect) fallback */
    if (win.HealthConnect && win.HealthConnect.getTodayActivity) {
      return win.HealthConnect.getTodayActivity().then(function (a) {
        if (!a || a.available === false)         return { available: false };
        if (a.permissionGranted === false)       return { available: true, granted: false };
        return {
          available: true, granted: true,
          steps:          a.today_steps     || 0,
          distance_km:    +(a.distance_km   || 0),
          calories:       a.calories_burned || 0,
          active_minutes: a.active_minutes  || 0,
        };
      }).catch(function (e) {
        console.error('[SYNC] Health Connect read failed', e);
        return { available: true, granted: true, error: String(e) };
      });
    }
    return Promise.resolve({ available: false });
  };

  /* Fires a rollover + fresh sync a moment after local midnight, then
     re-arms for the next day. Only matters while the app stays open
     across midnight — the app-open sync covers every other case. */
  function _scheduleMidnightRollover() {
    if (_midnightTimer) clearTimeout(_midnightTimer);
    var now  = new Date();
    var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
    var ms   = next.getTime() - now.getTime();
    console.log('[SYNC] midnight rollover scheduled in', Math.round(ms / 60000), 'min');
    _midnightTimer = setTimeout(function () {
      console.log('[SYNC] midnight — rolling the day over');
      syncTodayActivity().then(_scheduleMidnightRollover);
    }, ms);
  }

  /* ── Optional evening reminder (permission asked in onboarding) ──
     Fires once per day at/after 6 PM if the user is under 40% of their
     effective goal. Web Notification API only — shows while the webview
     is alive; a fully-backgrounded scheduled notification would need the
     LocalNotifications native plugin (future enhancement). */
  function _maybeStepReminder() {
    try {
      if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
      var A = win.ZitlasActivity;
      if (!A) return;
      var today = A.todayStr();
      if (localStorage.getItem('zitlas_step_reminder_sent') === today) return;
      if (new Date().getHours() < 18) return;
      var eff = A.getEffectiveGoal();
      if (eff.rest || eff.goal <= 0) return;
      var steps = A.getTodaySteps();
      if (steps >= eff.goal * 0.4) return;
      localStorage.setItem('zitlas_step_reminder_sent', today);
      new Notification('ZITLAS — evening walk? 🚶', {
        body: "You've walked " + steps.toLocaleString() + ' of ' + eff.goal.toLocaleString() +
              ' steps today. A short 10-minute walk gets you moving!',
        tag: 'zitlas-step-reminder',
      });
    } catch (_) {}
  }

  function init() {
    if (init._done) return;
    init._done = true;

    syncTodayActivity().then(_startLivePoll);
    _scheduleMidnightRollover();

    /* One diagnostic report per session — answers "why 0 steps?" in the
       console without anyone having to reproduce with a debugger attached. */
    setTimeout(function () { runStepDiagnostics(); }, 4000);

    /* Re-sync when the app returns to the foreground (Capacitor webview
       fires visibilitychange on resume) — also catches a midnight that
       passed while the device slept, since the timer above doesn't run
       during sleep. Hidden -> stop the live poll and the sensor listener
       (zero work while backgrounded; the hardware counter keeps counting
       on its own and we catch up on the next resume). */
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') {
        syncTodayActivity().then(function () {
          _startLivePoll();
          if (!_hcIsSource && win.ZitlasStepSensor) win.ZitlasStepSensor.startLiveWatch();
        });
        _scheduleMidnightRollover();
        _maybeStepReminder();
      } else {
        _stopLivePoll();
        if (win.ZitlasStepSensor) win.ZitlasStepSensor.stopLiveWatch();
      }
    });

    /* Reminder check every 30 min while the app stays open in the evening */
    setInterval(_maybeStepReminder, 30 * 60000);
    _maybeStepReminder();
  }

  win.ZitlasActivitySync = {
    syncTodayActivity: syncTodayActivity,
    init:              init,
  };
  /* Bare global aliases (spec-required names) */
  win.syncTodayActivity     = syncTodayActivity;
  win.ZitlasStepDiagnostics = runStepDiagnostics;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})(window);
