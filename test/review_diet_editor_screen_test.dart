import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/expert_dashboard/data/expert_repository.dart';
import 'package:zitlas_mobile/features/expert_dashboard/data/food_search_repository.dart';
import 'package:zitlas_mobile/features/expert_dashboard/models/expert_models.dart';
import 'package:zitlas_mobile/features/expert_dashboard/presentation/screens/review_diet_editor_screen.dart';

/// END-TO-END proof that the REAL "Review Diet Plan" screen is editable.
///
/// These pump `ReviewDietEditorScreen` itself — not a widget it happens to
/// import — and drive the whole path: render meal cards, tap one, edit fields
/// in the sheet, save, confirm the CARD updates, then Save & Send and confirm
/// what actually lands in Firestore.
///
/// The previous round shipped a correct editor sheet but verified only the
/// sheet in isolation, which proved nothing about whether the screen opened
/// it. That gap is what these close.

class _FakeAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Returns canned results without touching the network, so tapping "Swap" in
/// a test doesn't need a live backend.
class _FakeFoodSearch implements FoodSearchRepository {
  @override
  Future<List<FoodSearchResult>> search({
    String query = '',
    String? category,
    String? region,
    String? goal,
    String? diet,
    double? minProtein,
    double? maxCalories,
    int limit = 30,
  }) async =>
      const [
        FoodSearchResult(
          id: 1,
          name: 'Upma',
          display: 'Upma (1 bowl (150 g))',
          servingSize: '1 bowl (150 g)',
          calories: 210,
          protein: 6,
          region: 'South',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late ExpertRepository repo;

  const reviewId = 'review_1';

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ExpertRepository(firestore: db, auth: _FakeAuth());
    await db.collection('review_requests').doc(reviewId).set({
      'id': reviewId,
      'status': ReviewStatus.inProgress,
      'reviewType': 'diet',
      'userId': 'athlete_1',
      'expertId': 'expert_1',
      'expertName': 'Dr. Rao',
      'planData': {
        'days': [
          {
            'day': 'Monday',
            'meals': [
              {
                'meal_name': 'Breakfast',
                'foods': ['Poha (1 plate (200 g))'],
                'calories': 181,
                'protein_g': 4.5,
              },
              {
                'meal_name': 'Lunch',
                'foods': ['Dal', 'Rice'],
                'calories': 520,
                'protein_g': 18,
              },
            ],
          },
          {
            'day': 'Tuesday',
            'meals': [
              {'meal_name': 'Breakfast', 'foods': ['Idli'], 'calories': 200, 'protein_g': 5},
            ],
          },
        ],
      },
    });
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReviewDietEditorScreen(
        reviewId: reviewId,
        repository: repo,
        foodRepository: _FakeFoodSearch(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the screen renders an EDITABLE plan', () {
    testWidgets('meal cards load from the review', (tester) async {
      await pumpEditor(tester);

      expect(find.text('Review Diet Plan'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Poha (1 plate (200 g))'), findsOneWidget);
    });

    testWidgets('every meal card shows a visible Edit control', (tester) async {
      await pumpEditor(tester);

      // Two meals on Monday -> two Edit affordances. An icon-only control was
      // the reason this screen read as view-only.
      expect(find.text('Edit'), findsNWidgets(2));
    });

    testWidgets('day tabs and Copy Day are present', (tester) async {
      await pumpEditor(tester);

      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Tuesday'), findsOneWidget);
      expect(find.byTooltip('Copy this day to another'), findsOneWidget);
    });
  });

  group('tapping a meal card OPENS the editor', () {
    testWidgets('tapping the card body opens the meal editor sheet',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();

      // The sheet is open with every editable field.
      expect(find.text('Save Meal'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Poha'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Calories'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Protein'), findsOneWidget);
      expect(find.text('Add from database'), findsOneWidget);
    });

    testWidgets('tapping the Edit chip also opens it', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();

      expect(find.text('Save Meal'), findsOneWidget);
    });
  });

  group('edits are visible on the card immediately', () {
    testWidgets('renaming a food updates the card', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Poha'), 'Upma');
      await tester.tap(find.text('Save Meal'));
      await tester.pumpAndSettle();

      // The card now shows the new value and is flagged as edited.
      expect(find.text('Upma (1 plate (200 g))'), findsOneWidget);
      expect(find.text('Poha (1 plate (200 g))'), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
    });

    testWidgets('changing calories/protein updates the card', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Calories'), '250');
      await tester.enterText(find.widgetWithText(TextField, 'Protein'), '9');
      await tester.tap(find.text('Save Meal'));
      await tester.pumpAndSettle();

      expect(find.textContaining('250 kcal'), findsOneWidget);
      expect(find.textContaining('9g protein'), findsOneWidget);
    });

    testWidgets('deleting a food updates the card', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Lunch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Meal'));
      await tester.pumpAndSettle();

      // Was "Dal, Rice" — one item removed.
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Dal, Rice'), findsNothing);
    });

    testWidgets('swapping a food from the database updates the card',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Swap').first);
      await tester.pumpAndSettle();

      // The fake database returns Upma; picking it replaces the item.
      await tester.tap(find.text('Upma').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Meal'));
      await tester.pumpAndSettle();

      expect(find.text('Upma (1 bowl (150 g))'), findsOneWidget);
    });
  });

  group('Save & Send writes the edited plan to Firestore', () {
    testWidgets('the modified plan, history and status all persist',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Poha'), 'Upma');
      await tester.tap(find.text('Save Meal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Send'));
      await tester.pumpAndSettle();

      final data = (await db.collection('review_requests').doc(reviewId).get()).data()!;

      expect(data['status'], ReviewStatus.reviewCompleted);
      expect(data['reviewedDietPlan'], isNotNull);
      expect(data['mealChangeHistory'], isNotEmpty);
      expect(data['completedAt'], isNotNull);
      expect(data['expertName'], 'Dr. Rao');

      // The athlete must receive the EDITED food, not the original.
      final history = (data['mealChangeHistory'] as List).first as Map;
      expect(history['mealName'], 'Breakfast');
      expect(history['oldFoods'], ['Poha (1 plate (200 g))']);
      expect(history['newFoods'], ['Upma (1 plate (200 g))']);

      final plan = data['reviewedDietPlan'] as Map;
      final monday = (plan['days'] as List).first as Map;
      final breakfast = (monday['meals'] as List).first as Map;
      expect(breakfast['foods'], ['Upma (1 plate (200 g))']);
    });

    testWidgets('Save & Send refuses when nothing was changed', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Save & Send'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least one change'), findsOneWidget);

      final data = (await db.collection('review_requests').doc(reviewId).get()).data()!;
      expect(data['status'], ReviewStatus.inProgress,
          reason: 'an empty review must not complete');
    });
  });

  group('days stay independent', () {
    testWidgets('editing Monday does not change Tuesday', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.text('Breakfast'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Poha'), 'Upma');
      await tester.tap(find.text('Save Meal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tuesday'));
      await tester.pumpAndSettle();

      expect(find.text('Idli'), findsOneWidget);
      expect(find.text('Edited'), findsNothing,
          reason: "Tuesday must be untouched by Monday's edit");
    });
  });
}
