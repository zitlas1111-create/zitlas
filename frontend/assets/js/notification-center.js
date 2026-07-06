/*!
 * ZITLAS — Notification Center (assets/js/notification-center.js)
 *
 * The central activity feed for the entire app. Any feature — present or
 * future — creates a notification by calling ONE function:
 *
 *   ZitlasNotify.send(userId, {
 *     title, message,
 *     category,   // any string — see CATEGORY_META for the known set,
 *                 // but unknown categories still render fine (generic icon)
 *     type,       // optional specific sub-type, e.g. 'review_completed'
 *     icon,       // optional emoji override; falls back to category icon
 *     action,     // optional page key — see navigateForAction()
 *     actionId,   // optional id passed to the action (e.g. expertId)
 *     priority,   // optional 'critical'|'high'|'medium'|'low'; inferred
 *                 // from category if omitted
 *   })
 *
 * The Notification Center page (pages/notifications/) never switches on a
 * fixed enum of types — it renders whatever's in the document. New
 * features never need to touch that page.
 *
 * Firestore: notifications/{notificationId}
 *   { notificationId, userId, title, message, category, icon, type,
 *     action, actionId, isRead, priority, createdAt }
 *
 * FCM-READY: every field above is a flat primitive, which is exactly the
 * shape a Cloud Function trigger needs to call FCM — e.g. on document
 * create, send `{notification:{title, body: message}, data:{category,
 * type, action, actionId}}` to the user's registered device token. No
 * Cloud Function exists yet; this is what "future ready" means here.
 */
(function (win) {
  'use strict';

  function db() { return (typeof ZitlasDB !== 'undefined') ? ZitlasDB : null; }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function newId() { return 'NTF_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8); }
  function myUid() {
    if (typeof ZitlasAuth !== 'undefined' && ZitlasAuth.currentUser) return ZitlasAuth.currentUser.uid;
    try {
      var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || 'null');
      if (fb && fb.uid) return fb.uid;
    } catch (_) {}
    return localStorage.getItem('zitlas_athlete_id') || null;
  }

  /* Rendering/filtering metadata only — NEVER used to gate what can be
     created. An unrecognized category still saves and displays fine. */
  var CATEGORY_META = {
    achievement:    { icon: '🏆', label: 'Achievement',    priority: 'low',      filter: 'achievements' },
    ai_coach:       { icon: '🤖', label: 'AI Coach',       priority: 'medium',   filter: 'ai' },
    expert:         { icon: '👨‍⚕️', label: 'Expert',        priority: 'high',     filter: 'coach' },
    chat:           { icon: '💬', label: 'Chat',           priority: 'high',     filter: 'chats' },
    diet:           { icon: '🥗', label: 'Diet',           priority: 'medium',   filter: 'coach' },
    training:       { icon: '💪', label: 'Training',       priority: 'medium',   filter: 'coach' },
    meal_snap:      { icon: '📷', label: 'Meal Snap',      priority: 'medium',   filter: 'coach' },
    review:         { icon: '⭐', label: 'Review',         priority: 'high',     filter: 'coach' },
    payment:        { icon: '💳', label: 'Payment',        priority: 'critical', filter: 'payments' },
    goal:           { icon: '🎯', label: 'Goal',           priority: 'medium',   filter: 'ai' },
    health:         { icon: '⚠️', label: 'Health',         priority: 'critical', filter: 'ai' },
    daily_reminder: { icon: '🔥', label: 'Daily Reminder', priority: 'low',      filter: 'ai' },
  };
  var PRIORITY_RANK = { critical: 4, high: 3, medium: 2, low: 1 };

  function metaFor(category) {
    return CATEGORY_META[category] || { icon: '🔔', label: category || 'Update', priority: 'medium', filter: 'all' };
  }

  /* ── Create ── */
  function send(userId, opts) {
    var d = db();
    if (!d || !userId || !opts || !opts.title) return Promise.resolve(null);
    var meta = metaFor(opts.category);
    var id = newId();
    var doc = {
      notificationId: id, userId: userId,
      title: opts.title, message: opts.message || '',
      category: opts.category || 'general',
      icon: opts.icon || meta.icon,
      type: opts.type || null,
      action: opts.action || null, actionId: opts.actionId || null,
      isRead: false,
      priority: opts.priority || meta.priority,
      createdAt: new Date().toISOString(),
    };
    console.log('[NOTIFY] send', doc);
    return d.collection('notifications').doc(id).set(doc)
      .then(function () { return doc; })
      .catch(function (e) { console.warn('[NOTIFY] send failed', e); return null; });
  }

  /* ── Read ── */
  function listenAll(userId, cb) {
    var d = db();
    if (!d || !userId) return function () {};
    return d.collection('notifications').where('userId', '==', userId)
      .onSnapshot(function (snap) {
        var items = snap.docs.map(function (x) { return x.data(); })
          .sort(function (a, b) { return (b.createdAt || '') < (a.createdAt || '') ? -1 : 1; });
        cb(items);
      }, function (e) { console.warn('[NOTIFY] listenAll error', e); });
  }
  function listenUnreadCount(userId, cb) {
    var d = db();
    if (!d || !userId) return function () {};
    return d.collection('notifications')
      .where('userId', '==', userId).where('isRead', '==', false)
      .onSnapshot(function (snap) { cb(snap.size); },
        function (e) { console.warn('[NOTIFY] unread-count error', e); });
  }

  /* ── Mutate ── */
  function markRead(notificationId) {
    var d = db();
    if (!d) return Promise.resolve();
    return d.collection('notifications').doc(notificationId).update({ isRead: true }).catch(function () {});
  }
  function markAllRead(userId) {
    var d = db();
    if (!d || !userId) return Promise.resolve();
    return d.collection('notifications').where('userId', '==', userId).where('isRead', '==', false).get()
      .then(function (snap) {
        var batch = d.batch();
        snap.docs.forEach(function (doc) { batch.update(doc.ref, { isRead: true }); });
        return batch.commit();
      }).catch(function (e) { console.warn('[NOTIFY] markAllRead failed', e); });
  }
  function deleteNotification(notificationId) {
    var d = db();
    if (!d) return Promise.resolve();
    return d.collection('notifications').doc(notificationId).delete().catch(function () {});
  }

  /* ── Navigation on tap ── */
  function navigateForAction(action, actionId) {
    switch (action) {
      case 'diet':             win.location.href = '/pages/diet/diet.html'; break;
      case 'training':         win.location.href = '/pages/dashboard/weekly-plan/weekly-plan.html'; break;
      case 'dashboard':        win.location.href = '/pages/dashboard/dashboard.html'; break;
      case 'coaches':          win.location.href = '/pages/coaches/coaches.html'; break;
      case 'expert_profile':   win.location.href = actionId ? '/pages/coaches/cprofile.html?expertId=' + encodeURIComponent(actionId) : '/pages/coaches/coaches.html'; break;
      case 'chat':             win.location.href = actionId ? '/pages/coaches/cprofile.html?expertId=' + encodeURIComponent(actionId) + '&action=ask' : '/pages/coaches/coaches.html'; break;
      case 'expert_dashboard': win.location.href = '/pages/experts/expert-dashboard.html'; break;
      case 'profile':          win.location.href = '/pages/profile/profile.html'; break;
      default: break; /* no-op — stay on the Notification Center */
    }
  }

  /* ── Daily motivation: exactly one per calendar day, deterministic dedup ── */
  var MOTIVATIONS = [
    "You're only one workout away from consistency.",
    'Every healthy meal counts — keep stacking them up.',
    'Your coach believes in you. Show up today.',
    "Small steps today, big transformation tomorrow.",
    "Consistency beats intensity — just show up.",
    'One more day of discipline is one step closer to your goal.',
    'Your future self is thanking you for today’s effort.',
    "Progress isn't always visible on the scale — trust the process.",
  ];
  function maybeSendDailyMotivation(userId) {
    if (!userId) return Promise.resolve(null);
    var today = new Date().toISOString().slice(0, 10);
    var key = 'zitlas_notify_daily_' + today;
    if (localStorage.getItem(key)) return Promise.resolve(null);
    localStorage.setItem(key, '1');

    var msg = MOTIVATIONS[Math.floor(Math.random() * MOTIVATIONS.length)];
    if (typeof ZitlasStreak !== 'undefined' && ZitlasStreak.getStreak) {
      var s = ZitlasStreak.getStreak();
      if (s && s.currentStreak >= 3) {
        msg = "You've kept a " + s.currentStreak + '-day streak going — don’t stop now!';
      }
    }
    return send(userId, {
      title: '🔥 Daily Motivation', message: msg,
      category: 'daily_reminder', action: 'dashboard',
    });
  }

  /* ── Reusable bell-icon wiring: click -> open Notification Center,
     realtime unread badge. Same three lines were about to be duplicated
     across dashboard/coaches/expert-dashboard, so it lives here once. ── */
  function wireBell(btnId, dotId, notificationsUrl) {
    var btn = document.getElementById(btnId);
    var dot = document.getElementById(dotId);
    if (!btn) return;
    btn.addEventListener('click', function () {
      win.location.href = notificationsUrl || '/pages/notifications/notifications.html';
    });
    if (!dot) return;
    dot.style.display = 'none';
    var uid = myUid();
    if (!uid) return;
    listenUnreadCount(uid, function (count) {
      if (count > 0) {
        dot.textContent = count > 9 ? '9+' : String(count);
        dot.style.display = 'flex';
        dot.style.width = 'auto';
        dot.style.minWidth = '16px';
        dot.style.height = '16px';
        dot.style.borderRadius = '9px';
        dot.style.alignItems = 'center';
        dot.style.justifyContent = 'center';
        dot.style.fontSize = '9px';
        dot.style.fontWeight = '800';
        dot.style.color = '#fff';
        dot.style.padding = '0 3px';
        dot.style.lineHeight = '1';
      } else {
        dot.style.display = 'none';
      }
    });
  }

  win.ZitlasNotify = {
    CATEGORY_META: CATEGORY_META,
    PRIORITY_RANK: PRIORITY_RANK,
    metaFor: metaFor,
    send: send,
    listenAll: listenAll,
    listenUnreadCount: listenUnreadCount,
    markRead: markRead,
    markAllRead: markAllRead,
    deleteNotification: deleteNotification,
    navigateForAction: navigateForAction,
    maybeSendDailyMotivation: maybeSendDailyMotivation,
    myUid: myUid,
    wireBell: wireBell,
  };
})(window);
