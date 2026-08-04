/*!
 * ZITLAS — Web push notifications (assets/js/push-notifications.js)
 *
 * The missing layer between the in-app Notification Center (which only
 * shows a badge while the app is OPEN) and real device notifications.
 * Pipeline this module owns, end to end:
 *
 *   dashboard visit (logged in, browser supports push)
 *     -> friendly pre-prompt dialog (once — never re-asks after granted)
 *     -> Notification.requestPermission()
 *     -> register /firebase-messaging-sw.js (root scope)
 *     -> firebase.messaging().getToken()
 *     -> users/{uid}.pushTokens  arrayUnion (multi-device safe, no overwrite)
 *     -> foreground messages: onMessage -> system notification via the SW
 *     -> background messages: handled inside firebase-messaging-sw.js
 *
 * Denied -> one-time instructions for enabling from browser settings.
 * Skipped entirely in the Capacitor app (web push doesn't apply inside the
 * native webview — native uses its own channel) and on browsers without
 * serviceWorker/PushManager support.
 *
 * State: zitlas_push_state { status:'granted'|'denied_seen'|'snoozed', ts }
 * Sending: any server with FCM credentials can now deliver to
 * users/{uid}.pushTokens — see backend/routes/system.py test-push endpoint.
 */
(function (win) {
  'use strict';

  var STATE_KEY   = 'zitlas_push_state';
  var TOKEN_KEY   = 'zitlas_push_token';
  var SNOOZE_DAYS = 7;

  function $(id) { return document.getElementById(id); }
  function _state() {
    try { return JSON.parse(localStorage.getItem(STATE_KEY) || 'null'); } catch (_) { return null; }
  }
  function _setState(s) {
    try { localStorage.setItem(STATE_KEY, JSON.stringify(s)); } catch (_) {}
  }
  function myUid() {
    if (typeof ZitlasAuth !== 'undefined' && ZitlasAuth.currentUser) return ZitlasAuth.currentUser.uid;
    try {
      var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || 'null');
      if (fb && fb.uid) return fb.uid;
    } catch (_) {}
    return null;
  }

  function supported() {
    return !win.Capacitor &&
      typeof Notification !== 'undefined' &&
      'serviceWorker' in navigator &&
      'PushManager' in win &&
      typeof firebase !== 'undefined' &&
      typeof firebase.messaging === 'function';
  }

  /* ── Core pipeline (permission already granted) ────────────────────── */

  /* register() resolves when the registration EXISTS, not when the worker
     is ACTIVE — and PushManager.subscribe (inside getToken) aborts with
     "no active Service Worker" on a first-ever install if we don't wait. */
  function _waitForActive(reg) {
    if (reg.active) return Promise.resolve(reg);
    return new Promise(function (resolve) {
      var sw = reg.installing || reg.waiting;
      if (!sw) return resolve(reg);
      var to = setTimeout(function () { resolve(reg); }, 10000); /* never hang */
      sw.addEventListener('statechange', function () {
        if (sw.state === 'activated') { clearTimeout(to); resolve(reg); }
      });
    });
  }

  function registerAndStoreToken() {
    return navigator.serviceWorker.register('/firebase-messaging-sw.js')
      .then(_waitForActive)
      .then(function (reg) {
        console.log('[PUSH] service worker registered + active, scope:', reg.scope);
        var opts = { serviceWorkerRegistration: reg };
        /* Optional project VAPID key (Firebase console -> Cloud Messaging ->
           Web Push certificates). Without it the SDK uses FCM's default
           key pair, which works but a project key is recommended. */
        if (win.ZITLAS_VAPID_KEY) opts.vapidKey = win.ZITLAS_VAPID_KEY;
        return firebase.messaging().getToken(opts);
      })
      .then(function (token) {
        if (!token) throw new Error('FCM returned no token');
        console.log('[PUSH] FCM token:', token.slice(0, 24) + '…');
        try { localStorage.setItem(TOKEN_KEY, token); } catch (_) {}
        var uid = myUid();
        if (uid && typeof ZitlasDB !== 'undefined') {
          /* arrayUnion: each device APPENDS its own token — logging in on a
             second device never overwrites the first one's. */
          return ZitlasDB.collection('users').doc(uid).set({
            pushTokens: firebase.firestore.FieldValue.arrayUnion(token),
            pushTokensUpdatedAt: new Date().toISOString(),
          }, { merge: true }).then(function () {
            console.log('[PUSH] token stored in users/' + uid + '.pushTokens');
            return token;
          });
        }
        return token;
      });
  }

  /* Foreground messages: FCM only calls this while a ZITLAS tab has focus
     (background/closed is the SW's onBackgroundMessage). Show a system
     notification through the SW so look & tap behavior match. */
  function attachForegroundHandler() {
    try {
      firebase.messaging().onMessage(function (payload) {
        console.log('[PUSH] foreground message', payload);
        var n = payload.notification || {};
        var data = payload.data || {};
        navigator.serviceWorker.getRegistration('/firebase-messaging-sw.js').then(function (reg) {
          if (!reg) return;
          reg.showNotification(n.title || data.title || 'ZITLAS', {
            body: n.body || data.message || '',
            icon: '/assets/zino.png',
            tag: 'zitlas-foreground',
            data: { url: data.url || '/pages/notifications/notifications.html' },
          });
        });
      });
    } catch (e) { console.warn('[PUSH] onMessage attach failed', e); }
  }

  /* ── Permission UX ─────────────────────────────────────────────────── */

  function closeDialog() {
    var el = $('pushOverlay');
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }

  function showDeniedHelp() {
    var s = _state();
    if (s && s.status === 'denied_seen') return; /* one-time only */
    _setState({ status: 'denied_seen', ts: Date.now() });
    var overlay = document.createElement('div');
    overlay.id = 'pushOverlay';
    overlay.className = 'push-overlay';
    overlay.innerHTML =
      '<div class="push-card" role="dialog" aria-modal="true">' +
        '<span class="push-icon">🔕</span>' +
        '<h3 class="push-title">Notifications are blocked</h3>' +
        '<p class="push-sub">To get reminders and expert updates, enable notifications for zitlas.com in your browser:</p>' +
        '<ol class="push-steps">' +
          '<li>Tap the <b>lock / tune icon</b> next to the address bar</li>' +
          '<li>Open <b>Permissions</b> (or <b>Site settings</b>)</li>' +
          '<li>Set <b>Notifications</b> to <b>Allow</b>, then reload</li>' +
        '</ol>' +
        '<div class="push-btns"><button class="push-btn push-btn--later" id="pushCloseBtn">Got it</button></div>' +
      '</div>';
    document.body.appendChild(overlay);
    $('pushCloseBtn').addEventListener('click', closeDialog);
  }

  function requestPermissionFlow() {
    var btn = $('pushEnableBtn');
    if (btn) { btn.disabled = true; btn.textContent = 'Waiting for browser…'; }
    Notification.requestPermission().then(function (perm) {
      console.log('[PUSH] permission result:', perm);
      if (perm === 'granted') {
        _setState({ status: 'granted', ts: Date.now() });
        var status = $('pushStatus');
        if (status) status.textContent = '✅ Notifications enabled!';
        registerAndStoreToken()
          .then(function () { attachForegroundHandler(); })
          .catch(function (e) { console.warn('[PUSH] token setup failed', e); });
        setTimeout(closeDialog, 1100);
      } else if (perm === 'denied') {
        closeDialog();
        showDeniedHelp();
      } else { /* dismissed the browser prompt */
        _setState({ status: 'snoozed', ts: Date.now() });
        closeDialog();
      }
    });
  }

  function showPrePrompt() {
    if ($('pushOverlay')) return;
    var overlay = document.createElement('div');
    overlay.id = 'pushOverlay';
    overlay.className = 'push-overlay';
    overlay.innerHTML =
      '<div class="push-card" role="dialog" aria-modal="true" aria-label="Enable notifications">' +
        '<span class="push-icon">🔔</span>' +
        '<h3 class="push-title">Stay in the loop</h3>' +
        '<p class="push-sub">Get notified the moment your expert reviews your plan, your coach replies, or it’s time to move — even when ZITLAS isn’t open.</p>' +
        '<ul class="push-list">' +
          '<li><span class="push-tick">✔</span> Expert review &amp; coach updates</li>' +
          '<li><span class="push-tick">✔</span> Diet &amp; workout reminders</li>' +
          '<li><span class="push-tick">✔</span> Wallet &amp; request activity</li>' +
        '</ul>' +
        '<p class="push-status" id="pushStatus"></p>' +
        '<div class="push-btns">' +
          '<button class="push-btn push-btn--enable" id="pushEnableBtn">Enable Notifications</button>' +
          '<button class="push-btn push-btn--later" id="pushLaterBtn">Not Now</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(overlay);
    $('pushEnableBtn').addEventListener('click', requestPermissionFlow);
    $('pushLaterBtn').addEventListener('click', function () {
      _setState({ status: 'snoozed', ts: Date.now() });
      closeDialog();
    });
  }

  /* ── Eligibility + boot ────────────────────────────────────────────── */

  function maybeInit() {
    if (!supported()) { console.log('[PUSH] web push not supported in this context — skipping'); return; }
    if (!myUid()) return; /* only after login */

    firebase.messaging.isSupported && !firebase.messaging.isSupported()
      ? console.log('[PUSH] messaging.isSupported() = false — skipping')
      : route();

    function route() {
      var perm = Notification.permission;
      if (perm === 'granted') {
        /* Already granted (now or previously): NEVER show the dialog again.
           Refresh the token silently — getToken rotates/revalidates and
           arrayUnion is idempotent, so this also handles token refresh. */
        _setState({ status: 'granted', ts: Date.now() });
        registerAndStoreToken()
          .then(function () { attachForegroundHandler(); })
          .catch(function (e) { console.warn('[PUSH] silent token refresh failed', e); });
        return;
      }
      if (perm === 'denied') { showDeniedHelp(); return; }

      /* perm === 'default' — show the pre-prompt unless snoozed */
      var s = _state();
      if (s && s.status === 'snoozed' && (Date.now() - (s.ts || 0)) / 86400000 < SNOOZE_DAYS) return;

      /* Don't stack on the geo-location prompt — wait our turn (same
         coordination pattern as step-permissions.js). */
      var tries = 0;
      var t = setInterval(function () {
        tries++;
        if (!document.getElementById('geoLocOverlay') || tries > 30) {
          clearInterval(t);
          showPrePrompt();
        }
      }, 1000);
    }
  }

  function init() {
    /* Small delay so the dashboard paints and the geo prompt (600ms) can
       claim its slot first. */
    setTimeout(maybeInit, 2200);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  win.ZitlasPush = {
    show: showPrePrompt,
    getSavedToken: function () { return localStorage.getItem(TOKEN_KEY); },
    refreshToken: registerAndStoreToken,
  };
})(window);
