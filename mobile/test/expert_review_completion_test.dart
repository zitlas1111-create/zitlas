import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/expert_dashboard/data/expert_repository.dart';
import 'package:zitlas_mobile/features/expert_dashboard/models/expert_models.dart';

/// Expert review completion — the "Complete Verification" flow.
///
/// The reported bug was a review completing TWICE. These lock the data layer's
/// half of the fix: completion is idempotent, so no matter how many times the
/// UI (or a retry, or a second device) asks, exactly one completion is
/// recorded and the athlete is notified exactly once.

class _FakeAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late ExpertRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ExpertRepository(firestore: db, auth: _FakeAuth());
  });

  Future<void> seedReview(
    String id, {
    String status = ReviewStatus.inProgress,
    String reviewType = 'diet',
  }) {
    return db.collection('review_requests').doc(id).set({
      'id': id,
      'status': status,
      'reviewType': reviewType,
      'userId': 'athlete_1',
      'athleteName': 'Test Athlete',
      'expertId': 'expert_1',
      'planData': {'days': []},
    });
  }

  Future<Map<String, dynamic>> read(String id) async =>
      (await db.collection('review_requests').doc(id).get()).data()!;

  Future<int> notificationCount() async =>
      (await db.collection('notifications').get()).docs.length;

  group('completeReview (chat-only reviews)', () {
    test('a single call marks the review completed with timestamps', () async {
      await seedReview('r1', reviewType: 'chat_only');

      await repo.completeReview('r1', expertId: 'expert_1', expertName: 'Dr. Rao');

      final data = await read('r1');
      expect(data['status'], ReviewStatus.reviewCompleted);
      expect(data['completedAt'], isNotNull);
      expect(data['reviewedAt'], isNotNull);
      expect(data['expertName'], 'Dr. Rao');
    });

    test('calling it twice does NOT overwrite the first completion', () async {
      await seedReview('r1', reviewType: 'chat_only');

      await repo.completeReview('r1', expertId: 'expert_1', expertName: 'Dr. Rao');
      final first = await read('r1');

      // A retry, a resumed app, or a second tap that slipped past the UI guard.
      await repo.completeReview('r1', expertId: 'expert_1', expertName: 'Someone Else');
      final second = await read('r1');

      expect(second['completedAt'], first['completedAt'],
          reason: 'the original completion time must stand');
      expect(second['expertName'], 'Dr. Rao',
          reason: 'a duplicate call must not rewrite the completing expert');
    });

    test('concurrent completions still produce exactly one result', () async {
      await seedReview('r1', reviewType: 'chat_only');

      await Future.wait([
        repo.completeReview('r1', expertId: 'expert_1', expertName: 'Dr. Rao'),
        repo.completeReview('r1', expertId: 'expert_1', expertName: 'Dr. Rao'),
        repo.completeReview('r1', expertId: 'expert_1', expertName: 'Dr. Rao'),
      ]);

      expect((await read('r1'))['status'], ReviewStatus.reviewCompleted);
    });

    test('a missing review is a no-op rather than a crash', () async {
      await repo.completeReview('ghost', expertId: 'expert_1', expertName: 'Dr. Rao');
      final snap = await db.collection('review_requests').doc('ghost').get();
      expect(snap.exists, isFalse);
    });
  });

  group('submitDietReview', () {
    final plan = {
      'days': [
        {'day': 'Monday', 'meals': []},
      ],
    };
    final history = [
      {'dayIndex': 0, 'mealName': 'Breakfast', 'newFoods': ['Poha']},
    ];

    test('saves plan, history, status and timestamps in one write', () async {
      await seedReview('r1');

      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: plan,
        mealChangeHistory: history,
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        expertNotes: 'Increase protein at breakfast.',
        athleteId: 'athlete_1',
      );

      final data = await read('r1');
      expect(data['status'], ReviewStatus.reviewCompleted);
      expect(data['reviewedDietPlan'], isNotNull);
      expect(data['mealChangeHistory'], isNotEmpty);
      expect(data['expertNotes'], 'Increase protein at breakfast.');
      expect(data['completedAt'], isNotNull);
    });

    test('the athlete is notified exactly ONCE, even on a duplicate submit',
        () async {
      await seedReview('r1');

      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: plan,
        mealChangeHistory: history,
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        athleteId: 'athlete_1',
      );
      await Future<void>.delayed(Duration.zero); // let the fire-and-forget land
      expect(await notificationCount(), 1);

      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: plan,
        mealChangeHistory: history,
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        athleteId: 'athlete_1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(await notificationCount(), 1,
          reason: 'a duplicate submit must not buzz the athlete a second time');
    });

    test('a second submit cannot clobber the plan the athlete already got',
        () async {
      await seedReview('r1');
      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: plan,
        mealChangeHistory: history,
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        athleteId: 'athlete_1',
      );

      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: {'days': [], 'clobbered': true},
        mealChangeHistory: const [],
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        athleteId: 'athlete_1',
      );

      final data = await read('r1');
      expect((data['reviewedDietPlan'] as Map).containsKey('clobbered'), isFalse);
      expect(data['mealChangeHistory'], isNotEmpty);
    });
  });

  group('submitWorkoutReview', () {
    final plan = {
      'weekly_plan': [
        {'focus': 'Upper body'},
      ],
    };

    test('saves the workout plan and completes the review', () async {
      await seedReview('r2', reviewType: 'workout');

      await repo.submitWorkoutReview(
        reviewId: 'r2',
        reviewedWorkoutPlan: plan,
        workoutChangeHistory: const [
          {'dayIndex': 0, 'focus': 'Upper body'},
        ],
        expertId: 'expert_1',
        expertName: 'Coach K',
        athleteId: 'athlete_1',
      );

      final data = await read('r2');
      expect(data['status'], ReviewStatus.reviewCompleted);
      expect(data['reviewedWorkoutPlan'], isNotNull);
      expect(data['workoutChangeHistory'], isNotEmpty);
    });

    test('is idempotent and notifies once, like the diet path', () async {
      await seedReview('r2', reviewType: 'workout');

      for (var i = 0; i < 3; i++) {
        await repo.submitWorkoutReview(
          reviewId: 'r2',
          reviewedWorkoutPlan: plan,
          workoutChangeHistory: const [],
          expertId: 'expert_1',
          expertName: 'Coach K',
          athleteId: 'athlete_1',
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(await notificationCount(), 1);
    });
  });

  group('what the athlete sees afterwards', () {
    test('every field the athlete needs is present after one completion',
        () async {
      await seedReview('r1');
      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: {'days': []},
        mealChangeHistory: const [
          {'dayIndex': 0, 'mealName': 'Breakfast', 'newFoods': ['Poha']},
        ],
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        expertNotes: 'Great progress — keep it up.',
        athleteId: 'athlete_1',
      );

      final data = await read('r1');
      // Expert name, completion timestamp, the modified plan, the diff, and
      // the review notes — the whole "Verification Completed" card.
      expect(data['expertName'], 'Dr. Rao');
      expect(data['completedAt'], isNotNull);
      expect(data['reviewedDietPlan'], isNotNull);
      expect(data['mealChangeHistory'], isNotEmpty);
      expect(data['expertNotes'], isNotEmpty);
      expect(data['status'], ReviewStatus.reviewCompleted);
    });

    test('completion does not touch the athlete-accept flag', () async {
      // `athleteAccepted` belongs to the athlete's own accept action; the
      // expert completing must never pre-answer it for them.
      await seedReview('r1');
      await repo.submitDietReview(
        reviewId: 'r1',
        reviewedDietPlan: {'days': []},
        mealChangeHistory: const [],
        expertId: 'expert_1',
        expertName: 'Dr. Rao',
        athleteId: 'athlete_1',
      );
      expect((await read('r1')).containsKey('athleteAccepted'), isFalse);
    });
  });

  group('status normalization', () {
    test('review_completed is the single canonical completed status', () {
      expect(ReviewStatus.reviewCompleted, 'review_completed');
      // The website also writes a bare 'completed'; both must normalize to one
      // value or the inbox would show a finished review as still in progress.
      expect(ReviewStatus.normalize('completed'), ReviewStatus.reviewCompleted);
      expect(
        ReviewStatus.normalize('review_completed'),
        ReviewStatus.reviewCompleted,
      );
    });
  });
}
