import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/voice/voice_language.dart';
import '../../../core/voice/voice_recorder.dart';
import '../../../core/voice/voice_service.dart';
import '../data/zino_context_builder.dart';

/// Where the call is in its cycle. Drives every animation and label on the
/// call screen, so the athlete always knows whether Zino is hearing them,
/// thinking, or talking.
enum ZinoCallState {
  /// Connecting / warming up.
  connecting,

  /// Mic open, capturing the athlete.
  listening,

  /// Transcribing + waiting on Zino's reply.
  thinking,

  /// Playing Zino's answer.
  speaking,

  /// Between turns — tap to talk again.
  idle,

  /// Something failed; [ZinoCallController.errorMessage] explains it and the
  /// athlete can retry without losing the call.
  error,
}

/// One line of the call transcript.
@immutable
class CallTurn {
  const CallTurn({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

/// Runs a voice conversation with Zino.
///
/// PHASE 1 SCOPE — plumbing only. This drives mic → transcript → existing Zino
/// brain → speech, and nothing else. It deliberately does NOT run an
/// assessment script, set goals, or generate diet/workout plans; those are
/// Phase 2 and would need their own explicit flows.
class ZinoCallController extends ChangeNotifier {
  ZinoCallController({
    required this.uid,
    required this.athleteName,
    required VoiceLanguage language,
    required VoiceService voice,
    required VoiceRecorder recorder,
    ZinoContextBuilder? contextBuilder,
  })  : _voice = voice,
        _recorder = recorder,
        _contextBuilder = contextBuilder,
        _language = language;

  final String uid;
  final String athleteName;
  final VoiceService _voice;
  final VoiceRecorder _recorder;
  final ZinoContextBuilder? _contextBuilder;

  VoiceLanguage _language;
  VoiceLanguage get language => _language;

  ZinoCallState state = ZinoCallState.connecting;
  String? errorMessage;
  bool muted = false;
  bool speakerOn = true;

  /// Running transcript, newest last. Kept in memory only — a voice call is
  /// ephemeral, and persisting it would silently duplicate the text chat's
  /// history under a second key.
  final List<CallTurn> transcript = [];

  /// Elapsed call time, for the duration readout.
  Duration elapsed = Duration.zero;
  Timer? _ticker;
  StreamSubscription<void>? _speechDone;

  bool _disposed = false;
  bool get isBusy => state == ZinoCallState.thinking || state == ZinoCallState.speaking;

  /// True when Zino's real ElevenLabs voice is in use; false means the device
  /// fallback is speaking. Surfaced so the UI never implies premium audio it
  /// isn't actually delivering.
  bool get usingZinoVoice => _voice.lastSource == VoiceSource.elevenLabs;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  Future<void> start() async {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      _notify();
    });
    _speechDone = _voice.onSpeechComplete.listen((_) {
      if (_disposed) return;
      if (state == ZinoCallState.speaking) {
        state = ZinoCallState.idle;
        _notify();
      }
    });

    if (!await _recorder.hasPermission()) {
      _fail('I need microphone access to hear you. '
          'Enable it in Settings, then tap to try again.');
      return;
    }

    state = ZinoCallState.idle;
    _notify();

    // Zino opens the call — a companion that waits in silence for the athlete
    // to speak first feels like a voicemail box, not a conversation.
    await _greet();
  }

  Future<void> _greet() async {
    final first = athleteName.trim().split(' ').first;
    final greeting = switch (_language) {
      VoiceLanguage.english => "Hey ${first.isEmpty ? 'there' : first}! Zino here. What's up?",
      VoiceLanguage.hindi => 'नमस्ते ${first.isEmpty ? '' : first}! मैं ज़ीनो हूँ। बताइए, कैसे हैं आप?',
      VoiceLanguage.hinglish =>
        "Hey ${first.isEmpty ? '' : first}! Zino here. Bolo, kya haal hai?",
    };
    transcript.add(CallTurn(text: greeting, isUser: false));
    state = ZinoCallState.speaking;
    _notify();

    // Spoken locally rather than through /voice/chat: a fixed greeting needs
    // no LLM turn, and skipping it gets Zino talking a second sooner.
    final audio = await _voice.synthesize(text: greeting, language: _language);
    await _voice.speak(VoiceReply(
      text: greeting,
      language: _language,
      audio: audio,
    ));
    if (_disposed) return;
    if (state == ZinoCallState.speaking) {
      state = ZinoCallState.idle;
      _notify();
    }
  }

  // ── Turn taking ────────────────────────────────────────────────────────

  /// Opens the mic. No-op while Zino is mid-sentence, so the two never talk
  /// over each other.
  Future<void> startListening() async {
    if (_disposed || isBusy) return;
    await _voice.stop();
    final ok = await _recorder.start();
    if (!ok) {
      _fail("I couldn't reach the microphone. Check permissions and try again.");
      return;
    }
    errorMessage = null;
    state = ZinoCallState.listening;
    _notify();
  }

  /// Closes the mic and runs the turn: transcribe → Zino → speak.
  Future<void> stopAndSend() async {
    if (_disposed || state != ZinoCallState.listening) return;
    state = ZinoCallState.thinking;
    _notify();

    final clip = await _recorder.stopAndRead();
    if (clip == null) {
      // Silence isn't an error — just go back to waiting.
      state = ZinoCallState.idle;
      _notify();
      return;
    }

    try {
      // Trimmed here rather than relying on the transport to have done it —
      // a whitespace-only transcript is silence, and sending it would spend a
      // real LLM turn asking Zino to respond to nothing.
      final said = (await _voice.transcribe(audio: clip, language: _language)).trim();
      if (_disposed) return;
      if (said.isEmpty) {
        state = ZinoCallState.idle;
        _notify();
        return;
      }
      transcript.add(CallTurn(text: said, isUser: true));
      _notify();
      await _respondTo(said);
    } on ApiException catch (e) {
      _fail(_friendly(e));
    } catch (e) {
      if (kDebugMode) debugPrint('[VOICE CALL] turn failed: $e');
      _fail("Something went wrong on my end. Tap to try again.");
    }
  }

  Future<void> _respondTo(String message) async {
    final context = await _buildContext();
    if (_disposed) return;

    final reply = await _voice.ask(
      message: message,
      language: _language,
      context: context,
      history: [
        for (final t in transcript.take(transcript.length - 1))
          {'role': t.isUser ? 'user' : 'zino', 'text': t.text},
      ],
    );
    if (_disposed) return;

    transcript.add(CallTurn(text: reply.text, isUser: false));
    state = ZinoCallState.speaking;
    errorMessage = null;
    _notify();

    await _voice.speak(reply);
    if (_disposed) return;
    if (state == ZinoCallState.speaking && _voice.playbackState == VoicePlaybackState.idle) {
      state = ZinoCallState.idle;
      _notify();
    }
  }

  /// The same athlete snapshot the text chat sends, so a spoken question gets
  /// the same grounded answer a typed one would.
  Future<Map<String, dynamic>> _buildContext() async {
    final builder = _contextBuilder;
    if (builder == null) return const {};
    try {
      return await builder.build(uid: uid, athleteName: athleteName);
    } catch (e) {
      // Thin context still produces a useful reply; a failed read must not
      // drop the call.
      if (kDebugMode) debugPrint('[VOICE CALL] context unavailable: $e');
      return const {};
    }
  }

  /// Re-runs the last athlete turn after a failure.
  Future<void> retry() async {
    if (_disposed) return;
    final lastUser = transcript.lastWhere((t) => t.isUser, orElse: () => const CallTurn(text: '', isUser: true));
    errorMessage = null;
    if (lastUser.text.isEmpty) {
      state = ZinoCallState.idle;
      _notify();
      return;
    }
    state = ZinoCallState.thinking;
    _notify();
    try {
      await _respondTo(lastUser.text);
    } on ApiException catch (e) {
      _fail(_friendly(e));
    } catch (_) {
      _fail("Still having trouble. Check your connection?");
    }
  }

  Future<void> replayLast() async {
    if (_disposed) return;
    state = ZinoCallState.speaking;
    _notify();
    await _voice.replay();
  }

  // ── Controls ───────────────────────────────────────────────────────────

  Future<void> toggleMute() async {
    muted = !muted;
    await _voice.setMuted(muted);
    _notify();
  }

  void toggleSpeaker() {
    // Routing to the earpiece needs a native audio-session change that
    // `audioplayers` doesn't expose; the toggle currently reflects intent
    // only, and is left visible because the call UI would feel broken without
    // it. Wiring real routing is a Phase 2 item.
    speakerOn = !speakerOn;
    _notify();
  }

  Future<void> setLanguage(VoiceLanguage language) async {
    _language = language;
    _notify();
  }

  Future<void> endCall() async {
    await _voice.stop();
    await _recorder.cancel();
    _ticker?.cancel();
    _ticker = null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _fail(String message) {
    if (_disposed) return;
    errorMessage = message;
    state = ZinoCallState.error;
    _notify();
  }

  static String _friendly(ApiException e) {
    if (e.isNetworkError) return "I can't reach the internet right now. Check your connection?";
    if (e.statusCode == 503) return "My voice is taking a quick break. Try again in a moment?";
    return "Something went wrong on my end. Tap to try again.";
  }

  String get durationLabel {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get statusLabel => switch (state) {
        ZinoCallState.connecting => 'Connecting…',
        ZinoCallState.listening => 'Listening…',
        ZinoCallState.thinking => 'Thinking…',
        ZinoCallState.speaking => 'Speaking',
        ZinoCallState.idle => 'Tap to talk',
        ZinoCallState.error => 'Tap to retry',
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_speechDone?.cancel());
    unawaited(_voice.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
