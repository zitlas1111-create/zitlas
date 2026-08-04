import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/steps/step_history.dart';
import 'package:zitlas_mobile/core/steps/step_tracking_service.dart';
import 'package:zitlas_mobile/features/health/presentation/screens/step_history_screen.dart';

/// The History screen renders what was recorded — and, just as importantly,
/// admits when nothing was.
void main() {
  StepHistory historyOf(Map<String, (int steps, int goal)> days) => StepHistory({
        for (final e in days.entries)
          e.key: StepDaySummary(
            date: e.key,
            steps: e.value.$1,
            goal: e.value.$2,
            completed: e.value.$1 >= e.value.$2,
            lastUpdated: DateTime(2026, 7, 30),
          ),
      });

  Future<void> pump(
    WidgetTester tester,
    StepHistory history, {
    double? heightCm,
    double? weightKg,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: StepHistoryScreen(
        history: history,
        heightCm: heightCm,
        weightKg: weightKg,
        now: DateTime(2026, 7, 30, 12),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('all four ranges the task asks for are present', (tester) async {
    await pump(tester, historyOf({'2026-07-30': (5000, 8000)}));
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Yesterday'), findsWidgets);
    expect(find.text('Last 7 Days'), findsOneWidget);
    expect(find.text('Last 30 Days'), findsOneWidget);
  });

  testWidgets('today shows steps, goal, completion, distance and calories',
      (tester) async {
    await pump(
      tester,
      historyOf({'2026-07-30': (10000, 8000)}),
      heightCm: 175,
      weightKg: 70,
    );

    expect(find.text('10,000'), findsOneWidget);
    expect(find.text('125% of a 8,000 step goal'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('Time active'), findsOneWidget);
    // 10,000 steps x 0.726m stride = 7.26 km.
    expect(find.text('7.26 km'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('yesterday renders its own recorded day, not today\'s',
      (tester) async {
    await pump(
      tester,
      historyOf({'2026-07-30': (1000, 8000), '2026-07-29': (9500, 8000)}),
    );
    await tester.tap(find.text('Yesterday').first);
    await tester.pumpAndSettle();

    expect(find.text('9,500'), findsOneWidget);
    expect(find.text('1,000'), findsNothing);
  });

  testWidgets('a day with no record says so instead of showing zero',
      (tester) async {
    await pump(tester, historyOf({'2026-07-30': (5000, 8000)}));
    await tester.tap(find.text('Yesterday').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('No steps recorded'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a range averages only the days that have data', (tester) async {
    // Two recorded days out of seven: the average is 8,000, not 2,285.
    await pump(
      tester,
      historyOf({'2026-07-30': (10000, 8000), '2026-07-29': (6000, 8000)}),
    );
    await tester.tap(find.text('Last 7 Days'));
    await tester.pumpAndSettle();

    expect(find.text('8,000'), findsOneWidget);
    expect(find.textContaining('days with no data are'), findsOneWidget);
  });

  testWidgets('a range lists every date, gaps included', (tester) async {
    await pump(tester, historyOf({'2026-07-30': (10000, 8000)}));
    await tester.tap(find.text('Last 7 Days'));
    await tester.pumpAndSettle();

    // Only the on-screen rows are built, so assert presence rather than an
    // exact count — the point is that unrecorded dates are LISTED, not elided.
    expect(find.text('No data'), findsWidgets);
    expect(find.text('Goals hit'), findsOneWidget);
  });

  testWidgets('the estimate footnote is honest about missing body data',
      (tester) async {
    await pump(tester, historyOf({'2026-07-30': (5000, 8000)}));
    expect(find.textContaining('average adult height and weight'), findsOneWidget);

    await pump(
      tester,
      historyOf({'2026-07-30': (5000, 8000)}),
      heightCm: 175,
      weightKg: 70,
    );
    expect(find.textContaining('average adult height and weight'), findsNothing);
    expect(find.textContaining('your step count, height and weight'), findsOneWidget);
  });

  testWidgets('an empty history opens without crashing', (tester) async {
    await pump(tester, StepHistory.empty);
    expect(find.textContaining('No steps recorded'), findsOneWidget);
  });
}
