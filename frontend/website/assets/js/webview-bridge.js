/* ══════════════════════════════════════════════════════════════════════
   ZITLAS — Flutter WebView bridge  (assets/js/webview-bridge.js)
   ══════════════════════════════════════════════════════════════════════

   Loaded ONLY on the pages the Flutter app embeds as the Personal Coaching
   module (cprofile.html, expert-dashboard.html, expert-review.html,
   modify-diet.html, modify-workout.html), immediately AFTER firebase-config.js
   so `firebase`/`ZitlasAuth` already exist.

   AUTH BRIDGE. The native Flutter app is signed in with the native Firebase
   SDK; this page runs the Firebase JS SDK, and the two sessions are NOT shared.
   Without a web session every onSnapshot (chat, meal reviews, coaching status)
   is denied by Firestore rules. So: on first load, once Firebase reports NO
   restored session, we ask Flutter for a custom token; Flutter replies by
   calling window.__zitlasWebviewSignIn(token) → signInWithCustomToken → a real
   web session for the SAME uid. The JS SDK then keeps its own refresh token so
   the session persists across app launches.

   Every stage is logged with a [WEBVIEW] prefix AND (where it matters) reported
   back to Flutter over the `ZitlasWebview` channel as a structured message, so
   the native logs show exactly which stage failed:
       need-token            — no web session, asking Flutter for a token
       auth-start            — signInWithCustomToken invoked
       auth-ok:<uid>         — signInWithCustomToken resolved
       auth-fail:<code>      — signInWithCustomToken rejected (Firebase code)
       auth-state:<uid|null> — onAuthStateChanged transition

   Detection: `?webview=1` in the URL, OR the presence of the `ZitlasWebview`
   channel Flutter injects. A normal browser has neither, so this file is inert
   on the public website.
*/
(function () {
  'use strict';

  var isWebview = /[?&]webview=1(&|$)/.test(window.location.search) ||
                  !!window.ZitlasWebview;
  if (!isWebview) return;

  /* Log locally AND to Flutter (the native side forwards console too, but an
     explicit channel message survives even if console forwarding is off). */
  function report(msg) {
    try { console.log('[WEBVIEW] ' + msg); } catch (e) {}
    try {
      if (window.ZitlasWebview && typeof window.ZitlasWebview.postMessage === 'function') {
        window.ZitlasWebview.postMessage(msg);
      }
    } catch (e) {}
  }

  report('bridge-active path=' + window.location.pathname);

  /* ── 1. Native feel: hide global site chrome ───────────────────────── */
  document.documentElement.classList.add('webview-mode');
  try {
    var style = document.createElement('style');
    style.id = 'zitlas-webview-chrome';
    style.textContent =
      'html.webview-mode #zitlas-navbar,' +   /* shared bottom nav (navbar.js) */
      'html.webview-mode #znFab,' +           /* Zino floating assistant (zino.js) */
      'html.webview-mode #zwBtn,' +           /* wallet launcher (wallet.js) */
      'html.webview-mode #zwPanel' +          /* wallet slide-over panel */
      '{display:none !important;}' +
      'html.webview-mode body{padding-bottom:0 !important;}';
    (document.head || document.documentElement).appendChild(style);
  } catch (e) {
    console.warn('[WEBVIEW] chrome-hide style failed', e);
  }

  /* Decode a JWT payload WITHOUT verifying — for logging non-secret claims only
     (aud / iss / sub / exp), so a custom-token-mismatch is obvious in the logs.
     A signature is never logged. */
  function decodeJwtClaims(jwt) {
    try {
      var parts = String(jwt).split('.');
      if (parts.length < 2) return null;
      var b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      var pad = b64.length % 4; if (pad) b64 += '===='.slice(pad);
      var json = decodeURIComponent(atob(b64).split('').map(function (c) {
        return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
      }).join(''));
      return JSON.parse(json);
    } catch (e) { return null; }
  }

  /* ── 2. Auth bridge ─────────────────────────────────────────────────── */

  /* Called BY FLUTTER (via runJavaScript) with a freshly minted custom token. */
  window.__zitlasWebviewSignIn = function (customToken) {
    if (!customToken) {
      report('auth-fail:empty-token');
      return;
    }
    var claims = decodeJwtClaims(customToken);
    if (claims) {
      report('token-claims aud=' + claims.aud + ' iss=' + (claims.iss || '').slice(0, 40) +
             ' sub=' + (claims.sub || '').slice(0, 40) + ' uid=' + claims.uid + ' exp=' + claims.exp);
    } else {
      report('token-claims UNPARSEABLE (token is not a JWT?)');
    }
    report('auth-start');
    try {
      firebase.auth().signInWithCustomToken(customToken)
        .then(function (cred) {
          report('auth-ok:' + (cred.user && cred.user.uid));
        })
        .catch(function (err) {
          var code = (err && err.code) || 'unknown';
          report('auth-fail:' + code);
          try { console.error('[WEBVIEW] signInWithCustomToken error', err && err.message); } catch (e) {}
        });
    } catch (e) {
      report('auth-fail:threw');
      try { console.error('[WEBVIEW] sign-in threw', e); } catch (_) {}
    }
  };

  var tokenRequested = false;
  function requestTokenFromFlutter() {
    if (tokenRequested) return;
    tokenRequested = true;
    if (window.ZitlasWebview && typeof window.ZitlasWebview.postMessage === 'function') {
      report('need-token');
    } else {
      report('auth-fail:no-channel');
    }
  }

  /* Wait for the SDK to finish restoring any PERSISTED session before deciding
     we need a token — currentUser is null synchronously on a cold load even
     when a valid session is about to be restored. */
  var settled = false;
  function settle(hasUser) {
    if (settled) return;
    settled = true;
    if (!hasUser) requestTokenFromFlutter();
    else report('session-restored');
  }

  try {
    firebase.auth().onAuthStateChanged(function (user) {
      report('auth-state:' + (user ? user.uid : 'null'));
      settle(!!user);
    });
  } catch (e) {
    report('auth-fail:no-firebase');
    try { console.error('[WEBVIEW] onAuthStateChanged unavailable', e); } catch (_) {}
  }

  /* Safety net: if onAuthStateChanged never fires, still ask for a token. */
  window.setTimeout(function () {
    var cur = null;
    try { cur = firebase.auth().currentUser; } catch (e) {}
    settle(!!cur);
  }, 2500);
})();
