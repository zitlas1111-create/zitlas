import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Tears down the coaching WebView's own browser session at logout.
///
/// WHY THIS EXISTS: the Firebase JS SDK running inside the coaching WebView
/// keeps its OWN persisted session in WebView storage, completely separate from
/// the native Firebase session. `FirebaseAuth.signOut()` does not touch it. So
/// after an account switch the WebView would still be signed in as the previous
/// user, and the coaching pages would read THEIR profile — which is how an
/// expert login ended up in the athlete area.
///
/// BEST-EFFORT BY DESIGN, and deliberately not the only guard: the JS SDK
/// prefers IndexedDB for auth persistence, which `clearLocalStorage()` does not
/// necessarily cover. The authoritative fix is in `webview-bridge.js`, which
/// compares the restored web session's uid against the native uid on EVERY load
/// and re-authenticates on mismatch — that works regardless of which storage
/// backend the SDK chose. This class reduces how often that path is needed and
/// avoids leaving another account's data cached on the device.
///
/// Never throws: it runs during sign-out, which must always complete.
abstract final class CoachingWebViewSession {
  static Future<void> clear() async {
    try {
      await WebViewCookieManager().clearCookies();
    } catch (e) {
      if (kDebugMode) debugPrint('[WEBVIEW SESSION] cookie clear failed (non-fatal): $e');
    }
    try {
      // A controller with no widget attached is still a valid platform object,
      // which is what lets this run at logout when the coaching screen is gone.
      final controller = WebViewController();
      await controller.clearCache();
      await controller.clearLocalStorage();
      if (kDebugMode) debugPrint('[WEBVIEW SESSION] cleared cookies + cache + localStorage');
    } catch (e) {
      if (kDebugMode) debugPrint('[WEBVIEW SESSION] storage clear failed (non-fatal): $e');
    }
  }
}
