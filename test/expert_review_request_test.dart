import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/expert_dashboard/models/expert_models.dart';
import 'package:zitlas_mobile/features/experts/data/experts_repository.dart';
import 'package:zitlas_mobile/features/experts/expert_profile_controller.dart';

/// Covers the two pieces of business logic this Phase 6 task explicitly
/// calls out as high-risk: the fail-closed review-status whitelist
/// (cprofile.js's documented history of getting this wrong via a blocklist)
/// and the `review_requests` submission payload shape (including the
/// "both" bundle).
void main() {
  ReviewRequest review(String id, String status, {String type = 'diet', String? bundleRole}) {
    return ReviewRequest(id: id, status: status, reviewType: type, bundleRole: bundleRole);
  }

  group('latestReviewOfTypePure — fail-closed whitelist', () {
    test('an unknown/future status is NOT active and NOT terminal — falls through to idle', () {
      // The exact historical bug: a 'dismissed' status introduced elsewhere
      // must never look "active" (stuck) nor "terminal" (wrongly rendered).
      final reviews = [review('r1', 'dismissed')];
      final latest = latestReviewOfTypePure(reviews, 'diet');
      expect(latest, isNull, reason: 'unknown status must not be picked up by either whitelist');
      expect(verifyButtonStatePure(latest).state, VerifyButtonState.requestReview);
    });

    test('withdrawn/superseded/declined/expired/cancelled all fail closed to idle', () {
      for (final status in ['withdrawn', 'superseded', 'declined', 'expired', 'cancelled']) {
        final latest = latestReviewOfTypePure([review('r', status)], 'diet');
        expect(latest, isNull, reason: '"$status" must not block a new request');
      }
    });

    test('pending is active — surfaces as pendingWithdraw, not requestReview', () {
      final reviews = [review('r1', 'pending')];
      final latest = latestReviewOfTypePure(reviews, 'diet');
      final info = verifyButtonStatePure(latest);
      expect(info.state, VerifyButtonState.pendingWithdraw);
      expect(canSubmitNewReviewPure(latest), isFalse);
    });

    test('in_progress / expert_reviewing both normalize to the in-progress button state', () {
      expect(
        verifyButtonStatePure(review('r1', 'in_progress')).state,
        VerifyButtonState.inProgress,
      );
      expect(
        verifyButtonStatePure(review('r2', 'expert_reviewing')).state,
        VerifyButtonState.inProgress,
      );
    });

    test('completed/review_completed are terminal-rendered — new requests allowed', () {
      final latest = latestReviewOfTypePure([review('r1', 'review_completed')], 'diet');
      expect(verifyButtonStatePure(latest).state, VerifyButtonState.completed);
      expect(canSubmitNewReviewPure(latest), isTrue);
    });

    test('rejected is terminal-rendered — new requests allowed', () {
      final latest = latestReviewOfTypePure([review('r1', 'rejected')], 'diet');
      expect(verifyButtonStatePure(latest).state, VerifyButtonState.rejected);
      expect(canSubmitNewReviewPure(latest), isTrue);
    });

    test('an active review takes priority over an older terminal one', () {
      final reviews = [review('old', 'review_completed'), review('new', 'pending')];
      final latest = latestReviewOfTypePure(reviews, 'diet');
      expect(latest!.id, 'new');
    });

    test('filters strictly by reviewType — a workout review never blocks a diet request', () {
      final reviews = [review('w1', 'pending', type: 'workout')];
      expect(latestReviewOfTypePure(reviews, 'diet'), isNull);
    });
  });

  group('buildReviewRequestDocs — review_requests payload shape', () {
    final ids = <String>['id1', 'id2'];
    int idIdx = 0;
    String nextId() => ids[idIdx++];

    setUp(() => idIdx = 0);

    test('single diet review — one pending doc, correct fields', () {
      final docs = buildReviewRequestDocs(
        idFactory: nextId,
        userId: 'u1',
        userName: 'Athlete One',
        expertId: 'e1',
        expertName: 'Dr. Rao',
        expertRole: 'Nutritionist',
        reviewType: 'diet',
        serviceType: 'verification',
        dietPlanData: {'days': []},
        assessmentData: const {},
        profileBasics: const {},
        planId: 'plan_123',
        totalPrice: 49,
      );

      expect(docs, hasLength(1));
      final d = docs.single;
      expect(d['id'], 'id1');
      expect(d['userId'], 'u1');
      expect(d['expertId'], 'e1');
      expect(d['reviewType'], 'diet');
      expect(d['planId'], 'plan_123');
      expect(d['totalPrice'], 49);
      expect(d['status'], 'pending');
      expect(d['paymentStatus'], 'unpaid');
      expect(d['bundleId'], isNull);
      expect(d['siblingId'], isNull);
    });

    test('chat_only review carries no planData', () {
      final docs = buildReviewRequestDocs(
        idFactory: nextId,
        userId: 'u1',
        userName: 'Athlete',
        expertId: 'e1',
        expertName: 'Dr. Rao',
        expertRole: 'Nutritionist',
        reviewType: 'chat_only',
        serviceType: 'chat',
        assessmentData: const {},
        profileBasics: const {},
        totalPrice: 149,
      );
      expect(docs.single['planData'], isNull);
      expect(docs.single['totalPrice'], 149);
    });

    test('"both" writes two linked docs — primary carries price, secondary is free', () {
      final docs = buildReviewRequestDocs(
        idFactory: nextId,
        userId: 'u1',
        userName: 'Athlete',
        expertId: 'e1',
        expertName: 'Dr. Rao',
        expertRole: 'Nutritionist',
        reviewType: 'both',
        serviceType: 'verification',
        dietPlanData: {'days': []},
        workoutPlanData: {'weekly_plan': []},
        assessmentData: const {},
        profileBasics: const {},
        totalPrice: 99,
      );

      expect(docs, hasLength(2));
      final diet = docs.firstWhere((d) => d['reviewType'] == 'diet');
      final workout = docs.firstWhere((d) => d['reviewType'] == 'workout');

      expect(diet['bundleRole'], 'primary');
      expect(diet['totalPrice'], 99);
      expect(diet['planData'], isNotNull);

      expect(workout['bundleRole'], 'secondary');
      expect(workout['totalPrice'], 0, reason: 'the bundle price lives on the primary doc only');
      expect(workout['planData'], isNotNull);

      // Cross-linked by id, and share one bundleId.
      expect(diet['siblingId'], workout['id']);
      expect(workout['siblingId'], diet['id']);
      expect(diet['bundleId'], workout['bundleId']);
    });
  });
}
