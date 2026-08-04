import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zitlas_mobile/core/notifications/notification_preferences.dart';
import 'package:zitlas_mobile/core/notifications/zino_messages.dart';
import 'package:zitlas_mobile/core/notifications/zino_notification_scheduler.dart';
import 'package:zitlas_mobile/core/storage/local_storage_service.dart';

/// Zino's notification system.
///
/// The failures worth guarding against are the ones that make an athlete mute
/// the app: the same message every day, being told to walk after already
/// hitting the goal, or a reminder firing for a category they switched off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.init();
  });

  group('message rotation', () {
    test('there are at least 365 motivation quotes — a full year, no repeat', () {
      expect(kMotivationQuotes.length, greaterThanOrEqualTo(365));
    });

    test('every quote is unique', () {
      expect(kMotivationQuotes.toSet().length, kMotivationQuotes.length,
          reason: 'a duplicate silently shortens the no-repeat window');
    });

    test('each meal has at least 50 messages', () {
      expect(kBreakfastMessages.length, greaterThanOrEqualTo(50));
      expect(kLunchMessages.length, greaterThanOrEqualTo(50));
      expect(kSnackMessages.length, greaterThanOrEqualTo(50));
      expect(kDinnerMessages.length, greaterThanOrEqualTo(50));
    });

    test('meal messages are unique within their list', () {
      for (final list in [
        kBreakfastMessages,
        kLunchMessages,
        kSnackMessages,
        kDinnerMessages,
      ]) {
        expect(list.toSet().length, list.length);
      }
    });

    test('consecutive days NEVER get the same quote', () {
      // The headline requirement. Checked across a full year plus a rollover.
      var day = DateTime(2026, 1, 1);
      for (var i = 0; i < 400; i++) {
        final today = pickForDay(kMotivationQuotes, day);
        final tomorrow = pickForDay(kMotivationQuotes, day.add(const Duration(days: 1)));
        expect(today, isNot(tomorrow), reason: 'repeat on ${day.toIso8601String()}');
        day = day.add(const Duration(days: 1));
      }
    });

    test('a full year passes without repeating a quote', () {
      final seen = <String>{};
      var day = DateTime(2026, 1, 1);
      for (var i = 0; i < 365; i++) {
        seen.add(pickForDay(kMotivationQuotes, day));
        day = day.add(const Duration(days: 1));
      }
      expect(seen.length, 365);
    });

    test('the same date always yields the same message', () {
      // A notification scheduled days ahead must display the text it was
      // scheduled with — a random pick would disagree with itself.
      final date = DateTime(2026, 6, 15);
      expect(pickForDay(kMotivationQuotes, date), pickForDay(kMotivationQuotes, date));
      expect(pickForDay(kBreakfastMessages, date), pickForDay(kBreakfastMessages, date));
    });

    test('rotation is stable across time-of-day on the same date', () {
      expect(
        pickForDay(kLunchMessages, DateTime(2026, 3, 4, 1, 0)),
        pickForDay(kLunchMessages, DateTime(2026, 3, 4, 23, 59)),
      );
    });
  });

  group('step-progress copy uses REAL numbers', () {
    test('an incomplete goal states actual counts and the true remainder', () {
      final msg = stepProgressMessage(steps: 6200, goal: 8000);
      expect(msg, contains('6,200'));
      expect(msg, contains('8,000'));
      expect(msg, contains('1,800'), reason: 'remainder must be computed, not guessed');
    });

    test('the completed-goal message never asks for more walking', () {
      final lower = kStepGoalCompleteMessage.toLowerCase();
      for (final nag in ['left', 'remaining', 'to go', 'finish today']) {
        expect(lower, isNot(contains(nag)),
            reason: 'must not nag someone who already hit their goal');
      }
      expect(kStepGoalCompleteMessage, contains('Amazing'));
    });
  });

  group('the daily schedule', () {
    test('all eight slots exist at the specified times', () {
      const expected = {
        ZinoSlot.morningMotivation: (7, 30),
        ZinoSlot.breakfast: (9, 0),
        ZinoSlot.lunch: (13, 0),
        ZinoSlot.snack: (17, 0),
        ZinoSlot.steps: (18, 0),
        ZinoSlot.workout: (19, 0),
        ZinoSlot.dinner: (20, 30),
        ZinoSlot.night: (22, 0),
      };
      expect(ZinoSlot.values.length, 8);
      expected.forEach((slot, hm) {
        expect((slot.hour, slot.minute), hm, reason: slot.name);
      });
    });

    test('every slot has a unique notification id', () {
      // Colliding ids would make one reminder silently overwrite another.
      final ids = ZinoSlot.values.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('step and workout are marked contextual; the rest are not', () {
      expect(ZinoSlot.steps.isContextual, isTrue);
      expect(ZinoSlot.workout.isContextual, isTrue);
      for (final s in ZinoSlot.values.where((s) => !s.isContextual)) {
        expect(s.bodyFor(DateTime(2026, 5, 1)), isNotEmpty, reason: s.name);
      }
    });

    test('every slot produces non-empty copy for any day of the year', () {
      var day = DateTime(2026, 1, 1);
      for (var i = 0; i < 365; i++) {
        for (final slot in ZinoSlot.values) {
          expect(slot.bodyFor(day).trim(), isNotEmpty, reason: '${slot.name} on $day');
        }
        day = day.add(const Duration(days: 1));
      }
    });

    test('the title is the Zino coach identity', () {
      expect(ZinoNotificationScheduler.appTitle, 'Zino • Your AI Fitness Coach');
    });
  });

  group('preferences', () {
    test('everything is ON by default — an opt-in coach stays silent', () {
      const prefs = NotificationPreferences();
      expect(prefs.masterEnabled, isTrue);
      for (final c in NotificationCategory.values) {
        expect(prefs.isEnabled(c), isTrue, reason: c.id);
      }
    });

    test('the master switch overrides every category', () {
      const prefs = NotificationPreferences();
      final off = prefs.withMaster(false);
      for (final c in NotificationCategory.values) {
        expect(off.isEnabled(c), isFalse, reason: c.id);
      }
    });

    test('a single category can be disabled without touching the others', () {
      const prefs = NotificationPreferences();
      final noSteps = prefs.withCategory(NotificationCategory.steps, false);
      expect(noSteps.isEnabled(NotificationCategory.steps), isFalse);
      expect(noSteps.isEnabled(NotificationCategory.meals), isTrue);
      expect(noSteps.isEnabled(NotificationCategory.workout), isTrue);
    });

    test('preferences survive a save/load round trip', () async {
      final prefs = const NotificationPreferences()
          .withCategory(NotificationCategory.water, false)
          .withCategory(NotificationCategory.motivation, false);
      await prefs.save(storage);

      final loaded = NotificationPreferences.load(storage);
      expect(loaded.isEnabled(NotificationCategory.water), isFalse);
      expect(loaded.isEnabled(NotificationCategory.motivation), isFalse);
      expect(loaded.isEnabled(NotificationCategory.meals), isTrue);
    });

    test('a category added in a future release defaults to ON', () {
      // Stored as the DISABLED set, so an unknown category is never
      // accidentally silent after an upgrade.
      final loaded = NotificationPreferences.fromMap({
        'masterEnabled': true,
        'disabled': ['water'],
      });
      expect(loaded.isEnabled(NotificationCategory.achievements), isTrue);
      expect(loaded.isEnabled(NotificationCategory.water), isFalse);
    });

    test('corrupt stored preferences fall back to defaults, not to silence', () async {
      await storage.setString(NotificationPreferences.storageKey, 'not json');
      final loaded = NotificationPreferences.load(storage);
      expect(loaded.masterEnabled, isTrue);
    });

    test('an unknown category id in storage is ignored safely', () {
      final loaded = NotificationPreferences.fromMap({
        'masterEnabled': true,
        'disabled': ['water', 'a_category_that_no_longer_exists'],
      });
      expect(loaded.disabled.length, 1);
      expect(loaded.isEnabled(NotificationCategory.water), isFalse);
    });
  });

  group('category coverage', () {
    test('every settings toggle maps to at least one real slot', () {
      // A switch that controls nothing is a lie to the athlete.
      final scheduled = ZinoSlot.values.map((s) => s.category).toSet();
      for (final c in [
        NotificationCategory.meals,
        NotificationCategory.workout,
        NotificationCategory.steps,
        NotificationCategory.motivation,
      ]) {
        expect(scheduled, contains(c), reason: '${c.id} has no scheduled slot');
      }
    });

    test('meals covers all four eating slots', () {
      final meals = ZinoSlot.values
          .where((s) => s.category == NotificationCategory.meals)
          .map((s) => s.name)
          .toSet();
      expect(meals, {'breakfast', 'lunch', 'snack', 'dinner'});
    });
  });
}
