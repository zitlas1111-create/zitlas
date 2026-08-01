import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/features/diet/models/diet_meal.dart';
import 'package:zitlas_mobile/features/expert_dashboard/presentation/widgets/meal_editor_sheet.dart';

/// Typing in the meal editor must not be interrupted.
///
/// The bug these lock out: the food row's key embedded the food NAME
/// (`ValueKey('food_$i${item.name}')`) and every keystroke called `setState`.
/// Typing changed the key, so Flutter tore down the row's State, built a new
/// `TextEditingController`, and destroyed the `TextField`'s focus — the
/// keyboard closed after each character.
void main() {
  Future<void> pumpEditor(WidgetTester tester, DietMeal meal) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showMealEditorSheet(context, meal: meal),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The row's State must SURVIVE a rename — its TextEditingController lives
  /// there, and a new controller means a new field, lost focus, and a reset
  /// cursor. Controller identity is the most direct observable proxy for
  /// "the State was not torn down".
  testWidgets('the food row keeps its controller while the name is edited',
      (tester) async {
    const meal = DietMeal(mealName: 'Breakfast', foods: ['Poha (1 plate (200 g))']);
    await pumpEditor(tester, meal);

    final nameField = find.byType(TextField).first;
    final controllerBefore = tester.widget<TextField>(nameField).controller;

    await tester.enterText(nameField, 'Poh');
    await tester.pump();

    final controllerAfter =
        tester.widget<TextField>(find.byType(TextField).first).controller;

    expect(identical(controllerBefore, controllerAfter), isTrue,
        reason: 'a rebuilt row means a fresh controller — and a closed keyboard');
    expect(controllerAfter!.text, 'Poh');
  });

  testWidgets('focus is retained after typing into the name field',
      (tester) async {
    const meal = DietMeal(mealName: 'Breakfast', foods: ['Poha (1 plate (200 g))']);
    await pumpEditor(tester, meal);

    await tester.tap(find.widgetWithText(TextField, 'Poha'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    final focusAfterTap = FocusManager.instance.primaryFocus;

    await tester.enterText(find.widgetWithText(TextField, 'Poha'), 'Upma');
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, same(focusAfterTap),
        reason: 'the keyboard must stay on the SAME field while typing');
  });

  testWidgets('typing character by character accumulates without loss',
      (tester) async {
    // The real-world symptom: only the first character or word survived
    // because the field was rebuilt from the (stale) model between strokes.
    const meal = DietMeal(mealName: 'Breakfast', foods: ['A']);
    DietMeal? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async =>
                saved = await showMealEditorSheet(context, meal: meal),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'A');
    await tester.tap(field);
    await tester.pumpAndSettle();

    // Simulate real typing: one character at a time, pumping between each.
    const target = 'Grilled Chicken Breast';
    for (var i = 1; i <= target.length; i++) {
      await tester.enterText(find.byType(TextField).first, target.substring(0, i));
      await tester.pump();
    }

    await tester.tap(find.text('Save Meal'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.foods.single, target,
        reason: 'every character typed must survive to the saved meal');
  });

  testWidgets('quantity and unit fields also keep focus while typing',
      (tester) async {
    const meal = DietMeal(mealName: 'Lunch', foods: ['Rice (1 bowl)']);
    await pumpEditor(tester, meal);

    for (final hint in ['Qty', 'Unit (e.g. bowl (150 g))']) {
      final field = find.widgetWithText(TextField, hint).evaluate().isNotEmpty
          ? find.widgetWithText(TextField, hint)
          : null;
      if (field == null) continue;
      await tester.tap(field);
      await tester.pumpAndSettle();
      final before = FocusManager.instance.primaryFocus;
      await tester.enterText(field, '2');
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(before),
          reason: '$hint must not lose focus while typing');
    }
  });

  testWidgets('nutrition fields keep focus while typing', (tester) async {
    const meal = DietMeal(mealName: 'Lunch', foods: ['Rice'], calories: 400);
    await pumpEditor(tester, meal);

    for (final label in ['Calories', 'Protein', 'Carbs', 'Fat']) {
      final field = find.widgetWithText(TextField, label);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final before = FocusManager.instance.primaryFocus;

      await tester.enterText(field, '123');
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(before),
          reason: '$label must not lose focus while typing');
    }
  });

  testWidgets('renaming one food does not disturb another row', (tester) async {
    const meal = DietMeal(mealName: 'Lunch', foods: ['Rice', 'Dal']);
    DietMeal? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async =>
                saved = await showMealEditorSheet(context, meal: meal),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Rice'), 'Quinoa');
    await tester.pump();

    // The untouched row must still hold its own value.
    expect(find.widgetWithText(TextField, 'Dal'), findsOneWidget);

    await tester.tap(find.text('Save Meal'));
    await tester.pumpAndSettle();
    expect(saved!.foods, ['Quinoa', 'Dal']);
  });

  testWidgets('reordering still works after the key change', (tester) async {
    // The fix swaps a content-based key for an identity-based one; reorder
    // and duplicate must keep working, since both rely on stable keys.
    const meal = DietMeal(mealName: 'Lunch', foods: ['Rice', 'Dal']);
    DietMeal? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async =>
                saved = await showMealEditorSheet(context, meal: meal),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Duplicate').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Meal'));
    await tester.pumpAndSettle();

    expect(saved!.foods, ['Rice', 'Rice', 'Dal'],
        reason: 'duplicate must insert next to its source, not at the end');
  });
}
