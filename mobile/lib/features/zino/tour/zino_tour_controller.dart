import 'package:flutter/foundation.dart';

import 'zino_tour_stops.dart';
import 'zino_tour_store.dart';

/// Drives the walkthrough: which stop is showing, which screen it needs, and
/// when completion is recorded.
///
/// Deliberately UI-free so the sequencing rules — skipping unreachable
/// optional stops, treating Skip as completion, never re-persisting — are
/// testable without pumping widgets.
class ZinoTourController extends ChangeNotifier {
  ZinoTourController({
    required this.uid,
    required ZinoTourStore store,
    List<ZinoTourStop>? stops,
    bool hasActiveCoach = false,
  })  : _store = store,
        _stops = stops ?? kZinoTourStops,
        _hasActiveCoach = hasActiveCoach;

  final String uid;
  final ZinoTourStore _store;
  final List<ZinoTourStop> _stops;
  final bool _hasActiveCoach;

  bool _disposed = false;

  // Guards dispose-during-notify: a tour step advanced from an async callback
  // can fire after the tour overlay (and this controller) is torn down.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  int _index = 0;
  bool _running = false;
  bool _completed = false;

  bool get isRunning => _running;
  bool get isCompleted => _completed;
  int get index => _index;
  int get totalStops => _stops.length;
  ZinoTourStop get current => _stops[_index];

  /// 1-based, for the "3 / 13" counter.
  int get stepNumber => _index + 1;
  bool get isFirst => _index == 0;
  bool get isLast => _index == _stops.length - 1;

  /// The body copy actually shown — appends `coachExtra` only when the athlete
  /// really has an active coach, exactly like `renderSpotlight()` on the web.
  String get currentBody {
    final stop = current;
    final extra = stop.coachExtra;
    if (extra == null || !_hasActiveCoach) return stop.body;
    return '${stop.body}\n\n$extra';
  }

  /// Starts the tour for a genuinely new account. Returns whether it started.
  Future<bool> startIfNewUser() async {
    if (_running) return false;
    final should = await _store.shouldAutoStart(uid);
    if (!should) return false;
    _index = 0;
    _running = true;
    notifyListeners();
    return true;
  }

  /// Manual replay ("Take Zino Tour Again"). Skips the new-user check
  /// entirely and does NOT reset [ZinoTourStore] state — replaying must never
  /// turn an existing athlete back into a "new user".
  void startManually() {
    _index = 0;
    _running = true;
    notifyListeners();
  }

  void next() {
    if (isLast) {
      finish();
      return;
    }
    _index++;
    notifyListeners();
  }

  void back() {
    if (isFirst) return;
    _index--;
    notifyListeners();
  }

  /// Advances past a stop whose target widget isn't on screen.
  ///
  /// The website does the same: a `querySelector` miss on an `optional` stop
  /// skips it immediately, and a non-optional miss skips after a short retry
  /// window. A fresh account legitimately has no diet plan, no experts and no
  /// coach yet, so several stops have nothing to point at — silently moving on
  /// is far better than spotlighting empty space.
  void skipUnavailableStop() {
    if (kDebugMode) debugPrint('[ZINO TOUR] stop "${current.id}" has no target — skipping');
    next();
  }

  /// Skip and Finish are the same outcome, per the website (`skip()` calls
  /// `finish()`): the athlete has seen the tour and shouldn't be shown it
  /// again unattended.
  Future<void> skip() => finish();

  Future<void> finish() async {
    _running = false;
    _completed = true;
    notifyListeners();
    await _store.markCompleted(uid);
  }
}
