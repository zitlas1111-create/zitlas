import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/admin_repository.dart';

/// Drives the Admin certificate-review screen. Mirrors `admin-review.js`:
/// gate on the admin claim, live-list pending certificates, approve/reject via
/// the backend. All verification state changes happen server-side; this only
/// reflects the live Firestore stream (the backend flipping a cert out of
/// `pending_review` makes it disappear from the list automatically).
class AdminController extends ChangeNotifier {
  AdminController(this._repo) {
    _init();
  }

  final AdminRepository _repo;

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  List<AdminCert> _certs = const [];
  List<AdminCert> get certs => _certs;

  final Set<String> _busy = <String>{};
  bool isBusy(String certId) => _busy.contains(certId);

  StreamSubscription<List<AdminCert>>? _sub;

  Future<void> _init() async {
    try {
      _isAdmin = await _repo.isAdmin();
      if (!_isAdmin) {
        _loading = false;
        notifyListeners();
        return;
      }
      _sub = _repo.watchPendingCertificates().listen(
        (list) {
          _certs = list;
          _loading = false;
          _error = null;
          notifyListeners();
        },
        onError: (Object e) {
          _error = e;
          _loading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = e;
      _loading = false;
      notifyListeners();
    }
  }

  /// Returns null on success, or a human-readable error message the screen can
  /// surface in a snackbar. The list itself updates via the stream.
  Future<String?> approve(String certId) => _action(certId, () => _repo.approve(certId));

  Future<String?> reject(String certId, String reason) =>
      _action(certId, () => _repo.reject(certId, reason));

  Future<String?> _action(String certId, Future<void> Function() op) async {
    if (_busy.contains(certId)) return null;
    _busy.add(certId);
    notifyListeners();
    try {
      await op();
      return null;
    } catch (e) {
      return e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Action failed — please try again.';
    } finally {
      _busy.remove(certId);
      notifyListeners();
    }
  }

  bool _disposed = false;

  // Guards dispose-during-notify: an async Firestore snapshot can arrive after
  // this controller is disposed. A disposed notifier stops notifying.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
