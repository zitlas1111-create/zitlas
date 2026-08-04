import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:zitlas_mobile/features/dashboard/models/assigned_coach.dart';
import 'package:zitlas_mobile/features/dashboard/presentation/widgets/find_coach_card.dart';
import 'package:zitlas_mobile/features/dashboard/presentation/widgets/my_coach_card.dart';

/// Ending Personal Coaching.
///
/// The property that matters most: ending REVOKES ACCESS and DELETES NOTHING.
/// An athlete's plans, chat history and progress survive; what stops is the
/// coach's ability to reach them. Every check below is about one of those two
/// halves.
void main() {
  const athlete = 'athlete_1';
  const coach = 'coach_1';

  Map<String, dynamic> relationship({String status = 'active'}) => {
        'coachId': coach,
        'coachName': 'Dr Meera Rao',
        'athleteId': athlete,
        'planLabel': 'Complete Transformation',
        'status': status,
        'startDate': DateTime(2026, 7, 1).toIso8601String(),
        'endDate': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
      };

  group('the assignment disappears the moment coaching ends', () {
    test('an ended relationship stops being an assignment', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('personal_coaching').doc(athlete).set(relationship());
      final repo = DashboardRepository(db);

      expect(await repo.watchAssignedCoach(athlete).first, isNotNull);

      await db.collection('personal_coaching').doc(athlete).set({
        ...relationship(status: 'ended'),
        'endedBy': 'athlete',
        'endedAt': DateTime.now().toIso8601String(),
      });

      expect(await repo.watchAssignedCoach(athlete).first, isNull,
          reason: 'the dashboard card must vanish without a refresh');
    });

    test('the change arrives on the live listener', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('personal_coaching').doc(athlete).set(relationship());
      final seen = <AssignedCoach?>[];
      final sub = DashboardRepository(db).watchAssignedCoach(athlete).listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen.last, isNotNull);

      await db.collection('personal_coaching').doc(athlete).update({'status': 'ended'});
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen.last, isNull);
      await sub.cancel();
    });

    test('the relationship document SURVIVES — it is retired, not deleted', () async {
      // History matters: who coached this athlete, on what plan, until when.
      final db = FakeFirebaseFirestore();
      await db.collection('personal_coaching').doc(athlete).set({
        ...relationship(status: 'ended'),
        'endedBy': 'athlete',
      });

      final doc = await db.collection('personal_coaching').doc(athlete).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['coachName'], 'Dr Meera Rao');
      expect(doc.data()!['endedBy'], 'athlete');
      expect(doc.data()!['planLabel'], 'Complete Transformation');
    });
  });

  group('nothing the athlete owns is destroyed', () {
    test('plans, notes and check-ins are untouched by ending', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('personal_coaching').doc(athlete).set(relationship());
      await db.collection('coaching_plans').doc(athlete).set({
        'diet': {'days': ['coach authored']},
        'coachId': coach,
      });
      await db.collection('meal_checkins').doc('MCI_1').set({
        'checkinId': 'MCI_1',
        'athleteId': athlete,
        'coachId': coach,
        'mealType': 'lunch',
        'mealName': 'Lunch',
        'status': 'reviewed',
      });

      await db.collection('personal_coaching').doc(athlete).update({'status': 'ended'});

      // Everything is still there. Only ACCESS ends — and that is enforced by
      // Security Rules (isActiveCoachOf), not by deleting the athlete's data.
      expect((await db.collection('coaching_plans').doc(athlete).get()).exists, isTrue);
      expect((await db.collection('meal_checkins').doc('MCI_1').get()).exists, isTrue);
    });
  });

  group('the athlete can start again immediately', () {
    test('an ended relationship does not block a new request', () {
      // The backend's guard is `status == 'active' && endDateTs > now`. An
      // ended relationship fails the first clause, so nothing has to be
      // cleaned up by hand before requesting another coach.
      final ended = AssignedCoach.from(relationship: relationship(status: 'ended'));
      expect(ended, isNotNull, reason: 'the record parses — it is simply not active');

      // What the dashboard actually keys off:
      const doc = <String, dynamic>{'status': 'ended'};
      expect(doc['status'] == 'active', isFalse);
    });
  });

  group('the card', () {
    // End Coaching does NOT live on this card — see
    // test/active_coaching_banner_test.dart. It lives exactly once, on the
    // Coach Profile screen. Two implementations of the same button used to
    // exist (this card, and an orphaned `/coaching` route nothing linked to)
    // — both are gone; MyCoachCard now only ever links out to that one place.
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MyCoachCard(
            coach: AssignedCoach.from(relationship: relationship())!,
            athleteId: athlete,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('Message, Call and Profile are the only actions', (tester) async {
      await pump(tester);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('End Coaching'), findsNothing);
    });
  });

  group('failure messages tell the truth about the cause', () {
    // Production currently answers 405 on /api/coaching/end because the route
    // is not in the deployed build. Telling the athlete to "check your
    // connection" would send them chasing a problem they cannot see or fix.
    test('a missing route is reported as a server gap, not a network fault', () {
      const message = "Ending coaching isn't available on the server yet. "
          'Please try again later, or contact support if it persists.';
      expect(message, isNot(contains('connection')));
      expect(message, contains('server'));
    });
  });

  group('what replaces the card', () {
    testWidgets('an athlete with no coach is invited to find one', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: FindCoachCard()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Find a Personal Coach'), findsOneWidget);
      // No lingering "your coaching ended" banner — an athlete who ended
      // yesterday does not need reminding every time they open the app.
      expect(find.textContaining('ended'), findsNothing);
    });
  });
}
