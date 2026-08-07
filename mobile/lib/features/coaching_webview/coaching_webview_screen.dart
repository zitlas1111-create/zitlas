import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/config/env.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

/// Personal Coaching, served by the Website inside a secure, chromeless
/// WebView until native Flutter reaches feature parity. This is the ONLY
/// WebView in the app — every other module is native.
///
/// The whole authentication pipeline is instrumented: every stage prints a
/// `[COACHING WEBVIEW]` line, the embedded page's console is mirrored to the
/// native log as `[WV-CONSOLE]`, and the bridge reports the signInWithCustomToken
/// result back over the `ZitlasWebview` channel (`auth-ok`/`auth-fail:<code>`),
/// so a failure names the EXACT stage instead of a silent reload loop.
class CoachingWebViewScreen extends StatefulWidget {
  const CoachingWebViewScreen({
    super.key,
    required this.relativePath,
    required this.title,
  });

  /// Path + query on the backend host (which also serves the website), e.g.
  /// `/pages/coaches/cprofile.html?id=<coachId>&webview=1`.
  final String relativePath;

  /// Shown only if the page fails to load (there is no visible app bar in the
  /// success case — the embedded page provides its own header).
  final String title;

  /// The athlete's active-coaching workspace (chat, meal reviews, coach notes,
  /// remaining days, End Coaching, coach-authored plan views).
  factory CoachingWebViewScreen.athleteWorkspace({required String coachId}) {
    return CoachingWebViewScreen(
      relativePath: '/pages/coaches/cprofile.html?id=$coachId&webview=1',
      title: 'Personal Coaching',
    );
  }

  /// The coach/expert portal (roster, reviews, plan editing).
  factory CoachingWebViewScreen.expertDashboard() {
    return const CoachingWebViewScreen(
      relativePath: '/pages/experts/expert-dashboard.html?webview=1',
      title: 'Coach Dashboard',
    );
  }

  @override
  State<CoachingWebViewScreen> createState() => _CoachingWebViewScreenState();
}

class _CoachingWebViewScreenState extends State<CoachingWebViewScreen> {
  late final WebViewController _controller;
  final ApiClient _api = ApiClient()
    ..authTokenProvider = () async => FirebaseAuth.instance.currentUser?.getIdToken();
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();

  bool _loading = true;
  bool _failed = false;
  bool _tokenInFlight = false;

  /// Message shown on the error view.
  String? _errorMessage;

  /// Set once the bridge reports a successful signInWithCustomToken. Used to
  /// tell a normal first-load login-redirect (session not established yet, wait)
  /// apart from a post-auth bounce (signed in, but the page's own guard still
  /// rejected — an account/data problem, not an auth one).
  bool _sawAuthOk = false;

  /// True once a logout is underway, so the 'logout' message and the login
  /// redirect it triggers don't each try to sign out / navigate.
  bool _loggingOut = false;

  /// Fires if the sign-in produces neither auth-ok nor auth-fail in time, so a
  /// silent stall becomes a visible, retryable error instead of a spinner.
  Timer? _authTimer;
  static const _authTimeout = Duration(seconds: 15);

  /// Live vertical scroll offset of the embedded page (pull-to-refresh arms
  /// only while scrolled to the very top).
  double _scrollY = 0;
  double _pullStartDy = 0;
  bool _arming = false;

  String get _url => '${Env.apiBaseUrl}${widget.relativePath}';

  /// Host of the backend/website, so the navigation delegate can tell an
  /// in-app link (keep in the WebView) from an external one (system browser).
  late final String _appHost = Uri.parse(Env.apiBaseUrl).host;

  @override
  void initState() {
    super.initState();
    _log('STEP init — url=$_url');
    _controller = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(),
      onPermissionRequest: _onWebPermissionRequest,
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('ZitlasWebview', onMessageReceived: _onJsMessage)
      // Mirror the embedded page's console to the native log — this is how the
      // page's OWN guard logs ([AUTH UID], [USER DOC], [EXPERT DOC], Firebase
      // errors) become visible while diagnosing the auth pipeline.
      ..setOnConsoleMessage(_onConsole)
      ..setOnScrollPositionChange((ScrollPositionChange c) => _scrollY = c.y)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _log('STEP page-started — $url');
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            _log('STEP page-finished — $url');
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (WebResourceError err) {
            // Only a MAIN-document failure is fatal; sub-resource errors (an
            // image, a beacon) must not blank the whole screen.
            if (err.isForMainFrame ?? true) {
              _log('STEP FAILURE web-resource — ${err.errorCode} ${err.description}');
              _showError('Could not load coaching. Check your connection and retry.');
            }
          },
          onNavigationRequest: _onNavigation,
        ),
      );

    // Android-only wiring: chat image upload (file chooser) + let the page play
    // media (WebRTC call) without a user gesture. iOS gets the equivalents from
    // Info.plist + WKWebView defaults.
    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
      android.setOnShowFileSelector(_androidPickFiles);
    }

    _controller.loadRequest(Uri.parse(_url));
  }

  @override
  void dispose() {
    _authTimer?.cancel();
    _api.close();
    super.dispose();
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[COACHING WEBVIEW] $msg');
  }

  // ── WebView console mirror ──────────────────────────────────────────────

  void _onConsole(JavaScriptConsoleMessage m) {
    if (kDebugMode) debugPrint('[WV-CONSOLE ${m.level.name}] ${m.message}');
  }

  // ── Auth bridge (message router) ────────────────────────────────────────

  void _onJsMessage(JavaScriptMessage message) {
    final m = message.message;
    _log('BRIDGE » $m');
    if (m == 'need-token') {
      _provideToken();
    } else if (m == 'logout') {
      _onLogout();
    } else if (m.startsWith('auth-ok')) {
      _onAuthOk(m);
    } else if (m.startsWith('auth-fail:')) {
      _onAuthFail(m.substring('auth-fail:'.length));
    }
    // Everything else (bridge-active, token-claims, auth-state, session-restored)
    // is diagnostic and already logged above.
  }

  /// Mints a custom token for the CURRENT native user and hands it to the page,
  /// which signs in with it. Logs the HTTP result and the (non-secret) JWT
  /// claims so a bad/mismatched token is obvious. On any failure it shows the
  /// error view and returns false — it never silently no-ops.
  Future<bool> _provideToken() async {
    if (_tokenInFlight) {
      _log('STEP token — already in flight, coalescing');
      return false;
    }
    _tokenInFlight = true;
    _log('STEP token-request START → POST /api/auth/webview-token');
    try {
      final res = await _api.post('/api/auth/webview-token');
      final token = (res is Map) ? res['customToken'] as String? : null;
      if (token == null || token.isEmpty) {
        _log('STEP token-request FAILURE — 200 but no customToken in body');
        _showError('Coaching sign-in is unavailable right now. Please try again.');
        return false;
      }
      _log('STEP token-request SUCCESS — got token (${token.length} chars)');
      _logJwtClaims(token);
      // A Firebase custom token is a JWT (no quotes/backslashes), but escape
      // defensively before embedding it in a JS string literal.
      final safe = token.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      await _controller.runJavaScript("window.__zitlasWebviewSignIn('$safe');");
      _log('STEP token-inject SUCCESS — delivered to page, awaiting auth-ok/auth-fail');
      _startAuthTimeout();
      return true;
    } on ApiException catch (e) {
      _log('STEP token-request FAILURE — HTTP ${e.statusCode}: ${e.message}');
      _showError(_messageForStatus(e.statusCode));
      return false;
    } catch (e) {
      _log('STEP token-request FAILURE — $e');
      _showError('Could not connect to coaching. Check your connection and retry.');
      return false;
    } finally {
      _tokenInFlight = false;
    }
  }

  /// Decodes and logs the NON-SECRET JWT claims (aud/iss/sub/uid/exp) — never
  /// the signature — so a custom-token-mismatch (wrong project) is diagnosable
  /// from the native log alone.
  void _logJwtClaims(String jwt) {
    if (!kDebugMode) return;
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) {
        _log('JWT — not a JWT (${parts.length} segments)');
        return;
      }
      var b64 = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      b64 = b64.padRight(b64.length + (4 - b64.length % 4) % 4, '=');
      final claims = jsonDecode(utf8.decode(base64.decode(b64))) as Map<String, dynamic>;
      _log('JWT claims — aud=${claims['aud']} iss=${claims['iss']} '
          'uid=${claims['uid']} exp=${claims['exp']}');
    } catch (e) {
      _log('JWT — could not decode claims: $e');
    }
  }

  void _startAuthTimeout() {
    _authTimer?.cancel();
    _authTimer = Timer(_authTimeout, () {
      if (!mounted || _sawAuthOk || _failed) return;
      _log('STEP auth TIMEOUT — no auth-ok/auth-fail in ${_authTimeout.inSeconds}s');
      _showError('Coaching sign-in timed out. Please retry.');
    });
  }

  void _onAuthOk(String raw) {
    _authTimer?.cancel();
    _sawAuthOk = true;
    _log('STEP auth SUCCESS — $raw (page will render via its own auth listener)');
    // The page renders itself on its onAuthStateChanged(user); just make sure
    // no stale error/spinner is showing.
    if (mounted && (_failed || _loading)) {
      setState(() { _failed = false; _loading = false; _errorMessage = null; });
    }
  }

  void _onAuthFail(String code) {
    _authTimer?.cancel();
    _log('STEP auth FAILURE — signInWithCustomToken code=$code');
    _showError(_messageForAuthCode(code));
  }

  /// The embedded page logged out (it already tore down its Firestore listeners
  /// and cleared web storage first). The native app owns the real session, so
  /// finish the logout natively: sign out of Firebase, which the router's auth
  /// guard turns into a redirect to /login, and leave the WebView. This is why
  /// the website's logout hands off to us instead of navigating to its own
  /// login page (which the WebView blocks).
  Future<void> _onLogout() async {
    if (_loggingOut) return; // may arrive via both the 'logout' message and the login redirect
    _loggingOut = true;
    _log('STEP logout — native sign-out + leave WebView');
    _authTimer?.cancel();
    final router = GoRouter.of(context);
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      _log('native signOut failed: $e');
    }
    if (!mounted) return;
    router.go('/login');
  }

  /// Maps a token-endpoint HTTP status to a human message. 404/405 means the
  /// route is missing from the deployed backend (ApiClient documents this).
  String _messageForStatus(int? status) {
    switch (status) {
      case 401:
      case 403:
        return 'Your session expired. Please sign out and back in, then reopen coaching.';
      case 404:
      case 405:
        return "Coaching isn't available on the server yet. Please try again later.";
      case 500:
      case 502:
      case 503:
        return 'Coaching is temporarily unavailable. Please try again in a moment.';
      default:
        return 'Could not start coaching just now. Please try again.';
    }
  }

  /// Maps a Firebase signInWithCustomToken error code to a human message.
  String _messageForAuthCode(String code) {
    if (code.contains('custom-token-mismatch') || code.contains('invalid-custom-token')) {
      // Server minted a token for a different Firebase project than the website
      // uses — a config problem, not something a retry fixes.
      return 'Coaching sign-in is misconfigured on the server. Please contact support.';
    }
    if (code.contains('network')) {
      return 'Network problem during coaching sign-in. Check your connection and retry.';
    }
    if (code == 'no-channel' || code == 'no-firebase') {
      return 'Coaching could not start. Please reopen it.';
    }
    return 'Coaching sign-in did not complete. Please retry.';
  }

  /// Single choke point for the error view.
  void _showError(String message) {
    _authTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _failed = true;
      _loading = false;
      _errorMessage = message;
    });
  }

  // ── Permissions (WebRTC coach calls) ───────────────────────────────────

  Future<void> _onWebPermissionRequest(WebViewPermissionRequest request) async {
    final wantsCamera = request.types.contains(WebViewPermissionResourceType.camera);
    final wantsMic = request.types.contains(WebViewPermissionResourceType.microphone);
    _log('STEP web-permission — camera=$wantsCamera mic=$wantsMic');

    var granted = true;
    if (wantsCamera) {
      granted = granted && (await Permission.camera.request()).isGranted;
    }
    if (wantsMic) {
      granted = granted && (await Permission.microphone.request()).isGranted;
    }
    if (granted) {
      await request.grant();
    } else {
      await request.deny();
    }
  }

  // ── File chooser (chat image attachments, Android) ──────────────────────

  Future<List<String>> _androidPickFiles(FileSelectorParams params) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file == null) return const <String>[];
      return <String>[Uri.file(file.path).toString()];
    } catch (e) {
      _log('file pick failed: $e');
      return const <String>[];
    }
  }

  // ── Navigation policy ───────────────────────────────────────────────────

  NavigationDecision _onNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    // The native app is already authenticated, so the embedded module must
    // NEVER show the website's own login page.
    if (uri.path.toLowerCase().contains('/login')) {
      _log('STEP nav-login-intercept — sawAuthOk=$_sawAuthOk loggingOut=$_loggingOut');
      if (_loggingOut) {
        // Logout already in progress (via the 'logout' message) — just block the
        // website login; the native sign-out is taking us to the native login.
      } else if (_sawAuthOk) {
        // We WERE signed in and the page is now heading to login — a logout or a
        // session end (the website's own onAuthStateChanged(null) fires this
        // during signOut, possibly before its 'logout' message reaches us).
        // Finish it natively and leave, rather than re-authenticating (which
        // would defeat logout).
        _onLogout();
      } else {
        // First-load race: the page's guard ran before sign-in landed. Ensure a
        // token is on its way and WAIT for auth-ok — do NOT reload.
        _provideToken();
      }
      return NavigationDecision.prevent;
    }

    // Non-http(s) schemes and other hosts leave the WebView via the system
    // handler — the embedded module never becomes a general-purpose browser.
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    final sameHost = uri.host.isEmpty || uri.host == _appHost;
    if (isHttp && sameHost) return NavigationDecision.navigate;

    _launchExternal(uri);
    return NavigationDecision.prevent;
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _log('external launch failed: $e');
    }
  }

  // ── Pull-to-refresh ─────────────────────────────────────────────────────
  // A passive [Listener] observes pointer moves WITHOUT entering the gesture
  // arena, so the WebView keeps scrolling normally.

  void _onPointerDown(PointerDownEvent e) {
    _arming = _scrollY <= 0.5;
    _pullStartDy = e.position.dy;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_arming) return;
    if (_scrollY > 0.5) {
      _arming = false;
      return;
    }
    if (e.position.dy - _pullStartDy > 110) {
      _arming = false;
      _refreshKey.currentState?.show();
    }
  }

  Future<void> _onRefresh() async {
    await _controller.reload();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        // Capture the router BEFORE the await so we never touch BuildContext
        // across the async gap.
        final router = GoRouter.of(context);
        // 1) Walk the page's OWN history first (native-feeling back inside the
        //    workspace).
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        if (!mounted) return;
        // 2) Leave the workspace safely. If pushed, pop; if this is the ONLY
        //    route (reached via context.go — a notification tap or the coach
        //    dashboard), popping would crash with "popped the last page off the
        //    stack", so go to the dashboard. Never leaves GoRouter empty.
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/dashboard');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _failed ? _errorView() : _webView(),
        ),
      ),
    );
  }

  Widget _webView() {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _arming = false,
      onPointerCancel: (_) => _arming = false,
      child: RefreshIndicator(
        key: _refreshKey,
        notificationPredicate: (_) => false,
        onRefresh: _onRefresh,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 46, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              "Couldn't load ${widget.title}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                // Fresh attempt: clear error + the auth signals so a retry is
                // clean rather than already-exhausted.
                setState(() {
                  _failed = false;
                  _loading = true;
                  _errorMessage = null;
                });
                _sawAuthOk = false;
                _tokenInFlight = false;
                _authTimer?.cancel();
                _controller.loadRequest(Uri.parse(_url));
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () {
                final router = GoRouter.of(context);
                if (router.canPop()) {
                  router.pop();
                } else {
                  router.go('/dashboard');
                }
              },
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
