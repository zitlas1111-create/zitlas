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

  function _emitUpdated(model) {
    try {
      win.dispatchEvent(new CustomEvent('zitlas-activity-updated', { detail: model }));
    } catch (_) {}
  }

  /* Full sync pass. Resolves the up-to-date today model. */
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
          model = A.setTodayFromHealth(hc);
        } else {
          /* Browser / no permission / HC error — persisted model stands */
          console.log('[SYNC] Health Connect unavailable — using persisted data');
          model = A.getToday();
        }
        A.flushPendingSync();
        _emitUpdated(model);
        return model;
      });
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

  function init() {
    if (init._done) return;
    init._done = true;

    syncTodayActivity();
    _scheduleMidnightRollover();

    /* Re-sync when the app returns to the foreground (Capacitor webview
       fires visibilitychange on resume) — also catches a midnight that
       passed while the device slept, since the timer above doesn't run
       during sleep. */
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible') {
        syncTodayActivity();
        _scheduleMidnightRollover();
      }
    });
  }

  win.ZitlasActivitySync = {
    syncTodayActivity: syncTodayActivity,
    init:              init,
  };
  /* Bare global alias (spec-required name) */
  win.syncTodayActivity = syncTodayActivity;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})(window);
