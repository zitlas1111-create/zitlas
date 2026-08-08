import 'dart:async';

import 'package:flutter/foundation.dart';

/// Holds the app on the branded splash for a short MINIMUM, so a fast startup
/// doesn't flash the logo for two frames and cut away.
///
/// The router keeps the app on `/splash` while EITHER this gate is not ready
/// OR authentication is still resolving — whichever finishes last wins. So:
///   * fast init  -> splash stays for [minimumDuration], then routes;
///   * slow init  -> splash stays until auth resolves (longer than the gate).
///
/// This is deliberately NOT an artificial delay bolted on after startup: the
/// timer runs CONCURRENTLY with Firebase init and the session check, which are
/// what actually gate the app. It only prevents the splash being shown for an
/// imperceptible flicker.
///
/// A [ChangeNotifier] because GoRouter's redirect is not re-evaluated on a bare
/// timer — the router merges this with `AuthState` as its `refreshListenable`,
/// so becoming ready triggers exactly one re-evaluation and the redirect away
/// from `/splash`.
class SplashGate extends ChangeNotifier {
  SplashGate._();

  static final SplashGate instance = SplashGate._();

  /// Long enough for the logo/tagline animation to read as intentional, short
  /// enough that it never feels like waiting.
  static const minimumDuration = Duration(milliseconds: 1200);

  bool _ready = false;
  Timer? _timer;

  /// Whether the app may leave the splash.
  ///
  /// Reading this LAZILY STARTS the clock if nobody has yet. `main()` starts it
  /// explicitly (so it runs concurrently with initialization, which is the
  /// point), but the router asks this question on its very first redirect — so
  /// self-starting here guarantees the gate can never leave the app stranded on
  /// the splash forever just because `start()` was missed on some entry path
  /// (a test harness, a future alternate `main`, an integration driver).
  bool get isReady {
    if (!_ready) start();
    return _ready;
  }

  /// Starts the minimum-duration clock. Called once from `main()` BEFORE
  /// `runApp`, so the clock runs alongside initialization rather than after it.
  /// Idempotent — a second call is ignored, so a hot restart cannot stack
  /// timers or re-hold the splash.
  void start() {
    if (_ready || _timer != null) return;
    _timer = Timer(minimumDuration, () {
      _timer = null;
      _ready = true;
      if (kDebugMode) debugPrint('[SPLASH] minimum duration elapsed — routing unblocked');
      notifyListeners();
    });
  }

  /// Test seam: lets a widget test skip the hold entirely.
  @visibleForTesting
  void forceReadyForTest() {
    _timer?.cancel();
    _timer = null;
    _ready = true;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _ready = false;
  }
}
