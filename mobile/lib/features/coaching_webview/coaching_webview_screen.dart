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
/// It feels native because:
///  * no browser chrome, URL bar, or external-browser hand-off (external links
///    open in the system browser, everything on zitlas.com stays in-place);
///  * the Android back button walks the page's own history before leaving;
///  * pull-to-refresh reloads the page;
///  * the athlete never logs in again — the native Firebase session is bridged
///    to a real web session via a one-time custom-token exchange.
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

  /// Message shown on the error view. Set by [_showError] so a token/auth
  /// failure explains itself instead of a generic "check your connection".
  String? _errorMessage;

  /// Bounds the "blocked a login redirect → re-auth → reload" recovery so a
  /// genuine auth failure surfaces the error view instead of looping forever.
  int _loginRecoveries = 0;
  static const _maxLoginRecoveries = 3;

  /// Live vertical scroll offset of the embedded page, fed by
  /// [WebViewController.setOnScrollPositionChange]. Pull-to-refresh only arms
  /// while the page is scrolled to the very top.
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
    _controller = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(),
      onPermissionRequest: _onWebPermissionRequest,
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('ZitlasWebview', onMessageReceived: _onJsMessage)
      ..setOnScrollPositionChange((ScrollPositionChange c) => _scrollY = c.y)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (WebResourceError err) {
            // Only a failure of the MAIN document is fatal; sub-resource errors
            // (an image, an analytics beacon) must not blank the whole screen.
            if (err.isForMainFrame ?? true) {
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
    _api.close();
    super.dispose();
  }

  // ── Auth bridge ────────────────────────────────────────────────────────

  void _onJsMessage(JavaScriptMessage message) {
    // The only message the page sends: "I have no web session, send a token".
    if (message.message == 'need-token') _provideToken();
  }

  /// Mints a custom token for the CURRENT native user and hands it to the page,
  /// which signs in with it (`window.__zitlasWebviewSignIn`). This is what lets
  /// the athlete skip a second login.
  ///
  /// Returns true only if a token was actually delivered to the page. On ANY
  /// failure it shows the error view and returns false — it never silently
  /// no-ops, because a silent failure is exactly what turned a dead
  /// `/api/auth/webview-token` (405) into a page that reload-looped forever.
  /// Overlapping calls are coalesced (returns false, does not re-fetch).
  Future<bool> _provideToken() async {
    if (_tokenInFlight) return false;
    _tokenInFlight = true;
    try {
      final res = await _api.post('/api/auth/webview-token');
      final token = (res is Map) ? res['customToken'] as String? : null;
      if (token == null || token.isEmpty) {
        _showError('Coaching sign-in is unavailable right now. Please try again.');
        return false;
      }
      // A Firebase custom token is a JWT (no quotes/backslashes), but escape
      // defensively before embedding it in a JS string literal.
      final safe = token.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      await _controller.runJavaScript("window.__zitlasWebviewSignIn('$safe');");
      if (kDebugMode) debugPrint('[COACHING WEBVIEW] custom token delivered to page');
      return true;
    } on ApiException catch (e) {
      // 401/403/404/405/500 — a clear, specific message, and NO retry loop.
      if (kDebugMode) debugPrint('[COACHING WEBVIEW] token endpoint ${e.statusCode}: ${e.message}');
      _showError(_messageForStatus(e.statusCode));
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[COACHING WEBVIEW] token fetch failed: $e');
      _showError('Could not connect to coaching. Check your connection and retry.');
      return false;
    } finally {
      _tokenInFlight = false;
    }
  }

  /// Maps a token-endpoint HTTP status to a human message. 404/405 specifically
  /// means the route is missing from the deployed backend (see ApiClient's own
  /// note) — telling the athlete to check their connection would be a lie.
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

  /// Single choke point for showing the error view. Stops the loading spinner
  /// and records the reason; the view offers Retry (which resets the recovery
  /// budget) so the athlete is never stranded on a blank screen.
  void _showError(String message) {
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

    // Ensure the OS-level runtime grant first — granting to the page while the
    // app itself lacks the permission just yields a black/silent stream.
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
      // Android's WebView expects file:// URIs back.
      return <String>[Uri.file(file.path).toString()];
    } catch (e) {
      if (kDebugMode) debugPrint('[COACHING WEBVIEW] file pick failed: $e');
      return const <String>[];
    }
  }

  // ── Navigation policy ───────────────────────────────────────────────────

  NavigationDecision _onNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    // The native app is already authenticated, so the embedded module must
    // NEVER show the website's own login page. It can only try during the brief
    // first-load window before the custom-token sign-in lands (the page's auth
    // guard sees no web session yet and redirects). Block it and recover.
    if (uri.path.toLowerCase().contains('/login')) {
      _recoverFromLoginRedirect();
      return NavigationDecision.prevent;
    }

    // Non-http(s) schemes (tel:, mailto:, intent:, whatsapp:) and links to a
    // different host leave the WebView and open in the system handler — the
    // embedded module never becomes a general-purpose browser.
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    final sameHost = uri.host.isEmpty || uri.host == _appHost;
    if (isHttp && sameHost) return NavigationDecision.navigate;

    _launchExternal(uri);
    return NavigationDecision.prevent;
  }

  /// Re-establishes the web session (in case it lapsed) and reloads the
  /// intended coaching page, so the athlete lands back in the module rather
  /// than on a login screen. Bounded, so a real auth failure ends on the error
  /// view instead of an endless reload loop.
  Future<void> _recoverFromLoginRedirect() async {
    if (_loginRecoveries >= _maxLoginRecoveries) {
      _showError('Coaching sign-in did not complete. Please retry.');
      return;
    }
    _loginRecoveries++;
    final delivered = await _provideToken();
    // If the token could not be delivered (e.g. the endpoint is down / 405),
    // _provideToken already showed the error. Do NOT reload — reloading would
    // just hit the same failure again. This is what breaks the infinite loop.
    if (!delivered) return;
    // Token delivered: give signInWithCustomToken a moment to persist, then
    // reload so the page's guard finds the session instead of redirecting.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) _controller.loadRequest(Uri.parse(_url));
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[COACHING WEBVIEW] external launch failed: $e');
    }
  }

  // ── Pull-to-refresh ─────────────────────────────────────────────────────
  //
  // A passive [Listener] observes pointer moves WITHOUT entering the gesture
  // arena, so the WebView keeps scrolling normally. When the page is at the top
  // and the finger is dragged down past a threshold, we fire the standard
  // Material refresh indicator, which reloads the page.

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
    _failed = false;
    await _controller.reload();
    // Give the load a moment so the spinner doesn't vanish before content
    // starts painting; onPageFinished clears the loading flag properly.
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
        // 1) Walk the page's OWN history first (e.g. coach dashboard → back to
        //    the review list) so back feels native inside the workspace.
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        if (!mounted) return;
        // 2) Otherwise leave the workspace safely. If this screen was pushed,
        //    pop it; if it is the ONLY route (reached via context.go, e.g. a
        //    notification tap or the coach dashboard), popping would crash with
        //    "popped the last page off the stack" — so go to the dashboard
        //    instead. Never leaves GoRouter with zero pages.
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
        // Never auto-trigger off scroll notifications (a WebView emits none) —
        // we drive it manually via _refreshKey.currentState.show().
        notificationPredicate: (_) => false,
        onRefresh: _onRefresh,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
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
                // Fresh attempt: clear the error AND reset the recovery budget
                // and in-flight guard, so the athlete gets a clean retry rather
                // than an already-exhausted one.
                setState(() {
                  _failed = false;
                  _loading = true;
                  _errorMessage = null;
                });
                _loginRecoveries = 0;
                _tokenInFlight = false;
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
