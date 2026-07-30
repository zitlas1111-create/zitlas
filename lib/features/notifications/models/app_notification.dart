import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/util/json_coerce.dart';

/// `notifications/{notificationId}` — mirrors `ZitlasNotify.send()`'s doc
/// shape exactly (`assets/js/notification-center.js`). This is the ONE real
/// central activity feed already in production (backend `coaching.py`'s
/// `notify()` and multiple website JS files write here); a Cloud Function
/// that turns these into OS push notifications does not exist yet — see
/// docs/MIGRATION_INVENTORY.md Phase 8 for why that's a real, pre-existing
/// gap rather than something faked from the client.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    this.message = '',
    this.category = 'general',
    this.icon,
    this.type,
    this.action,
    this.actionId,
    this.expertId,
    this.isRead = false,
    this.priority = 'medium',
    this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final String message;
  final String category;
  final String? icon;
  final String? type;

  /// A page key `navigateForAction()` (notification-center.js:145-157)
  /// switches on — e.g. `'diet'`, `'training'`, `'chat'`, `'expert_profile'`.
  final String? action;
  final String? actionId;
  final String? expertId;
  final bool isRead;

  /// `'critical' | 'high' | 'medium' | 'low'`
  final String priority;
  final DateTime? createdAt;

  static const Map<String, ({String icon, String label})> categoryMeta = {
    'achievement': (icon: '🏆', label: 'Achievement'),
    'ai_coach': (icon: '🤖', label: 'AI Coach'),
    'expert': (icon: '👨‍⚕️', label: 'Expert'),
    'chat': (icon: '💬', label: 'Chat'),
    'diet': (icon: '🥗', label: 'Diet'),
    'training': (icon: '💪', label: 'Training'),
    'meal_snap': (icon: '📷', label: 'Meal Snap'),
    'review': (icon: '⭐', label: 'Review'),
    'payment': (icon: '💳', label: 'Payment'),
    'goal': (icon: '🎯', label: 'Goal'),
    'health': (icon: '⚠️', label: 'Health'),
    'daily_reminder': (icon: '🔥', label: 'Daily Reminder'),
  };

  String get displayIcon => icon ?? categoryMeta[category]?.icon ?? '🔔';

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) {
    final createdRaw = m['createdAt'];
    return AppNotification(
      id: id,
      userId: asText(m['userId']) ?? '',
      title: asText(m['title']) ?? '',
      message: asText(m['message']) ?? '',
      category: asText(m['category']) ?? 'general',
      icon: asText(m['icon']),
      type: asText(m['type']),
      action: asText(m['action']),
      actionId: asText(m['actionId']),
      expertId: asText(m['expertId']),
      isRead: m['isRead'] == true,
      priority: asText(m['priority']) ?? 'medium',
      createdAt: createdRaw is Timestamp ? createdRaw.toDate() : DateTime.tryParse(asText(createdRaw) ?? ''),
    );
  }
}
