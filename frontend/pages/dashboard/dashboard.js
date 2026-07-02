/* =============================================
   ZITLAS Dashboard — dashboard.js
   ============================================= */

(function () {
  'use strict';

  /* ══════════════════════════════════════════
     RECENT CHATS
     Reads from zitlas_chats localStorage. Shows
     empty state when no real conversations exist.
  ══════════════════════════════════════════ */
  function renderChats() {
    const list = document.getElementById('dashChatsList');
    if (!list) return;

    var chats = [];
    try {
      var raw = localStorage.getItem('zitlas_chats');
      if (raw) {
        var stored = JSON.parse(raw);
        /* zitlas_chats is an object keyed by conversationId */
        if (stored && typeof stored === 'object' && !Array.isArray(stored)) {
          chats = Object.values(stored).map(function(conv) {
            var lastMsg = (conv.messages && conv.messages.length)
              ? conv.messages[conv.messages.length - 1]
              : null;
            var name = conv.expertName || conv.coachName || 'Expert';
            var initials = name.split(' ').slice(0, 2).map(function(w) { return w[0] || ''; }).join('').toUpperCase();
            return {
              initials: initials,
              color:    'var(--primary)',
              name:     name,
              role:     conv.expertRole || 'Expert',
              msg:      lastMsg ? (lastMsg.text || lastMsg.content || '') : 'No messages yet',
              time:     lastMsg ? (lastMsg.time || '') : '',
              unread:   conv.unreadByAthlete || 0,
            };
          }).filter(function(c) { return c.msg; });
        }
      }
    } catch (_) {}

    if (!chats.length) {
      list.innerHTML = '<div class="dash-chat-empty">'
        + '<div class="dash-chat-empty-icon">💬</div>'
        + '<div class="dash-chat-empty-text">No conversations yet</div>'
        + '<div class="dash-chat-empty-sub">Connect with a coach or nutritionist to start a chat</div>'
        + '</div>';
      return;
    }

    list.innerHTML = chats.map(function(c) {
      const badge = c.unread > 0 ? `<div class="dash-chat-unread">${c.unread}</div>` : '';
      return `<div class="dash-chat-card${c.unread > 0 ? ' unread' : ''}">`
        + `<div class="dash-chat-avatar" style="background:${c.color}1F;color:${c.color};border:1.5px solid ${c.color}40;">${c.initials}</div>`
        + `<div class="dash-chat-info"><div class="dash-chat-name">${c.name}</div><div class="dash-chat-role">${c.role}</div><div class="dash-chat-msg">${c.msg}</div></div>`
        + `<div class="dash-chat-right"><div class="dash-chat-time">${c.time}</div>${badge}</div>`
        + `</div>`;
    }).join('');
    list.querySelectorAll('.dash-chat-card').forEach(function(card) {
      card.addEventListener('click', function() { showToast('Chats — coming soon!'); });
    });
  }

  /* ══════════════════════════════════════════
     STORAGE KEYS
  ══════════════════════════════════════════ */
  const THEME_KEY      = 'zitlas_theme';
  const GOAL_KEY       = 'zitlas_goal';
  const SURVEY_KEY     = 'zitlas_survey';
  const SURVEY_PROG    = 'zitlas_survey_progress'; /* survey page progress counter */
  const ROADMAP_KEY    = 'zitlas_roadmap';
  const RECOMMEND_KEY  = 'zitlas_recommendations';

  /* ══════════════════════════════════════════
     GOAL TYPE → display name
  ══════════════════════════════════════════ */
  const GOAL_NAMES = {
    'Weight Loss': 'Lose Weight',
    'Eat Healthier': 'Eat Healthier',
    Nutrition: 'Improve Nutrition',
    Fitness:   'Improve Fitness',
    Habits:    'Build Better Habits',
    Custom:    'Personal Goal',
  };

  const GOAL_UNITS = {
    'Weight Loss': 'kg',
    'Eat Healthier': 'Score',
    Nutrition: 'Score',
    Fitness:   'Score',
    Habits:    'Streak',
    Custom:    'Value',
  };

  /* ══════════════════════════════════════════
     THEME
  ══════════════════════════════════════════ */
  const html = document.documentElement;

  function getSystemTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(pref) {
    const resolved = pref === 'system' ? getSystemTheme() : pref;
    html.setAttribute('data-theme', resolved);
  }

  function loadTheme() {
    applyTheme(localStorage.getItem(THEME_KEY) || 'dark');
  }

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if ((localStorage.getItem(THEME_KEY) || 'dark') === 'system') applyTheme('system');
  });

  /* ══════════════════════════════════════════
     TOAST
  ══════════════════════════════════════════ */
  let toastTimer = null;

  function showToast(msg, duration = 2800) {
    const el = document.getElementById('toast');
    if (!el) return;
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), duration);
  }

  /* ══════════════════════════════════════════
     GREETING
  ══════════════════════════════════════════ */
  function initGreeting() {
    const lineEl = document.getElementById('greetingLine');
    const nameEl = document.getElementById('greetingName');
    if (lineEl) {
      const h = new Date().getHours();
      lineEl.textContent = h < 12 ? 'Good Morning,' : h < 17 ? 'Good Afternoon,' : 'Good Evening,';
    }
    if (nameEl) {
      try {
        var _u    = JSON.parse(localStorage.getItem('zitlas_user')          || '{}');
        var _pi   = JSON.parse(localStorage.getItem('zitlas_personal_info') || '{}');
        var _fb   = JSON.parse(localStorage.getItem('zitlas_firebase_user') || '{}');
        var _full = (_pi.fullName || _u.name || _fb.name || _fb.displayName || '').trim();
        var _first = _full.split(/\s+/)[0] || '';
        nameEl.textContent = _first ? _first + '! 👋' : 'Athlete! 👋';
      } catch (_) {}
    }
  }

  /* ══════════════════════════════════════════
     NOTIFICATION BELL
  ══════════════════════════════════════════ */
  function initNotifBell() {
    const btn = document.getElementById('notifBtn');
    const dot = document.getElementById('notifDot');
    if (!btn) return;
    btn.addEventListener('click', () => {
      if (dot) {
        dot.style.transform = 'scale(1.7)';
        setTimeout(() => { dot.style.transform = ''; }, 500);
      }
      showToast('No new notifications');
    });
  }

  /* ══════════════════════════════════════════
     GOAL — HELPERS
  ══════════════════════════════════════════ */
  function loadGoal() {
    try {
      const goal = JSON.parse(localStorage.getItem(GOAL_KEY));
      console.log('GOAL:', goal ? `${goal.goalName} (${goal.type}) — ${goal.currentVal}→${goal.targetVal}` : 'null');
      return goal;
    } catch { return null; }
  }

  function saveGoal(goal) {
    localStorage.setItem(GOAL_KEY, JSON.stringify(goal));
  }

  function clearGoal() {
    localStorage.removeItem(GOAL_KEY);
  }

  /* Removes EVERYTHING tied to the user's generated fitness profile so the
     app behaves like a brand-new user after Reset Goal. Deliberately keeps:
     identity/session (zitlas_user, zitlas_token, zitlas_firebase_user, …),
     chat history (zitlas_chats), wallet, theme, and streak — those belong
     to the account, not to the goal being reset. */
  function clearAllGoalData() {
    const keys = [
      /* Core survey + goal data */
      GOAL_KEY, SURVEY_KEY, SURVEY_PROG, ROADMAP_KEY, RECOMMEND_KEY,
      /* Brain 1 (Mental) */
      'mental_scores', 'mental_swot', 'mental_recommendations', 'mental_assessment',
      /* Brain 2 (Physical) */
      'physical_scores', 'physical_swot', 'physical_recommendations', 'physical_bottleneck', 'physical_assessment',
      /* Lifestyle & Brain 3 (Nutrition) */
      'lifestyle_data', 'nutrition_scores', 'nutrition_swot', 'nutrition_recommendations',
      'nutrition_bottleneck', 'nutrition_assessment', 'nutrition_weekly_plan',
      /* User profile + SWOT */
      'athlete_profile', 'athlete_summary', 'overall_score', 'athlete_tier', 'development_priority', 'zitlas_swot',
      /* Fitness snapshot (BMI/TDEE/calorie/protein targets) + assessment —
         written by ai-coach.js saveToLocalStorage() on plan generation */
      'zitlas_calculations', 'zitlas_assessment',
      /* Generated plans + metadata (incl. legacy plan-source fallback keys
         still read by cprofile.js) */
      'zitlas_diet_plan', 'zitlas_workout_plan', 'zitlas_current_diet',
      'zitlas_generated_diet', 'zitlas_meal_plan', 'zitlas_meal_swap_history',
      'zitlas_sources', 'zitlas_plan_generated_at', 'zitlas_plan_id',
      /* Expert review cycle — tied to the plan being discarded (same list
         ai-coach.js clears when a new plan is generated) */
      'zitlas_expert_review', 'zitlas_plan_versions', 'zitlas_review_request',
      'expert_plan_reviews', 'expert_review', 'expert_diet_override', 'reviewed_diet_plan',
      'modifiedBy', 'expertApproval', 'review_request',
      'expertDiet', 'expertOverride', 'dietOverride', 'reviewStatus',
      'expertReviewedPlan', 'approvedPlan', 'expertWorkoutOverride',
    ];
    keys.forEach(k => localStorage.removeItem(k));
    console.log('[GOAL] clearAllGoalData — cleared', keys.length, 'keys; remaining zitlas_* keys:',
      Object.keys(localStorage).filter(k => k.startsWith('zitlas_')));
  }

  function clearAllSurveyData() {
    clearAllGoalData();
  }

  function calcDaysLeft(endDateStr) {
    if (!endDateStr) return null;
    const end  = new Date(endDateStr);
    const now  = new Date();
    end.setHours(0, 0, 0, 0);
    now.setHours(0, 0, 0, 0);
    return Math.max(0, Math.ceil((end - now) / 86400000));
  }

  function formatDate(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  /* ══════════════════════════════════════════
     GOAL RING ANIMATION
  ══════════════════════════════════════════ */
  const CIRCUMFERENCE = 188.496; // 2π × r=30

  function animateRing(pct) {
    const ring = document.getElementById('goalRing');
    if (!ring) return;
    const offset = CIRCUMFERENCE * (1 - Math.min(pct, 100) / 100);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        ring.style.strokeDashoffset = offset;
      });
    });
  }

  /* ══════════════════════════════════════════
     RENDER GOAL CARD
  ══════════════════════════════════════════ */
  function renderGoalCard() {
    const goal       = loadGoal();
    const btn        = document.getElementById('goalActionBtn');
    const surveyDone = !!localStorage.getItem(SURVEY_KEY);

    if (!goal || !surveyDone) {
      document.getElementById('goalTitle').textContent    = 'No goal set yet.';
      document.getElementById('goalPct').textContent      = '0%';
      document.getElementById('goalCurrent').textContent  = '—';
      document.getElementById('goalTarget').textContent   = '—';
      document.getElementById('goalDaysLeft').textContent = 'Set a goal to begin';
      document.getElementById('goalStartDate').textContent = '—';
      document.getElementById('goalEndDate').textContent   = '—';
      document.getElementById('goalStatLabelA').textContent = 'Current';
      document.getElementById('goalStatLabelB').textContent = 'Target';
      animateRing(0);

      if (btn) {
        btn.textContent = '🎯 Set Goal';
        btn.classList.remove('reset-mode');
      }
      return;
    }

    const pct     = Math.min(100, Math.round((goal.currentVal / goal.targetVal) * 100));
    const days    = calcDaysLeft(goal.endDate);
    const unit    = GOAL_UNITS[goal.type] || 'Value';
    const name    = goal.goalName || GOAL_NAMES[goal.type] || goal.type;

    document.getElementById('goalTitle').textContent      = name;
    document.getElementById('goalPct').textContent        = pct + '%';
    document.getElementById('goalStatLabelA').textContent = 'Current ' + unit;
    document.getElementById('goalStatLabelB').textContent = 'Target ' + unit;
    document.getElementById('goalCurrent').textContent    = goal.currentVal;
    document.getElementById('goalTarget').textContent     = goal.targetVal;
    document.getElementById('goalStartDate').textContent  = formatDate(goal.startDate);
    document.getElementById('goalEndDate').textContent    = formatDate(goal.endDate);

    const daysEl = document.getElementById('goalDaysLeft');
    if (days === null)       daysEl.textContent = 'No end date';
    else if (days === 0)     daysEl.textContent = 'Goal ends today!';
    else if (days > 0)       daysEl.textContent = days + ' Days Left';

    animateRing(pct);

    if (btn) {
      btn.textContent = '🔄 Reset Goal';
      btn.classList.add('reset-mode');
    }
  }

  /* ══════════════════════════════════════════
     SET GOAL MODAL
  ══════════════════════════════════════════ */
  let selectedGoalType = 'Weight Loss';

  function openSetGoalModal() {
    const modal = document.getElementById('setGoalModal');
    if (!modal) return;

    /* Pre-fill with existing goal if any */
    const goal = loadGoal();
    if (goal) {
      selectedGoalType = goal.type;
      document.getElementById('goalCurrentInput').value    = goal.currentVal;
      document.getElementById('goalTargetInput').value     = goal.targetVal;
      document.getElementById('goalTargetDateInput').value = goal.endDate;
    } else {
      selectedGoalType = 'Weight Loss';
      document.getElementById('goalCurrentInput').value    = '';
      document.getElementById('goalTargetInput').value     = '';
      document.getElementById('goalTargetDateInput').value = '';
    }

    /* Sync type pill active state */
    document.querySelectorAll('.goal-type-pill').forEach((p) => {
      p.classList.toggle('active', p.dataset.type === selectedGoalType);
    });

    modal.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeSetGoalModal() {
    const modal = document.getElementById('setGoalModal');
    if (!modal) return;
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  function initSetGoalModal() {
    const modal    = document.getElementById('setGoalModal');
    const closeBtn = document.getElementById('closeSetGoalModal');
    const saveBtn  = document.getElementById('saveGoalBtn');
    if (!modal) return;

    /* Type pill selection */
    document.querySelectorAll('.goal-type-pill').forEach((pill) => {
      pill.addEventListener('click', () => {
        document.querySelectorAll('.goal-type-pill').forEach((p) => p.classList.remove('active'));
        pill.classList.add('active');
        selectedGoalType = pill.dataset.type;
      });
    });

    if (closeBtn) closeBtn.addEventListener('click', closeSetGoalModal);
    modal.addEventListener('click', (e) => { if (e.target === modal) closeSetGoalModal(); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeSetGoalModal(); });

    if (saveBtn) {
      saveBtn.addEventListener('click', () => {
        const cur  = parseFloat(document.getElementById('goalCurrentInput').value);
        const tgt  = parseFloat(document.getElementById('goalTargetInput').value);
        const date = document.getElementById('goalTargetDateInput').value;

        if (isNaN(cur) || cur <= 0) { showToast('⚠️ Enter a valid current value'); return; }
        if (isNaN(tgt) || tgt <= 0) { showToast('⚠️ Enter a valid target value'); return; }
        if (tgt === cur) { showToast('⚠️ Target must differ from current value'); return; }
        if (!date) { showToast('⚠️ Select a goal end date'); return; }

        const today = new Date().toISOString().split('T')[0];
        if (date <= today) { showToast('⚠️ End date must be in the future'); return; }

        saveGoal({
          type:       selectedGoalType,
          currentVal: cur,
          targetVal:  tgt,
          startDate:  today,
          endDate:    date,
        });

        closeSetGoalModal();
        renderGoalCard();
        showToast('🎯 Goal saved! Keep pushing.');
      });
    }
  }

  /* ══════════════════════════════════════════
     RESET GOAL MODAL
  ══════════════════════════════════════════ */
  function openResetGoalModal() {
    const modal = document.getElementById('resetGoalModal');
    if (!modal) return;
    modal.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeResetGoalModal() {
    const modal = document.getElementById('resetGoalModal');
    if (!modal) return;
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  function initResetGoalModal() {
    const modal      = document.getElementById('resetGoalModal');
    const cancelBtn  = document.getElementById('cancelResetBtn');
    const confirmBtn = document.getElementById('confirmResetBtn');
    if (!modal) return;

    if (cancelBtn)  cancelBtn.addEventListener('click',  closeResetGoalModal);
    modal.addEventListener('click', (e) => { if (e.target === modal) closeResetGoalModal(); });

    if (confirmBtn) {
      confirmBtn.addEventListener('click', () => {
        clearAllSurveyData();
        closeResetGoalModal();
        window.location.href = './ai-coach/ai-coach.html';
      });
    }
  }

  /* ══════════════════════════════════════════
     AUTH HELPER
  ══════════════════════════════════════════ */
  function isLoggedIn() {
    const result = !!(
      localStorage.getItem('zitlas_token') ||
      localStorage.getItem('zitlas_user')  ||
      localStorage.getItem('user')          ||
      sessionStorage.getItem('zitlas_guest')||
      sessionStorage.getItem('user')
    );
    return result;
  }

  /* ══════════════════════════════════════════
     PROFILE PHOTO — single source of truth
     Priority: custom base64 upload (zitlas_personal_info.photo)
               → Firebase/Google URL (zitlas_user.photo)
               → fallback initials SVG
  ══════════════════════════════════════════ */

  function getCurrentUserProfileImage() {
    try {
      var info = JSON.parse(localStorage.getItem('zitlas_personal_info') || '{}');
      if (info.photo && info.photo.startsWith('data:')) {
        console.log('[DASHBOARD] Loaded image: custom upload');
        return info.photo;
      }
      var zUser = JSON.parse(localStorage.getItem('zitlas_user') || '{}');
      if (zUser.photo) {
        console.log('[DASHBOARD] Loaded image:', zUser.photo);
        return zUser.photo;
      }
      var fbUser = JSON.parse(localStorage.getItem('zitlas_firebase_user') || '{}');
      var fbPhoto = fbUser.photo || fbUser.photoURL;
      if (fbPhoto) {
        console.log('[DASHBOARD] Loaded image:', fbPhoto);
        return fbPhoto;
      }
    } catch (_) {}
    console.log('[DASHBOARD] Loaded image: fallback SVG');
    return null;
  }

  function applyProfileImages() {
    var user = {};
    try { user = JSON.parse(localStorage.getItem('zitlas_user') || '{}'); } catch (_) {}
    var url      = getCurrentUserProfileImage();
    var initials = getUserInitials();

    /* ── Header avatar (top-right) ── */
    var headerAvatar = document.getElementById('headerAvatar');
    if (headerAvatar) {
      headerAvatar.src = url || makeFallbackSVG(initials, 'var(--primary)', 38);
      headerAvatar.onerror = function () {
        headerAvatar.src = makeFallbackSVG(initials, 'var(--primary)', 38);
      };
    }

    /* ── Goal card avatar ── */
    var goalPanel = document.getElementById('goalAvatarWrap');
    console.log('[ZITLAS] user photo:', url);
    console.log('[ZITLAS] avatar element:', goalPanel);

    if (goalPanel) {
      if (url) {
        goalPanel.innerHTML = '<img'
          + ' src="' + url + '"'
          + ' alt="Profile"'
          + ' style="width:100%;height:100%;object-fit:cover;border-radius:50%;"'
          + '>';
        var newImg = goalPanel.querySelector('img');
        if (newImg) {
          newImg.onerror = function () {
            goalPanel.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;'
              + 'width:100%;height:100%;font-size:3rem;font-weight:800;'
              + 'color:var(--primary);opacity:0.5;">' + initials + '</div>';
          };
        }
      } else {
        goalPanel.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;'
          + 'width:100%;height:100%;font-size:3rem;font-weight:800;'
          + 'color:var(--primary);opacity:0.5;">' + initials + '</div>';
      }
    }
  }

  function loadFirebaseUserProfile() {
    /* Sync Firebase photo URL into zitlas_user so it's available offline */
    try {
      var user = JSON.parse(localStorage.getItem('zitlas_user') || '{}');
      if (!user.photo) {
        var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || '{}');
        if (fb.photo || fb.photoURL) {
          user.photo = fb.photo || fb.photoURL;
          if (!user.name) user.name = fb.name || fb.displayName || '';
          localStorage.setItem('zitlas_user', JSON.stringify(user));
        }
      }
    } catch (e) {
      console.warn('[ZITLAS] loadFirebaseUserProfile error:', e);
    }
    applyProfileImages();
  }

  /* Firebase auth state: update localStorage then re-apply.
     Goes through applyProfileImages() so custom upload always wins. */
  if (typeof ZitlasAuth !== 'undefined') {
    ZitlasAuth.onAuthStateChanged(function (user) {
      if (user) {
        try {
          var zUser = JSON.parse(localStorage.getItem('zitlas_user') || '{}');
          if (user.photoURL) zUser.photo = user.photoURL;
          if (user.displayName) zUser.name = user.displayName;
          localStorage.setItem('zitlas_user', JSON.stringify(zUser));
        } catch (_) {}
        applyProfileImages();
      }
    });
  }

  /* Cross-tab: re-apply when personal_info or user profile changes in another tab */
  window.addEventListener('storage', function (e) {
    if (e.key === 'zitlas_personal_info' || e.key === 'zitlas_user') {
      applyProfileImages();
    }
  });

  /* Back-forward cache: refresh images when user navigates back */
  window.addEventListener('pageshow', function (e) {
    if (e.persisted) applyProfileImages();
  });

  /* ══════════════════════════════════════════
     GOAL ACTION BUTTON → auth → survey → modal
  ══════════════════════════════════════════ */
  function initGoalActionBtn() {
    const btn = document.getElementById('goalActionBtn');
    if (!btn) {
      console.error('[ZITLAS] goalActionBtn not found in DOM');
      return;
    }
    console.log('[ZITLAS] initGoalActionBtn — listener attached to', btn.id);

    btn.addEventListener('click', () => {
      console.log('[ZITLAS] Button clicked:', btn.textContent.trim());
      console.log('[ZITLAS] Checking auth');

      const loggedIn = isLoggedIn();
      console.log('[ZITLAS] User logged in:', loggedIn);

      if (!loggedIn) {
        console.log('[ZITLAS] Not logged in — opening login modal');
        openLoginModal('set-goal');
        return;
      }

      const surveyDone = !!localStorage.getItem(SURVEY_KEY);
      console.log('[ZITLAS] Survey done:', surveyDone);

      if (!surveyDone) {
        console.log('[ZITLAS] Survey not done — redirecting to coach assessment');
        window.location.href = './ai-coach/ai-coach.html';
        return;
      }

      const goal = loadGoal();
      console.log('[ZITLAS] Existing goal:', goal ? goal.goalName : 'none');

      if (goal) {
        console.log('[ZITLAS] Opening reset goal modal');
        openResetGoalModal();
      } else {
        console.log('[ZITLAS] Opening set goal modal');
        openSetGoalModal();
      }
    });
  }

  /* ══════════════════════════════════════════
     PENDING ACTION — resume goal flow after
     login page redirect (fallback path)
  ══════════════════════════════════════════ */
  function checkPendingAction() {
    const params = new URLSearchParams(window.location.search);
    if (params.get('action') !== 'set-goal') return;

    history.replaceState({}, '', window.location.pathname);
    if (!isLoggedIn()) return;

    setTimeout(() => {
      const surveyDone = !!localStorage.getItem(SURVEY_KEY);
      if (surveyDone) {
        openSetGoalModal();
      } else {
        window.location.href = './ai-coach/ai-coach.html';
      }
    }, 600);
  }

  /* ══════════════════════════════════════════
     LOGIN MODAL
  ══════════════════════════════════════════ */
  function openLoginModal(pendingAction) {
    console.log('[ZITLAS] openLoginModal called, pendingAction:', pendingAction);
    const modal = document.getElementById('loginModal');
    if (!modal) {
      console.error('[ZITLAS] loginModal element NOT FOUND in DOM');
      return;
    }

    if (pendingAction) {
      sessionStorage.setItem('zitlas_pending_action', pendingAction);
    }

    /* Contextual subtitle */
    const subtitle = document.getElementById('loginModalSubtitle');
    if (subtitle) {
      if (pendingAction === 'set-goal') {
        subtitle.textContent = 'Sign in to set your goal and start your weight-loss journey.';
      } else {
        subtitle.textContent = 'Sign in to continue.';
      }
    }

    /* Clear any previous form state */
    const form = document.getElementById('loginModalForm');
    if (form) form.reset();
    ['lmEmailGroup', 'lmPasswordGroup'].forEach(id =>
      document.getElementById(id)?.classList.remove('lm-error')
    );

    modal.classList.add('open');
    document.body.style.overflow = 'hidden';
    console.log('[ZITLAS] loginModal.classList:', modal.className);

    /* Auto-focus email on open */
    setTimeout(() => document.getElementById('lmEmailInput')?.focus(), 400);
  }

  function closeLoginModal() {
    const modal = document.getElementById('loginModal');
    if (!modal) return;
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  /* Called after successful login inside the modal */
  function onModalLoginSuccess() {
    closeLoginModal();

    const pending = sessionStorage.getItem('zitlas_pending_action');
    sessionStorage.removeItem('zitlas_pending_action');

    if (pending === 'set-goal') {
      setTimeout(() => {
        const surveyDone = !!localStorage.getItem(SURVEY_KEY);
        if (surveyDone) {
          openSetGoalModal();
        } else {
          window.location.href = './ai-coach/ai-coach.html';
        }
      }, 320);
    }
  }

  function initLoginModal() {
    const modal    = document.getElementById('loginModal');
    const closeBtn = document.getElementById('closeLoginModal');
    if (!modal) return;

    if (closeBtn) closeBtn.addEventListener('click', closeLoginModal);
    modal.addEventListener('click', (e) => { if (e.target === modal) closeLoginModal(); });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && modal.classList.contains('open')) closeLoginModal();
    });

    /* ── Form ── */
    const form        = document.getElementById('loginModalForm');
    const loginBtn    = document.getElementById('lmLoginBtn');
    const btnText     = document.getElementById('lmBtnText');
    const spinner     = document.getElementById('lmSpinner');
    const emailInput  = document.getElementById('lmEmailInput');
    const pwInput     = document.getElementById('lmPasswordInput');

    function setModalLoading(on) {
      if (!loginBtn) return;
      loginBtn.disabled = on;
      if (btnText)  btnText.style.opacity = on ? '0' : '1';
      if (spinner)  spinner.style.display = on ? 'block' : 'none';
    }

    function setLmError(groupId) {
      const el = document.getElementById(groupId);
      if (!el) return;
      el.classList.add('lm-error');
      el.addEventListener('animationend', () => el.classList.remove('lm-error'), { once: true });
    }

    if (emailInput) emailInput.addEventListener('input', () =>
      document.getElementById('lmEmailGroup')?.classList.remove('lm-error'));
    if (pwInput) pwInput.addEventListener('input', () =>
      document.getElementById('lmPasswordGroup')?.classList.remove('lm-error'));

    if (form) {
      form.addEventListener('submit', async (e) => {
        e.preventDefault();

        const email    = emailInput?.value.trim() || '';
        const password = pwInput?.value || '';

        if (!email)    { setLmError('lmEmailGroup');    return; }
        if (!password) { setLmError('lmPasswordGroup'); return; }

        setModalLoading(true);

        try {
          /* TODO: real API call
             const res = await fetch('/api/auth/login', {
               method: 'POST',
               headers: { 'Content-Type': 'application/json' },
               body: JSON.stringify({ email, password }),
             });
             const data = await res.json();
             if (!res.ok) throw new Error(data.message);
             localStorage.setItem('zitlas_token', data.token);
          */
          await new Promise(r => setTimeout(r, 1100));
          localStorage.setItem('zitlas_token', 'demo_' + Date.now());

          if (btnText) btnText.textContent = '✓ Signed In';
          if (btnText) btnText.style.opacity = '1';
          if (spinner) spinner.style.display = 'none';

          showToast('Signed in successfully 👋');

          setTimeout(() => {
            if (btnText) btnText.textContent = 'Sign In';
            setModalLoading(false);
            onModalLoginSuccess();
          }, 700);

        } catch {
          setModalLoading(false);
          setLmError('lmEmailGroup');
          setLmError('lmPasswordGroup');
          showToast('⚠️ Sign in failed. Try again.');
        }
      });
    }

    /* ── Google ── */
    const googleBtn = document.getElementById('lmGoogleBtn');
    if (googleBtn) {
      googleBtn.addEventListener('click', () => {
        /* TODO: window.location.href = '/api/auth/google'; */
        localStorage.setItem('zitlas_token', 'demo_google_' + Date.now());
        showToast('Signed in with Google 👋');
        onModalLoginSuccess();
      });
    }

    /* ── Skip ── */
    const skipBtn = document.getElementById('lmSkipBtn');
    if (skipBtn) {
      skipBtn.addEventListener('click', () => {
        sessionStorage.setItem('zitlas_guest', '1');
        sessionStorage.removeItem('zitlas_pending_action');
        closeLoginModal();
        showToast('Browsing as guest');
      });
    }

    /* ── Password toggle ── */
    const pwToggle = document.getElementById('lmPwToggle');
    const eyeIcon  = document.getElementById('lmEyeIcon');
    const EYE_OPEN   = `<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>`;
    const EYE_CLOSED = `<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>`;

    if (pwToggle && pwInput && eyeIcon) {
      pwToggle.addEventListener('click', () => {
        const hidden = pwInput.type === 'password';
        pwInput.type = hidden ? 'text' : 'password';
        eyeIcon.innerHTML = hidden ? EYE_CLOSED : EYE_OPEN;
      });
    }
  }

  /* training modal / task-completion removed — replaced by Recent Chats + Nearby Nutritionists */
  var TRAINING_DB = {};
  var fadeTimer;

  /* ══════════════════════════════════════════
     TASK CARD CLICK → open modal
  ══════════════════════════════════════════ */
  function initTaskCardClick() {
    document.querySelectorAll('.task-card').forEach((card) => {
      const taskId = card.dataset.taskId;
      card.addEventListener('click', (e) => {
        if (e.target.closest('.task-check-btn')) return;
        openTrainingModal(taskId);
      });
      card.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          openTrainingModal(taskId);
        }
      });
    });
  }

  /* ══════════════════════════════════════════
     IMAGE FALLBACKS
  ══════════════════════════════════════════ */
  function makeFallbackSVG(initials, color, size) {
    return `data:image/svg+xml,${encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
        <rect width="${size}" height="${size}" rx="${size / 2}" fill="${color}"/>
        <text x="50%" y="52%" dominant-baseline="central" text-anchor="middle"
              font-size="${Math.round(size * 0.36)}" font-weight="800" fill="white"
              font-family="-apple-system,sans-serif">${initials}</text>
      </svg>`
    )}`;
  }

  function getUserInitials() {
    try {
      var info   = JSON.parse(localStorage.getItem('zitlas_personal_info') || '{}');
      var zUser  = JSON.parse(localStorage.getItem('zitlas_user')           || '{}');
      var fbUser = JSON.parse(localStorage.getItem('zitlas_firebase_user')  || '{}');
      var name   = (info.fullName || zUser.name || fbUser.name || fbUser.displayName || '').trim();
      if (name) {
        return name.split(/\s+/).slice(0, 2).map(function(w) { return w[0] || ''; }).join('').toUpperCase() || name[0].toUpperCase();
      }
    } catch (_) {}
    return 'ZT';
  }

  function initImageFallbacks() {
    applyProfileImages();
  }

  /* ══════════════════════════════════════════
     VIEW BUTTONS
  ══════════════════════════════════════════ */
  function initViewButtons() {
    const viewRoadmap  = document.getElementById('viewRoadmapBtn');
    const viewTraining = document.getElementById('viewAllTraining');
    if (viewRoadmap)  viewRoadmap.addEventListener('click',  () => {
      window.location.href = './weekly-plan/weekly-plan.html';
    });
    if (viewTraining) viewTraining.addEventListener('click', () => {
      window.location.href = './weekly-plan/weekly-plan.html';
    });
  }

  /* ══════════════════════════════════════════
     AI ROADMAP RENDERER
     Reads zitlas_roadmap from localStorage and
     populates the roadmap cards + training section.
  ══════════════════════════════════════════ */
  function loadRoadmap() {
    try {
      const raw  = localStorage.getItem('zitlas_roadmap');
      const plan = raw ? JSON.parse(raw) : null;
      console.log('ROADMAP:', plan ? `${plan.days?.length ?? 0} days | role: ${plan.role}` : 'null');
      return plan;
    } catch { return null; }
  }

  const DRILL_ICONS = {
    Cardio: '🏃', Strength: '💪', Flexibility: '🧘', Walking: '🚶',
    HIIT: '🔥', Recovery: '😴', Mental: '🧠', Habit: '⭐',
  };

  const DRILL_COLORS = [
    'rgba(var(--primary-rgb),0.15)',
    'rgba(var(--success-rgb),0.15)',
    'rgba(var(--ai-rgb),0.15)',
  ];

  /* ── Render training cards for the selected day ── */
  function renderDayTraining(plan, dayIdx) {
    const day = plan.days[dayIdx];
    if (!day) return;

    const trainingSection = document.querySelector('.training-section');
    const trainingHeader  = document.querySelector('.training-section .section-title');

    function applyContent() {
      if (trainingHeader) {
        trainingHeader.textContent = `Day ${day.dayNumber} Training`;
      }

      if (!day.drills || !day.drills.length) return;

      day.drills.slice(0, 3).forEach((drill, idx) => {
        const card = document.getElementById(`taskCard${idx + 1}`);
        if (!card) return;

        const nameEl    = card.querySelector('.task-name');
        const objEl     = card.querySelector('.task-objective');
        const iconEl    = card.querySelector('.task-icon');
        const bgEl      = card.querySelector('.task-icon-wrap');
        const metaChips = card.querySelectorAll('.task-meta-chip');
        const drillIcon = DRILL_ICONS[drill.cat] || '💪';

        if (nameEl)       nameEl.textContent      = drill.name;
        if (objEl)        objEl.textContent        = drill.cue.length > 55 ? drill.cue.slice(0, 52) + '…' : drill.cue;
        if (bgEl)         bgEl.style.background    = DRILL_COLORS[idx] || DRILL_COLORS[0];
        if (iconEl)       iconEl.textContent       = drillIcon;
        if (metaChips[0]) metaChips[0].textContent = `⏱ ${drill.duration}`;
        if (metaChips[1]) metaChips[1].textContent = `🎯 ${drill.sets} Sets`;

        TRAINING_DB[String(idx + 1)] = {
          id:        String(idx + 1),
          name:      drill.name,
          icon:      drillIcon,
          iconBg:    DRILL_COLORS[idx] || DRILL_COLORS[0],
          objective: drill.target,
          duration:  drill.duration,
          drills:    drill.sets,
          goal:      drill.instruction,
          why:       `${day.whyItMatters || ''} Trainer cue: ${drill.cue}`,
          outcome:   drill.target,
          steps: [
            { name: 'Sets × Reps',      duration: `${drill.sets} sets × ${drill.reps}` },
            { name: 'Training Cue',     duration: drill.cue },
            { name: 'Performance Goal', duration: drill.target },
          ],
        };
      });
    }

    clearTimeout(fadeTimer);
    if (trainingSection) {
      trainingSection.classList.add('training-fading');
      fadeTimer = setTimeout(() => {
        applyContent();
        trainingSection.classList.remove('training-fading');
      }, 220);
    } else {
      applyContent();
    }
  }

  /* ── Select a roadmap day card and load its training ── */
  function selectRoadmapDay(plan, dayIdx) {
    document.querySelectorAll('.roadmap-card').forEach((card, i) => {
      const isSelected = i === dayIdx;
      card.classList.toggle('active', isSelected);
      const statusEl = card.querySelector('.rmap-status');
      if (statusEl) {
        statusEl.className = `rmap-status ${isSelected ? 'active-badge' : 'upcoming-badge'}`;
      }
    });
    renderDayTraining(plan, dayIdx);
  }

  function renderProfileFallbackRoadmap() {
    const scrollEl = document.getElementById('roadmapScroll');
    if (!scrollEl) return;

    /* Check what the user has actually completed based on localStorage keys */
    const hasAssessment  = !!localStorage.getItem('zitlas_assessment');
    const hasCalcs       = !!localStorage.getItem('zitlas_calculations');
    const hasSwot        = !!localStorage.getItem('zitlas_swot');
    const hasDiet        = !!localStorage.getItem('zitlas_diet_plan');
    const hasWorkout     = !!localStorage.getItem('zitlas_workout_plan');

    if (!hasAssessment && !hasSwot) {
      scrollEl.innerHTML = `
        <div class="roadmap-card active" onclick="window.location.href='./ai-coach/ai-coach.html'">
          <span class="rmap-week">START</span>
          <span class="rmap-icon">🎯</span>
          <h4 class="rmap-title">Begin Your Assessment</h4>
          <span class="rmap-status active-badge">Tap Here</span>
        </div>`;
      return;
    }

    const steps = [
      {
        week: 'STEP 1', icon: hasAssessment ? '✅' : '🎯',
        title: 'Assessment',
        done: hasAssessment,
        href: './ai-coach/ai-coach.html',
      },
      {
        week: 'STEP 2', icon: hasCalcs ? '✅' : '📊',
        title: 'Fitness Snapshot',
        done: hasCalcs,
        href: './ai-coach/ai-coach.html',
      },
      {
        week: 'STEP 3', icon: hasSwot ? '✅' : '🧠',
        title: 'SWOT Analysis',
        done: hasSwot,
        href: './ai-coach/ai-coach.html',
      },
      {
        week: 'STEP 4', icon: hasDiet ? '✅' : '🥗',
        title: 'Diet Plan',
        done: hasDiet,
        href: '../diet/diet.html',
      },
      {
        week: 'STEP 5', icon: hasWorkout ? '✅' : '💪',
        title: 'Workout Plan',
        done: hasWorkout,
        href: './ai-coach/ai-coach.html?view=workout',
      },
      {
        week: 'STEP 6', icon: '📈',
        title: 'Progress Tracking',
        done: false,
        href: null,
      },
    ];

    /* First incomplete step is "active" */
    let activeIdx = steps.findIndex(s => !s.done);
    if (activeIdx === -1) activeIdx = steps.length - 1;

    scrollEl.innerHTML = steps.map((s, i) => {
      const isActive = i === activeIdx;
      const cls      = s.done ? 'done-badge' : isActive ? 'active-badge' : 'upcoming-badge';
      const badge    = s.done ? '✓ Done' : isActive ? 'Next Up' : 'Upcoming';
      return `<div class="roadmap-card${isActive ? ' active' : ''}${s.done ? ' rmap-done' : ''}" data-step="${i}">
        <span class="rmap-week">${s.week}</span>
        <span class="rmap-icon">${s.icon}</span>
        <h4 class="rmap-title">${s.title}</h4>
        <span class="rmap-status ${cls}">${badge}</span>
      </div>`;
    }).join('');

    document.querySelectorAll('.roadmap-card[data-step]').forEach((card, i) => {
      const step = steps[i];
      card.addEventListener('click', () => {
        if (step.href) {
          window.location.href = step.href;
        } else {
          showToast('Progress Tracking coming soon!');
        }
      });
    });
  }

  function renderRoadmap() {
    const plan = loadRoadmap();
    if (!plan || !plan.days) {
      renderProfileFallbackRoadmap();
      return;
    }

    /* ── Update plan label in header ── */
    const roleLabelEl = document.querySelector('.roadmap-sub');
    if (roleLabelEl) roleLabelEl.textContent = plan.goalLabel || plan.goal_label || 'Weight Loss Plan';

    const scrollEl  = document.querySelector('.roadmap-scroll');
    const todayStr  = new Date().toISOString().split('T')[0];
    const DAY_NAMES = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    const todayName = DAY_NAMES[new Date().getDay()];

    /* ── Replace roadmap scroll cards with 7-day plan ── */
    if (scrollEl) {
      scrollEl.innerHTML = plan.days.map((day, i) => {
        let isToday, isPast;
        if (day.date) {
          isToday = day.isToday || day.date === todayStr;
          isPast  = day.date < todayStr && !isToday;
        } else {
          /* No date on plan — match by weekday name */
          isToday = day.isToday || day.dayName === todayName;
          isPast  = false;
        }
        const badge    = isToday ? '🟠 TODAY' : isPast ? '✓ Done' : day.dayName;
        const badgeCls = isToday ? 'active-badge' : isPast ? 'done-badge' : 'upcoming-badge';
        return `<div class="roadmap-card${isToday ? ' active' : ''}" data-day="${i}">
          <span class="rmap-week">DAY ${day.dayNumber}</span>
          <span class="rmap-icon">${day.icon}</span>
          <h4 class="rmap-title">${day.theme}</h4>
          <span class="rmap-status ${badgeCls}">${badge}</span>
        </div>`;
      }).join('');
    }

    /* ── Attach click handlers — select day inline ── */
    document.querySelectorAll('.roadmap-card[data-day]').forEach((card) => {
      card.addEventListener('click', () => {
        selectRoadmapDay(plan, parseInt(card.dataset.day));
      });
    });

    /* ── Find today's index — by date if available, by dayName otherwise ── */
    let todayIdx = 0;
    plan.days.forEach((day, i) => {
      const isTd = day.date
        ? (day.isToday || day.date === todayStr)
        : (day.isToday || day.dayName === todayName);
      if (isTd) todayIdx = i;
    });

    /* ── Auto-select today ── */
    selectRoadmapDay(plan, todayIdx);

    /* ── Scroll today's card into view in the horizontal rail ── */
    if (scrollEl) {
      const todayCard = scrollEl.querySelector(`.roadmap-card[data-day="${todayIdx}"]`);
      if (todayCard) {
        setTimeout(() => {
          const left = todayCard.offsetLeft - scrollEl.offsetWidth / 2 + todayCard.offsetWidth / 2;
          scrollEl.scrollTo({ left: Math.max(0, left), behavior: 'smooth' });
        }, 250);
      }
    }
  }

  /* ══════════════════════════════════════════
     ROADMAP CARD CLICK (fallback for static cards only)
  ══════════════════════════════════════════ */
  function initRoadmapCards() {
    document.querySelectorAll('.roadmap-card').forEach((card) => {
      if (card.dataset.day !== undefined) return; /* AI roadmap — already handled */
      card.addEventListener('click', () => {
        const title = card.querySelector('.rmap-title')?.textContent || 'Week';
        showToast(`${title} — coming soon`);
      });
    });
  }

  /* ══════════════════════════════════════════
     SWOT SUMMARY WIDGET
  ══════════════════════════════════════════ */
  function renderSwotWidget() {
    const content = document.getElementById('swotWidgetContent');
    if (!content) return;

    let swot = null;
    try { swot = JSON.parse(localStorage.getItem('zitlas_swot') || 'null'); } catch (_) {}

    console.log('SWOT DATA:', swot);
    console.log('VIEW FULL TARGET:', './ai-coach/ai-coach.html?view=swot');

    if (!swot || !swot.swot) {
      content.innerHTML = `<div class="widget-empty-state">
        <p class="widget-empty-text">Complete your AI assessment to unlock your SWOT analysis.</p>
        <a href="./ai-coach/ai-coach.html" class="widget-empty-cta">Start Assessment →</a>
      </div>`;
      return;
    }

    const archetype = swot.user_archetype || 'Athlete';
    const scores    = swot.scores || {};
    const overall   = scores.overall ? Math.round(scores.overall) : null;
    const s = swot.swot;

    function topItem(arr) {
      const item = (arr || [])[0];
      if (!item) return '—';
      return typeof item === 'object' ? (item.title || '—') : String(item);
    }

    const scoreChips = [
      { label: 'Physical', val: scores.physical, color: 'var(--success)' },
      { label: 'Mental',   val: scores.mental,   color: 'var(--ai-accent)' },
      { label: 'Diet',     val: scores.diet,      color: 'var(--primary)' },
      { label: 'Lifestyle',val: scores.lifestyle, color: 'var(--ai-accent)' },
    ].filter(c => c.val != null);

    const archetypePill = document.getElementById('swotArchetypePill');
    if (archetypePill) archetypePill.textContent = archetype + (overall ? ` · ${overall}/10` : '');

    content.innerHTML = `
      <div class="swot-widget-scores">
        ${scoreChips.map(c => `
          <div class="swot-score-chip">
            <span class="swot-score-dot" style="background:${c.color}"></span>
            <span class="swot-score-label">${c.label}</span>
            <span class="swot-score-val" style="color:${c.color}">${Math.round(c.val)}</span>
          </div>`).join('')}
      </div>
      <div class="swot-widget-grid">
        <div class="swot-widget-card swot-widget-S">
          <span class="swot-widget-icon">💪</span>
          <span class="swot-widget-label">Strength</span>
          <p class="swot-widget-text">${topItem(s.strengths)}</p>
        </div>
        <div class="swot-widget-card swot-widget-W">
          <span class="swot-widget-icon">⚠️</span>
          <span class="swot-widget-label">Weakness</span>
          <p class="swot-widget-text">${topItem(s.weaknesses)}</p>
        </div>
        <div class="swot-widget-card swot-widget-O">
          <span class="swot-widget-icon">🚀</span>
          <span class="swot-widget-label">Opportunity</span>
          <p class="swot-widget-text">${topItem(s.opportunities)}</p>
        </div>
        <div class="swot-widget-card swot-widget-T">
          <span class="swot-widget-icon">🔴</span>
          <span class="swot-widget-label">Threat</span>
          <p class="swot-widget-text">${topItem(s.threats)}</p>
        </div>
      </div>
      ${swot.priority_action ? `<p class="swot-widget-action">→ ${swot.priority_action}</p>` : ''}
    `;
  }

  /* ══════════════════════════════════════════
     TODAY'S ACTIVITY — STEP COUNTER CARD
     All values come from window.zitlasSteps so
     Health Connect can swap in live data later
     without touching the UI code.
  ══════════════════════════════════════════ */

  /* Baseline zeros — Health Connect overwrites with real data when available */
  window.zitlasSteps = window.zitlasSteps || {
    today_steps:     0,
    daily_step_goal: 10000,
    calories_burned: 0,
    distance_km:     0,
    active_minutes:  85,
    streak_days:     7,
  };

  /* Returns { pct, circumference, targetOffset } for the SVG ring */
  function calculateStepProgress() {
    const { today_steps, daily_step_goal } = window.zitlasSteps;
    const pct           = Math.min(100, (today_steps / daily_step_goal) * 100);
    const R             = 80;
    const circumference = +(2 * Math.PI * R).toFixed(2);
    const targetOffset  = +(circumference * (1 - pct / 100)).toFixed(2);
    return { pct, circumference, targetOffset, R };
  }

  /* Animates an already-rendered ring to the current progress value.
     Call this after updateStepRing() to drive the animation, or when
     window.zitlasSteps changes without a full re-render. */
  function updateStepRing() {
    const content = document.getElementById('stepCounterContent');
    if (!content) return;
    const { pct, targetOffset } = calculateStepProgress();
    const arc   = content.querySelector('.sac-ring-progress');
    const count = content.querySelector('.sac-step-count');
    const label = document.getElementById('stepCounterLabel');

    if (label) label.textContent = `${Math.round(pct)}% of daily goal`;

    if (arc) {
      arc.style.transition = 'none';
      arc.style.strokeDashoffset = arc.getAttribute('stroke-dasharray');
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          arc.style.transition = '';
          arc.style.strokeDashoffset = String(targetOffset);
        });
      });
    }

    if (count) {
      const target = window.zitlasSteps.today_steps || 0;
      const goal   = window.zitlasSteps.daily_step_goal || 10000;
      const pctEl  = content.querySelector('#sacStepPct');
      const dur    = 1000;
      const start  = performance.now();
      const tick   = (now) => {
        const t       = Math.min(1, (now - start) / dur);
        const eased   = 1 - Math.pow(1 - t, 3);
        const current = Math.round(eased * target);
        count.textContent = current.toLocaleString();
        if (pctEl) pctEl.textContent = Math.round(Math.min(100, (current / goal) * 100)) + '%';
        if (t < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }
  }

  /* Renders the full step counter card then triggers the animation */
  function renderStepCounterCard() {
    const content = document.getElementById('stepCounterContent');
    const label   = document.getElementById('stepCounterLabel');
    if (!content) return;

    const d = window.zitlasSteps;
    const { pct, circumference, targetOffset, R } = calculateStepProgress();
    const CX = 96, CY = 96;
    const pctRounded = Math.round(pct);

    /* Format active_minutes as "Xh Ym" when >= 60 */
    const mins    = d.active_minutes || 0;
    const hStr    = mins >= 60 ? `${Math.floor(mins / 60)}h ` : '';
    const mStr    = `${mins % 60}m`;
    const timeStr = hStr + mStr;

    /* Remaining steps */
    const remaining = Math.max((d.daily_step_goal || 10000) - (d.today_steps || 0), 0);
    const remainingLine = remaining === 0
      ? `<p class="sac-remaining sac-remaining--done">🎉 Goal completed! Amazing work today.</p>`
      : `<p class="sac-remaining">🚀 ${remaining.toLocaleString()} steps left today</p>`;

    /* Motivational message */
    const motiveMsg = pctRounded >= 100
      ? `🏆 Outstanding! You've smashed today's goal!`
      : `🚶 Keep going, you're ${pctRounded}% of the way there!`;

    /* Streak badge */
    const streakDays  = d.streak_days || 0;
    const streakBadge = streakDays > 0
      ? `<div class="sac-streak-badge">🔥 ${streakDays} Day Streak</div>`
      : '';

    if (label) label.textContent = `${pctRounded}% of daily goal`;

    content.innerHTML = `
      <div class="sac-card">

        <div class="sac-ring-wrap">
          <svg class="sac-ring-svg" viewBox="0 0 192 192"
               aria-label="${pctRounded}% of step goal reached">
            <circle class="sac-ring-bg"
              cx="${CX}" cy="${CY}" r="${R}"
              fill="none" stroke-width="14"/>
            <circle class="sac-ring-glow"
              cx="${CX}" cy="${CY}" r="${R}"
              fill="none" stroke-width="14"
              stroke-linecap="round"
              stroke-dasharray="${circumference}"
              stroke-dashoffset="${circumference}"
              transform="rotate(-90 ${CX} ${CY})"/>
            <circle class="sac-ring-progress"
              cx="${CX}" cy="${CY}" r="${R}"
              fill="none" stroke-width="14"
              stroke-linecap="round"
              stroke-dasharray="${circumference}"
              stroke-dashoffset="${circumference}"
              transform="rotate(-90 ${CX} ${CY})"/>
          </svg>

          <div class="sac-ring-center">
            <span class="sac-step-count">0</span>
            <span class="sac-step-lbl">Steps</span>
            <span class="sac-step-pct" id="sacStepPct">0%</span>
          </div>
        </div>

        <div class="sac-right">
          <p class="sac-goal-line">🎯 Today's Target: ${(d.daily_step_goal || 10000).toLocaleString()} Steps</p>
          ${remainingLine}

          <div class="sac-stats-row">
            <div class="sac-stat">
              <span class="sac-stat-icon">🔥</span>
              <span class="sac-stat-val">${d.calories_burned} kcal</span>
              <span class="sac-stat-lbl">Calories</span>
            </div>
            <div class="sac-stat-div"></div>
            <div class="sac-stat">
              <span class="sac-stat-icon">🚶</span>
              <span class="sac-stat-val">${d.distance_km} km</span>
              <span class="sac-stat-lbl">Distance</span>
            </div>
            <div class="sac-stat-div"></div>
            <div class="sac-stat">
              <span class="sac-stat-icon">⏱</span>
              <span class="sac-stat-val">${timeStr}</span>
              <span class="sac-stat-lbl">Active Time</span>
            </div>
          </div>

          ${streakBadge}

          <p class="sac-motive">${motiveMsg}</p>
        </div>

      </div>
    `;

    /* Animate ring + count-up + percentage after two frames */
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        const arc  = content.querySelector('.sac-ring-progress');
        const glow = content.querySelector('.sac-ring-glow');
        if (arc)  arc.style.strokeDashoffset  = String(targetOffset);
        if (glow) glow.style.strokeDashoffset = String(targetOffset);

        const count  = content.querySelector('.sac-step-count');
        const pctEl  = content.querySelector('#sacStepPct');
        const target = d.today_steps || 0;
        const dur    = 1000;
        const start  = performance.now();
        const tick   = (now) => {
          const t       = Math.min(1, (now - start) / dur);
          const eased   = 1 - Math.pow(1 - t, 3);
          const current = Math.round(eased * target);
          if (count)  count.textContent = current.toLocaleString();
          if (pctEl)  pctEl.textContent = Math.round(Math.min(100, (current / (d.daily_step_goal || 10000)) * 100)) + '%';
          if (t < 1) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
    });
  }

  /* ══════════════════════════════════════════
     TODAY'S TRAINING CARD
  ══════════════════════════════════════════ */
  function renderTrainingWidget() {
    const content  = document.getElementById('trainingWidgetContent');
    const dayLabel = document.getElementById('trainingDayLabel');
    if (!content) return;

    let plan = null;
    try { plan = JSON.parse(localStorage.getItem('zitlas_workout_plan') || 'null'); } catch (_) {}

    if (!plan || !plan.weekly_plan || !plan.weekly_plan.length) {
      if (dayLabel) dayLabel.textContent = 'Complete assessment to unlock';
      content.innerHTML = `<div class="widget-empty-state">
        <p class="widget-empty-text">Generate your AI workout plan to see today's training.</p>
        <a href="./ai-coach/ai-coach.html" class="widget-empty-cta">Get Workout Plan →</a>
      </div>`;
      return;
    }

    const DAY_NAMES  = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    const todayName  = DAY_NAMES[new Date().getDay()];
    const weeklyPlan = plan.weekly_plan;

    let todayDay = weeklyPlan.find(d => d.day && d.day.toLowerCase() === todayName.toLowerCase());
    if (!todayDay) todayDay = weeklyPlan[0];

    const planName = plan.plan_name || 'Personalised Plan';
    const freq     = plan.weekly_frequency || (weeklyPlan.length + ' days/week');

    if (dayLabel) dayLabel.textContent = `${freq} · ${planName}`;

    const isRest    = (todayDay.type || '').toLowerCase().includes('rest');
    const exercises = todayDay.exercises || [];

    function typeClass(t) {
      const s = (t || '').toLowerCase();
      if (s.includes('rest'))     return 'ttc-badge--rest';
      if (s.includes('recovery')) return 'ttc-badge--recovery';
      if (s.includes('walking'))  return 'ttc-badge--walking';
      return 'ttc-badge--workout';
    }

    content.innerHTML = `
      <div class="ttc-card">
        <div class="ttc-header">
          <div class="ttc-day-row">
            <span class="ttc-day-name">${todayDay.day || todayName}</span>
            <span class="ttc-type-badge ${typeClass(todayDay.type)}">${todayDay.type || 'Workout'}</span>
          </div>
          <h3 class="ttc-focus">${todayDay.focus || planName}</h3>
        </div>

        ${isRest ? `<div class="ttc-rest-banner">😴 Rest Day — recover and recharge</div>` : ''}

        <div class="ttc-stats">
          ${todayDay.duration_minutes ? `
          <div class="ttc-stat-block">
            <span class="ttc-stat-icon">⏱</span>
            <span class="ttc-stat-val">${todayDay.duration_minutes} min</span>
            <span class="ttc-stat-lbl">Duration</span>
          </div>` : ''}
          ${todayDay.calories_burned_est ? `
          <div class="ttc-stat-block">
            <span class="ttc-stat-icon">🔥</span>
            <span class="ttc-stat-val">${todayDay.calories_burned_est} kcal</span>
            <span class="ttc-stat-lbl">Est. Calories</span>
          </div>` : ''}
          ${!isRest && exercises.length ? `
          <div class="ttc-stat-block">
            <span class="ttc-stat-icon">💪</span>
            <span class="ttc-stat-val">${exercises.length}</span>
            <span class="ttc-stat-lbl">Exercises</span>
          </div>` : ''}
        </div>

        ${todayDay.daily_tip ? `<p class="ttc-tip">💡 ${todayDay.daily_tip}</p>` : ''}
      </div>
    `;
  }

  /* ══════════════════════════════════════════
     WEEKLY PLAN MODAL
  ══════════════════════════════════════════ */
  function openWeeklyPlanModal() {
    let plan = null;
    try { plan = JSON.parse(localStorage.getItem('zitlas_workout_plan') || 'null'); } catch (_) {}

    console.log('WORKOUT PLAN (weekly modal):', plan);

    const modal    = document.getElementById('weeklyPlanModal');
    const subtitle = document.getElementById('weeklyPlanSubtitle');
    const list     = document.getElementById('weeklyPlanList');
    if (!modal) return;

    if (plan && plan.plan_name && subtitle) {
      subtitle.textContent = (plan.weekly_frequency || '7 days/week') + ' · ' + plan.plan_name;
    }

    if (list) {
      if (!plan || !plan.weekly_plan || !plan.weekly_plan.length) {
        list.innerHTML = `<div class="widget-empty-state">
          <p class="widget-empty-text">No workout plan found. Complete your assessment first.</p>
          <a href="./ai-coach/ai-coach.html" class="widget-empty-cta">Get Workout Plan →</a>
        </div>`;
      } else {
        const DAY_NAMES = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
        const todayName = DAY_NAMES[new Date().getDay()];

        function dayTypeIcon(t) {
          const s = (t || '').toLowerCase();
          if (s.includes('rest'))     return '😴';
          if (s.includes('recovery')) return '🧘';
          if (s.includes('walking'))  return '🚶';
          if (s.includes('cardio'))   return '🏃';
          return '💪';
        }

        list.innerHTML = plan.weekly_plan.map((day, i) => {
          const isToday = day.day && day.day.toLowerCase() === todayName.toLowerCase();
          const isRest  = (day.type || '').toLowerCase().includes('rest');
          const icon    = dayTypeIcon(day.type);
          const exList  = (day.exercises || []).slice(0, 4);

          const exercisesHtml = !isRest && exList.length ? `
            <ul class="wpl-ex-list">
              ${exList.map(ex => `<li>${ex.name || ''}${ex.reps_or_duration ? ' — ' + ex.reps_or_duration : ''}</li>`).join('')}
              ${day.exercises.length > 4 ? `<li class="wpl-ex-more">+${day.exercises.length - 4} more</li>` : ''}
            </ul>` : '';

          return `
            <div class="wpl-day-card${isToday ? ' wpl-today' : ''}" data-wpl-idx="${i}">
              <button class="wpl-trigger" data-wpl-idx="${i}">
                <div class="wpl-trigger-left">
                  <span class="wpl-day-abbr">${(day.day || '').slice(0,3).toUpperCase()}</span>
                  <span class="wpl-icon">${icon}</span>
                  <div class="wpl-info">
                    <span class="wpl-day-full">${day.day || ('Day ' + (i+1))}${isToday ? ' <span class="wpl-today-chip">Today</span>' : ''}</span>
                    <span class="wpl-focus">${day.focus || day.type || 'Training'}</span>
                  </div>
                </div>
                <div class="wpl-trigger-right">
                  ${day.duration_minutes ? `<span class="wpl-meta-chip">⏱ ${day.duration_minutes}m</span>` : ''}
                  ${day.calories_burned_est ? `<span class="wpl-meta-chip">🔥 ${day.calories_burned_est}</span>` : ''}
                  <span class="wpl-arrow">▼</span>
                </div>
              </button>
              ${exercisesHtml || isRest ? `
              <div class="wpl-body">
                ${isRest ? '<p class="wpl-rest-note">😴 Rest — no structured exercise today.</p>' : exercisesHtml}
                ${day.daily_tip ? `<p class="wpl-tip">💡 ${day.daily_tip}</p>` : ''}
              </div>` : ''}
            </div>`;
        }).join('');

        /* Accordion toggle */
        list.querySelectorAll('.wpl-trigger').forEach(btn => {
          btn.addEventListener('click', () => {
            const card = btn.closest('.wpl-day-card');
            const wasOpen = card.classList.contains('open');
            list.querySelectorAll('.wpl-day-card.open').forEach(c => c.classList.remove('open'));
            if (!wasOpen) card.classList.add('open');
          });
        });

        /* Auto-open today */
        const todayCard = list.querySelector('.wpl-today');
        if (todayCard) todayCard.classList.add('open');
      }
    }

    modal.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeWeeklyPlanModal() {
    const modal = document.getElementById('weeklyPlanModal');
    if (!modal) return;
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  function initWeeklyPlanModal() {
    const viewBtn  = document.getElementById('viewWeeklyPlanBtn');
    const closeBtn = document.getElementById('closeWeeklyPlanModal');
    const modal    = document.getElementById('weeklyPlanModal');

    if (viewBtn) viewBtn.addEventListener('click', function () {
      window.location.href = './weekly-plan/weekly-plan.html';
    });
    if (closeBtn) closeBtn.addEventListener('click', closeWeeklyPlanModal);
    if (modal) {
      modal.addEventListener('click', e => { if (e.target === modal) closeWeeklyPlanModal(); });
    }
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && modal && modal.classList.contains('open')) closeWeeklyPlanModal();
    });
  }

  /* ══════════════════════════════════════════
     STAT COUNT-UP
  ══════════════════════════════════════════ */
  function countUp(el, target, suffix, duration = 800) {
    const start = performance.now();
    const dec   = suffix === '' && String(target).includes('.') ? 2 : 0;
    function tick(now) {
      const p = Math.min((now - start) / duration, 1);
      const e = 1 - Math.pow(1 - p, 3);
      el.textContent = dec ? (target * e).toFixed(dec) + suffix : Math.round(target * e) + suffix;
      if (p < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  function initStatCountUp() {
    const stats = [
      { sel: '.qs-card:nth-child(1) .qs-val', val: 7,    suf: '' },
      { sel: '.qs-card:nth-child(2) .qs-val', val: 5,    suf: '' },
      { sel: '.qs-card:nth-child(3) .qs-val', val: 3,    suf: '' },
      { sel: '.qs-card:nth-child(4) .qs-val', val: 4.50, suf: '' },
    ];
    setTimeout(() => {
      stats.forEach(({ sel, val, suf }, i) => {
        const el = document.querySelector(sel);
        if (el) {
          el.textContent = '0' + suf;
          setTimeout(() => countUp(el, val, suf, 700), i * 80);
        }
      });
    }, 350);
  }

  /* ══════════════════════════════════════════
     STREAK PULSE
  ══════════════════════════════════════════ */
  function initStreakPulse() {
    const card = document.querySelector('.streak-card');
    if (!card) return;
    let count = 0;
    setInterval(() => {
      count++;
      if (count % 4 === 0) {
        card.style.boxShadow = '0 0 18px rgba(var(--primary-rgb),0.45)';
        setTimeout(() => { card.style.boxShadow = ''; }, 500);
      }
    }, 2000);
  }

  /* ══════════════════════════════════════════
     SCROLL ENTRANCE ANIMATIONS
  ══════════════════════════════════════════ */
  function initScrollAnimations() {
    if (!('IntersectionObserver' in window)) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.08 }
    );

    ['.roadmap-card', '.task-card', '.qs-card'].forEach((sel) => {
      document.querySelectorAll(sel).forEach((el, i) => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(12px)';
        el.style.transition = `opacity 0.36s ease ${0.06 * i}s, transform 0.4s cubic-bezier(0.34,1.2,0.64,1) ${0.06 * i}s`;
        observer.observe(el);
      });
    });
  }

  /* ══════════════════════════════════════════
     INIT
  ══════════════════════════════════════════ */
  function safeRun(name, fn) {
    try { fn(); }
    catch (err) { console.error('[ZITLAS] Error in', name, ':', err); }
  }

  function init() {
    if (!isLoggedIn()) {
      window.location.replace('../login/login.html');
      return;
    }

    var _nb = document.getElementById('zitlas-navbar');
    if (_nb) document.documentElement.style.setProperty('--nav-height', (window.innerHeight - _nb.getBoundingClientRect().top) + 'px');

    safeRun('loadFirebaseUserProfile', loadFirebaseUserProfile);
    safeRun('loadTheme',        loadTheme);
    safeRun('initGreeting',     initGreeting);
    safeRun('initNotifBell',    initNotifBell);

    /* Debug: print key data sources on load */
    try {
      const athleteProfile = JSON.parse(localStorage.getItem('athlete_profile') || 'null');
      console.log('[ZITLAS] PROFILE:', athleteProfile
        ? `role: ${athleteProfile.role} | goal: ${athleteProfile.goal} | time: ${athleteProfile.daily_training_time}`
        : 'null');
      console.log('[ZITLAS] SURVEY:', localStorage.getItem('zitlas_survey') || 'null');
      console.log('[ZITLAS] AUTH:', isLoggedIn() ? 'logged-in' : 'logged-out');
      console.log('[ZITLAS] KEYS:', Object.keys(localStorage).filter(k => k.startsWith('zitlas') || k === 'athlete_profile').join(', '));
    } catch(_) {}

    safeRun('checkPendingAction',   checkPendingAction);
    safeRun('renderGoalCard',       renderGoalCard);
    safeRun('applyProfileImages',   applyProfileImages);
    safeRun('initGoalActionBtn',    initGoalActionBtn);
    safeRun('initSetGoalModal',     initSetGoalModal);
    safeRun('initResetGoalModal',   initResetGoalModal);
    safeRun('initLoginModal',       initLoginModal);
    safeRun('initTaskCardClick',    initTaskCardClick);
    safeRun('initImageFallbacks',   initImageFallbacks);
    safeRun('initViewButtons',      initViewButtons);
    safeRun('renderSwotWidget',       renderSwotWidget);
    safeRun('renderStepCounterCard',  renderStepCounterCard);
    loadHealthConnectData();
    safeRun('renderTrainingWidget',   renderTrainingWidget);
    safeRun('initWeeklyPlanModal',  initWeeklyPlanModal);
    safeRun('renderChats',          renderChats);
    safeRun('initStatCountUp',      initStatCountUp);
    safeRun('initStreakPulse',      initStreakPulse);
    requestAnimationFrame(initScrollAnimations);

    console.log('[ZITLAS] init() complete — all handlers attached');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  /* ══════════════════════════════════════════
     HEALTH CONNECT — live data loader
     Runs after renderStepCounterCard() so dummy
     data is always visible first. On success,
     updates window.zitlasSteps and re-renders.
  ══════════════════════════════════════════ */
  async function loadHealthConnectData() {
    console.log('[HealthConnect] Plugin:', !!(window.Capacitor?.Plugins?.HealthConnect));

    if (!window.Capacitor) return;

    try {
      const HealthConnect = window.Capacitor.Plugins.HealthConnect;
      if (!HealthConnect) {
        console.log('[HealthConnect] Plugin not found — using dummy data');
        return;
      }

      const status = await HealthConnect.isAvailable();
      console.log('[HealthConnect] Status:', status);
      if (!status.available) {
        console.log('[HealthConnect] Not installed — using dummy data');
        return;
      }

      const permission = await HealthConnect.requestPermissions();
      console.log('[HealthConnect] Permission:', permission);
      if (!permission.permissionGranted) {
        console.log('[HealthConnect] Permission denied — using dummy data');
        return;
      }

      const activity = await HealthConnect.getTodayActivity();
      console.log('[HealthConnect] Activity:', activity);

      window.zitlasSteps = {
        today_steps:     activity.today_steps     || 0,
        daily_step_goal: window.zitlasSteps?.daily_step_goal || 10000,
        calories_burned: activity.calories_burned || 0,
        distance_km:     activity.distance_km     || 0,
        active_minutes:  activity.active_minutes  || 0,
        streak_days:     window.zitlasSteps?.streak_days    || 0,
      };

      console.log('[HealthConnect] Updated Steps:', window.zitlasSteps);
      renderStepCounterCard();

    } catch (e) {
      console.error('[HealthConnect] Failed:', e);
    }
  }

})();