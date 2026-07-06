/*!
 * ZITLAS — Pending Requests Status Bar (assets/js/pending-requests-bar.js)
 *
 * Floating card above the bottom navbar on the Experts page. Listens
 * realtime to BOTH:
 *   review_requests        where userId == athleteUid
 *   personal_coach_requests where athleteId == athleteUid
 * and shows any request still in a "waiting" state (status: pending).
 * Self-mounting/self-injecting — no HTML changes needed beyond the
 * script/stylesheet tags.
 */
(function (win) {
  'use strict';

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function uid() {
    if (typeof ZitlasAuth !== 'undefined' && ZitlasAuth.currentUser) return ZitlasAuth.currentUser.uid;
    try {
      var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || 'null');
      if (fb && fb.uid) return fb.uid;
    } catch (_) {}
    return localStorage.getItem('zitlas_athlete_id') || null;
  }
  function db() { return (typeof ZitlasDB !== 'undefined') ? ZitlasDB : null; }

  var REVIEW_TYPE_LABEL = { diet: 'Diet Review', workout: 'Training Review', both: 'Full Plan Review' };
  var PLAN_LABEL_FALLBACK = { diet: 'Diet Coaching', training: 'Training Coaching', complete: 'Complete Transformation' };

  function timeAgo(iso) {
    if (!iso) return '';
    var ms = Date.now() - new Date(iso).getTime();
    var min = Math.floor(ms / 60000);
    if (min < 1) return 'just now';
    if (min < 60) return min + ' min ago';
    var hr = Math.floor(min / 60);
    if (hr < 24) return hr + (hr === 1 ? ' hour ago' : ' hours ago');
    var d = Math.floor(hr / 24);
    return d + (d === 1 ? ' day ago' : ' days ago');
  }

  /* ══════════════════════════════════════════════
     STATE
  ══════════════════════════════════════════════ */
  var S = {
    reviewItems: [],   /* normalized pending review requests */
    coachItems: [],    /* normalized pending coaching requests */
    prevStatus: {},    /* id -> last seen status, for transition detection */
    expanded: false,
  };

  function normalizeReview(r) {
    return {
      kind: 'review', id: r.id, raw: r,
      coachId: r.expertId, coachName: r.expertName || 'Expert',
      requestType: REVIEW_TYPE_LABEL[r.reviewType] || (r.reviewType ? r.reviewType + ' Review' : 'Plan Review'),
      submittedAt: r.submittedAt || r.createdAt,
      status: r.status || 'pending',
    };
  }
  function normalizeCoach(r) {
    return {
      kind: 'coaching', id: r.requestId, raw: r,
      coachId: r.expertId, coachName: r.expertName || 'Expert',
      requestType: r.planLabel || PLAN_LABEL_FALLBACK[r.planType] || 'Personal Coaching',
      submittedAt: r.createdAt,
      status: r.status || 'pending',
    };
  }

  function allPending() {
    return S.reviewItems.filter(function (i) { return i.status === 'pending'; })
      .concat(S.coachItems.filter(function (i) { return i.status === 'pending'; }));
  }

  /* ══════════════════════════════════════════════
     TOAST + SUCCESS OVERLAY
  ══════════════════════════════════════════════ */
  var _toastEl = null, _toastTimer = null;
  function toast(msg) {
    if (!_toastEl) {
      _toastEl = document.createElement('div');
      _toastEl.className = 'prb-toast';
      document.body.appendChild(_toastEl);
    }
    _toastEl.textContent = msg;
    _toastEl.classList.add('show');
    clearTimeout(_toastTimer);
    _toastTimer = setTimeout(function () { _toastEl.classList.remove('show'); }, 3400);
  }

  function ensureSuccessOverlay() {
    var el = $('prbSuccessOverlay');
    if (el) return el;
    el = document.createElement('div');
    el.id = 'prbSuccessOverlay';
    el.className = 'prb-success-overlay';
    document.body.appendChild(el);
    return el;
  }
  function showSuccess(coachName, navigateUrl) {
    var el = ensureSuccessOverlay();
    el.innerHTML =
      '<div class="prb-success-check">✅</div>' +
      '<p class="prb-success-title">' + esc(coachName) + ' accepted your coaching request.</p>' +
      '<p class="prb-success-sub">Opening coaching dashboard…</p>';
    el.classList.add('show');
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { el.classList.add('open'); });
    });
    setTimeout(function () {
      if (navigateUrl) win.location.href = navigateUrl;
    }, 2000);
  }

  /* ══════════════════════════════════════════════
     TRANSITION DETECTION (fires toasts / success overlay once per change)
  ══════════════════════════════════════════════ */
  function detectTransitions(items) {
    items.forEach(function (it) {
      var prev = S.prevStatus[it.id];
      if (prev && prev !== it.status) {
        if (it.kind === 'coaching' && it.status === 'accepted') {
          showSuccess(it.coachName, 'cprofile.html?expertId=' + encodeURIComponent(it.coachId));
        } else if (it.kind === 'coaching' && it.status === 'declined') {
          toast('Your coaching request with ' + it.coachName + ' was declined.');
        } else if (it.kind === 'review' && it.status === 'in_progress') {
          toast('🎉 ' + it.coachName + ' started reviewing your plan.');
        } else if (it.kind === 'review' && it.status === 'rejected') {
          toast(it.coachName + ' was unable to accept your review request.');
        }
      }
      S.prevStatus[it.id] = it.status;
    });
  }

  /* ══════════════════════════════════════════════
     FIRESTORE LISTENERS
  ══════════════════════════════════════════════ */
  function attachListeners() {
    var d = db();
    var myUid = uid();
    if (!d || !myUid) return;

    d.collection('review_requests').where('userId', '==', myUid)
      .onSnapshot(function (snap) {
        var items = snap.docs.map(function (x) { return normalizeReview(x.data()); });
        detectTransitions(items);
        S.reviewItems = items;
        render();
      }, function (e) { console.warn('[PENDING BAR] review listener error', e); });

    d.collection('personal_coach_requests').where('athleteId', '==', myUid)
      .onSnapshot(function (snap) {
        var items = snap.docs.map(function (x) { return normalizeCoach(x.data()); });
        detectTransitions(items);
        S.coachItems = items;
        render();
      }, function (e) { console.warn('[PENDING BAR] coaching listener error', e); });
  }

  /* ══════════════════════════════════════════════
     WITHDRAW (transaction re-checks status server-side, same guard pattern
     as the athlete's Withdraw Request flow on cprofile.js)
  ══════════════════════════════════════════════ */
  function withdraw(item, btn) {
    var d = db();
    if (!d) return;
    var col = item.kind === 'review' ? 'review_requests' : 'personal_coach_requests';
    var docRef = d.collection(col).doc(item.id);
    if (btn) { btn.disabled = true; btn.textContent = 'Withdrawing…'; }

    d.runTransaction(function (tx) {
      return tx.get(docRef).then(function (snap) {
        if (!snap.exists) throw new Error('not_found');
        if (snap.data().status !== 'pending') throw new Error('not_pending');
        tx.update(docRef, { status: 'withdrawn', withdrawnAt: new Date().toISOString() });
      });
    }).then(function () {
      console.log('[PENDING BAR] withdrawn', col, item.id);
      toast('Request withdrawn.');
      closeModal();
    }).catch(function (err) {
      console.error('[PENDING BAR] withdraw failed', err);
      toast(err && err.message === 'not_pending'
        ? 'This request was already updated — refreshing.'
        : 'Could not withdraw — please try again.');
      if (btn) { btn.disabled = false; btn.textContent = 'Withdraw Request'; }
    });
  }

  /* ══════════════════════════════════════════════
     DETAIL MODAL
  ══════════════════════════════════════════════ */
  function ensureModal() {
    var bd = $('prbModalBackdrop');
    if (bd) return bd;
    bd = document.createElement('div');
    bd.id = 'prbModalBackdrop';
    bd.className = 'prb-modal-backdrop';
    bd.innerHTML = '<div class="prb-modal" id="prbModal"></div>';
    document.body.appendChild(bd);
    bd.addEventListener('click', function (e) { if (e.target === bd) closeModal(); });
    return bd;
  }
  function closeModal() {
    var bd = $('prbModalBackdrop');
    if (!bd) return;
    bd.classList.remove('open');
    setTimeout(function () { bd.style.display = 'none'; }, 200);
  }
  function hasExistingChat(coachId) {
    try {
      var myUid = uid();
      var all = JSON.parse(localStorage.getItem('zitlas_chats') || '{}');
      var conv = all['chat_' + myUid + '_' + coachId];
      return !!(conv && conv.messages && conv.messages.length);
    } catch (_) { return false; }
  }

  function openModal(item) {
    var bd = ensureModal();
    var pillCls = 'prb-status-pill--' + (
      item.status === 'accepted' ? 'accepted' :
      item.status === 'rejected' || item.status === 'declined' ? 'rejected' :
      item.status === 'in_progress' || item.status === 'active' ? 'accepted' :
      item.status === 'review_completed' || item.status === 'completed' ? 'completed' : 'pending'
    );
    var statusText = {
      pending: 'Pending', in_progress: 'In Progress', accepted: 'Accepted',
      rejected: 'Rejected', declined: 'Declined',
      review_completed: 'Completed', completed: 'Completed', active: 'Active',
    }[item.status] || item.status;

    $('prbModal').innerHTML =
      '<p class="prb-modal-title">' + (item.kind === 'coaching' ? '👨‍🏫 Coaching Request' : '📝 Review Request') + '</p>' +
      '<div class="prb-modal-row"><span>Coach</span><b>' + esc(item.coachName) + '</b></div>' +
      '<div class="prb-modal-row"><span>Request Type</span><b>' + esc(item.requestType) + '</b></div>' +
      '<div class="prb-modal-row"><span>Submitted</span><b>' + esc(timeAgo(item.submittedAt)) + '</b></div>' +
      '<div class="prb-modal-row"><span>Status</span><b><span class="prb-status-pill ' + pillCls + '">' + esc(statusText) + '</span></b></div>' +
      '<div class="prb-modal-row"><span>Est. Response</span><b>Usually within 24–48 hrs</b></div>' +
      '<div class="prb-modal-actions">' +
        (hasExistingChat(item.coachId) ? '<button class="prb-modal-btn prb-modal-btn--msg" id="prbMsgBtn">Message Coach</button>' : '') +
        '<button class="prb-modal-btn prb-modal-btn--withdraw" id="prbWithdrawBtn">Withdraw Request</button>' +
      '</div>' +
      '<button class="prb-modal-close" id="prbCloseBtn">Close</button>';

    bd.style.display = 'flex';
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { bd.classList.add('open'); });
    });

    var msgBtn = $('prbMsgBtn');
    if (msgBtn) msgBtn.addEventListener('click', function () {
      win.location.href = 'cprofile.html?expertId=' + encodeURIComponent(item.coachId);
    });
    $('prbWithdrawBtn').addEventListener('click', function () { withdraw(item, $('prbWithdrawBtn')); });
    $('prbCloseBtn').addEventListener('click', closeModal);
  }

  /* ══════════════════════════════════════════════
     BAR RENDER
  ══════════════════════════════════════════════ */
  function ensureBar() {
    var el = $('prbBar');
    if (el) return el;
    el = document.createElement('div');
    el.id = 'prbBar';
    el.className = 'prb-bar';
    document.body.appendChild(el);
    return el;
  }

  function render() {
    var pending = allPending();
    var bar = ensureBar();

    if (!pending.length) {
      bar.classList.remove('open', 'expanded');
      bar.classList.remove('show');
      return;
    }

    var single = pending.length === 1 ? pending[0] : null;

    if (single) {
      var icon = single.kind === 'coaching' ? '⏳' : '📝';
      var title = single.kind === 'coaching' ? 'Waiting for Coach' : 'Review Requested';
      bar.innerHTML =
        '<div class="prb-row">' +
          '<span class="prb-icon">' + icon + '</span>' +
          '<div class="prb-body">' +
            '<p class="prb-title">' + esc(title) + '</p>' +
            '<p class="prb-sub">' + esc(single.requestType) + ' — ' + esc(single.coachName) +
              ' · ' + esc(timeAgo(single.submittedAt)) + '</p>' +
          '</div>' +
        '</div>';
      bar.onclick = function () { openModal(single); };
      bar.classList.remove('expanded');
    } else {
      bar.innerHTML =
        '<div class="prb-row">' +
          '<span class="prb-icon">⏳</span>' +
          '<div class="prb-body">' +
            '<p class="prb-title">' + pending.length + ' Pending Requests</p>' +
            '<p class="prb-sub">Tap to view</p>' +
          '</div>' +
          '<svg class="prb-chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>' +
        '</div>' +
        '<div class="prb-list">' +
          pending.map(function (it) {
            return '<div class="prb-item" data-prb-item="' + esc(it.id) + '">' +
              '<span class="prb-item-dot"></span>' +
              '<span class="prb-item-text">' + esc(it.requestType) + ' — ' + esc(it.coachName) +
                '<span class="prb-item-sub">' + esc(timeAgo(it.submittedAt)) + '</span></span>' +
            '</div>';
          }).join('') +
        '</div>';
      bar.onclick = function (e) {
        var itemEl = e.target.closest('[data-prb-item]');
        if (itemEl) {
          var found = pending.find(function (p) { return p.id === itemEl.dataset.prbItem; });
          if (found) openModal(found);
          return;
        }
        bar.classList.toggle('expanded');
      };
    }

    bar.classList.add('show');
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { bar.classList.add('open'); });
    });
  }

  /* ── Boot ── */
  function init() { attachListeners(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  win.ZitlasPendingRequestsBar = { refresh: render };
})(window);
