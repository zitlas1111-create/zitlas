import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../models/zino_message.dart';

/// Backend access for Zino — `POST /api/ai/zino-chat`, the SAME endpoint
/// `zino.js` calls.
///
/// Nothing about the AI lives here: the persona (`ZINO_COMPANION_SYSTEM`),
/// the provider chain (Groq → Gemini → OpenRouter), RAG, and the safety rules
/// are all already implemented server-side. Flutter sends a message plus
/// context and renders the reply — no prompt, no model id, and no API key
/// ever exists in the app.
class ZinoRepository {
  ZinoRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// Sends one turn. Throws [ApiException] on transport/HTTP failure so the
  /// controller can classify it and offer a retry.
  Future<String> send({
    required String message,
    required Map<String, dynamic> context,
    required List<ZinoMessage> history,
  }) async {
    final res = await _api.post(
      '/api/ai/zino-chat',
      // The endpoint makes one LLM call with a fallback chain behind it; the
      // common case is a few seconds, but a provider failover can push past
      // the default budget. A slow answer still beats a spurious error.
      timeout: const Duration(seconds: 45),
      body: {
        'message': message,
        'context': context,
        // The backend reads the last 16 turns; sending a bounded slice keeps
        // the payload small on a long conversation without changing what it
        // can actually use.
        'history': [
          for (final m in _lastN(history, 16))
            {'role': m.isUser ? 'user' : 'zino', 'text': m.text},
        ],
      },
    );

    if (res is Map && res['reply'] is String) {
      return unwrapZinoReply(res['reply'] as String);
    }
    throw FormatException('Unexpected zino-chat response shape: ${res.runtimeType}');
  }

  static Iterable<T> _lastN<T>(List<T> list, int n) =>
      list.length <= n ? list : list.skip(list.length - n);
}

/// Keys checked, in order, when a reply arrives wrapped in JSON.
/// Mirrors `_REPLY_KEY_PRIORITY` (groq_service.py) and zino.js's `REPLY_KEYS`.
const _replyKeys = ['response', 'message', 'answer', 'reply', 'text', 'content'];

/// Defense-in-depth against a model self-wrapping a plain answer in JSON.
///
/// The backend already runs `unwrap_conversational_reply()`, and zino.js
/// duplicates the same guard client-side for the same reason this does: a
/// chat bubble must NEVER render raw braces, even if that layer regresses or
/// a future endpoint skips it. Plain prose — the overwhelming common case —
/// returns unchanged, because the parse is skipped entirely unless the text
/// actually starts like JSON.
String unwrapZinoReply(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return raw;

  // A ```json ... ``` fence is checked first: it starts with a backtick, so
  // the first-character guard below would otherwise reject it outright.
  var candidate = trimmed;
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(trimmed);
  if (fence != null) candidate = fence.group(1)!.trim();
  if (candidate.isEmpty) return raw;
  if (!candidate.startsWith('{') && !candidate.startsWith('"')) return raw;

  final Object? parsed;
  try {
    parsed = jsonDecode(candidate);
  } catch (_) {
    return raw; // Not actually JSON — the normal path for real prose.
  }

  if (parsed is String) return parsed;
  if (parsed is Map) {
    for (final key in _replyKeys) {
      final v = parsed[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    // Exactly one string field is unambiguous enough to use; anything else
    // would be guessing, so fall back to a friendly line rather than showing
    // the athlete a serialized object.
    final strings = parsed.values.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    if (strings.length == 1) return strings.first;
    return "Sorry, I got a bit tangled up there 😅 Could you ask that again?";
  }
  return raw;
}
