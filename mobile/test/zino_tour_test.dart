import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';
import 'package:zitlas_mobile/features/zino/tour/zino_tour_controller.dart';
import 'package:zitlas_mobile/features/zino/tour/zino_tour_stops.dart';
import 'package:zitlas_mobile/features/zino/tour/zino_tour_store.dart';

/// Zino first-run tour.
///
/// The rule that matters most and is easiest to get wrong: the tour is
/// ACCOUNT-level, not install-level. An existing athlete must never be
/// onboarded again just because the app was migrated to Flutter, reinstalled,
/// or logged out and back in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late LocalStorageService storage;

  setUp(() async {
    db = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.init();
  });

  ZinoTourStore store() => ZinoTourStore(firestore: db, storage: storage);

  ZinoTourController controller({String uid = 'new_user', bool hasCoach = false}) =>
      ZinoTourController(uid: uid, store: store(), hasActiveCoach: hasCoach);

  Future<void> seedUser(String uid, {Object? completed}) async {
    await db.collection('users').doc(uid).set({
      'name': 'Test',
      ZinoTourStore.fieldName: ?completed,
    });
  }

  group('who sees the tour', () {
    test('CASE 1 — a brand-new account gets the tour', () async {
      await seedUser('new_user');
      expect(await store().shouldAutoStart('new_user'), isTrue);
    });

    test('an account with no user doc at all still counts as new', () async {
      // Signup can land on the dashboard before the profile doc is written.
      expect(await store().shouldAutoStart('never_seen'), isTrue);
    });

    test('CASE 2/3 — after finishing OR skipping, it never auto-starts again',
        () async {
      for (final finishBySkipping in [false, true]) {
        final uid = 'user_$finishBySkipping';
        await seedUser(uid);
        final c = ZinoTourController(uid: uid, store: store());
        expect(await c.startIfNewUser(), isTrue);

        if (finishBySkipping) {
          await c.skip();
        } else {
          await c.finish();
        }

        // A fresh store instance = a later launch / a new login session.
        expect(await store().shouldAutoStart(uid), isFalse,
            reason: finishBySkipping
                ? 'skipping counts as completing'
                : 'finishing counts as completing');
      }
    });

    test('CASE 4 — an existing website athlete is NEVER re-toured', () async {
      // The website writes the STRING 'true' via ZitlasCloudSync.
      await seedUser('web_veteran', completed: 'true');
      expect(await store().shouldAutoStart('web_veteran'), isFalse);
    });

    test('a boolean true is also honoured, not just the string', () async {
      await seedUser('bool_user', completed: true);
      expect(await store().shouldAutoStart('bool_user'), isFalse);
    });

    test('CASE 5 — a reinstall (empty local cache) does not re-tour', () async {
      await seedUser('reinstaller', completed: 'true');
      // Fresh SharedPreferences == a reinstalled app with no local state.
      SharedPreferences.setMockInitialValues({});
      final freshStorage = await LocalStorageService.init();
      final s = ZinoTourStore(firestore: db, storage: freshStorage);
      expect(await s.shouldAutoStart('reinstaller'), isFalse,
          reason: 'account state, not install state, decides');
    });

    test('CASE 6/7 — status is per-account on a shared phone', () async {
      await seedUser('account_a');
      await seedUser('account_b');

      final a = ZinoTourController(uid: 'account_a', store: store());
      expect(await a.startIfNewUser(), isTrue);
      await a.finish();

      expect(await store().shouldAutoStart('account_a'), isFalse);
      expect(await store().shouldAutoStart('account_b'), isTrue,
          reason: "B is a different account and has never been toured");
    });

    test('completion is written to the ONE canonical shared field', () async {
      await seedUser('writer');
      await store().markCompleted('writer');

      final doc = await db.collection('users').doc('writer').get();
      expect(doc.data()![ZinoTourStore.fieldName], 'true',
          reason: 'string form keeps the website and app interoperable');
      expect(ZinoTourStore.fieldName, 'zinoTourCompleted');
    });

    test('completion merges — it never clobbers the rest of the profile',
        () async {
      await db.collection('users').doc('merger').set({
        'name': 'Atharva',
        'goal': {'type': 'weight_loss'},
      });
      await store().markCompleted('merger');

      final data = (await db.collection('users').doc('merger').get()).data()!;
      expect(data['name'], 'Atharva');
      expect(data['goal'], isNotNull);
      expect(data[ZinoTourStore.fieldName], 'true');
    });
  });

  group('CASE 10 — failures must not create an onboarding loop', () {
    test('an unreadable profile fails CLOSED (does not tour)', () async {
      // A store whose Firestore throws on read stands in for offline /
      // permission-denied. Touring on an unknown status would re-onboard
      // every existing athlete on any flaky connection.
      final s = ZinoTourStore(firestore: _ThrowingFirestore(), storage: storage);
      expect(await s.shouldAutoStart('someone'), isFalse);
    });

    test('a failed cloud write still suppresses the tour locally', () async {
      final s = ZinoTourStore(firestore: _ThrowingFirestore(), storage: storage);
      await s.markCompleted('offline_user'); // must not throw

      // The local mirror alone is enough to prevent an immediate re-tour.
      expect(await s.shouldAutoStart('offline_user'), isFalse);
    });
  });

  group('tour sequencing', () {
    test('starts at the first stop and reports its position', () async {
      await seedUser('new_user');
      final c = controller();
      await c.startIfNewUser();

      expect(c.isRunning, isTrue);
      expect(c.index, 0);
      expect(c.isFirst, isTrue);
      expect(c.stepNumber, 1);
      expect(c.totalStops, kZinoTourStops.length);
    });

    test('next/back move through the stops without falling off either end',
        () async {
      await seedUser('new_user');
      final c = controller();
      await c.startIfNewUser();

      c.back();
      expect(c.index, 0, reason: 'back on the first stop is a no-op');

      c.next();
      expect(c.index, 1);
      c.back();
      expect(c.index, 0);
    });

    test('Next on the final stop finishes and persists', () async {
      await seedUser('finisher');
      final c = ZinoTourController(uid: 'finisher', store: store());
      await c.startIfNewUser();

      while (!c.isLast) {
        c.next();
      }
      expect(c.isLast, isTrue);
      c.next();
      // finish() is async; let the persist settle.
      await Future<void>.delayed(Duration.zero);

      expect(c.isRunning, isFalse);
      expect(c.isCompleted, isTrue);
      expect(await store().shouldAutoStart('finisher'), isFalse);
    });

    test('a stop with no visible target is skipped, not stuck on', () async {
      await seedUser('new_user');
      final c = controller();
      await c.startIfNewUser();
      final before = c.index;

      c.skipUnavailableStop();

      expect(c.index, before + 1,
          reason: 'a fresh account has no diet/experts yet — move on');
    });

    test('coachExtra only appears for an athlete who HAS a coach', () async {
      await seedUser('new_user');
      final withCoach = controller(hasCoach: true);
      final without = controller(hasCoach: false);
      await withCoach.startIfNewUser();
      await without.startIfNewUser();

      final swapIndex = kZinoTourStops.indexWhere((s) => s.id == 'diet-swap');
      expect(swapIndex, greaterThan(-1));
      for (var i = 0; i < swapIndex; i++) {
        withCoach.next();
        without.next();
      }

      expect(withCoach.currentBody, contains('Personal Coach'));
      expect(without.currentBody, isNot(contains('ONLY')));
      expect(without.currentBody, kZinoTourStops[swapIndex].body);
    });
  });

  group('manual replay', () {
    test('CASE 8 — replay opens the tour on demand', () async {
      await seedUser('veteran', completed: 'true');
      final c = ZinoTourController(uid: 'veteran', store: store());

      expect(await c.startIfNewUser(), isFalse, reason: 'not auto-started');

      c.startManually();
      expect(c.isRunning, isTrue);
      expect(c.index, 0);
    });

    test('replay does NOT turn the athlete back into a new user', () async {
      await seedUser('veteran', completed: 'true');
      final c = ZinoTourController(uid: 'veteran', store: store());
      c.startManually();
      await c.finish();

      expect(await store().shouldAutoStart('veteran'), isFalse);
      final doc = await db.collection('users').doc('veteran').get();
      expect(doc.data()![ZinoTourStore.fieldName], 'true');
    });
  });

  group('tour content — website parity', () {
    test('opens and closes on the hero slides, like the website', () {
      expect(kZinoTourStops.first.id, 'intro');
      expect(kZinoTourStops.first.isSlide, isTrue);
      expect(kZinoTourStops.last.id, 'finish');
      expect(kZinoTourStops.last.isSlide, isTrue);
    });

    test('the intro and finish copy is verbatim from zino.js', () {
      expect(kZinoTourStops.first.title, '👋 Hey! Welcome to ZITLAS.');
      expect(kZinoTourStops.first.body,
          startsWith("I'm Zino, your personal AI fitness companion."));
      expect(kZinoTourStops.last.title, "Awesome! You're all set.");
      expect(kZinoTourStops.last.body, contains("Let's build the healthiest version of you."));
    });

    test('the walkthrough introduces Zino\'s own top-right location', () {
      final stop = kZinoTourStops.firstWhere((s) => s.id == 'zino-here');
      expect(stop.title, contains("I'll always be right here"));
      expect(stop.body.toLowerCase(), contains('top-right'));
      expect(zinoTourTargetFor('zino-here'), ZinoTourKeys.zinoFab);
    });

    test('every stop has real copy and a resolvable target or hero', () {
      for (final stop in kZinoTourStops) {
        expect(stop.title.trim(), isNotEmpty, reason: stop.id);
        expect(stop.body.trim(), isNotEmpty, reason: stop.id);
        final hasTarget = zinoTourTargetFor(stop.id) != null;
        expect(hasTarget || stop.isSlide, isTrue,
            reason: '${stop.id} must spotlight something or be a slide');
      }
    });

    test('stop ids are unique', () {
      final ids = kZinoTourStops.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('stops are grouped so the tour never ping-pongs between tabs', () {
      // Revisiting a tab you already left is disorienting; each screen should
      // appear as one contiguous run.
      final seen = <ZinoTourScreen>{};
      ZinoTourScreen? previous;
      for (final stop in kZinoTourStops) {
        if (stop.screen != previous) {
          expect(seen.contains(stop.screen), isFalse,
              reason: 'returned to ${stop.screen.name} after leaving it');
          seen.add(stop.screen);
          previous = stop.screen;
        }
      }
    });

    test('the tour covers the main areas the task asks for', () {
      final screens = kZinoTourStops.map((s) => s.screen).toSet();
      expect(screens, containsAll(ZinoTourScreen.values));
    });
  });

  group('tour vs assessment — separate concerns', () {
    test('completing the tour writes ONLY the tour field', () async {
      await seedUser('separate');
      await store().markCompleted('separate');

      final data = (await db.collection('users').doc('separate').get()).data()!;
      expect(data[ZinoTourStore.fieldName], 'true');
      // Nothing about the assessment may be implied by finishing a walkthrough.
      expect(data.containsKey('assessment'), isFalse);
      expect(data.containsKey('assessmentCompleted'), isFalse);
      expect(data.containsKey('calculations'), isFalse);
    });

    test('having completed the assessment does not suppress the tour', () async {
      await db.collection('users').doc('assessed').set({
        'assessment': {'age': 22},
        'calculations': {'bmi': 21.5},
      });
      expect(await store().shouldAutoStart('assessed'), isTrue,
          reason: 'assessment completion is not tour completion');
    });
  });
}

/// A Firestore whose every call fails — stands in for offline,
/// permission-denied, and timeout.
///
/// `noSuchMethod` covers the whole surface, so `collection(...)` throws before
/// a read or write is ever attempted.
class _ThrowingFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw FirebaseException(plugin: 'test', message: 'network unavailable');
}
