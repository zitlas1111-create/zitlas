import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zitlas_mobile/core/network/api_exception.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';
import 'package:zitlas_mobile/core/voice/voice_language.dart';
import 'package:zitlas_mobile/core/voice/voice_language_store.dart';
import 'package:zitlas_mobile/core/voice/voice_recorder.dart';
import 'package:zitlas_mobile/core/voice/voice_service.dart';
import 'package:zitlas_mobile/features/zino/voice/zino_call_controller.dart';

/// Voice infrastructure (Phase 1).
///
/// The behaviours that would be user-visible failures on a call: the wrong
/// language reaching the backend, a silent app when ElevenLabs is unavailable,
/// a call that gets stuck in one state, and one athlete's language preference
/// leaking to another account.

class _FakeVoice implements VoiceService {
  _FakeVoice({this.reply = 'Sure thing!', this.audio, this.error});

  String reply;
  Uint8List? audio;
  Object? error;

  int askCalls = 0;
  int speakCalls = 0;
  int replayCalls = 0;
  int stopCalls = 0;
  bool disposed = false;
  bool? mutedTo;
  String? lastMessage;
  VoiceLanguage? lastLanguage;
  Map<String, dynamic>? lastContext;
  String transcriptResult = 'hello zino';

  @override
  VoiceSource lastSource = VoiceSource.none;

  @override
  VoicePlaybackState playbackState = VoicePlaybackState.idle;

  @override
  Stream<void> get onSpeechComplete => const Stream.empty();

  @override
  Future<VoiceReply> ask({
    required String message,
    required VoiceLanguage language,
    Map<String, dynamic> context = const {},
    List<Map<String, String>> history = const [],
  }) async {
    askCalls++;
    lastMessage = message;
    lastLanguage = language;
    lastContext = context;
    if (error != null) throw error!;
    return VoiceReply(text: reply, language: language, audio: audio);
  }

  @override
  Future<String> transcribe({
    required Uint8List audio,
    required VoiceLanguage language,
    String filename = 'speech.m4a',
  }) async {
    if (error != null) throw error!;
    return transcriptResult;
  }

  @override
  Future<Uint8List?> synthesize({
    required String text,
    required VoiceLanguage language,
  }) async =>
      audio;

  @override
  Future<void> speak(VoiceReply reply) async {
    speakCalls++;
    lastSource = reply.hasAudio ? VoiceSource.elevenLabs : VoiceSource.device;
  }

  @override
  Future<void> replay() async => replayCalls++;

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> setMuted(bool muted) async => mutedTo = muted;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRecorder implements VoiceRecorder {
  _FakeRecorder({this.permission = true, this.clip});

  bool permission;
  Uint8List? clip;
  bool started = false;
  bool cancelled = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> get isRecording async => started;

  @override
  Future<bool> start() async {
    if (!permission) return false;
    started = true;
    return true;
  }

  @override
  Future<Uint8List?> stopAndRead() async {
    started = false;
    return clip;
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;
  late FakeFirebaseFirestore db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.init();
    db = FakeFirebaseFirestore();
  });

  ZinoCallController buildCall({
    _FakeVoice? voice,
    _FakeRecorder? recorder,
    VoiceLanguage language = VoiceLanguage.hinglish,
  }) =>
      ZinoCallController(
        uid: 'athlete_1',
        athleteName: 'Atharva Sankpal',
        language: language,
        voice: voice ?? _FakeVoice(),
        recorder: recorder ?? _FakeRecorder(clip: Uint8List.fromList(List.filled(4096, 1))),
      );

  group('VoiceLanguage', () {
    test('ids match the backend contract exactly', () {
      // backend/services/voice_service.py SUPPORTED_LANGUAGES
      expect(VoiceLanguage.values.map((l) => l.id), ['english', 'hindi', 'hinglish']);
    });

    test('Hinglish is the recommended default', () {
      expect(VoiceLanguage.fallback, VoiceLanguage.hinglish);
      expect(VoiceLanguage.hinglish.recommended, isTrue);
      expect(VoiceLanguage.english.recommended, isFalse);
      expect(VoiceLanguage.hindi.recommended, isFalse);
    });

    test('parsing is case-insensitive and never throws on bad input', () {
      expect(VoiceLanguage.fromId('ENGLISH'), VoiceLanguage.english);
      expect(VoiceLanguage.fromId(' hindi '), VoiceLanguage.hindi);
      expect(VoiceLanguage.fromId('klingon'), VoiceLanguage.fallback);
      expect(VoiceLanguage.fromId(null), VoiceLanguage.fallback);
      expect(VoiceLanguage.fromId(''), VoiceLanguage.fallback);
    });

    test('every language carries a device locale for the fallback voice', () {
      for (final l in VoiceLanguage.values) {
        expect(l.localeId, isNotEmpty, reason: l.id);
        expect(l.localeId, contains('-'), reason: '${l.id} must be a BCP-47 tag');
      }
    });
  });

  group('VoiceLanguageStore — account-level, like every other preference', () {
    test('an athlete who never chose reports null so the picker can show', () async {
      await db.collection('users').doc('u1').set({'name': 'Test'});
      final result = await VoiceLanguageStore(firestore: db, storage: storage).load('u1');
      expect(result.language, isNull);
      expect(result.known, isTrue, reason: 'the read succeeded — they truly never chose');
    });

    test('a stored choice is returned and never re-asked', () async {
      final store = VoiceLanguageStore(firestore: db, storage: storage);
      await store.save('u1', VoiceLanguage.hindi);

      final reloaded = await store.load('u1');
      expect(reloaded.language, VoiceLanguage.hindi);
      expect(reloaded.known, isTrue);
    });

    test('the choice survives a cleared local cache (reinstall)', () async {
      await VoiceLanguageStore(firestore: db, storage: storage)
          .save('u1', VoiceLanguage.english);

      // Simulate a reinstall: the local cache is gone, Firestore is not.
      SharedPreferences.setMockInitialValues({});
      final freshStorage = await LocalStorageService.init();

      final result =
          await VoiceLanguageStore(firestore: db, storage: freshStorage).load('u1');
      expect(result.language, VoiceLanguage.english,
          reason: 'account-level, not install-level');
    });

    test('a failed read reports known:false so we do NOT overwrite a real choice',
        () async {
      final store = VoiceLanguageStore(firestore: _ThrowingFirestore(), storage: storage);
      final result = await store.load('u1');
      expect(result.language, isNull);
      expect(result.known, isFalse,
          reason: 'null-because-offline must be distinguishable from never-chose');
    });

    test('a failed cloud write still keeps the choice locally', () async {
      final store = VoiceLanguageStore(firestore: _ThrowingFirestore(), storage: storage);
      await store.save('u1', VoiceLanguage.hindi); // must not throw
      final result = await store.load('u1');
      expect(result.language, VoiceLanguage.hindi);
    });

    test('two accounts on one phone keep separate languages', () async {
      final store = VoiceLanguageStore(firestore: db, storage: storage);
      await store.save('user_a', VoiceLanguage.hindi);
      await store.save('user_b', VoiceLanguage.english);

      expect((await store.load('user_a')).language, VoiceLanguage.hindi);
      expect((await store.load('user_b')).language, VoiceLanguage.english);
    });

    test('writes to the ONE canonical field, merging the rest of the profile',
        () async {
      await db.collection('users').doc('u1').set({'name': 'Atharva'});
      await VoiceLanguageStore(firestore: db, storage: storage)
          .save('u1', VoiceLanguage.hinglish);

      final data = (await db.collection('users').doc('u1').get()).data()!;
      expect(data[VoiceLanguageStore.fieldName], 'hinglish');
      expect(data['name'], 'Atharva', reason: 'must not clobber the profile');
    });
  });

  group('call state machine', () {
    test('a missing microphone permission fails clearly, without crashing',
        () async {
      final c = buildCall(recorder: _FakeRecorder(permission: false));
      await c.start();

      expect(c.state, ZinoCallState.error);
      expect(c.errorMessage, contains('microphone'));
    });

    test('a granted mic opens the call and Zino greets first', () async {
      final voice = _FakeVoice();
      final c = buildCall(voice: voice);
      await c.start();

      expect(c.transcript, isNotEmpty);
      expect(c.transcript.first.isUser, isFalse,
          reason: 'Zino opens — waiting in silence feels like voicemail');
      expect(voice.speakCalls, 1);
    });

    test('the greeting is in the chosen language', () async {
      final hindi = buildCall(language: VoiceLanguage.hindi);
      await hindi.start();
      expect(hindi.transcript.first.text, contains('ज़ीनो'));

      final hinglish = buildCall(language: VoiceLanguage.hinglish);
      await hinglish.start();
      expect(hinglish.transcript.first.text, contains('kya haal hai'));
    });

    test('a full turn runs listening -> thinking -> speaking', () async {
      final voice = _FakeVoice(reply: 'You have 1,160 steps left!');
      final c = buildCall(voice: voice);
      await c.start();

      await c.startListening();
      expect(c.state, ZinoCallState.listening);

      await c.stopAndSend();

      expect(voice.askCalls, 1);
      expect(c.transcript.any((t) => t.isUser && t.text == 'hello zino'), isTrue);
      expect(c.transcript.last.text, 'You have 1,160 steps left!');
      expect(c.transcript.last.isUser, isFalse);
    });

    test('the chosen language is what actually reaches the backend', () async {
      final voice = _FakeVoice();
      final c = buildCall(voice: voice, language: VoiceLanguage.hindi);
      await c.start();
      await c.startListening();
      await c.stopAndSend();

      expect(voice.lastLanguage, VoiceLanguage.hindi);
    });

    test('silence is not an error — it just returns to idle', () async {
      final c = buildCall(recorder: _FakeRecorder(clip: null));
      await c.start();
      await c.startListening();
      await c.stopAndSend();

      expect(c.state, ZinoCallState.idle);
      expect(c.errorMessage, isNull);
      expect(c.transcript.where((t) => t.isUser), isEmpty);
    });

    test('an empty transcript also returns to idle without a turn', () async {
      final voice = _FakeVoice()..transcriptResult = '   ';
      final c = buildCall(voice: voice);
      await c.start();
      await c.startListening();
      await c.stopAndSend();

      expect(voice.askCalls, 0, reason: 'no point asking Zino about nothing');
      expect(c.state, ZinoCallState.idle);
    });

    test('Zino and the athlete never talk over each other', () async {
      final voice = _FakeVoice();
      final c = buildCall(voice: voice);
      await c.start();

      // Force the busy state, then try to open the mic.
      await c.startListening();
      await c.stopAndSend();
      final callsBefore = voice.askCalls;

      c.state = ZinoCallState.speaking;
      await c.startListening();
      expect(c.state, ZinoCallState.speaking, reason: 'mic must not open mid-sentence');
      expect(voice.askCalls, callsBefore);
    });
  });

  group('graceful degradation', () {
    test('no ElevenLabs audio still speaks — via the device voice', () async {
      // The exact production situation when the ElevenLabs plan has no quota.
      final voice = _FakeVoice(audio: null);
      final c = buildCall(voice: voice);
      await c.start();
      await c.startListening();
      await c.stopAndSend();

      expect(voice.speakCalls, greaterThan(0));
      expect(voice.lastSource, VoiceSource.device);
      expect(c.usingZinoVoice, isFalse, reason: 'the UI must not claim the premium voice');
      expect(c.transcript.last.isUser, isFalse, reason: 'the athlete still got an answer');
    });

    test('with ElevenLabs audio, the premium voice is reported', () async {
      final voice = _FakeVoice(audio: Uint8List.fromList([1, 2, 3]));
      final c = buildCall(voice: voice);
      await c.start();

      expect(voice.lastSource, VoiceSource.elevenLabs);
      expect(c.usingZinoVoice, isTrue);
    });

    test('a network failure surfaces friendly copy, not an exception', () async {
      final voice = _FakeVoice(error: const ApiException(message: 'offline'));
      final c = buildCall(voice: voice);
      await c.start();
      await c.startListening();
      await c.stopAndSend();

      expect(c.state, ZinoCallState.error);
      expect(c.errorMessage, isNotNull);
      expect(c.errorMessage, isNot(contains('Exception')));
      expect(c.errorMessage, contains('internet'));
    });

    test('a provider outage (503) gets its own message', () async {
      final voice = _FakeVoice(error: const ApiException(message: 'down', statusCode: 503));
      final c = buildCall(voice: voice);
      await c.start();
      await c.startListening();
      await c.stopAndSend();

      expect(c.errorMessage, contains('voice'));
    });

    test('retry re-runs the last turn and recovers', () async {
      final voice = _FakeVoice(error: const ApiException(message: 'temporary'));
      final c = buildCall(voice: voice);
      await c.start();
      await c.startListening();
      await c.stopAndSend();
      expect(c.state, ZinoCallState.error);

      voice.error = null;
      await c.retry();

      expect(c.errorMessage, isNull);
      expect(c.transcript.last.isUser, isFalse);
    });
  });

  group('controls', () {
    test('mute toggles and reaches the audio layer', () async {
      final voice = _FakeVoice();
      final c = buildCall(voice: voice);
      expect(c.muted, isFalse);

      await c.toggleMute();
      expect(c.muted, isTrue);
      expect(voice.mutedTo, isTrue);

      await c.toggleMute();
      expect(c.muted, isFalse);
      expect(voice.mutedTo, isFalse);
    });

    test('replay repeats the last line without another backend turn', () async {
      final voice = _FakeVoice();
      final c = buildCall(voice: voice);
      await c.start();
      await c.startListening();
      await c.stopAndSend();
      final asks = voice.askCalls;

      await c.replayLast();

      expect(voice.replayCalls, 1);
      expect(voice.askCalls, asks, reason: 'replay must not spend quota');
    });

    test('ending the call stops audio and releases the mic', () async {
      final voice = _FakeVoice();
      final recorder = _FakeRecorder(clip: Uint8List.fromList(List.filled(4096, 1)));
      final c = buildCall(voice: voice, recorder: recorder);
      await c.start();

      await c.endCall();

      expect(voice.stopCalls, greaterThan(0));
      expect(recorder.cancelled, isTrue);
    });

    test('disposing releases every resource', () async {
      final voice = _FakeVoice();
      final recorder = _FakeRecorder();
      final c = buildCall(voice: voice, recorder: recorder);
      await c.start();

      c.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(voice.disposed, isTrue);
      expect(recorder.disposed, isTrue);
    });

    test('the duration label is zero-padded mm:ss', () {
      final c = buildCall();
      expect(c.durationLabel, '00:00');
      c.elapsed = const Duration(seconds: 65);
      expect(c.durationLabel, '01:05');
      c.elapsed = const Duration(minutes: 12, seconds: 7);
      expect(c.durationLabel, '12:07');
    });

    test('every state has a human status label', () {
      final c = buildCall();
      for (final s in ZinoCallState.values) {
        c.state = s;
        expect(c.statusLabel.trim(), isNotEmpty, reason: s.name);
      }
    });
  });
}

/// Firestore that always fails — offline / permission-denied / timeout.
class _ThrowingFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw FirebaseException(plugin: 'test', message: 'network unavailable');
}
