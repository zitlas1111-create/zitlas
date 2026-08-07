/* ══════════════════════════════════════════════════════════════════════
   ZITLAS — Flutter WebView bridge  (assets/js/webview-bridge.js)
   ══════════════════════════════════════════════════════════════════════

   Loaded ONLY on the pages the Flutter app embeds as the Personal Coaching
   module (cprofile.html, expert-dashboard.html), immediately AFTER
   firebase-config.js so `firebase`/`ZitlasAuth` already exist.

   Does two things, and only when actually running inside the app's WebView:

   1. AUTH BRIDGE. The native Flutter app is signed in with the native Firebase
      SDK; this page runs the Firebase JS SDK, and the two sessions are NOT
      shared. Without a web session every onSnapshot (chat, meal reviews,
      coaching status) is denied by Firestore rules and the page looks broken.
      So: on first load, once Firebase reports NO restored session, we ask
      Flutter for a custom token (pull-based — timing-safe, we wait for the
      SDK to finish restoring any persisted session first). Flutter replies by
      calling window.__zitlasWebviewSignIn(token), which does
      signInWithCustomToken → a real web session for the SAME uid. After that
      the JS SDK keeps its own refresh token, so the session persists across
      app launches (WebView storage) and this handshake never runs again.

   2. NATIVE FEEL. Hides the site's global chrome (bottom navbar, wallet
      launcher, Zino FAB) so the embedded page is JUST Personal Coaching, with
      no website navigation inside the app. Injected here (one place) rather
      than in each page's CSS so it can never drift out of sync.

   Detection: `?webview=1` in the URL, OR the presence of the `ZitlasWebview`
   JavaScript channel that Flutter injects. A normal browser has neither, so
   this file is inert on the public website.
*/
(function () {
  'use strict';

  var isWebview = /[?&]webview=1(&|$)/.test(window.location.search) ||
                  !!window.ZitlasWebview;
  if (!isWebview) return;

  console.log('[WEBVIEW] bridge active');

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
      /* Reclaim the space the fixed bottom nav used to reserve. */
      'html.webview-mode body{padding-bottom:0 !important;}';
    (document.head || document.documentElement).appendChild(style);
  } catch (e) {
    console.warn('[WEBVIEW] chrome-hide style failed', e);
  }

  /* ── 2. Auth bridge ─────────────────────────────────────────────────── */

  /* Called BY FLUTTER (via runJavaScript) with a freshly minted custom token.
     Idempotent: harmless to call when already signed in as the same uid. */
  window.__zitlasWebviewSignIn = function (customToken) {
    if (!customToken) {
      console.warn('[WEBVIEW] sign-in called with empty token');
      return;
    }
    try {
      firebase.auth().signInWithCustomToken(customToken)
        .then(function (cred) {
          console.log('[WEBVIEW] signed in uid=' + (cred.user && cred.user.uid));
        })
        .catch(function (err) {
          console.error('[WEBVIEW] signInWithCustomToken failed', err && err.code, err && err.message);
        });
    } catch (e) {
      console.error('[WEBVIEW] sign-in threw', e);
    }
  };

  var tokenRequested = false;
  function requestTokenFromFlutter() {
    if (tokenRequested) return;
    tokenRequested = true;
    try {
      if (window.ZitlasWebview && typeof window.ZitlasWebview.postMessage === 'function') {
        console.log('[WEBVIEW] no web session — requesting token from Flutter');
        window.ZitlasWebview.postMessage('need-token');
      } else {
        console.warn('[WEBVIEW] ZitlasWebview channel missing — cannot request token');
      }
    } catch (e) {
      console.error('[WEBVIEW] token request failed', e);
    }
  }

  /* Wait for the SDK to finish restoring any PERSISTED session before deciding
     we need a token — firebase.auth().currentUser is null synchronously on a
     cold load even when a valid session is about to be restored. */
  var settled = false;
  function settle(hasUser) {
    if (settled) return;
    settled = true;
    if (!hasUser) requestTokenFromFlutter();
    else console.log('[WEBVIEW] existing web session restored — no token needed');
  }

  try {
    firebase.auth().onAuthStateChanged(function (user) {
      settle(!!user);
    });
  } catch (e) {
    /* firebase not ready (should not happen — we load after firebase-config.js) */
    console.error('[WEBVIEW] onAuthStateChanged unavailable', e);
  }

  /* Safety net: if onAuthStateChanged never fires (unexpected), still ask for a
     token after a short grace period so the page can authenticate. */
  window.setTimeout(function () {
    var cur = null;
    try { cur = firebase.auth().currentUser; } catch (e) {}
    settle(!!cur);
  }, 2000);
})();
