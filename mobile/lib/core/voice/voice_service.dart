import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../network/api_client.dart';
import 'voice_language.dart';

/// How Zino's speech was produced — surfaced so the UI can be honest about
/// which voice the athlete is hearing.
enum VoiceSource {
  /// Zino's real ElevenLabs voice, synthesized server-side.
  elevenLabs,

  /// The device's built-in speech engine, used when ElevenLabs is
  /// unavailable (no API quota, network failure, unconfigured deployment).
  device,

  none,
}

/// Playback lifecycle state.
enum VoicePlaybackState { idle, playing, paused }

/// Reusable voice layer for Zino: talk to the backend, get audio, play it.
///
/// ARCHITECTURE — this class is a mouth and ears, never a brain. It sends text
/// to ZITLAS's own FastAPI backend and plays what comes back; every decision
/// about WHAT Zino says is made server-side by the existing groq_service /
/// RAG / engine stack. No API key of any kind exists in this app: the
/// ElevenLabs and Groq credentials live only on the server, and Flutter's
/// entire vocabulary is three HTTP calls.
///
/// TWO VOICES, ONE INTERFACE. ElevenLabs is preferred and is Zino's real
/// voice. When it can't answer, [speak] transparently falls back to the
/// device's own TTS engine so a conversation still happens — a voice outage
/// degrades quality, never function. [lastSource] reports which was used.
class VoiceService {
  VoiceService({
    ApiClient? apiClient,
    AudioPlayer? player,
    FlutterTts? deviceTts,
  })  : _api = apiClient ?? ApiClient(),
        _player = player ?? AudioPlayer(),
        _deviceTts = deviceTts ?? FlutterTts();

  final ApiClient _api;
  final AudioPlayer _player;
  final FlutterTts _deviceTts;

  bool _disposed = false;
  bool _deviceTtsReady = false;

  /// The last clip played, kept so [replay] costs no synthesis quota and no
  /// network round trip.
  Uint8List? _lastAudio;
  String? _lastText;
  VoiceLanguage _lastLanguage = VoiceLanguage.fallback;

  VoiceSource lastSource = VoiceSource.none;
  VoicePlaybackState playbackState = VoicePlaybackState.idle;

  /// Fires whenever Zino finishes speaking — the call screen uses this to
  /// return to listening without polling.
  final _completion = StreamController<void>.broadcast();
  Stream<void> get onSpeechComplete => _completion.stream;

  StreamSubscription<void>? _playerCompleteSub;
  bool _wired = false;

  void _wirePlayer() {
    if (_wired) return;
    _wired = true;
    _playerCompleteSub = _player.onPlayerComplete.listen((_) {
      playbackState = VoicePlaybackState.idle;
      if (!_completion.isClosed) _completion.add(null);
    });
  }

  // ── Backend calls ──────────────────────────────────────────────────────

  /// One conversational turn: text in, Zino's reply (+ audio) out.
  ///
  /// Hits `/api/voice/chat`, which runs the SAME persona and provider chain as
  /// the text chat and returns reply + audio together — one round trip instead
  /// of two, which is the difference between a conversation and a wait.
  Future<VoiceReply> ask({
    required String message,
    required VoiceLanguage language,
    Map<String, dynamic> context = const {},
    List<Map<String, String>> history = const [],
  }) async {
    final res = await _api.post(
      '/api/voice/chat',
      // An LLM turn plus speech synthesis in one request; a provider failover
      // on either leg can outlast the default budget.
      timeout: const Duration(seconds: 60),
      body: {
        'message': message,
        'language': language.id,
        'context': context,
        'history': history,
      },
    );

    if (res is! Map) {
      throw FormatException('Unexpected voice-chat response: ${res.runtimeType}');
    }

    final text = (res['reply'] as String?)?.trim() ?? '';
    final b64 = res['audio_base64'] as String?;
    Uint8List? audio;
    if (b64 != null && b64.isNotEmpty) {
      try {
        audio = base64Decode(b64);
      } catch (e) {
        // Corrupt audio is not a failed turn — the text reply still stands.
        if (kDebugMode) debugPrint('[VOICE] could not decode audio: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('[VOICE] reply(${language.id}) audio=${audio?.length ?? 0}B '
          'voice_available=${res['voice_available']}');
    }

    return VoiceReply(
      text: text,
      language: VoiceLanguage.fromId(res['language'] as String?),
      audio: audio,
      voiceError: res['voice_error'] as String?,
    );
  }

  /// Transcribes a recorded clip via `/api/voice/stt`.
  ///
  /// An empty string is a legitimate result (the athlete said nothing), not an
  /// error — the caller decides whether to re-prompt.
  Future<String> transcribe({
    required Uint8List audio,
    required VoiceLanguage language,
    String filename = 'speech.m4a',
  }) async {
    final res = await _api.postMultipartBytes(
      '/api/voice/stt',
      fields: {'language': language.id},
      fileField: 'audio',
      fileName: filename,
      fileBytes: audio,
      timeout: const Duration(seconds: 45),
    );
    if (res is Map && res['text'] is String) {
      final text = (res['text'] as String).trim();
      if (kDebugMode) debugPrint('[VOICE] transcript: ${text.isEmpty ? '(silence)' : text}');
      return text;
    }
    throw FormatException('Unexpected stt response: ${res.runtimeType}');
  }

  /// Synthesizes arbitrary text without a conversational turn — used to give
  /// the device-TTS fallback a chance at ElevenLabs quality when only the
  /// chat leg failed.
  Future<Uint8List?> synthesize({
    required String text,
    required VoiceLanguage language,
  }) async {
    try {
      final bytes = await _api.postForBytes(
        '/api/voice/tts',
        body: {'text': text, 'language': language.id},
        timeout: const Duration(seconds: 45),
      );
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] tts unavailable: $e');
      return null;
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────

  /// Speaks a reply, preferring Zino's real voice and falling back to the
  /// device engine so the athlete is never left in silence.
  Future<void> speak(VoiceReply reply) async {
    if (_disposed) return;
    _lastText = reply.text;
    _lastLanguage = reply.language;

    if (reply.hasAudio) {
      _lastAudio = reply.audio;
      await _playBytes(reply.audio!);
      return;
    }

    _lastAudio = null;
    if (kDebugMode) {
      debugPrint('[VOICE] falling back to device voice '
          '(${reply.voiceError ?? 'no audio returned'})');
    }
    await _speakOnDevice(reply.text, reply.language);
  }

  Future<void> _playBytes(Uint8List bytes) async {
    _wirePlayer();
    lastSource = VoiceSource.elevenLabs;
    playbackState = VoicePlaybackState.playing;
    await _player.stop();
    await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
  }

  Future<void> _speakOnDevice(String text, VoiceLanguage language) async {
    if (text.trim().isEmpty) return;
    lastSource = VoiceSource.device;
    playbackState = VoicePlaybackState.playing;
    try {
      if (!_deviceTtsReady) {
        // Awaiting completion is what makes onSpeechComplete meaningful for
        // the device path too — otherwise `speak` returns instantly and the
        // call screen would flip back to "listening" mid-sentence.
        await _deviceTts.awaitSpeakCompletion(true);
        _deviceTtsReady = true;
      }
      await _deviceTts.setLanguage(language.localeId);
      await _deviceTts.setSpeechRate(0.5); // ~natural on Android
      await _deviceTts.setPitch(1.0);
      await _deviceTts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE] device tts failed: $e');
    } finally {
      playbackState = VoicePlaybackState.idle;
      if (!_completion.isClosed) _completion.add(null);
    }
  }

  Future<void> pause() async {
    if (playbackState != VoicePlaybackState.playing) return;
    if (lastSource == VoiceSource.elevenLabs) {
      await _player.pause();
    } else {
      // Device engines can't resume mid-utterance; stopping and replaying is
      // the only honest option, so pause behaves as stop for that path.
      await _deviceTts.stop();
    }
    playbackState = VoicePlaybackState.paused;
  }

  Future<void> resume() async {
    if (playbackState != VoicePlaybackState.paused) return;
    if (lastSource == VoiceSource.elevenLabs) {
      await _player.resume();
      playbackState = VoicePlaybackState.playing;
    } else {
      await replay();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    try {
      await _deviceTts.stop();
    } catch (_) {
      // Nothing to stop.
    }
    playbackState = VoicePlaybackState.idle;
  }

  /// Repeats the last line. Reuses the cached clip when there is one, so a
  /// replay costs neither quota nor latency.
  Future<void> replay() async {
    if (_disposed) return;
    final audio = _lastAudio;
    if (audio != null && audio.isNotEmpty) {
      await _playBytes(audio);
      return;
    }
    final text = _lastText;
    if (text == null || text.isEmpty) return;
    await _speakOnDevice(text, _lastLanguage);
  }

  /// Mute/unmute without stopping — the clip keeps advancing so unmuting
  /// rejoins the conversation where it actually is, rather than replaying.
  Future<void> setMuted(bool muted) async {
    await _player.setVolume(muted ? 0 : 1);
    try {
      await _deviceTts.setVolume(muted ? 0 : 1);
    } catch (_) {
      // Not fatal — the ElevenLabs path is already muted.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _playerCompleteSub?.cancel();
    await _player.stop();
    await _player.dispose();
    try {
      await _deviceTts.stop();
    } catch (_) {
      // Best effort during teardown.
    }
    await _completion.close();
  }
}
