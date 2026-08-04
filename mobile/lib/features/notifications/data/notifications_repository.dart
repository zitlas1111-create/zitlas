import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';

/// Native port of `ZitlasNotify` (assets/js/notification-center.js) — the
/// SAME `notifications` collection every website page and `coaching.py`'s
/// backend `notify()` already write to. No new collection, no new schema.
class NotificationsRepository {
  NotificationsRepository({required FirebaseFirestore firestore}) : _db = firestore;

  final FirebaseFirestore _db;

  /// `send(userId, opts)` (notification-center.js:75-100) — any feature
  /// creates a notification through this one call. `title` is required;
  /// a no-op (matches web) when missing.
  Future<void> send({
    required String userId,
    required String title,
    String message = '',
    String category = 'general',
    String? icon,
    String? type,
    String? action,
    String? actionId,
    String? expertId,
    String priority = 'medium',
  }) async {
    if (title.isEmpty) return;
    final id = 'NTF_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecond).toRadixString(36)}';
    await _db.collection('notifications').doc(id).set({
      'notificationId': id,
      'userId': userId,
      'title': title,
      'message': message,
      'category': category,
      'icon': icon,
      'type': type,
      'action': action,
      'actionId': actionId,
      'expertId': expertId,
      'isRead': false,
      'priority': priority,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// `listenAll()` — no `orderBy` (avoids a composite index requirement,
  /// same reasoning used throughout this codebase), sorted client-side.
  Stream<List<AppNotification>> watchAll(String userId) {
    return _db.collection('notifications').where('userId', isEqualTo: userId).snapshots().map((snap) {
      final list = snap.docs.map((d) => AppNotification.fromMap(d.id, d.data())).toList();
      list.sort((a, b) {
        final ad = a.createdAt, bd = b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  Stream<int> watchUnreadCount(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  Future<void> markRead(String notificationId) {
    return _db.collection('notifications').doc(notificationId).update({'isRead': true}).catchError((_) {});
  }

  Future<void> markAllRead(String userId) async {
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> delete(String notificationId) {
    return _db.collection('notifications').doc(notificationId).delete().catchError((_) {});
  }
}
