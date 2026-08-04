/*!
 * ZITLAS — Geo-Aware Food Intelligence: location permission (assets/js/geo-location.js)
 *
 * Self-mounting, same family as health-status.js / expert-review-promo.js,
 * but renders a full-screen modal (appended directly to <body>) instead of
 * an inline dashboard card, since this is a one-time permission ask rather
 * than a persistent card.
 *
 * Location is 100% optional. If the user denies, dismisses, or the browser
 * has no geolocation support, nothing here writes anything and every other
 * ZITLAS feature (diet engine, workout engine, assessment) continues to
 * work exactly as it does today — see services/location_food_engine.py's
 * build_region_boost(), which returns None for an absent/unmatched location
 * and is treated as a pure no-op by every caller.
 *
 * Reverse geocoding uses OpenStreetMap's Nominatim (free, no API key). If
 * that call fails (offline, rate-limited, blocked), we still save the raw
 * lat/lng — resolve_region() in location_food_engine.py only needs city/
 * state to do anything useful, so a geocode failure just means the location
 * layer stays a no-op until the next successful save, never a hard failure.
 */
(function (win) {
  'use strict';

  var LOCATION_KEY   = 'zitlas_location';
  var DISMISS_KEY     = 'zitlas_geo_prompt_dismissed_at';
  var SNOOZE_DAYS      = 14;
  var NOMINATIM_URL    = 'https://nominatim.openstreetmap.org/reverse';

  function $(id) { return document.getElementById(id); }
  function safeJSON(key) {
    try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch (_) { return null; }
  }

  function hasAiPlan() {
    return !!(safeJSON('zitlas_diet_plan') || safeJSON('zitlas_workout_plan'));
  }

  function hasSavedLocation() {
    var loc = safeJSON(LOCATION_KEY);
    return !!(loc && (loc.city || loc.latitude));
  }

  function isSnoozed() {
    var ts = localStorage.getItem(DISMISS_KEY);
    if (!ts) return false;
    var days = (Date.now() - Number(ts)) / 86400000;
    return days < SNOOZE_DAYS;
  }

  function eligible() {
    return hasAiPlan() && !hasSavedLocation() && !isSnoozed()
      && 'geolocation' in navigator;
  }

  function snooze() {
    localStorage.setItem(DISMISS_KEY, String(Date.now()));
  }

  function saveLocation(loc) {
    localStorage.setItem(LOCATION_KEY, JSON.stringify(loc));
    if (typeof ZitlasCloudSync !== 'undefined' && ZitlasCloudSync.save) {
      try { ZitlasCloudSync.save('location', loc); } catch (_) {}
    }
  }

  /* Free, no-key reverse geocode. Best-effort — a failure here still leaves
     usable lat/lng saved by the caller. */
  function reverseGeocode(lat, lon) {
    var url = NOMINATIM_URL + '?format=jsonv2&lat=' + lat + '&lon=' + lon + '&zoom=10&addressdetails=1';
    return fetch(url, { headers: { 'Accept': 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        var addr = (data && data.address) || {};
        return {
          city:     addr.city || addr.town || addr.village || addr.county || '',
          district: addr.county || addr.state_district || '',
          state:    addr.state || '',
          country:  addr.country || '',
          pincode:  addr.postcode || '',
        };
      })
      .catch(function () { return {}; });
  }

  function setStatus(text) {
    var el = $('geoLocStatus');
    if (el) el.textContent = text;
  }

  function requestLocation() {
    var allowBtn = $('geoLocAllowBtn');
    if (allowBtn) { allowBtn.disabled = true; allowBtn.textContent = 'Locating…'; }
    setStatus('Getting your location…');

    navigator.geolocation.getCurrentPosition(
      function (pos) {
        var lat = pos.coords.latitude, lon = pos.coords.longitude;
        var tz = '';
        try { tz = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (_) {}

        reverseGeocode(lat, lon).then(function (addr) {
          var loc = Object.assign({
            latitude: lat, longitude: lon, timezone: tz,
            city: '', district: '', state: '', country: '', pincode: '',
            savedAt: new Date().toISOString(),
          }, addr);
          saveLocation(loc);
          setStatus(loc.city ? ('📍 ' + loc.city + (loc.state ? ', ' + loc.state : '')) : 'Location saved.');
          setTimeout(closeModal, 900);
        });
      },
      function () {
        // Denied or unavailable — snooze so we don't nag every dashboard load,
        // but nothing else changes: the diet engine keeps working as-is.
        snooze();
        setStatus("Couldn't get your location — you can enable it later from Settings.");
        if (allowBtn) { allowBtn.disabled = false; allowBtn.textContent = 'Allow Location'; }
        setTimeout(closeModal, 1600);
      },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 600000 }
    );
  }

  function closeModal() {
    var overlay = $('geoLocOverlay');
    if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
  }

  function render() {
    if (!eligible() || $('geoLocOverlay')) return;

    var overlay = document.createElement('div');
    overlay.id = 'geoLocOverlay';
    overlay.className = 'geoloc-overlay';
    overlay.innerHTML =
      '<div class="geoloc-card" role="dialog" aria-modal="true" aria-label="Personalize with location">' +
        '<span class="geoloc-icon">📍</span>' +
        '<h3 class="geoloc-title">Personalize Your Diet with Your Location</h3>' +
        '<p class="geoloc-sub">' +
          "We'll suggest meals using foods that are common, affordable, and easy to find near you — " +
          'like Poha in Pune or Idli in Chennai. Fully optional.' +
        '</p>' +
        '<p class="geoloc-status" id="geoLocStatus"></p>' +
        '<div class="geoloc-btns">' +
          '<button class="geoloc-btn geoloc-btn--allow" id="geoLocAllowBtn">Allow Location</button>' +
          '<button class="geoloc-btn geoloc-btn--later" id="geoLocLaterBtn">Maybe Later</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(overlay);

    var allowBtn = $('geoLocAllowBtn');
    if (allowBtn) allowBtn.addEventListener('click', requestLocation);
    var laterBtn = $('geoLocLaterBtn');
    if (laterBtn) laterBtn.addEventListener('click', function () { snooze(); closeModal(); });
  }

  function init() {
    // Give the dashboard's own render pass (plan checks etc.) a moment so
    // this doesn't race the "hasAiPlan()" check against localStorage writes
    // still happening on first load right after assessment.
    setTimeout(render, 600);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  win.ZitlasGeoLocation = { show: render, getSaved: function () { return safeJSON(LOCATION_KEY); } };
})(window);
