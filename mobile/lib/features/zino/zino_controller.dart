import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/local_storage_service.dart';
import 'data/zino_context_builder.dart';
import 'data/zino_repository.dart';
import 'models/zino_action.dart';
import 'models/zino_message.dart';

/// Conversation state for Zino.
///
/// MEMORY MODEL — three deliberately separate tiers, so a passing remark
/// never becomes a permanent fact about the athlete:
///
///  1. **Conversation history** (here) — the recent thread, persisted locally
///     and replayed to the backend for continuity. "My knees are sore" said a
///     few turns ago is still visible to Zino when the athlete asks to make
///     today's workout easier. Capped and disposable.
///  2. **Durable profile data** — goal, assessment, medical conditions,
///     preferences. Owned by Assessment/Profile, written only through their
///     own flows. Zino READS this and never writes it, so a casual comment
///     can't silently rewrite a medical field.
///  3. **Live app state** — today's steps, plan, streak. Rebuilt fresh on
///     every message by [ZinoContextBuilder]; never stored.
///
/// PER-USER ISOLATION: history is persisted under a uid-scoped key and the
/// in-memory thread is dropped whenever the uid changes, so one athlete's
/// conversation can never appear in another's session on a shared device.
class ZinoController extends ChangeNotifier {
  ZinoController({
    required this.uid,
    required this.athleteName,
    required ZinoRepository repository,
    required ZinoContextBuilder contextBuilder,
    LocalStorageService? storage,
  })  : _repository = repository,
        _contextBuilder = contextBuilder,
        _storage = storage ?? LocalStorageService.instance {
    _restore();
  }

  final String uid;
  final String athleteName;
  final ZinoRepository _repository;
  final ZinoContextBuilder _contextBuilder;
  final LocalStorageService _storage;

  /// Scoped per athlete — the uid is IN the key, so switching accounts reads
  /// a different bucket entirely rather than filtering a shared one.
  String get _historyKey => 'zitlas_zino_history_$uid';

  /// Matches the website's 20-entry cap (`_history.slice(-20)`).
  static const _maxStored = 20;

  final List<ZinoMessage> _messages = [];
  List<ZinoMessage> get messages => List.unmodifiable(_messages);

  bool _sending = false;
  bool get sending => _sending;

  /// Set when the last send failed, for the retry affordance. Cleared on the
  /// next successful turn.
  String? errorMessage;
  String? errorCategory;

  /// The single navigation shortcut offered for the latest exchange, if any.
  ZinoAction? pendingAction;

  ZinoScreenContext screen = ZinoScreenContext.other;
  String? viewingExpertId;

  bool _disposed = false;

  /// The greeting shown on an empty thread — not persisted, so it never
  /// becomes a "turn" the backend has to reason about.
  String get greeting {
    final first = athleteName.trim().split(' ').first;
    return "Hey ${first.isEmpty ? 'there' : first}! 👋 I'm Zino — ask me anything about "
        'your plan, or tap a quick action below.';
  }

  bool get isEmpty => _messages.isEmpty;

  // ── Persistence ────────────────────────────────────────────────────────

  void _restore() {
    try {
      final raw = _storage.getString(_historyKey);
      if (raw == null) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final m = ZinoMessage.fromMap(e);
          if (m != null) _messages.add(m);
        }
      }
    } catch (e) {
      // Corrupt history is discarded rather than crashing the screen — the
      // conversation is convenience state, never a source of truth.
      if (kDebugMode) debugPrint('[ZINO] history restore failed: $e');
    }
  }

  Future<void> _persist() async {
    final keep = _messages.length <= _maxStored
        ? _messages
        : _messages.sublist(_messages.length - _maxStored);
    // Failed turns are UI-only; replaying them to the backend as if they were
    // real exchanges would corrupt the conversation.
    final payload = [for (final m in keep.where((m) => !m.failed)) m.toMap()];
    await _storage.setString(_historyKey, jsonEncode(payload));
  }

  /// Wipes this athlete's thread — used by the in-chat "clear" affordance and
  /// on sign-out.
  Future<void> clear() async {
    _messages.clear();
    pendingAction = null;
    errorMessage = null;
    await _storage.remove(_historyKey);
    _notify();
  }

  // ── Sending ────────────────────────────────────────────────────────────

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;

    _messages.add(ZinoMessage(text: message, isUser: true, at: DateTime.now()));
    _sending = true;
    errorMessage = null;
    errorCategory = null;
    pendingAction = null;
    _notify();

    await _dispatch(message);
  }

  /// Re-sends the last failed athlete turn.
  Future<void> retry() async {
    if (_sending) return;
    final lastUserIndex = _messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIndex < 0) return;
    final text = _messages[lastUserIndex].text;
    _messages[lastUserIndex] = _messages[lastUserIndex].copyWith(failed: false);
    _sending = true;
    errorMessage = null;
    _notify();
    await _dispatch(text);
  }

  Future<void> _dispatch(String message) async {
    try {
      final context = await _contextBuilder.build(
        uid: uid,
        athleteName: athleteName,
        screen: screen,
        viewingExpertId: viewingExpertId,
      );

      if (kDebugMode) {
        debugPrint('[ZINO] uid=$uid screen=${screen.name} '
            'context_keys=${context.keys.toList()}');
      }

      // History excludes the just-added turn (it's sent as `message`) and any
      // failed turns, which have no reply to pair with.
      final history = [
        for (final m in _messages.where((m) => !m.failed)) m,
      ]..removeLast();

      final reply = await _repository.send(
        message: message,
        context: context,
        history: history,
      );

      _messages.add(ZinoMessage(text: reply, isUser: false, at: DateTime.now()));
      // Derived from the ATHLETE's message, never the reply — see
      // zino_action.dart's security model.
      pendingAction = detectZinoAction(message);
      if (kDebugMode) debugPrint('[ZINO] action = ${describeAction(pendingAction)}');
      errorMessage = null;
      errorCategory = null;
      await _persist();
    } catch (e) {
      final lastUserIndex = _messages.lastIndexWhere((m) => m.isUser);
      if (lastUserIndex >= 0) {
        _messages[lastUserIndex] = _messages[lastUserIndex].copyWith(failed: true);
      }
      errorCategory = _classify(e);
      errorMessage = _friendlyError(errorCategory!);
      if (kDebugMode) {
        debugPrint('[ZINO] send failed [$errorCategory]: $e');
        if (e is ApiException) {
          debugPrint('[ZINO]   status=${e.statusCode} body=${e.body}');
        }
      }
    } finally {
      _sending = false;
      _notify();
    }
  }

  static String _classify(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError) return 'NETWORK_ERROR';
      if (e.isUnauthorized) return 'AUTH_ERROR';
      if (e.statusCode == 503) return 'AI_PROVIDER_ERROR';
      if (e.isServerError) return 'BACKEND_ERROR';
      return 'BACKEND_ERROR';
    }
    if (e is FormatException) return 'INVALID_RESPONSE';
    return 'NETWORK_ERROR';
  }

  /// The athlete never sees an error code — just Zino, being Zino about it.
  static String _friendlyError(String category) => switch (category) {
        'NETWORK_ERROR' =>
          "I can't reach the internet right now 😅 Check your connection and try again?",
        'AI_PROVIDER_ERROR' =>
          "My brain's taking a quick nap 😴 Give me a moment and try again?",
        _ => "Hmm, I'm having trouble connecting right now 😅 Try again in a moment?",
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
