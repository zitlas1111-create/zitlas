import 'package:flutter_test/flutter_test.dart';
import 'package:zitlas_mobile/core/notifications/notification_payload.dart';
import 'package:zitlas_mobile/core/notifications/notification_router.dart';

/// Proves the notification -> destination mapping, which is the part of the
/// push pipeline that decides whether a tap lands on the right screen.
/// `destinationFor` is deliberately pure so this needs no widget tree, no
/// Firebase, and no device.
void main() {
  String? dest(Map<String, dynamic> data) =>
      NotificationRouter.destinationFor(NotificationPayload.fromData(data));

  group('chat_message', () {
    test('athlete lands in their coach\'s Website workspace with chat open', () {
      expect(
        dest({
          'type': 'chat_message',
          'recipientRole': 'athlete',
          'counterpartId': 'coach9',
          'chatId': 'chat_a1_coach9',
        }),
        '/coach-profile/coach9?action=ask',
      );
    });

    test('coach lands on their dashboard — same message, different side', () {
      expect(
        dest({
          'type': 'chat_message',
          'recipientRole': 'coach',
          'counterpartId': 'athlete1',
          'chatId': 'chat_athlete1_c9',
        }),
        '/expert-dashboard',
      );
    });

    test('falls back to senderId when counterpartId is absent', () {
      expect(
        dest({'type': 'chat_message', 'recipientRole': 'athlete', 'senderId': 'coach7'}),
        '/coach-profile/coach7?action=ask',
      );
    });

    test('never dead-ends when no coach id can be resolved', () {
      expect(dest({'type': 'chat_message', 'recipientRole': 'athlete'}), '/experts');
    });
  });

  group('meal reviews', () {
    test('pending meal (coach side) opens the coach dashboard', () {
      expect(dest({'type': 'meal_review_pending', 'mealId': 'MCI_1'}), '/expert-dashboard');
    });
    test('completed review (athlete side) opens Diet', () {
      expect(dest({'type': 'meal_review_completed', 'mealId': 'MCI_1'}), '/diet');
    });
    test('legacy meal_checkin/meal_reviewed types still route', () {
      expect(dest({'type': 'meal_checkin'}), '/expert-dashboard');
      expect(dest({'type': 'meal_reviewed'}), '/diet');
    });
  });

  group('plans stay native', () {
    test('diet_updated -> /diet', () {
      expect(dest({'type': 'diet_updated'}), '/diet');
    });
    test('workout_updated -> /training', () {
      expect(dest({'type': 'workout_updated'}), '/training');
    });
  });

  group('coaching lifecycle', () {
    test('athlete coaching event opens the Website coach profile, not a native screen', () {
      expect(
        dest({'type': 'coaching_accepted', 'recipientRole': 'athlete', 'coachId': 'c5'}),
        '/coach-profile/c5',
      );
    });
    test('coach-side coaching event opens the dashboard', () {
      expect(
        dest({'type': 'coaching_request_received', 'recipientRole': 'coach'}),
        '/expert-dashboard',
      );
    });
    test('payment events route like coaching events', () {
      expect(
        dest({'type': 'payment_success', 'recipientRole': 'athlete', 'coachId': 'c5'}),
        '/coach-profile/c5',
      );
    });
  });

  group('legacy notification-centre action keys', () {
    // These predate push; honouring them keeps a pushed notification and an
    // in-app tap landing on the SAME screen.
    test('action=diet / training / dashboard / coaches / profile', () {
      expect(dest({'type': 'x', 'action': 'diet'}), '/diet');
      expect(dest({'type': 'x', 'action': 'training'}), '/training');
      expect(dest({'type': 'x', 'action': 'dashboard'}), '/dashboard');
      expect(dest({'type': 'x', 'action': 'coaches'}), '/experts');
      expect(dest({'type': 'x', 'action': 'profile'}), '/profile');
    });
    test('action=expert_dashboard', () {
      expect(dest({'type': 'x', 'action': 'expert_dashboard'}), '/expert-dashboard');
    });
    test('action=expert_profile uses actionId', () {
      expect(
        dest({'type': 'x', 'action': 'expert_profile', 'actionId': 'e3'}),
        '/coach-profile/e3',
      );
    });
    test('action=chat opens the workspace with chat', () {
      expect(
        dest({'type': 'x', 'action': 'chat', 'actionId': 'e3'}),
        '/coach-profile/e3?action=ask',
      );
    });
  });

  group('fallbacks', () {
    test('zino_message -> /zino', () {
      expect(dest({'type': 'zino_message'}), '/zino');
    });
    test('unknown type with no action falls back to the Notification Centre', () {
      expect(dest({'type': 'something_new'}), '/notifications');
    });
    test('empty data is still safe (defaults to general -> /notifications)', () {
      expect(dest({}), '/notifications');
    });
  });

  group('payload parsing', () {
    test('round-trips through the local-notification payload string', () {
      const original = NotificationPayload(
        type: 'chat_message',
        chatId: 'chat_1_2',
        counterpartId: 'coach9',
        recipientRole: 'athlete',
      );
      final decoded = NotificationPayload.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.type, 'chat_message');
      expect(decoded.chatId, 'chat_1_2');
      expect(decoded.counterpartId, 'coach9');
      expect(decoded.recipientRole, 'athlete');
    });

    test('FCM string values and null-ish placeholders are normalised', () {
      final p = NotificationPayload.fromData({
        'type': 'chat_message',
        'chatId': '',           // empty -> null
        'senderId': 'null',     // literal "null" from a stringified payload -> null
        'counterpartId': ' c9 ', // trimmed
      });
      expect(p.chatId, isNull);
      expect(p.senderId, isNull);
      expect(p.counterpartId, 'c9');
    });

    test('malformed local payload decodes to null instead of throwing', () {
      expect(NotificationPayload.decode('not json'), isNull);
      expect(NotificationPayload.decode(null), isNull);
      expect(NotificationPayload.decode(''), isNull);
    });
  });
}
