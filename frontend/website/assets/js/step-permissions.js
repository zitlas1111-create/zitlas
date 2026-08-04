/*!
 * ZITLAS — Step-tracking permission onboarding (assets/js/step-permissions.js)
 *
 * "Stay Active with ZITLAS 🚶" modal shown ONCE on the dashboard when the
 * app runs natively (Capacitor) and step permissions haven't been granted.
 * Same self-mounting overlay pattern as geo-location.js.
 *
 * Allow Permissions requests, in order:
 *   1. Health Connect permission sheet (preferred source of truth)
 *   2. ACTIVITY_RECOGNITION for the hardware step sensor (fallback source,
 *      also requested when HC is present — it covers HC-outage gaps)
 *   3. Notifications (optional — reminders; denial is fine)
 *
 * State: zitlas_step_perm_state { status: 'granted'|'snoozed', ts, source }.
 * 'granted' is permanent — the modal never shows again (per spec: "Do NOT
 * repeatedly ask once permissions are granted"). 'Not Now' snoozes 3 days.
 * Plain browsers (no Capacitor) never see the modal — there is nothing a
 * browser can grant; the dashboard just shows persisted data.
 */
(function (win) {
  'use strict';

  var STATE_KEY   = 'zitlas_step_perm_state';
  var SNOOZE_DAYS = 3;

  function $(id) { return document.getElementById(id); }
  function _state() {
    try { return JSON.parse(localStorage.getItem(STATE_KEY) || 'null'); } catch (_) { return null; }
  }
  function _setState(s) {
    try { localStorage.setItem(STATE_KEY, JSON.stringify(s)); } catch (_) {}
  }

  function eligible() {
    if (!win.Capacitor || !win.Capacitor.Plugins) return false; /* native only */
    var s = _state();
    if (!s) return true;
    if (s.status === 'granted') return false;
    if (s.status === 'snoozed') {
      return (Date.now() - (s.ts || 0)) / 86400000 >= SNOOZE_DAYS;
    }
    return true;
  }

  function setStatus(text) {
    var el = $('sppStatus');
    if (el) el.textContent = text;
  }

  function closeModal() {
    var overlay = $('sppOverlay');
    if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
  }

  /* The full grant sequence. Resolves 'hc' | 'sensor' | null (nothing granted). */
  function runPermissionFlow() {
    var source = null;

    setStatus('Opening Health Connect…');
    var hcP = (win.requestHealthPermissions ? win.requestHealthPermissions() : Promise.resolve({ available: false }))
      .then(function (hc) {
        if (hc && hc.available && hc.granted) source = 'hc';
      });

    return hcP
      .then(function () {
        setStatus('Requesting motion sensor access…');
        if (!win.ZitlasStepSensor) return null;
        return win.ZitlasStepSensor.requestPermission().then(function (r) {
          if (r && r.granted && !source) source = 'sensor';
        });
      })
      .then(function () {
        /* Notifications are optional — never block on the answer */
        setStatus('Almost done…');
        try {
          if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
            return Promise.race([
              Notification.requestPermission(),
              new Promise(function (res) { setTimeout(res, 4000); }),
            ]).catch(function () {});
          }
        } catch (_) {}
        return null;
      })
      .then(function () { return source; });
  }

  function onAllow() {
    var btn = $('sppAllowBtn');
    if (btn) { btn.disabled = true; btn.textContent = 'Setting up…'; }

    runPermissionFlow().then(function (source) {
      if (source) {
        _setState({ status: 'granted', source: source, ts: Date.now() });
        setStatus(source === 'hc'
          ? '✅ Connected to Health Connect!'
          : '✅ Motion sensor connected!');
        /* Kick a sync immediately so the first numbers appear right away */
        if (win.ZitlasActivitySync) win.ZitlasActivitySync.syncTodayActivity();
        setTimeout(closeModal, 1200);
      } else {
        _setState({ status: 'snoozed', ts: Date.now() });
        setStatus("Couldn't get permission — you can enable it anytime from Settings.");
        if (btn) { btn.disabled = false; btn.textContent = 'Allow Permissions'; }
        setTimeout(closeModal, 2200);
      }
    });
  }

  function render() {
    if (!eligible() || $('sppOverlay')) return;

    var overlay = document.createElement('div');
    overlay.id = 'sppOverlay';
    overlay.className = 'spp-overlay';
    overlay.innerHTML =
      '<div class="spp-card" role="dialog" aria-modal="true" aria-label="Step tracking permissions">' +
        '<span class="spp-icon">🚶</span>' +
        '<h3 class="spp-title">Stay Active with ZITLAS</h3>' +
        '<p class="spp-sub">To accurately measure your daily activity we need a few permissions.</p>' +
        '<ul class="spp-list">' +
          '<li><span class="spp-tick">✔</span> Physical activity &amp; motion sensors</li>' +
          '<li><span class="spp-tick">✔</span> Health Connect (recommended)</li>' +
          '<li><span class="spp-tick">✔</span> Notifications — optional reminders</li>' +
        '</ul>' +
        '<p class="spp-note">Steps keep counting with the screen locked or the app minimised — the phone’s built-in counter does the work, so there’s no extra battery drain.</p>' +
        '<p class="spp-status" id="sppStatus"></p>' +
        '<div class="spp-btns">' +
          '<button class="spp-btn spp-btn--allow" id="sppAllowBtn">Allow Permissions</button>' +
          '<button class="spp-btn spp-btn--later" id="sppLaterBtn">Not Now</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(overlay);

    var allowBtn = $('sppAllowBtn');
    if (allowBtn) allowBtn.addEventListener('click', onAllow);
    var laterBtn = $('sppLaterBtn');
    if (laterBtn) laterBtn.addEventListener('click', function () {
      _setState({ status: 'snoozed', ts: Date.now() });
      closeModal();
    });
  }

  function init() {
    /* Small delay so the dashboard paints first and the geo-location prompt
       (600ms) never stacks on the same frame — this one waits its turn. */
    setTimeout(function () {
      if (document.getElementById('geoLocOverlay')) {
        /* Location prompt is up — try again after it's dealt with */
        var retry = setInterval(function () {
          if (!document.getElementById('geoLocOverlay')) {
            clearInterval(retry);
            render();
          }
        }, 1000);
        setTimeout(function () { clearInterval(retry); }, 30000);
        return;
      }
      render();
    }, 1400);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  win.ZitlasStepPermissions = {
    show: render,
    isGranted: function () { var s = _state(); return !!(s && s.status === 'granted'); },
  };
})(window);
