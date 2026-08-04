/*!
 * ZITLAS — Notification Center page (pages/notifications/notifications.js)
 * Renders whatever's in the notifications collection — no hardcoded switch
 * over notification types. New features never need to touch this file.
 */
(function () {
  'use strict';

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  var _all = [];
  var _filter = 'all';
  var _uid = null;

  function timeAgo(iso) {
    if (!iso) return '';
    var min = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
    if (min < 1) return 'just now';
    if (min < 60) return min + 'm ago';
    var hr = Math.floor(min / 60);
    if (hr < 24) return hr + 'h ago';
    var d = new Date(iso);
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  }
  function dateBucket(iso) {
    var d = new Date(iso);
    var now = new Date();
    var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var startYest = new Date(startToday); startYest.setDate(startYest.getDate() - 1);
    if (d >= startToday) return 'Today';
    if (d >= startYest) return 'Yesterday';
    return 'Earlier';
  }

  function matchesFilter(n) {
    if (_filter === 'all') return true;
    if (_filter === 'unread') return !n.isRead;
    var meta = ZitlasNotify.metaFor(n.category);
    return meta.filter === _filter;
  }

  function render() {
    var main = $('ncMain');
    var items = _all.filter(matchesFilter);

    if (!items.length) {
      main.innerHTML =
        '<div class="nc-empty">' +
          '<span class="nc-empty-icon">🎉</span>' +
          '<p class="nc-empty-title">You’re all caught up!</p>' +
          '<p class="nc-empty-sub">We’ll notify you when something important happens.</p>' +
        '</div>';
      return;
    }

    var groups = { Today: [], Yesterday: [], Earlier: [] };
    items.forEach(function (n) { groups[dateBucket(n.createdAt)].push(n); });

    var html = '';
    ['Today', 'Yesterday', 'Earlier'].forEach(function (label) {
      if (!groups[label].length) return;
      html += '<div class="nc-group-label">' + label + '</div>';
      html += groups[label].map(buildCard).join('');
    });
    main.innerHTML = html;
    wireCards();
    _fillNotificationBadges();
  }

  function buildCard(n) {
    var priorityCls = n.priority === 'critical' ? ' nc-priority-critical' : n.priority === 'high' ? ' nc-priority-high' : '';
    var titleBadge = n.expertId ? '<span class="nc-item-badge" data-expert-id="' + esc(n.expertId) + '"></span>' : '';
    return (
      '<div class="nc-item-wrap" data-ntf-wrap="' + esc(n.notificationId) + '">' +
        '<div class="nc-item-delete-bg">Delete</div>' +
        '<div class="nc-item' + (n.isRead ? '' : ' nc-item--unread') + priorityCls + '" data-ntf="' + esc(n.notificationId) + '">' +
          '<div class="nc-item-icon">' + esc(n.icon || '🔔') + '</div>' +
          '<div class="nc-item-body">' +
            '<div class="nc-item-title-row"><div class="nc-item-title">' + esc(n.title) + '</div>' + titleBadge + '</div>' +
            (n.message ? '<div class="nc-item-msg">' + esc(n.message) + '</div>' : '') +
            '<div class="nc-item-time">' + esc(timeAgo(n.createdAt)) + '</div>' +
          '</div>' +
          (n.isRead ? '' : '<span class="nc-item-dot"></span>') +
        '</div>' +
      '</div>'
    );
  }

  /* Batches the badge lookups: one fetch per distinct expertId on screen,
     no matter how many notifications mention them. */
  function _fillNotificationBadges() {
    if (typeof ZitlasBadge === 'undefined') return;
    var seen = {};
    document.querySelectorAll('.nc-item-badge[data-expert-id]').forEach(function (el) {
      var id = el.dataset.expertId;
      if (!id || seen[id]) return;
      seen[id] = true;
      ZitlasBadge.fetchVerification(id).then(function (v) {
        var html = ZitlasBadge.render(v, { size: 'sm' });
        if (!html) return;
        document.querySelectorAll('.nc-item-badge[data-expert-id="' + id + '"]').forEach(function (b) { b.innerHTML = html; });
      });
    });
  }

  /* Swipe-to-delete via pointer events; tap (no meaningful drag) opens it. */
  function wireCards() {
    document.querySelectorAll('[data-ntf]').forEach(function (card) {
      var id = card.dataset.ntf;
      var notif = _all.find(function (n) { return n.notificationId === id; });
      if (!notif) return;

      var startX = null, dx = 0, dragging = false;
      card.addEventListener('pointerdown', function (e) {
        startX = e.clientX; dx = 0; dragging = true;
        card.style.transition = 'none';
      });
      card.addEventListener('pointermove', function (e) {
        if (!dragging || startX === null) return;
        dx = e.clientX - startX;
        if (dx > 0) dx = 0; /* only swipe left */
        card.style.transform = 'translateX(' + Math.max(dx, -110) + 'px)';
      });
      function endDrag() {
        if (!dragging) return;
        dragging = false;
        card.style.transition = 'transform 0.2s ease';
        if (dx < -70) {
          card.style.transform = 'translateX(-100%)';
          setTimeout(function () {
            ZitlasNotify.deleteNotification(id);
          }, 180);
        } else {
          card.style.transform = '';
          if (Math.abs(dx) < 6) openNotification(notif);
        }
        startX = null;
      }
      card.addEventListener('pointerup', endDrag);
      card.addEventListener('pointercancel', endDrag);
      card.addEventListener('pointerleave', function () { if (dragging && dx === 0) endDrag(); });
    });
  }

  function openNotification(n) {
    if (!n.isRead) ZitlasNotify.markRead(n.notificationId);
    if (n.action) ZitlasNotify.navigateForAction(n.action, n.actionId);
  }

  function initFilters() {
    document.querySelectorAll('[data-filter]').forEach(function (chip) {
      chip.addEventListener('click', function () {
        _filter = chip.dataset.filter;
        document.querySelectorAll('[data-filter]').forEach(function (c) { c.classList.remove('active'); });
        chip.classList.add('active');
        render();
      });
    });
  }

  function boot() {
    $('ncBack').addEventListener('click', function () {
      if (window.history.length > 1) window.history.back();
      else window.location.href = '../dashboard/dashboard.html';
    });
    $('ncMarkAll').addEventListener('click', function () {
      if (_uid) ZitlasNotify.markAllRead(_uid);
    });
    initFilters();

    if (typeof ZitlasAuth === 'undefined') { render(); return; }
    ZitlasAuth.onAuthStateChanged(function (user) {
      _uid = (user && user.uid) || ZitlasNotify.myUid();
      if (!_uid) { render(); return; }
      ZitlasNotify.listenAll(_uid, function (items) {
        _all = items;
        render();
      });
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
