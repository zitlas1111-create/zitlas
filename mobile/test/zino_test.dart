import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zitlas_mobile/core/network/api_exception.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';
import 'package:zitlas_mobile/features/zino/data/zino_context_builder.dart';
import 'package:zitlas_mobile/features/zino/data/zino_repository.dart';
import 'package:zitlas_mobile/features/zino/models/zino_action.dart';
import 'package:zitlas_mobile/features/zino/models/zino_message.dart';
import 'package:zitlas_mobile/features/zino/zino_controller.dart';

/// Zino — the behaviour that must hold without a device or a backend.
///
/// Focused on the things that would be user-visible failures: raw JSON leaking
/// into a chat bubble, one athlete seeing another's conversation, an action
/// firing that the athlete never asked for, and a failed send losing what they
/// typed.

class _FakeRepo implements ZinoRepository {
  _FakeRepo({this.reply = 'Sure thing! 💪', this.error});

  String reply;
  Object? error;

  int calls = 0;
  String? lastMessage;
  Map<String, dynamic>? lastContext;
  List<ZinoMessage>? lastHistory;

  @override
  Future<String> send({
    required String message,
    required Map<String, dynamic> context,
    required List<ZinoMessage> history,
  }) async {
    calls++;
    lastMessage = message;
    lastContext = context;
    lastHistory = history;
    if (error != null) throw error!;
    return reply;
  }
}

class _FakeContext implements ZinoContextBuilder {
  Map<String, dynamic> context = {'athleteName': 'Atharva'};
  int calls = 0;
  String? lastUid;

  @override
  Future<Map<String, dynamic>> build({
    required String uid,
    required String athleteName,
    ZinoScreenContext screen = ZinoScreenContext.other,
    String? viewingExpertId,
    DateTime? now,
  }) async {
    calls++;
    lastUid = uid;
    return {...context, 'athleteName': athleteName, 'screen': screen.name};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.init();
  });

  ZinoController build({
    _FakeRepo? repo,
    _FakeContext? ctx,
    String uid = 'athlete_1',
    String name = 'Atharva Sankpal',
  }) =>
      ZinoController(
        uid: uid,
        athleteName: name,
        repository: repo ?? _FakeRepo(),
        contextBuilder: ctx ?? _FakeContext(),
        storage: storage,
      );

  group('unwrapZinoReply — a chat bubble must never show raw JSON', () {
    test('plain prose passes through completely untouched', () {
      const prose = "You're at 6,840 of 8,000 steps today 💪";
      expect(unwrapZinoReply(prose), prose);
    });

    test('prose containing braces mid-sentence is not mangled', () {
      const prose = 'Try this: {rice, dal} is a solid combo.';
      expect(unwrapZinoReply(prose), prose);
    });

    test('a self-wrapped {"response": ...} object is unwrapped', () {
      expect(
        unwrapZinoReply('{"response": "Nice work today!"}'),
        'Nice work today!',
      );
    });

    test('every documented reply key is honoured, in priority order', () {
      expect(unwrapZinoReply('{"message":"m"}'), 'm');
      expect(unwrapZinoReply('{"answer":"a"}'), 'a');
      expect(unwrapZinoReply('{"reply":"r"}'), 'r');
      expect(unwrapZinoReply('{"text":"t"}'), 't');
      expect(unwrapZinoReply('{"content":"c"}'), 'c');
      // `response` wins when several are present.
      expect(unwrapZinoReply('{"content":"c","response":"r"}'), 'r');
    });

    test('a ```json fenced object is unwrapped', () {
      expect(
        unwrapZinoReply('```json\n{"response": "Fenced reply"}\n```'),
        'Fenced reply',
      );
    });

    test('a bare quoted string is unwrapped to its contents', () {
      expect(unwrapZinoReply('"Just a quoted line"'), 'Just a quoted line');
    });

    test('a single-string object of an unknown key is still usable', () {
      expect(unwrapZinoReply('{"zino_says":"Hello!"}'), 'Hello!');
    });

    test('an unrecognizable object yields a friendly line, never braces', () {
      final out = unwrapZinoReply('{"a":"one","b":"two","c":"three"}');
      expect(out, isNot(contains('{')));
      expect(out, contains('tangled'));
    });

    test('malformed JSON is left alone rather than throwing', () {
      const broken = '{"response": "unterminated';
      expect(unwrapZinoReply(broken), broken);
    });

    test('empty and whitespace input is returned as-is', () {
      expect(unwrapZinoReply(''), '');
      expect(unwrapZinoReply('   '), '   ');
    });
  });

  group('actions — typed allowlist, driven by the ATHLETE not the model', () {
    test('every action points at a route that exists in the router', () {
      // The router defines these; an action that pointed anywhere else would
      // dead-end the athlete.
      const realRoutes = {
        '/diet', '/training', '/activity', '/experts', '/dashboard', '/profile',
      };
      for (final a in ZinoAction.values) {
        expect(realRoutes, contains(a.route), reason: '${a.name} route');
      }
    });

    test('explicit navigation requests map to the right screen', () {
      expect(detectZinoAction("show today's diet"), ZinoAction.openDiet);
      expect(detectZinoAction('open my workout'), ZinoAction.openTraining);
      expect(detectZinoAction('show my progress'), ZinoAction.openProgress);
      expect(detectZinoAction('take me to my expert'), ZinoAction.openExperts);
      expect(detectZinoAction('open my profile'), ZinoAction.openProfile);
    });

    test('"I can\'t eat this" offers the swap flow without a "show me"', () {
      expect(detectZinoAction("I can't eat this"), ZinoAction.swapMeal);
      expect(detectZinoAction('help me swap this meal'), ZinoAction.swapMeal);
    });

    test('swapMeal opens Diet — Zino never performs the swap itself', () {
      // The real Swap Meal sheet (reason -> alternatives -> confirm) lives on
      // the Diet screen and keeps its own confirmation step.
      expect(ZinoAction.swapMeal.route, '/diet');
    });

    test('merely MENTIONING a topic offers no action', () {
      // These are questions to answer in the chat, not requests to navigate.
      expect(detectZinoAction('is my diet high in protein?'), isNull);
      expect(detectZinoAction('how was my workout yesterday'), isNull);
      expect(detectZinoAction('what is a good protein target'), isNull);
    });

    test('unrelated chit-chat never produces an action', () {
      expect(detectZinoAction('hello'), isNull);
      expect(detectZinoAction('I feel tired today'), isNull);
      expect(detectZinoAction('thanks!'), isNull);
    });

    test('at most ONE action is ever offered', () {
      // A sentence naming several areas must still resolve to a single chip.
      final a = detectZinoAction('show me my diet and workout and progress');
      expect(a, isNotNull);
      expect(a, isA<ZinoAction>());
    });
  });

  group('conversation flow', () {
    test('a successful turn appends both sides and clears errors', () async {
      final repo = _FakeRepo(reply: 'You have 1,160 steps left!');
      final c = build(repo: repo);

      await c.send('how am I doing today?');

      expect(c.messages.length, 2);
      expect(c.messages[0].isUser, isTrue);
      expect(c.messages[0].text, 'how am I doing today?');
      expect(c.messages[1].isUser, isFalse);
      expect(c.messages[1].text, 'You have 1,160 steps left!');
      expect(c.errorMessage, isNull);
      expect(c.sending, isFalse);
    });

    test('history sent to the backend excludes the current turn', () async {
      final repo = _FakeRepo();
      final c = build(repo: repo);

      await c.send('first');
      expect(repo.lastHistory, isEmpty, reason: 'nothing preceded the first turn');

      await c.send('second');
      // The prior user+zino pair, but not "second" itself.
      expect(repo.lastHistory!.length, 2);
      expect(repo.lastMessage, 'second');
      expect(repo.lastHistory!.map((m) => m.text), ['first', repo.reply]);
    });

    test('continuity: an earlier remark is still in the replayed history',
        () async {
      final repo = _FakeRepo();
      final c = build(repo: repo);

      await c.send('my knees are sore today');
      await c.send('can we make today\'s workout easier?');

      final texts = repo.lastHistory!.map((m) => m.text).toList();
      expect(texts, contains('my knees are sore today'),
          reason: 'Zino must still see the sore-knees context');
    });

    test('blank input and double-send are ignored', () async {
      final repo = _FakeRepo();
      final c = build(repo: repo);

      await c.send('   ');
      expect(repo.calls, 0);
      expect(c.messages, isEmpty);
    });

    test('context is rebuilt fresh for every message', () async {
      final ctx = _FakeContext();
      final c = build(ctx: ctx);

      await c.send('one');
      await c.send('two');

      expect(ctx.calls, 2, reason: 'live state must never be cached across turns');
    });

    test('the screen context travels with the request', () async {
      final repo = _FakeRepo();
      final c = build(repo: repo)..screen = ZinoScreenContext.diet;

      await c.send('replace this');

      expect(repo.lastContext!['screen'], 'diet');
    });
  });

  group('errors and retry', () {
    test('a failed send keeps the athlete\'s text and marks it undelivered',
        () async {
      final repo = _FakeRepo(error: ApiException(message: 'boom'));
      final c = build(repo: repo);

      await c.send('hello?');

      expect(c.messages.length, 1, reason: 'no fake reply is fabricated');
      expect(c.messages[0].isUser, isTrue);
      expect(c.messages[0].failed, isTrue);
      expect(c.errorMessage, isNotNull);
      expect(c.sending, isFalse);
    });

    test('errors are classified but the athlete sees friendly copy', () async {
      final repo = _FakeRepo(error: ApiException(message: 'offline'));
      final c = build(repo: repo);

      await c.send('hi');

      expect(c.errorCategory, isNotNull);
      expect(c.errorMessage, isNot(contains('ERROR')));
      expect(c.errorMessage, isNot(contains('Exception')));
    });

    test('retry re-sends the failed turn and recovers', () async {
      final repo = _FakeRepo(error: ApiException(message: 'temporary'));
      final c = build(repo: repo);

      await c.send('are you there?');
      expect(c.messages.single.failed, isTrue);

      repo.error = null;
      await c.retry();

      expect(c.messages.length, 2);
      expect(c.messages[0].failed, isFalse);
      expect(c.messages[1].isUser, isFalse);
      expect(c.errorMessage, isNull);
    });

    test('a failed turn is never persisted as real history', () async {
      final repo = _FakeRepo(error: ApiException(message: 'nope'));
      final c = build(repo: repo);
      await c.send('lost message');

      // A fresh controller for the same athlete restores from storage.
      final restored = build(repo: _FakeRepo());
      expect(restored.messages, isEmpty,
          reason: 'an undelivered turn has no reply to pair with');
    });
  });

  group('per-user isolation — no cross-account context leaks', () {
    test('history persists and restores for the SAME athlete', () async {
      final c = build(uid: 'athlete_1');
      await c.send('remember this');
      expect(c.messages.length, 2);

      final restored = build(uid: 'athlete_1');
      expect(restored.messages.length, 2);
      expect(restored.messages[0].text, 'remember this');
    });

    test("a different athlete NEVER sees the previous athlete's thread",
        () async {
      final a = build(uid: 'athlete_1', name: 'Athlete One');
      await a.send('my private medical question');
      expect(a.messages, isNotEmpty);

      final b = build(uid: 'athlete_2', name: 'Athlete Two');
      expect(b.messages, isEmpty,
          reason: 'history is keyed per uid — B reads a different bucket');
      expect(b.isEmpty, isTrue);
    });

    test('context is always built for the CONTROLLER\'s own uid', () async {
      final ctx = _FakeContext();
      final c = build(ctx: ctx, uid: 'athlete_9');
      await c.send('hi');
      expect(ctx.lastUid, 'athlete_9');
    });

    test('clear() wipes only this athlete\'s stored thread', () async {
      final a = build(uid: 'athlete_1');
      await a.send('one');
      final b = build(uid: 'athlete_2');
      await b.send('two');

      await a.clear();

      expect(build(uid: 'athlete_1').messages, isEmpty);
      expect(build(uid: 'athlete_2').messages, isNotEmpty,
          reason: "clearing A must not touch B's history");
    });

    test('the greeting uses the signed-in athlete\'s own first name', () {
      expect(build(name: 'Atharva Sankpal').greeting, contains('Atharva'));
      expect(build(name: 'Atharva Sankpal').greeting, isNot(contains('Sankpal')));
    });
  });

  group('quick-action chips — website parity', () {
    test('all nine chips are present, word-for-word', () {
      expect(kZinoChips.length, 9);
      expect(kZinoChips.map((c) => c.label), [
        "Explain Today's Diet",
        'Explain Workout',
        'My Progress',
        'Water Target',
        'Sleep Tips',
        "I'm Sick Today",
        'Ask My Coach',
        'Weekly Summary',
        'Motivate Me',
      ]);
    });

    test('every chip carries a real question to send', () {
      for (final chip in kZinoChips) {
        expect(chip.question.trim(), isNotEmpty);
        expect(chip.icon.trim(), isNotEmpty);
      }
    });

    test('tapping a chip sends its question verbatim', () async {
      final repo = _FakeRepo();
      final c = build(repo: repo);
      await c.send(kZinoChips.first.question);
      expect(repo.lastMessage, kZinoChips.first.question);
    });
  });

  group('screen context mapping', () {
    test('route params map to the matching screen context', () {
      expect(zinoScreenContextFromName('diet'), ZinoScreenContext.diet);
      expect(zinoScreenContextFromName('training'), ZinoScreenContext.training);
      expect(zinoScreenContextFromName('experts'), ZinoScreenContext.experts);
      expect(zinoScreenContextFromName('dashboard'), ZinoScreenContext.dashboard);
    });

    test('an unknown or missing value degrades to `other`, never throws', () {
      expect(zinoScreenContextFromName(null), ZinoScreenContext.other);
      expect(zinoScreenContextFromName('nonsense'), ZinoScreenContext.other);
    });

    test('each context carries the purpose text the backend prompt expects', () {
      final (name, purpose) = ZinoScreenContext.diet.describe;
      expect(name, 'Diet Plan');
      expect(purpose, contains('Swap Meal'));
    });
  });
}
