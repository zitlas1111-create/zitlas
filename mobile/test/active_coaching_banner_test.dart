import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/expert_dashboard/models/expert_models.dart';
import 'package:zitlas_mobile/features/experts/presentation/widgets/active_coaching_banner.dart';

/// The ONE End Coaching implementation in the app, on the Coach Profile
/// screen. It used to be duplicated: a copy on the Dashboard's `MyCoachCard`
/// (see end_coaching_test.dart, "the card" group) and a second, orphaned copy
/// on a `/coaching` route nothing ever linked to. Both are gone; this is the
/// only place these behaviors are exercised now.
void main() {
  CoachingRelationship relationship({String status = 'active'}) => CoachingRelationship.fromMap(
        'athlete_1',
        {
          'coachId': 'coach_1',
          'coachName': 'Dr Meera Rao',
          'athleteId': 'athlete_1',
          'planLabel': 'Complete Transformation',
          'status': status,
          'startDate': DateTime(2026, 7, 1).toIso8601String(),
          'endDate': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
        },
      );

  Future<void> pump(
    WidgetTester tester, {
    required Future<void> Function() onEnd,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActiveCoachingBanner(
          relationship: relationship(),
          onEndCoaching: onEnd,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows ACTIVE status and the End Coaching action', (tester) async {
    await pump(tester, onEnd: () async {});
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Complete Transformation'), findsOneWidget);
    expect(find.text('End Coaching'), findsOneWidget);
  });

  testWidgets('the confirmation spells out what ends AND what is kept', (tester) async {
    await pump(tester, onEnd: () async {});
    await tester.tap(find.text('End Coaching'));
    await tester.pumpAndSettle();

    expect(find.text('End Personal Coaching?'), findsOneWidget);
    expect(find.textContaining('Dr Meera Rao'), findsWidgets);
    expect(find.text('Disable meal reviews'), findsOneWidget);
    expect(find.text('Disable coach chat and calls'), findsOneWidget);
    expect(find.text('Remove their access to your profile'), findsOneWidget);
    // The reassurance is the point — this is what athletes hesitate over.
    expect(find.textContaining('are kept'), findsOneWidget);
    expect(find.textContaining('request a new coach right away'), findsOneWidget);
  });

  testWidgets('Cancel does nothing at all', (tester) async {
    var called = false;
    await pump(tester, onEnd: () async => called = true);

    await tester.tap(find.text('End Coaching'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('End Personal Coaching?'), findsNothing);
  });

  testWidgets('confirming runs the termination and reports it', (tester) async {
    var called = false;
    await pump(tester, onEnd: () async => called = true);

    await tester.tap(find.text('End Coaching'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'End Coaching').last);
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(find.textContaining('Personal Coaching ended'), findsOneWidget);
    expect(find.textContaining('unchanged'), findsOneWidget);
  });

  testWidgets('a failure is surfaced, not swallowed', (tester) async {
    await pump(tester, onEnd: () async => throw Exception('Network unreachable'));

    await tester.tap(find.text('End Coaching'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'End Coaching').last);
    await tester.pumpAndSettle();

    expect(find.text('Network unreachable'), findsOneWidget);
  });
}
