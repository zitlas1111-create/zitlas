import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:zitlas_mobile/features/dashboard/models/assigned_coach.dart';
import 'package:zitlas_mobile/features/dashboard/presentation/widgets/my_coach_card.dart';
import 'package:zitlas_mobile/features/expert_dashboard/models/expert_models.dart';

/// Personal Coach assignment.
///
/// The assignment IS `personal_coaching/{athleteUid}` — one backend-written
/// document, keyed by the athlete. These tests pin the properties that makes
/// true: it cannot duplicate, it survives a restart because it isn't stored on
/// the handset, and it disappears the moment the relationship stops being
/// active.
void main() {
  const athlete = 'athlete_1';
  const coach = 'coach_1';

  Map<String, dynamic> relationship({
    String status = 'active',
    String coachId = coach,
    String coachName = 'Dr Meera Rao',
    String planLabel = 'Complete Transformation',
    DateTime? endDate,
  }) =>
      {
        'coachId': coachId,
        'coachName': coachName,
        'athleteId': athlete,
        'planLabel': planLabel,
        'status': status,
        'startDate': DateTime(2026, 7, 1).toIso8601String(),
        'endDate': (endDate ?? DateTime.now().add(const Duration(days: 22)))
            .toIso8601String(),
      };

  Future<FakeFirebaseFirestore> db({
    Map<String, dynamic>? rel,
    Map<String, dynamic>? expert,
  }) async {
    final store = FakeFirebaseFirestore();
    if (rel != null) {
      await store.collection('personal_coaching').doc(athlete).set(rel);
    }
    if (expert != null) {
      await store.collection('experts').doc(coach).set(expert);
    }
    return store;
  }

  group('the assignment reaches the athlete', () {
    test('an active relationship resolves to an assigned coach', () async {
      final store = await db(
        rel: relationship(),
        expert: {'name': 'Dr Meera Rao', 'verified': true, 'specialization': 'Sports Nutrition'},
      );

      final assigned = await DashboardRepository(store).watchAssignedCoach(athlete).first;

      expect(assigned, isNotNull);
      expect(assigned!.coachId, coach);
      expect(assigned.coachName, 'Dr Meera Rao');
      expect(assigned.verified, isTrue);
      expect(assigned.specialization, 'Sports Nutrition');
      expect(assigned.planLabel, 'Complete Transformation');
    });

    test('no relationship means no coach — not an error', () async {
      final store = await db();
      expect(await DashboardRepository(store).watchAssignedCoach(athlete).first, isNull);
    });

    test('a pending relationship is not an assignment', () async {
      // Only `status == active` counts. A request that has been made but not
      // accepted must never render as "your coach".
      final store = await db(rel: relationship(status: 'pending'));
      expect(await DashboardRepository(store).watchAssignedCoach(athlete).first, isNull);
    });

    test('an ended relationship stops being an assignment', () async {
      final store = await db(rel: relationship(status: 'ended'));
      expect(await DashboardRepository(store).watchAssignedCoach(athlete).first, isNull);
    });

    test('acceptance arrives live, with no refresh', () async {
      final store = await db();
      final stream = DashboardRepository(store).watchAssignedCoach(athlete);
      final seen = <AssignedCoach?>[];
      final sub = stream.listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen.last, isNull, reason: 'unassigned to begin with');

      // The expert accepts: the backend writes the relationship.
      await store.collection('personal_coaching').doc(athlete).set(relationship());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen.last, isNotNull);
      expect(seen.last!.coachId, coach);
      await sub.cancel();
    });

    test('a missing expert doc costs a photo, not the assignment', () async {
      final store = await db(rel: relationship());
      final assigned = await DashboardRepository(store).watchAssignedCoach(athlete).first;

      expect(assigned, isNotNull);
      expect(assigned!.coachName, 'Dr Meera Rao', reason: 'name comes from the relationship');
      expect(assigned.verified, isFalse);
      expect(assigned.photo, isNull);
    });

    test('a relationship with no coachId is not a usable assignment', () async {
      final store = await db(rel: {'status': 'active', 'athleteId': athlete});
      expect(await DashboardRepository(store).watchAssignedCoach(athlete).first, isNull);
    });

    test('the relationship name wins over a later expert rename', () async {
      // It records who the athlete actually agreed to work with.
      final store = await db(
        rel: relationship(coachName: 'Dr Meera Rao'),
        expert: {'name': 'Meera R. (Nutrition Co.)'},
      );
      final assigned = await DashboardRepository(store).watchAssignedCoach(athlete).first;
      expect(assigned!.coachName, 'Dr Meera Rao');
    });
  });

  group('assignment cannot duplicate', () {
    test('a second accepted coach REPLACES rather than duplicating', () async {
      // The doc id is the athlete's uid, so there is physically no room for
      // two. (The backend also rejects it outright with
      // `athlete_has_other_active_coach`.)
      final store = await db(rel: relationship(coachId: 'coach_1', coachName: 'First'));
      await store
          .collection('personal_coaching')
          .doc(athlete)
          .set(relationship(coachId: 'coach_2', coachName: 'Second'));

      final all = await store.collection('personal_coaching').get();
      expect(all.docs.length, 1);
      final assigned = await DashboardRepository(store).watchAssignedCoach(athlete).first;
      expect(assigned!.coachId, 'coach_2');
    });

    test('another athlete\'s assignment is a separate document', () async {
      final store = await db(rel: relationship());
      await store.collection('personal_coaching').doc('athlete_2').set({
        ...relationship(),
        'athleteId': 'athlete_2',
      });

      final mine = await DashboardRepository(store).watchAssignedCoach(athlete).first;
      final theirs = await DashboardRepository(store).watchAssignedCoach('athlete_2').first;
      expect(mine!.coachId, coach);
      expect(theirs!.coachId, coach);
    });
  });

  group('days remaining', () {
    test('counts down from the stored end date', () {
      final coachModel = AssignedCoach.from(
        relationship: relationship(endDate: DateTime.now().add(const Duration(days: 10, hours: 2))),
      );
      expect(coachModel!.daysRemaining, 10);
    });

    test('a lapsed relationship reads as zero, never negative', () {
      final coachModel = AssignedCoach.from(
        relationship: relationship(endDate: DateTime.now().subtract(const Duration(days: 3))),
      );
      expect(coachModel!.daysRemaining, 0);
    });

    test('no end date simply omits the countdown', () {
      final coachModel = AssignedCoach.from(
        relationship: {'coachId': coach, 'coachName': 'X', 'status': 'active'},
      );
      expect(coachModel!.daysRemaining, isNull);
    });
  });

  group('the athlete snapshot on a coaching request', () {
    test('every field the expert needs is parsed', () {
      final req = CoachingRequest.fromMap('PCR_1', {
        'status': 'pending',
        'athleteId': athlete,
        'athleteName': 'Rohit S',
        'expertId': coach,
        'athleteProfile': {
          'photo': 'https://example.com/a.jpg',
          'gender': 'male',
          'age': 27,
          'heightCm': 175.0,
          'weightKg': 72.0,
          'bmi': 23.5,
          'goalType': 'muscle_gain',
        },
      });

      final p = req.athleteProfile!;
      expect(p.age, 27);
      expect(p.gender, 'male');
      expect(p.heightCm, 175);
      expect(p.weightKg, 72);
      expect(p.bmi, 23.5);
      expect(p.goalType, 'muscle_gain');
      expect(p.hasAny, isTrue);
    });

    test('a request made before the snapshot existed still renders', () async {
      final req = CoachingRequest.fromMap('PCR_old', {
        'status': 'pending',
        'athleteName': 'Rohit S',
        'expertId': coach,
      });
      expect(req.athleteProfile, isNull);
      expect(req.athleteName, 'Rohit S');
    });

    test('an athlete who filled in nothing has an empty, not fake, snapshot', () {
      final req = CoachingRequest.fromMap('PCR_2', {
        'status': 'pending',
        'expertId': coach,
        'athleteProfile': {
          'photo': null,
          'gender': null,
          'age': null,
          'heightCm': null,
          'weightKg': null,
          'bmi': null,
          'goalType': null,
        },
      });
      expect(req.athleteProfile!.hasAny, isFalse,
          reason: 'the card must not render a grid of blanks');
    });
  });

  group('the My Coach card', () {
    Future<void> pump(WidgetTester tester, AssignedCoach coachModel) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MyCoachCard(coach: coachModel, athleteId: athlete),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the coach, the ACTIVE status and all three actions',
        (tester) async {
      await pump(
        tester,
        AssignedCoach.from(
          relationship: relationship(),
          expert: {'verified': true, 'specialization': 'Sports Nutrition'},
        )!,
      );

      expect(find.text('My Personal Coach'), findsOneWidget);
      expect(find.text('Dr Meera Rao'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Complete Transformation'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('an unverified coach gets no badge', (tester) async {
      await pump(
        tester,
        AssignedCoach.from(relationship: relationship(), expert: {'verified': false})!,
      );
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
    });

    testWidgets('Call explains itself instead of doing nothing', (tester) async {
      // Voice calling is Phase 7. A button that looks live and silently does
      // nothing is worse than one that says when it arrives.
      await pump(tester, AssignedCoach.from(relationship: relationship())!);

      await tester.tap(find.text('Call'));
      await tester.pump();
      expect(find.textContaining('coming soon'), findsOneWidget);
    });
  });
}
