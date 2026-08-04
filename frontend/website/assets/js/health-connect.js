/**
 * ZITLAS Health Connect Bridge
 *
 * Wraps the native Capacitor HealthConnect plugin into window.HealthConnect.
 * Falls back gracefully when running in a browser (no Capacitor runtime).
 *
 * Usage:
 *   const data = await window.HealthConnect.getTodayActivity();
 *   // { today_steps, calories_burned, distance_km, active_minutes }
 */
(function () {
  'use strict';

  function getPlugin() {
    return (
      window.Capacitor &&
      window.Capacitor.Plugins &&
      window.Capacitor.Plugins.HealthConnect
    ) || null;
  }

  window.HealthConnect = {

    /**
     * Returns { available: bool, status: int }.
     * status codes: 0 = unavailable, 2 = needs update, 3 = available.
     */
    isAvailable: function () {
      var plugin = getPlugin();
      if (!plugin) return Promise.resolve({ available: false, status: 0 });
      return plugin.isAvailable();
    },

    /**
     * Launches the Health Connect permission sheet.
     * Resolves { permissionGranted: bool } or { available: false }.
     */
    requestPermissions: function () {
      var plugin = getPlugin();
      if (!plugin) return Promise.resolve({ available: false });
      return plugin.requestPermissions();
    },

    /**
     * Resolves { steps: number }.
     * Returns { available: false } if Health Connect is not installed.
     */
    getTodaySteps: function () {
      var plugin = getPlugin();
      if (!plugin) return Promise.resolve({ available: false });
      return plugin.getTodaySteps();
    },

    /**
     * Resolves the full activity object:
     *   { today_steps, calories_burned, distance_km, active_minutes }
     *
     * On failure:
     *   { available: false }          — Health Connect not installed
     *   { permissionGranted: false }  — permissions denied
     *
     * The shape is intentionally identical to window.zitlasSteps so the
     * dashboard can do: Object.assign(window.zitlasSteps, data)
     */
    getTodayActivity: function () {
      var plugin = getPlugin();
      if (!plugin) return Promise.resolve({ available: false });
      return plugin.getTodayActivity();
    },
  };

  /* Spec-named helper: availability check + permission sheet in one call.
     Resolves { available, granted }. Safe in browsers ({available:false}). */
  window.requestHealthPermissions = function () {
    return window.HealthConnect.isAvailable().then(function (st) {
      if (!st.available) return { available: false, granted: false };
      return window.HealthConnect.requestPermissions().then(function (p) {
        return { available: true, granted: !!p.permissionGranted };
      });
    }).catch(function (e) {
      console.error('[HealthConnect] requestHealthPermissions failed', e);
      return { available: false, granted: false };
    });
  };

})();
