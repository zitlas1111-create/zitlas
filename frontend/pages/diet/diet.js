/* =============================================
   ZITLAS Diet Plan — diet.js
   Dynamically renders a 7-day AI-generated meal
   plan from the Nutrition Brain (Brain 3) output.
   Falls back to cached plan or generates fresh.
   ============================================= */

(function () {
  'use strict';

  /* ══════════════════════════════════════════
     THEME
  ══════════════════════════════════════════ */
  function loadTheme() {
    const pref = localStorage.getItem('zitlas_theme') || 'dark';
    const resolved = pref === 'system'
      ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
      : pref;
    document.documentElement.setAttribute('data-theme', resolved);
  }

  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if ((localStorage.getItem('zitlas_theme') || 'dark') === 'system') loadTheme();
  });

  /* ══════════════════════════════════════════
     MOCK NUTRITIONISTS
  ══════════════════════════════════════════ */
  var MOCK_NUTRITIONISTS = [
    {
      id: 'n1',
      name: 'Dr. Priya Sharma',
      qualification: 'M.Sc. Clinical Nutrition, PhD Sports Dietetics',
      experience: '11 years',
      specialization: 'Sports nutrition, Performance diet planning, Recovery protocols',
      location: 'Pune, Maharashtra',
      rating: 4.9,
      reviews: 142,
      available: true,
      color: '#FF8A00',
      fee: '₹299',
      duration: '30 min',
    },
    {
      id: 'n2',
      name: 'Rahul Desai',
      qualification: 'B.Sc. Dietetics, Certified Sports Nutritionist (ISSN)',
      experience: '7 years',
      specialization: 'Youth athlete nutrition, Weight management, Supplement guidance',
      location: 'Mumbai, Maharashtra',
      rating: 4.7,
      reviews: 89,
      available: true,
      color: '#22C55E',
      fee: '₹199',
      duration: '20 min',
    },
    {
      id: 'n3',
      name: 'Kavita Nair',
      qualification: 'M.Sc. Food Science, SNEP Certified',
      experience: '9 years',
      specialization: 'Holistic nutrition & lifestyle coaching',
      location: 'Bengaluru, Karnataka',
      rating: 4.8,
      reviews: 115,
      available: false,
      color: '#818CF8',
      fee: '₹249',
      duration: '25 min',
    },
  ];

  /* ── Nutritionist card renderer ── */
  function renderNutritionistCards(list) {
    var nutriList  = document.getElementById('nutriList');
    var nutriEmpty = document.getElementById('nutriEmpty');
    var nutriCount = document.getElementById('nutriCount');
    if (!nutriList) return;

    if (!list || list.length === 0) {
      nutriList.innerHTML = '';
      if (nutriEmpty) nutriEmpty.style.display = '';
      if (nutriCount) nutriCount.textContent = '';
      return;
    }

    if (nutriEmpty) nutriEmpty.style.display = 'none';
    if (nutriCount) nutriCount.textContent = list.length + ' nutritionist' + (list.length !== 1 ? 's' : '') + ' available';

    nutriList.innerHTML = list.map(function (n) {
      var initials = n.name.split(' ').map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase();
      var stars = '';
      var full = Math.floor(n.rating);
      var half = n.rating - full >= 0.5;
      for (var i = 0; i < full; i++) stars += '<svg width="13" height="13" viewBox="0 0 24 24" fill="#FBBF24" stroke="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/></svg>';
      if (half) stars += '<svg width="13" height="13" viewBox="0 0 24 24" fill="#FBBF24" stroke="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77V2z"/><path d="M12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2v15.77z" fill="#374151"/></svg>';

      return '<div class="nutri-card">' +
        '<div class="nutri-card-body">' +
          '<div class="nutri-avatar" style="background:' + n.color + '22;border:2px solid ' + n.color + '44;">' +
            '<span class="nutri-initials" style="color:' + n.color + ';">' + esc(initials) + '</span>' +
            (n.available ? '<span class="nutri-online-dot"></span>' : '') +
          '</div>' +
          '<div class="nutri-info">' +
            '<div class="nutri-name-row">' +
              '<span class="nutri-name">' + esc(n.name) + '</span>' +
              '<span class="nutri-rating">' + stars + '<span class="nutri-rating-val">&thinsp;' + n.rating + '</span><span class="nutri-reviews">&nbsp;(' + n.reviews + ')</span></span>' +
            '</div>' +
            '<div class="nutri-qual">' + esc(n.qualification) + '</div>' +
            '<div class="nutri-spec">' + esc(n.specialization) + '</div>' +
            '<div class="nutri-meta">' +
              '<span class="nutri-meta-item"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>' + esc(n.location) + '</span>' +
              '<span class="nutri-meta-sep">·</span>' +
              '<span class="nutri-meta-item"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>' + esc(n.experience) + ' exp.</span>' +
            '</div>' +
          '</div>' +
        '</div>' +
        '<div class="nutri-card-actions">' +
          '<button class="nutri-btn nutri-btn--primary" data-nutri-action="book">Book Consultation</button>' +
          '<div class="nutri-btn-row">' +
            '<button class="nutri-btn nutri-btn--secondary" data-nutri-action="profile">View Profile</button>' +
            '<button class="nutri-btn nutri-btn--ghost" data-nutri-action="contact">Contact</button>' +
          '</div>' +
        '</div>' +
      '</div>';
    }).join('');

    /* Wire "Coming soon" on all action buttons */
    nutriList.querySelectorAll('[data-nutri-action]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        showToast('Coming soon — stay tuned!');
      });
    });
  }

  /* ── Coach role: Nearby Nutritionists view ── */
  function loadNearbyNutritionists() {
    var titleEl    = document.getElementById('dietPageTitle');
    var subtitleEl = document.getElementById('dietPageSubtitle');
    if (titleEl)    titleEl.textContent    = 'Nearby Nutritionists';
    if (subtitleEl) subtitleEl.textContent = 'Find certified sports nutritionists to support your athletes.';

    var loading     = document.getElementById('dietLoading');
    var dietContent = document.getElementById('dietContent');
    if (loading)     loading.style.display     = 'none';
    if (dietContent) dietContent.style.display = 'none';

    var nutriView = document.getElementById('nutriView');
    if (nutriView) nutriView.style.display = '';

    var data = safeJSON('zitlas_nutritionists', null);
    renderNutritionistCards(Array.isArray(data) && data.length ? data : MOCK_NUTRITIONISTS);
  }

  /* ── Nutritionist-only view ── */
  function renderNutritionistsOnly() {
    /* Update page header */
    var titleEl    = document.getElementById('dietPageTitle');
    var subtitleEl = document.getElementById('dietPageSubtitle');
    if (titleEl)    titleEl.textContent    = 'Nutritionists';
    if (subtitleEl) subtitleEl.textContent = 'Connect with certified nutrition specialists for your members.';

    /* Hide athlete-only sections */
    var loading     = document.getElementById('dietLoading');
    var dietContent = document.getElementById('dietContent');
    if (loading)     loading.style.display     = 'none';
    if (dietContent) dietContent.style.display = 'none';

    /* Show nutritionist view */
    var nutriView = document.getElementById('nutriView');
    if (nutriView) nutriView.style.display = '';

    /* Load from localStorage or fall back to mock */
    var data = safeJSON('zitlas_nutritionists', null);
    renderNutritionistCards(Array.isArray(data) && data.length ? data : MOCK_NUTRITIONISTS);
  }

  /* ══════════════════════════════════════════
     STATE
  ══════════════════════════════════════════ */
  let weeklyPlan        = null;   /* { days: [...], nutrition_focus, hydration_daily_target, weekly_notes } */
  let currentDay        = 0;      /* 0 = Monday */
  let dietRejectedFoods = [];     /* persisted in localStorage — foods the player never wants to see again */
  let expertReview      = null;   /* zitlas_expert_review — set when APPROVED plan exists */
  let planSource        = 'ai';   /* 'ai' | 'expert' — source of the currently displayed plan */
  let activePlanReview  = null;   /* expert_plan_reviews entry when planSource === 'expert' */

  /* ══════════════════════════════════════════
     EXPERT REVIEW INVALIDATION
     Call whenever the athlete changes the plan
     (meal swap, regenerate day, new assessment,
     new diet plan, new review request).
     Clears all expert-review keys and resets
     the in-memory flag so UI badges update.
  ══════════════════════════════════════════ */
  function clearExpertReview(reason) {
    [
      'zitlas_expert_review', 'zitlas_plan_versions', 'zitlas_review_request',
      'expert_review', 'expert_diet_override', 'reviewed_diet_plan',
      'modifiedBy', 'expertApproval', 'review_request',
      'expertDiet', 'expertOverride', 'dietOverride', 'reviewStatus',
      'expertReviewedPlan', 'approvedPlan', 'expertWorkoutOverride',
    ].forEach(function (k) { localStorage.removeItem(k); });
    expertReview = null;
    console.log('[DIET] Expert review invalidated —', reason || 'plan changed');
  }

  /* ══════════════════════════════════════════
     TOAST
  ══════════════════════════════════════════ */
  let toastTimer = null;

  function showToast(message, duration = 2800) {
    const el = document.getElementById('toast');
    if (!el) return;
    el.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), duration);
  }

  /* ══════════════════════════════════════════
     LOCALSTORAGE HELPERS
  ══════════════════════════════════════════ */
  function safeJSON(key, fallback) {
    try { return JSON.parse(localStorage.getItem(key) || 'null') || fallback; }
    catch (_) { return fallback; }
  }

  /* ══════════════════════════════════════════
     HTML ESCAPE
  ══════════════════════════════════════════ */
  function esc(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* ══════════════════════════════════════════
     SVG RING ANIMATION
  ══════════════════════════════════════════ */
  function animateRing(el, pct, circumference, delay = 0) {
    if (!el) return;
    const offset = circumference * (1 - Math.min(pct, 100) / 100);
    setTimeout(() => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => { el.style.strokeDashoffset = offset; });
      });
    }, delay);
  }

  /* ══════════════════════════════════════════
     SHOW / HIDE LOADING
  ══════════════════════════════════════════ */
  function showLoading(show) {
    const loadEl    = document.getElementById('dietLoading');
    const contentEl = document.getElementById('dietContent');
    if (loadEl)    loadEl.style.display    = show ? 'flex' : 'none';
    if (contentEl) contentEl.style.display = show ? 'none' : 'block';
  }

  /* ══════════════════════════════════════════
     RENDER FOCUS CARD
  ══════════════════════════════════════════ */
  function renderFocusCard(plan, nutritionScore) {
    const titleEl = document.getElementById('focusTitle');
    const descEl  = document.getElementById('focusDesc');
    const tagEl   = document.getElementById('focusTag');
    const pctEl   = document.getElementById('ringPct');

    if (tagEl)   tagEl.textContent  = 'Your Weight-Loss Plan';
    if (titleEl) titleEl.textContent = plan.plan_name || 'Personalised Weight-Loss Plan';
    if (descEl)  descEl.innerHTML   = esc(plan.nutrition_focus || 'Designed to help you lose weight while maintaining energy, muscle mass and long-term health.');
    if (pctEl)   pctEl.textContent  = nutritionScore ? nutritionScore + '%' : '—';

    /* Focus ring — animate to nutrition score */
    if (nutritionScore) {
      animateRing(document.getElementById('focusRing'), nutritionScore, 314.159, 300);
    }

    /* Hydration target */
    const hydrSection = document.getElementById('hydrationSection');
    const hydrVal     = document.getElementById('hydrationTarget');
    if (plan.hydration_daily_target && hydrSection && hydrVal) {
      hydrVal.textContent  = plan.hydration_daily_target;
      hydrSection.style.display = 'block';
    }

    /* Weekly notes */
    const notesSection = document.getElementById('weeklyNotesSection');
    const notesText    = document.getElementById('weeklyNotesText');
    if (plan.weekly_notes && notesSection && notesText) {
      notesText.textContent  = plan.weekly_notes;
      notesSection.style.display = 'block';
    }

    /* Badge — new expert_plan_reviews system takes precedence over old zitlas_expert_review */
    var aiBadge       = document.getElementById('planAiBadge');
    var verifiedBadge = document.getElementById('planVerifiedBadge');
    var infoEl        = document.getElementById('expertPlanInfo');
    var nameEl        = document.getElementById('epiName');
    var dateEl        = document.getElementById('epiDate');

    if (planSource === 'expert' && activePlanReview) {
      if (aiBadge)       aiBadge.style.display       = 'none';
      if (verifiedBadge) verifiedBadge.style.display = 'inline-flex';
      if (infoEl) {
        infoEl.style.display = 'flex';
        if (nameEl) nameEl.textContent = activePlanReview.expertName || 'Expert';
        if (dateEl && activePlanReview.reviewedAt) {
          dateEl.textContent = new Date(activePlanReview.reviewedAt).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
        }
      }
    } else if (expertReview && expertReview.status === 'APPROVED') {
      if (aiBadge) aiBadge.style.display = 'none';
      if (verifiedBadge) {
        verifiedBadge.style.display = 'inline-flex';
        verifiedBadge.textContent   = '✅ Modified By ' + expertReview.reviewedBy;
      }
      if (infoEl) infoEl.style.display = 'none';
    } else {
      if (aiBadge)       aiBadge.style.display       = 'inline-block';
      if (verifiedBadge) verifiedBadge.style.display = 'none';
      if (infoEl)        infoEl.style.display        = 'none';
    }

    renderVersionHistory(expertReview);
  }

  /* ══════════════════════════════════════════
     PLAN VERSION HISTORY
  ══════════════════════════════════════════ */
  function renderVersionHistory(review) {
    var section = document.getElementById('versionHistorySection');
    var list    = document.getElementById('versionHistoryList');
    var activeLabel = document.getElementById('versionActiveLabel');
    if (!section || !list) return;

    var versions = [];
    try { versions = JSON.parse(localStorage.getItem('zitlas_plan_versions') || '[]'); } catch(_) {}

    if (!versions || versions.length === 0) {
      section.style.display = 'none';
      return;
    }

    section.style.display = 'block';

    var latestVersion = versions[versions.length - 1];
    if (activeLabel) {
      if (latestVersion.type === 'expert_revised') {
        activeLabel.textContent = 'Expert Approved ✅';
        activeLabel.className = 'version-active-label version-active--expert';
      } else {
        activeLabel.textContent = 'Current Active';
        activeLabel.className = 'version-active-label';
      }
    }

    list.innerHTML = versions.map(function(v, i) {
      var isActive   = i === versions.length - 1;
      var typeClass  = v.type === 'expert_revised' ? 'version-card--expert' : 'version-card--ai';
      var typeIcon   = v.type === 'expert_revised' ? '👨‍⚕️' : '🤖';
      var typeLabel  = v.type === 'expert_revised'
        ? 'Expert Reviewed by ' + (v.expertName || 'Expert')
        : 'AI Generated';
      var dateStr = v.createdAt
        ? new Date(v.createdAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
        : '';
      var changeStr = v.changeCount != null ? ' · ' + v.changeCount + ' change' + (v.changeCount !== 1 ? 's' : '') : '';

      return '<div class="version-card ' + typeClass + (isActive ? ' version-card--active' : '') + '">' +
        '<div class="version-card-left">' +
          '<span class="version-icon">' + typeIcon + '</span>' +
          '<div class="version-info">' +
            '<span class="version-label">Version ' + v.version + '</span>' +
            '<span class="version-type">' + typeLabel + '</span>' +
            (dateStr ? '<span class="version-date">' + dateStr + changeStr + '</span>' : '') +
          '</div>' +
        '</div>' +
        (isActive ? '<span class="version-active-chip">Active</span>' : '') +
      '</div>';
    }).join('');
  }

  /* Translate common meal type names via i18n */
  function translateMealName(name) {
    if (!window.ZitlasLang || !name) return name;
    var key = 'meal_' + name.trim().toLowerCase().replace(/[\s\-]+/g, '_').replace(/[^a-z0-9_]/g, '');
    var translated = ZitlasLang.t(key);
    return translated !== key ? translated : name;
  }

  /* ══════════════════════════════════════════
     RENDER DAY MEALS
  ══════════════════════════════════════════ */
  function renderDay(dayIndex) {
    if (!weeklyPlan || !weeklyPlan.days || !weeklyPlan.days[dayIndex]) return;

    const dayData  = weeklyPlan.days[dayIndex];
    const mealList = document.getElementById('mealList');
    const themeWrap= document.getElementById('dayThemeWrap');
    const themeTag = document.getElementById('dayThemeTag');
    const typeTag  = document.getElementById('dayTypeTag');
    const tipText  = document.getElementById('tipText');

    /* Day theme strip */
    if (themeWrap && dayData.theme) {
      themeTag.textContent  = dayData.theme || '';
      typeTag.textContent   = dayData.day_type || '';
      themeWrap.style.display = 'flex';
    }

    /* Tip */
    if (tipText && dayData.nutrition_tip) {
      tipText.textContent = dayData.nutrition_tip;
    }

    if (!mealList) return;

    const meals = dayData.meals || [];

    const swapSvg = `<svg width="17" height="17" viewBox="0 0 24 24" fill="none"
      stroke="#FF8A00" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="17 1 21 5 17 9"/>
      <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
      <polyline points="7 23 3 19 7 15"/>
      <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
    </svg>`;

    const isExpertActive  = expertReview && expertReview.status === 'APPROVED';
    const isNewExpertPlan = planSource === 'expert';
    const reviewedBy      = isExpertActive ? (expertReview.reviewedBy || 'Expert') : '';

    mealList.innerHTML = meals.map((meal, i) => {
      const isLast     = i === meals.length - 1;
      const color      = esc(meal.color || '#FF8A00');
      const bg         = hexToRgba(meal.color || '#FF8A00', 0.13);
      const isModified = isExpertActive && meal._modified;

      /* Build foods display (legacy old-system expert modification) */
      let foodsHtml;
      if (isModified) {
        const origFoods = Array.isArray(meal._originalFoods) && meal._originalFoods.length
          ? meal._originalFoods.join(', ')
          : (meal._original || '');
        const newFoods = (meal.foods || []).join(', ') || meal._replacement || '';
        foodsHtml =
          `<span class="meal-foods meal-foods--strike">${esc(origFoods)}</span>` +
          `<span class="meal-foods meal-foods--expert">✓ ${esc(newFoods)}</span>` +
          `<span class="meal-expert-tag">Updated by ${esc(reviewedBy)}</span>`;
      } else {
        const foods = (meal.foods || []).join(', ');
        foodsHtml = `<span class="meal-foods">${esc(foods)}</span>`;
      }

      /* Small attribution note for new-system expert-edited meals */
      const isExpertEdited = isNewExpertPlan && meal._edited;
      const expertName     = (activePlanReview && activePlanReview.expertName) || 'Expert';
      const mealLabel      = esc(translateMealName(meal.meal_name || 'meal'));
      const expertNote     = isExpertEdited
        ? `<span class="meal-expert-note">✏️ ${esc(expertName)} changed your ${mealLabel}.</span>`
        : '';

      return `
        <article class="meal-card${isLast ? ' meal-card--last' : ''}${isModified ? ' meal-card--expert' : ''}">
          <div class="meal-icon-circle" style="background:${bg};">
            <span class="meal-emoji">${esc(meal.emoji || '🍽️')}</span>
          </div>
          <div class="meal-info">
            <span class="meal-name" style="color:${color};">${esc(translateMealName(meal.meal_name || ''))}</span>
            <span class="meal-time">${esc(meal.time || '')}</span>
            ${foodsHtml}
            ${meal.purpose ? `<span class="meal-purpose">${esc(meal.purpose)}</span>` : ''}
            ${expertNote}
          </div>
          <button class="swap-btn" data-meal="${esc(meal.meal_name || '')}" aria-label="Swap ${esc(meal.meal_name || '')}">
            ${swapSvg}
            <span class="swap-label">Can't eat<br>this?</span>
          </button>
        </article>`;
    }).join('');

    /* Re-wire swap buttons for newly rendered cards */
    wireSwapButtons();

    /* Animate cards in */
    requestAnimationFrame(() => {
      mealList.querySelectorAll('.meal-card').forEach((card, i) => {
        card.style.opacity   = '0';
        card.style.transform = 'translateY(10px)';
        card.style.transition = `opacity 0.35s ease ${0.05 * i}s, transform 0.38s cubic-bezier(0.34,1.2,0.64,1) ${0.05 * i}s`;
        requestAnimationFrame(() => {
          card.style.opacity   = '1';
          card.style.transform = 'translateY(0)';
        });
      });
    });
  }

  /* Convert a hex colour to rgba string */
  function hexToRgba(hex, alpha) {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!result) return `rgba(255,138,0,${alpha})`;
    return `rgba(${parseInt(result[1],16)},${parseInt(result[2],16)},${parseInt(result[3],16)},${alpha})`;
  }

  /* ══════════════════════════════════════════
     DAY SELECTOR
  ══════════════════════════════════════════ */
  function initDaySelector() {
    const pills    = document.querySelectorAll('.day-pill');
    /* Plan order: Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
       getDay()  : Sun=0, Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6 */
    const todayIdx = (new Date().getDay() + 6) % 7;
    currentDay     = todayIdx;

    pills.forEach((pill) => {
      const pillIdx = parseInt(pill.dataset.dayIndex || '0', 10);
      const isToday = pillIdx === todayIdx;

      /* Activate today's pill; deactivate all others */
      pill.classList.toggle('active', isToday);

      /* Set/clear "TODAY" sub-label */
      let subSpan = pill.querySelector('.day-sub');
      if (isToday) {
        if (!subSpan) {
          subSpan = document.createElement('span');
          subSpan.className = 'day-sub';
          pill.appendChild(subSpan);
        }
        subSpan.textContent = 'TODAY';
      } else if (subSpan) {
        subSpan.textContent = '';
      }

      pill.addEventListener('click', () => {
        pills.forEach(p => p.classList.remove('active'));
        pill.classList.add('active');
        currentDay = pillIdx;
        renderDay(pillIdx);
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    });

    /* Scroll today's pill into view in the day rail */
    const todayPill = document.querySelector(`.day-pill[data-day-index="${todayIdx}"]`);
    if (todayPill) {
      const rail = todayPill.closest('.day-scroll-wrap');
      if (rail) {
        setTimeout(() => {
          const left = todayPill.offsetLeft - rail.offsetWidth / 2 + todayPill.offsetWidth / 2;
          rail.scrollTo({ left: Math.max(0, left), behavior: 'smooth' });
        }, 150);
      }
    }
  }

  /* ══════════════════════════════════════════
     SWAP MODAL — 3-phase flow
     Phase A: choose reason
     Phase B: loading (AI call)
     Phase C: show result + accept/reject
  ══════════════════════════════════════════ */

  let _swapMealName  = '';
  let _swapMealFoods = [];
  let _swapMealTime  = '';
  let _swapResult    = null;
  let _swapReason    = '';
  let _swapHistory   = []; // foods arrays from every suggestion this session

  function showSwapPhase(phase) {
    ['swapPhaseA', 'swapPhaseB', 'swapPhaseC'].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.style.display = id === phase ? 'block' : 'none';
    });
  }

  function openSwapModal(mealName, foods, time) {
    _swapMealName  = mealName;
    _swapMealFoods = foods || [];
    _swapMealTime  = time  || '';
    _swapResult    = null;
    _swapReason    = '';
    _swapHistory   = [];

    const mealTag = document.getElementById('swapMealName');
    if (mealTag) mealTag.textContent = mealName;

    showSwapPhase('swapPhaseA');
    const modal = document.getElementById('swapModal');
    if (modal) {
      modal.classList.add('open');
      document.body.style.overflow = 'hidden';
    }
  }

  function closeSwapModal() {
    const modal = document.getElementById('swapModal');
    if (modal) modal.classList.remove('open');
    document.body.style.overflow = '';
    showSwapPhase('swapPhaseA');
  }

  async function callSwapMealApi(reason) {
    const athleteProfile = safeJSON('athlete_profile', {});
    const lifestyleData  = safeJSON('lifestyle_data', {});

    /* Current meal foods are forbidden immediately — they're the reason for the swap */
    const effectiveRejected = [...new Set([...dietRejectedFoods, ..._swapMealFoods])];

    console.log('[SWAP] Current Meal:', _swapMealFoods);
    console.log('[SWAP] Rejected Foods:', effectiveRejected);

    const MAX_RETRIES = 2;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      const resp = await fetch('/api/ai/swap-meal', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({
          meal_name:            _swapMealName,
          meal_time:            _swapMealTime,
          current_foods:        _swapMealFoods,
          reason:               reason,
          user_profile:         athleteProfile,
          lifestyle_data:       lifestyleData,
          rejected_foods:       effectiveRejected,
          previous_suggestions: _swapHistory,
        }),
      });

      if (!resp.ok) throw new Error('API error ' + resp.status);
      const data = await resp.json();
      if (!data.structured) throw new Error('No result');

      console.log('Swap API Response:', data);
      console.log('Rendered Swap:', data.structured && data.structured.swap);

      const meal = data.structured;
      if (!meal.swap) throw new Error('No swap in result');

      const swapFoods      = meal.swap.foods || [];
      const mealFoodsLower = swapFoods.map(f => f.toLowerCase());
      const rejectedLower  = effectiveRejected.map(f => f.toLowerCase());

      const violation = mealFoodsLower.find(f =>
        rejectedLower.some(r => f.includes(r) || r.includes(f))
      );

      if (!violation) {
        console.log('[SWAP] Replacement Generated:', swapFoods);
        console.log('[SWAP] Validation Passed');
        return meal;
      }

      console.warn(`[SWAP] Validation Failed (attempt ${attempt + 1}/${MAX_RETRIES + 1}) — "${violation}" is a rejected food. Retrying...`);
      _swapHistory.push(swapFoods);
    }

    throw new Error('Could not generate a valid swap after retries');
  }

  function renderSwapResult(meal) {
    const card = document.getElementById('swapResultCard');
    if (!card) return;

    const swap = meal && meal.swap;
    if (!swap) {
      card.innerHTML = '<p class="swap-no-result">No suitable alternative found. Try a different reason.</p>';
      return;
    }

    const foods = swap.foods || [];
    card.innerHTML = `
      <div class="swap-result-name">🥣 ${esc(swap.name || _swapMealName)}</div>
      <div class="swap-result-foods-section">
        <span class="swap-result-label">Foods:</span>
        <ul class="swap-result-foods-list">
          ${foods.map(f => `<li>${esc(f)}</li>`).join('')}
        </ul>
      </div>
      <div class="swap-result-macros">
        ${swap.calories  ? `<span class="swap-macro-chip">🔥 ${esc(String(swap.calories))} kcal</span>`   : ''}
        ${swap.protein_g ? `<span class="swap-macro-chip">💪 ${esc(String(swap.protein_g))}g protein</span>` : ''}
        ${meal.calories_saved ? `<span class="swap-macro-chip swap-macro-chip--green">−${esc(String(meal.calories_saved))} kcal saved</span>` : ''}
      </div>
      ${swap.reason ? `<div class="swap-result-reason"><span class="swap-result-label">Why this works:</span><p>${esc(swap.reason)}</p></div>` : ''}
    `;
  }

  function applySwappedMeal(swappedMeal) {
    if (!weeklyPlan || !weeklyPlan.days || !weeklyPlan.days[currentDay]) return;

    const day   = weeklyPlan.days[currentDay];
    const meals = day.meals || [];

    const idx = meals.findIndex((m) =>
      (m.meal_name || '').toLowerCase() === (_swapMealName || '').toLowerCase()
    );
    if (idx !== -1) {
      const swap = (swappedMeal && swappedMeal.swap) || swappedMeal;
      meals[idx] = Object.assign({}, meals[idx], {
        foods:   swap.foods   || meals[idx].foods,
        purpose: swap.reason  || swap.purpose || meals[idx].purpose,
      });
    }

    try {
      localStorage.setItem('zitlas_diet_plan', JSON.stringify(weeklyPlan));
    } catch (_) {}

    /* A meal swap invalidates any active expert review — the plan is now athlete-modified */
    if (expertReview) {
      clearExpertReview('meal swapped by athlete');
      renderFocusCard(weeklyPlan, null);
    }

    /* Re-render the day */
    renderDay(currentDay);
  }

  function wireSwapButtons() {
    document.querySelectorAll('.swap-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        const mealName = btn.dataset.meal || '';
        /* Find the foods for this meal from the current day plan */
        const day   = weeklyPlan && weeklyPlan.days && weeklyPlan.days[currentDay];
        const meals = day && day.meals ? day.meals : [];
        const meal  = meals.find((m) => (m.meal_name || '') === mealName);
        openSwapModal(mealName, meal ? (meal.foods || []) : [], meal ? (meal.time || '') : '');
      });
    });
  }

  function initSwapModal() {
    const modal = document.getElementById('swapModal');
    if (!modal) return;

    /* Close button Phase A */
    const closeA = document.getElementById('swapClose');
    if (closeA) closeA.addEventListener('click', closeSwapModal);

    /* Close button Phase C */
    const closeC = document.getElementById('swapCloseC');
    if (closeC) closeC.addEventListener('click', closeSwapModal);

    /* Dismiss on backdrop */
    modal.addEventListener('click', (e) => { if (e.target === modal) closeSwapModal(); });
    modal.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeSwapModal(); });

    /* Reason buttons */
    modal.querySelectorAll('.swap-option[data-reason]').forEach((opt) => {
      opt.addEventListener('click', async () => {
        const reason = opt.dataset.reason;
        _swapReason = reason;
        showSwapPhase('swapPhaseB');

        try {
          _swapResult = await callSwapMealApi(reason);
          _swapHistory.push((_swapResult.swap && _swapResult.swap.foods) || []);
          renderSwapResult(_swapResult);
          showSwapPhase('swapPhaseC');
        } catch (_e) {
          closeSwapModal();
          showToast("Couldn't find a swap right now — try again");
        }
      });
    });

    /* Accept swap */
    const acceptBtn = document.getElementById('swapAcceptBtn');
    if (acceptBtn) {
      acceptBtn.addEventListener('click', () => {
        if (_swapResult) {
          if (_swapMealFoods.length > 0) {
            const newRejections = _swapMealFoods.filter(f => !dietRejectedFoods.includes(f));
            if (newRejections.length > 0) {
              dietRejectedFoods = [...dietRejectedFoods, ...newRejections];
              try {
                localStorage.setItem('diet_rejected_foods', JSON.stringify(dietRejectedFoods));
              } catch (_) {}
            }
          }
          applySwappedMeal(_swapResult);
          showToast('✅ Meal swapped! Those foods won\'t appear again.');
        }
        closeSwapModal();
      });
    }

    /* Try Again — re-call API with same reason, excluding all previous suggestions */
    const rejectBtn = document.getElementById('swapRejectBtn');
    if (rejectBtn) {
      rejectBtn.addEventListener('click', async () => {
        console.log('TRY AGAIN CLICKED', { reason: _swapReason, historyLength: _swapHistory.length });
        _swapResult = null;
        showSwapPhase('swapPhaseB');

        try {
          _swapResult = await callSwapMealApi(_swapReason);
          _swapHistory.push((_swapResult.swap && _swapResult.swap.foods) || []);
          renderSwapResult(_swapResult);
          showSwapPhase('swapPhaseC');
        } catch (_e) {
          closeSwapModal();
          showToast("Couldn't find a swap right now — try again");
        }
      });
    }

    /* Keep original — just close the modal without changing anything */
    const keepBtn = document.getElementById('swapKeepBtn');
    if (keepBtn) {
      keepBtn.addEventListener('click', () => {
        closeSwapModal();
      });
    }

    /* Ask Nutritionist — opens nutritionist selection modal */
    const nutriBtn = document.getElementById('swapNutriBtn');
    if (nutriBtn) {
      nutriBtn.addEventListener('click', () => {
        closeSwapModal();
        openNutriSelectModal();
      });
    }
  }

  /* ══════════════════════════════════════════
     NUTRITIONIST SELECT MODAL
  ══════════════════════════════════════════ */

  function openNutriSelectModal() {
    /* Context pill */
    var ctxEl = document.getElementById('nutriSelectContext');
    if (ctxEl && _swapMealName) {
      ctxEl.innerHTML =
        '<span class="nutri-ctx-pill">' +
          '<span class="nutri-ctx-meal">' + esc(_swapMealName) + '</span>' +
          '<span class="nutri-ctx-sep">·</span>' +
          '<span class="nutri-ctx-foods">' + esc((_swapMealFoods || []).slice(0, 2).join(', ') + (_swapMealFoods.length > 2 ? ' +' + (_swapMealFoods.length - 2) + ' more' : '')) + '</span>' +
        '</span>';
      ctxEl.style.display = '';
    } else if (ctxEl) {
      ctxEl.style.display = 'none';
    }

    /* Meal tag subtitle */
    var mealTag = document.getElementById('nutriSelectMealTag');
    if (mealTag) mealTag.textContent = _swapMealName ? 'For: ' + _swapMealName : '';

    renderNutriSelectList();

    var modal = document.getElementById('nutriSelectModal');
    if (modal) {
      modal.classList.add('open');
      document.body.style.overflow = 'hidden';
    }
  }

  function closeNutriSelectModal() {
    var modal = document.getElementById('nutriSelectModal');
    if (modal) modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  function renderNutriSelectList() {
    var list = document.getElementById('nutriSelectList');
    if (!list) return;

    list.innerHTML = MOCK_NUTRITIONISTS.map(function (n) {
      var initials = n.name.split(' ').map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase();

      /* Star rating */
      var fullStars = Math.floor(n.rating);
      var halfStar  = (n.rating - fullStars) >= 0.5;
      var stars = '';
      for (var i = 0; i < fullStars; i++) {
        stars += '<svg class="nsc-star" viewBox="0 0 24 24" fill="#FBBF24" stroke="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/></svg>';
      }
      if (halfStar) {
        stars += '<svg class="nsc-star" viewBox="0 0 24 24" fill="#FBBF24" stroke="none"><path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77V2z"/><path d="M12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2v15.77z" fill="#374151"/></svg>';
      }

      var availBadge = n.available
        ? '<span class="nsc-badge nsc-badge--avail">● Available now</span>'
        : '<span class="nsc-badge nsc-badge--busy">Busy</span>';

      return '<div class="nsc-card' + (n.available ? '' : ' nsc-card--busy') + '" data-nutri-id="' + esc(n.id) + '">' +
        '<div class="nsc-top">' +
          '<div class="nsc-avatar" style="background:' + n.color + '22;border-color:' + n.color + '55;">' +
            '<span class="nsc-initials" style="color:' + n.color + ';">' + esc(initials) + '</span>' +
            (n.available ? '<span class="nsc-online-dot"></span>' : '') +
          '</div>' +
          '<div class="nsc-info">' +
            '<div class="nsc-name-row">' +
              '<span class="nsc-name">' + esc(n.name) + '</span>' +
              availBadge +
            '</div>' +
            '<span class="nsc-spec">' + esc(n.specialization) + '</span>' +
            '<div class="nsc-rating-row">' +
              '<span class="nsc-stars">' + stars + '</span>' +
              '<span class="nsc-rating-val">' + n.rating + '</span>' +
              '<span class="nsc-reviews">(' + n.reviews + ' reviews)</span>' +
            '</div>' +
          '</div>' +
        '</div>' +
        '<div class="nsc-meta">' +
          '<span class="nsc-meta-chip nsc-meta-chip--price">₹149 · 7–8 min Quick Review</span>' +
          '<span class="nsc-meta-chip">📍 ' + esc(n.location) + '</span>' +
        '</div>' +
        '<div class="nsc-actions">' +
          '<button class="nsc-btn nsc-btn--primary' + (n.available ? '' : ' nsc-btn--disabled') + '" data-action="book" data-nutri-id="' + esc(n.id) + '"' + (n.available ? '' : ' disabled') + '>Ask Nutritionist</button>' +
          '<button class="nsc-btn nsc-btn--secondary" data-action="profile" data-nutri-id="' + esc(n.id) + '">View Profile</button>' +
        '</div>' +
      '</div>';
    }).join('');

    /* Wire action buttons */
    list.querySelectorAll('[data-action]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var action   = btn.dataset.action;
        var nutriId  = btn.dataset.nutriId;
        var nutri    = MOCK_NUTRITIONISTS.find(function (n) { return n.id === nutriId; });
        if (!nutri) return;

        if (action === 'book') {
          var payload = {
            nutritionist_id:      nutri.id,
            nutritionist_name:    nutri.name,
            meal_name:            _swapMealName,
            meal_rejection_reason: _swapReason || 'Expert review requested',
            rejected_foods:       _swapMealFoods,
            assessment:           safeJSON('zitlas_assessment', {}),
            swot:                 safeJSON('zitlas_swot', {}),
            diet_plan:            safeJSON('zitlas_diet_plan', {}),
            workout_plan:         safeJSON('zitlas_workout_plan', {}),
          };
          console.log('[NUTRI ASK] Payload:', payload);
          showToast('Connecting you to ' + nutri.name + ' — coming soon!');
        } else {
          showToast('Profile for ' + nutri.name + ' — coming soon!');
        }
      });
    });
  }

  function initNutriSelectModal() {
    var modal = document.getElementById('nutriSelectModal');
    if (!modal) return;

    var closeBtn = document.getElementById('nutriSelectClose');
    if (closeBtn) closeBtn.addEventListener('click', closeNutriSelectModal);

    modal.addEventListener('click', function (e) { if (e.target === modal) closeNutriSelectModal(); });
    modal.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeNutriSelectModal(); });
  }

  /* ══════════════════════════════════════════
     HEADER BUTTONS
  ══════════════════════════════════════════ */
  function initHeader() {
    const backBtn = document.getElementById('backBtn');
    const infoBtn = document.getElementById('infoBtn');

    if (backBtn) {
      backBtn.addEventListener('click', () => {
        if (history.length > 1) history.back();
        else showToast('ZITLAS Home — coming soon');
      });
    }

    if (infoBtn) {
      infoBtn.addEventListener('click', () => {
        showToast('AI Diet Plan powered by ZITLAS Nutrition Brain ⚡');
      });
    }
  }

  /* ══════════════════════════════════════════
     FETCH WEEKLY PLAN FROM API
  ══════════════════════════════════════════ */
  async function fetchWeeklyPlan(athleteProfile, nutritionAssessment, lifestyleData, rejectedFoods) {
    const resp = await fetch('/api/ai/nutrition-weekly-plan', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({
        user_profile:          athleteProfile,
        nutrition_assessment:  nutritionAssessment || null,
        lifestyle_data:        lifestyleData       || null,
        rejected_foods:        rejectedFoods       || [],
      }),
    });
    if (!resp.ok) throw new Error('API ' + resp.status);
    const data = await resp.json();
    if (!data.structured) throw new Error('No structured data');
    return data.structured;
  }

  /* ══════════════════════════════════════════
     VERIFY BY NUTRITIONIST
  ══════════════════════════════════════════ */

  var SPONSORED_NUTRITIONISTS = [
    {
      id:         'rahul',
      name:       'Rahul Sharma',
      role:       'Weight Loss Nutritionist',
      initials:   'RS',
      colorAccent:'#FF8A00',
      rating:     4.9,
      reviews:    128,
      fee:        149,
      duration:   '15 Min',
      experience: '8+ Yrs',
      expertise:  ['Meal Planning', 'Calorie Targeting', 'Metabolism'],
    },
    {
      id:         'arjun',
      name:       'Arjun Nair',
      role:       'Sports Dietitian',
      initials:   'AN',
      colorAccent:'#3B82F6',
      rating:     4.8,
      reviews:    96,
      fee:        229,
      duration:   '20 Min',
      experience: '8+ Yrs',
      expertise:  ['Performance Analysis', 'Precision Nutrition', 'Diet Strategy'],
    },
    {
      id:         'prakash',
      name:       'Prakash Sir',
      role:       'Head Nutritionist',
      initials:   'PS',
      colorAccent:'#FF8A00',
      rating:     4.9,
      reviews:    210,
      fee:        299,
      duration:   '30 Min',
      experience: '12+ Yrs',
      expertise:  ['Holistic Nutrition', 'Sports Diets', 'Performance Planning'],
    },
  ];

  function _vnStars(rating) {
    var full = Math.floor(rating);
    var html = '';
    for (var i = 0; i < 5; i++) {
      var c = i < full ? '#FF8A00' : '#333';
      html += '<svg width="11" height="11" viewBox="0 0 24 24" fill="' + c + '" stroke="none"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>';
    }
    return html;
  }

  function renderVerifyNutriSection() {
    var section = document.getElementById('verifyNutriSection');
    var rail    = document.getElementById('vnNutriRail');
    if (!section || !rail) return;

    var existing = safeJSON('zitlas_review_request', null);
    if (existing) updateVerifyStatusUI(existing);

    var review = safeJSON('zitlas_expert_review', null);
    if (review && review.status === 'APPROVED') showVerifiedBanner(review);

    rail.innerHTML = SPONSORED_NUTRITIONISTS.map(function(n) {
      var profileUrl = '../coaches/cprofile.html?id=' + n.id;
      var isRequested = !!(existing && existing.expertId === n.id);
      return (
        '<div class="vn-card">' +
          '<div class="vn-card-header">' +
            '<div class="vn-avatar" style="background:' + n.colorAccent + '18;border:2px solid ' + n.colorAccent + '44;">' +
              '<span class="vn-initials" style="color:' + n.colorAccent + ';">' + esc(n.initials) + '</span>' +
              '<span class="vn-online-dot"></span>' +
            '</div>' +
            '<div class="vn-info">' +
              '<span class="vn-name">' + esc(n.name) + '</span>' +
              '<span class="vn-role">' + esc(n.role) + '</span>' +
            '</div>' +
            '<span class="vn-sponsored-chip">Sponsored</span>' +
          '</div>' +
          '<div class="vn-rating-row">' +
            _vnStars(n.rating) +
            '<span class="vn-rating-val">&thinsp;' + n.rating + '</span>' +
            '<span class="vn-review-count">(' + n.reviews + ')</span>' +
            '<span class="vn-exp-chip">' + esc(n.experience) + '</span>' +
          '</div>' +
          '<div class="vn-expertise-row">' +
            n.expertise.map(function(e) { return '<span class="vn-exp-tag">' + esc(e) + '</span>'; }).join('') +
          '</div>' +
          '<div class="vn-fee-row">' +
            '<span class="vn-fee">₹' + n.fee + '</span>' +
            '<span class="vn-fee-label">review fee</span>' +
            '<span class="vn-divider">·</span>' +
            '<span class="vn-duration">' + esc(n.duration) + '</span>' +
          '</div>' +
          '<div class="vn-card-actions">' +
            '<a href="' + profileUrl + '" class="vn-btn vn-btn--ghost">View Profile</a>' +
            '<button class="vn-btn vn-btn--primary" data-vn-expert="' + n.id + '"' + (isRequested ? ' disabled' : '') + '>' +
              (isRequested ? '✓ Sent' : 'Verify My Diet →') +
            '</button>' +
          '</div>' +
        '</div>'
      );
    }).join('');

    rail.querySelectorAll('.vn-btn--primary[data-vn-expert]').forEach(function(btn) {
      btn.addEventListener('click', function() {
        if (btn.disabled) return;
        submitVerifyRequest(btn.dataset.vnExpert);
      });
    });

    section.style.display = '';
  }

  function submitVerifyRequest(expertId) {
    var expert     = SPONSORED_NUTRITIONISTS.find(function(n) { return n.id === expertId; });
    var athleteId  = localStorage.getItem('zitlas_athlete_id') || ('athlete_' + Date.now());
    var fbUser     = safeJSON('zitlas_firebase_user', {});
    var athleteName = (fbUser && (fbUser.name || fbUser.displayName)) || 'Athlete';

    var reviewRequest = {
      id:           'rvw_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
      athleteId:    athleteId,
      athlete_name: athleteName,
      expertId:     expertId,
      status:       'pending',
      submittedAt:  new Date().toISOString(),
      context: {
        assessment:   safeJSON('zitlas_assessment', null) || safeJSON('zitlas_survey', null),
        calculations: safeJSON('zitlas_calculations', null),
        swot:         safeJSON('zitlas_swot', null),
        diet_plan:    safeJSON('zitlas_diet_plan', null),
        workout_plan: safeJSON('zitlas_workout_plan', null),
      },
      goal:   safeJSON('zitlas_goal', null),
      planId: localStorage.getItem('zitlas_plan_id'),
      fee:    expert ? expert.fee : 149,
    };

    try {
      localStorage.setItem('zitlas_review_request', JSON.stringify(reviewRequest));
    } catch (_) {}

    fetch('/api/review/submit', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(reviewRequest),
    }).catch(function() {});

    updateVerifyStatusUI(reviewRequest);

    document.querySelectorAll('.vn-btn--primary[data-vn-expert]').forEach(function(btn) {
      if (btn.dataset.vnExpert === expertId) {
        btn.textContent = '✓ Sent';
        btn.disabled    = true;
      }
    });

    var name = expert ? expert.name : 'the nutritionist';
    showToast('✅ Verification request sent to ' + name + '!', 3500);
  }

  function updateVerifyStatusUI(req) {
    if (!req) return;
    var banner = document.getElementById('vnStatusBanner');
    var icon   = document.getElementById('vnStatusIcon');
    var title  = document.getElementById('vnStatusTitle');
    var sub    = document.getElementById('vnStatusSub');
    var pill   = document.getElementById('vnStatusPill');
    if (!banner) return;

    var statusMap = {
      'pending':                { icon: '⏳', title: 'Request Sent',      sub: 'Awaiting expert review',        pill: 'Pending',      cls: 'vn-pill--pending'   },
      'expert_reviewing':       { icon: '🔍', title: 'Under Review',       sub: 'Expert is reviewing your plan', pill: 'Under Review', cls: 'vn-pill--reviewing' },
      'changes_suggested':      { icon: '📝', title: 'Changes Suggested',  sub: 'Expert made modifications',     pill: 'Changes Made', cls: 'vn-pill--changes'   },
      'approved':               { icon: '✅', title: 'Plan Approved',      sub: 'Your plan has been certified',  pill: 'Approved',     cls: 'vn-pill--approved'  },
      'revised_plan_published': { icon: '🚀', title: 'Updated Plan Active', sub: 'Expert-revised plan is live',  pill: 'Active',       cls: 'vn-pill--active'    },
    };
    var s = statusMap[req.status] || statusMap['pending'];

    if (icon)  icon.textContent  = s.icon;
    if (title) title.textContent = s.title;
    if (sub)   sub.textContent   = s.sub;
    if (pill)  { pill.textContent = s.pill; pill.className = 'vn-status-pill ' + s.cls; }

    banner.style.display = 'flex';

    if (req.status === 'approved' || req.status === 'revised_plan_published') {
      var expert = SPONSORED_NUTRITIONISTS.find(function(n) { return n.id === req.expertId; });
      showVerifiedBanner({ status: 'APPROVED', reviewedBy: expert ? expert.name : 'Expert', expertId: req.expertId });
    }
  }

  function showVerifiedBanner(review) {
    var banner = document.getElementById('vnVerifiedBanner');
    var link   = document.getElementById('vnVerifiedLink');
    if (!banner) return;
    if (link && review.expertId) {
      link.textContent = 'Verified by ' + (review.reviewedBy || 'Expert');
      link.href = '../coaches/cprofile.html?id=' + review.expertId;
    }
    banner.style.display = 'flex';
  }

  /* ══════════════════════════════════════════
     MAIN INIT
  ══════════════════════════════════════════ */
  async function init() {
    loadTheme();

    initDaySelector();
    initSwapModal();
    initNutriSelectModal();
    initHeader();

    /* Real-time listener: expert saves a review → show banner without refresh */
    window.addEventListener('storage', function (e) {
      if (e.key !== 'expert_plan_reviews') return;
      var updated = getCompletedPlanReview();
      if (!updated || !updated.reviewedDietPlan || !updated.reviewedDietPlan.days) return;
      /* Already showing this review */
      if (activePlanReview && activePlanReview.id === updated.id &&
          activePlanReview.reviewedAt === updated.reviewedAt) return;
      /* New review found — update plan and notify */
      planSource       = 'expert';
      activePlanReview = updated;
      weeklyPlan       = normalizePlan(updated.reviewedDietPlan);
      renderFocusCard(weeklyPlan, null);
      renderDay(currentDay);
      renderExpertChangeSummary(updated);
      if (!updated.athleteAccepted) {
        showExpertReviewBanner(updated);
        initExpertReviewBannerInteractions();
      }
      showToast('👨‍⚕️ Your nutritionist has reviewed your plan!', 4000);
    });

    /* Load persisted food restrictions */
    dietRejectedFoods = safeJSON('diet_rejected_foods', []);

    /* ── Purge stale sport-specific meal plan data ── */
    var _staleKeys = ['nutrition_weekly_plan', 'athlete_profile',
      'nutrition_assessment', 'nutrition_scores', 'nutrition_swot',
      'nutrition_recommendations', 'nutrition_bottleneck'];
    var _rawOld = localStorage.getItem('nutrition_weekly_plan');
    var _STALE_MARKERS = ['batsman', 'bowler', 'cricket', 'wicket', 'batting', 'bowling', 'all-rounder', 'all rounder'];
    if (_rawOld) {
      var _oldLower = _rawOld.toLowerCase();
      var _isStale  = _STALE_MARKERS.some(function (m) { return _oldLower.indexOf(m) !== -1; });
      if (_isStale) {
        console.log('[DIET CACHE] Stale sport-specific data detected — purging localStorage');
        _staleKeys.forEach(function (k) { localStorage.removeItem(k); });
        localStorage.removeItem('zitlas_diet_plan');
        localStorage.removeItem('zitlas_plan_generated_at');
      }
    }

    /* ── Check for APPROVED expert review first ── */
    var _er       = safeJSON('zitlas_expert_review', null);
    var _goalData = safeJSON('zitlas_goal', null);
    var _activePlanId = localStorage.getItem('zitlas_plan_id');

    console.log('Current Goal',  _goalData);
    console.log('ACTIVE PLAN',   _activePlanId);
    console.log('REVIEW PLAN',   _er ? _er.planId : null);
    console.log('Reviewed Diet', _er);

    /* ── planId guard ──────────────────────────────────────────────────────────
       Expert review is ONLY valid when:
         • _er.planId  is set (review was stamped to a specific plan)
         • _activePlanId is set (there is a known active plan)
         • both IDs are identical
       Any other case (missing planId, null activePlanId, mismatch) → stale.
       Remove the key so it never interferes again.
    ─────────────────────────────────────────────────────────────────────────── */
    if (_er) {
      /* Reject ONLY when both planIds are present and don't match.
         null/null means planId was never generated — still trust the review. */
      var _planIdMismatch = _er.planId && _activePlanId && (_er.planId !== _activePlanId);
      var _reviewValid    = !_planIdMismatch;
      console.log('[DIET] planId guard — er.planId:', _er.planId, '| active:', _activePlanId, '| mismatch:', _planIdMismatch, '| valid:', _reviewValid);
      if (!_reviewValid) {
        console.log('[DIET] Expert review DISCARDED — planId mismatch: review=' + _er.planId + ' active=' + _activePlanId);
        localStorage.removeItem('zitlas_expert_review');
        _er = null;
      }
    }

    if (_er && _er.status === 'APPROVED' && _er.modifiedDietPlan && _er.modifiedDietPlan.days) {
      expertReview = _er;
      console.log('[DIET] Expert plan loaded — reviewedBy:', _er.reviewedBy, '| planId:', _er.planId);
      console.log('Active Diet', _er.modifiedDietPlan);
      weeklyPlan = normalizePlan(_er.modifiedDietPlan);
      showLoading(false);
      renderPlanMeta();
      renderFocusCard(weeklyPlan, null);
      renderDay(currentDay);
      renderVerifyNutriSection();
      return;
    }

    /* ── Check expert_plan_reviews (new Verify Plan system) ── */
    var _newReview = getCompletedPlanReview();
    if (_newReview && _newReview.reviewedDietPlan && _newReview.reviewedDietPlan.days) {
      planSource       = 'expert';
      activePlanReview = _newReview;
      weeklyPlan       = normalizePlan(_newReview.reviewedDietPlan);
      showLoading(false);
      renderPlanMeta();
      renderFocusCard(weeklyPlan, null);
      renderDay(currentDay);
      renderExpertChangeSummary(_newReview);
      renderVerifyNutriSection();
      if (!_newReview.athleteAccepted) {
        showExpertReviewBanner(_newReview);
        initExpertReviewBannerInteractions();
      }
      return;
    }

    /* ── Load plan from canonical key (set by AI onboarding) ── */
    var cached = safeJSON('zitlas_diet_plan', null);

    /* Guard: ignore any plan still containing stale sport-specific keywords */
    if (cached) {
      var _cachedStr = JSON.stringify(cached).toLowerCase();
      var _isStaleCache = _STALE_MARKERS.some(function (m) { return _cachedStr.indexOf(m) !== -1; });
      if (_isStaleCache) {
        console.log('[DIET CACHE] Stale sport-specific content in zitlas_diet_plan — discarding');
        localStorage.removeItem('zitlas_diet_plan');
        cached = null;
      }
    }

    /* ── Valid cached plan → normalize & render immediately ── */
    if (cached && cached.days && cached.days.length) {
      console.log('Active Diet', cached);
      console.log('Current Goal', _goalData);
      console.log('[DIET CACHE] Found saved diet — days:', cached.days.length);
      weeklyPlan = normalizePlan(cached);
      showLoading(false);
      renderPlanMeta();
      renderFocusCard(weeklyPlan, null);
      renderDay(currentDay);
      renderVerifyNutriSection();
      return;
    }

    /* ── No plan found → show assessment CTA, never call old nutrition API ── */
    console.log('[DIET CACHE] No diet plan found — showing assessment CTA');
    showLoading(false);
    renderAssessmentCta();
  }

  /* ══════════════════════════════════════════
     PLAN META STRIP (goal / generated / valid until / reset)
  ══════════════════════════════════════════ */
  function renderPlanMeta() {
    const strip = document.getElementById('planMetaStrip');
    if (!strip) return;

    var generatedAt = localStorage.getItem('zitlas_plan_generated_at')
                      || (expertReview && expertReview.reviewedAt ? expertReview.reviewedAt : null);
    const goalData    = safeJSON('zitlas_goal', null);

    if (!generatedAt) { strip.style.display = 'none'; return; }

    const genDate   = new Date(generatedAt);
    const validDate = new Date(generatedAt);
    validDate.setDate(validDate.getDate() + 90);

    const fmt = (d) => d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
    const goalLabel = goalData ? (goalData.goalName || goalData.type || 'Performance') : 'Performance';

    strip.innerHTML =
      '<div class="pmeta-row">' +
        '<span class="pmeta-item">' +
          '<span class="pmeta-label">Goal</span>' +
          '<span class="pmeta-val">' + esc(String(goalLabel)) + '</span>' +
        '</span>' +
        '<span class="pmeta-sep">·</span>' +
        '<span class="pmeta-item">' +
          '<span class="pmeta-label">Generated</span>' +
          '<span class="pmeta-val">' + fmt(genDate) + '</span>' +
        '</span>' +
        '<span class="pmeta-sep">·</span>' +
        '<span class="pmeta-item">' +
          '<span class="pmeta-label">Valid Until</span>' +
          '<span class="pmeta-val">' + fmt(validDate) + '</span>' +
        '</span>' +
        '<span class="pmeta-sep">·</span>' +
        '<span class="pmeta-item pmeta-item--status">' +
          '<span class="pmeta-dot"></span>' +
          '<span class="pmeta-val pmeta-val--green">Active</span>' +
        '</span>' +
      '</div>' +
      '<button class="pmeta-reset-btn" id="resetGoalBtn">Reset Goal</button>';

    strip.style.display = '';

    const resetBtn = document.getElementById('resetGoalBtn');
    if (resetBtn) {
      resetBtn.addEventListener('click', function () {
        if (!confirm('Reset your goal? This will clear your diet and workout plans and redirect you to the AI assessment.')) return;
        [
          /* Core plan data */
          'zitlas_diet_plan', 'zitlas_workout_plan', 'zitlas_calculations',
          'zitlas_swot', 'zitlas_sources', 'zitlas_assessment',
          'zitlas_plan_generated_at', 'zitlas_plan_id', 'zitlas_roadmap', 'zitlas_goal', 'zitlas_survey',
          'nutrition_weekly_plan', 'athlete_profile', 'nutrition_assessment',
          'nutrition_scores', 'nutrition_swot', 'nutrition_recommendations',
          'nutrition_bottleneck', 'diet_rejected_foods',
          /* Expert review — zitlas_* prefix (current keys) */
          'zitlas_expert_review', 'zitlas_plan_versions', 'zitlas_review_request',
          /* Expert review — legacy / alternate key names */
          'expert_review', 'expert_diet_override', 'reviewed_diet_plan',
          'modifiedBy', 'expertApproval', 'review_request',
          'expertDiet', 'expertOverride', 'dietOverride', 'reviewStatus',
          'expertReviewedPlan', 'approvedPlan', 'expertWorkoutOverride',
        ].forEach(function (k) { localStorage.removeItem(k); });
        console.log('[DIET] Goal reset — all expert review keys cleared');
        window.location.href = '../dashboard/ai-coach/ai-coach.html';
      });
    }
  }

  /* ══════════════════════════════════════════
     NORMALIZE PLAN
     Converts new assessment-API format to the
     display format expected by renderDay /
     renderFocusCard. Both old and new formats
     pass through unchanged where fields match.
  ══════════════════════════════════════════ */
  function normalizePlan(plan) {
    if (!plan || !plan.days) return plan;

    var calc = safeJSON('zitlas_calculations', {});

    /* Top-level fields */
    plan.nutrition_focus = plan.nutrition_focus
      || plan.summary
      || 'Personalised weight-loss plan designed to help you reach your goal weight.';

    plan.hydration_daily_target = plan.hydration_daily_target
      || (calc.water_target_liters ? calc.water_target_liters + 'L per day' : null);

    plan.weekly_notes = plan.weekly_notes
      || (plan.key_rules && plan.key_rules.length ? plan.key_rules.join(' · ') : null);

    /* Per-day fields */
    var MEAL_COLORS = ['#FF8A00','#22C55E','#F97316','#A855F7','#3B82F6','#EF4444'];
    var MEAL_EMOJIS = { breakfast:'🌅', 'mid-morning':'🥤', midmorning:'🥤', lunch:'🍽️', 'evening snack':'⚡', 'pre-training':'⚡', dinner:'🫕', recovery:'💪' };

    plan.days.forEach(function (day) {
      day.day_type      = day.day_type      || 'Weight Loss Day';
      day.nutrition_tip = day.nutrition_tip || (day.meals && day.meals[0] && day.meals[0].tip ? day.meals[0].tip : '');

      if (day.meals) {
        day.meals.forEach(function (meal, idx) {
          /* Normalize meal_name: assessment uses 'meal_name', old uses 'meal_name' too — both fine */
          meal.meal_name = meal.meal_name || meal.name || ('Meal ' + (idx + 1));

          /* Add color and emoji defaults if missing */
          if (!meal.color) {
            meal.color = MEAL_COLORS[idx % MEAL_COLORS.length];
          }
          if (!meal.emoji) {
            var key = (meal.meal_name || '').toLowerCase().replace(/[^a-z\-]/g, '');
            meal.emoji = MEAL_EMOJIS[key] || '🍽️';
          }

          /* Map 'tip' → 'purpose' for display */
          if (!meal.purpose && meal.tip) {
            meal.purpose = meal.tip;
          }

          /* Ensure foods is always an array of strings */
          if (!Array.isArray(meal.foods)) {
            meal.foods = meal.foods ? [String(meal.foods)] : [];
          }
        });
      }
    });

    return plan;
  }

  /* ══════════════════════════════════════════
     ASSESSMENT CTA — shown when no plan exists
  ══════════════════════════════════════════ */
  function renderAssessmentCta() {
    var mealList = document.getElementById('mealList');
    var titleEl  = document.getElementById('focusTitle');
    var pctEl    = document.getElementById('ringPct');
    var tipText  = document.getElementById('tipText');

    if (titleEl) titleEl.textContent = 'No Plan Yet';
    if (pctEl)   pctEl.textContent   = '—';
    if (tipText) tipText.textContent  = 'Complete the AI Nutrition assessment to generate your personalised weight-loss diet plan.';

    if (!mealList) return;

    mealList.innerHTML =
      '<div style="text-align:center;padding:40px 20px;">' +
        '<div style="font-size:48px;margin-bottom:16px;">🤖</div>' +
        '<h3 style="font-size:18px;font-weight:700;margin-bottom:10px;color:var(--text-primary,#FAFAFA)">Get Your Personalised Diet Plan</h3>' +
        '<p style="font-size:14px;color:var(--text-secondary,#9CA3AF);line-height:1.6;margin-bottom:24px;max-width:280px;margin-left:auto;margin-right:auto">' +
          'Complete a 4-minute assessment and Zino will build a 7-day weight-loss meal plan tailored to your goals, food preferences, and lifestyle.' +
        '</p>' +
        '<a href="../dashboard/ai-coach/ai-coach.html" ' +
           'style="display:inline-block;padding:16px 32px;background:linear-gradient(135deg,#E07000,#FF8A00);' +
           'color:#fff;font-weight:700;font-size:15px;border-radius:14px;text-decoration:none;' +
           'box-shadow:0 4px 20px rgba(255,138,0,0.35);">' +
          'Start AI Assessment →' +
        '</a>' +
      '</div>';
  }

  /* ══════════════════════════════════════════
     STATIC FALLBACK (no profile / API error)
  ══════════════════════════════════════════ */
  function renderStaticFallback() {
    const titleEl = document.getElementById('focusTitle');
    const pctEl   = document.getElementById('ringPct');
    if (titleEl) titleEl.textContent = 'Personalised Weight-Loss Plan';
    if (pctEl)   pctEl.textContent   = '—';

    animateRing(document.getElementById('focusRing'), 75, 314.159, 300);

    const mealList = document.getElementById('mealList');
    if (!mealList) return;

    const swapSvg = `<svg width="17" height="17" viewBox="0 0 24 24" fill="none"
      stroke="#FF8A00" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="17 1 21 5 17 9"/>
      <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
      <polyline points="7 23 3 19 7 15"/>
      <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
    </svg>`;

    const staticMeals = [
      { emoji:'🌅', color:'#FF8A00', bg:'rgba(255,138,0,0.15)', name:'Breakfast',      time:'7:30 AM', foods:'Oats, Banana, Almonds, Milk'               },
      { emoji:'🥤', color:'#22C55E', bg:'rgba(34,197,94,0.15)', name:'Mid-Morning',    time:'10:30 AM',foods:'Greek Yogurt, Honey, Walnuts'              },
      { emoji:'🍽️', color:'#F97316', bg:'rgba(249,115,22,0.15)',name:'Lunch',          time:'1:00 PM', foods:'Rice, Dal, Chicken, Salad'                 },
      { emoji:'⚡',  color:'#EF4444', bg:'rgba(239,68,68,0.15)', name:'Pre-Training',  time:'4:30 PM', foods:'Banana, Peanut Butter Toast'               },
      { emoji:'💪', color:'#A855F7', bg:'rgba(168,85,247,0.15)',name:'Recovery',       time:'7:00 PM', foods:'Paneer, Roti, Curd, Vegetables'            },
      { emoji:'🫕', color:'#3B82F6', bg:'rgba(59,130,246,0.15)',name:'Dinner',         time:'8:30 PM', foods:'Khichdi / Sabzi, Roti, Salad'              },
    ];

    mealList.innerHTML = staticMeals.map((m, i) =>
      `<article class="meal-card${i === staticMeals.length-1 ? ' meal-card--last' : ''}">
        <div class="meal-icon-circle" style="background:${m.bg};">
          <span class="meal-emoji">${m.emoji}</span>
        </div>
        <div class="meal-info">
          <span class="meal-name" style="color:${m.color};">${m.name}</span>
          <span class="meal-time">${m.time}</span>
          <span class="meal-foods">${m.foods}</span>
        </div>
        <button class="swap-btn" data-meal="${m.name}" aria-label="Swap ${m.name}">
          ${swapSvg}
          <span class="swap-label">Can't eat<br>this?</span>
        </button>
      </article>`
    ).join('');

    wireSwapButtons();

    requestAnimationFrame(() => {
      mealList.querySelectorAll('.meal-card').forEach((card, i) => {
        card.style.opacity   = '0';
        card.style.transform = 'translateY(10px)';
        card.style.transition = `opacity 0.35s ease ${0.05 * i}s, transform 0.38s cubic-bezier(0.34,1.2,0.64,1) ${0.05 * i}s`;
        requestAnimationFrame(() => {
          card.style.opacity   = '1';
          card.style.transform = 'translateY(0)';
        });
      });
    });

    const tipText = document.getElementById('tipText');
    if (tipText) tipText.textContent = 'Complete your Nutrition Assessment to get a fully personalised 7-day meal plan.';
  }

  /* ══════════════════════════════════════════
     GET COMPLETED PLAN REVIEW (new Verify Plan system)
  ══════════════════════════════════════════ */
  function getCompletedPlanReview() {
    var all = safeJSON('expert_plan_reviews', []);
    if (!Array.isArray(all) || !all.length) return null;

    /* Get athlete's user ID */
    var uid = null;
    try {
      var fbUser = safeJSON('zitlas_firebase_user', null);
      if (fbUser && fbUser.uid) uid = fbUser.uid;
    } catch (_) {}
    if (!uid) uid = localStorage.getItem('zitlas_athlete_id');

    return all.slice().reverse().find(function (r) {
      return r.reviewType === 'diet' &&
             r.status === 'review_completed' &&
             r.reviewedDietPlan &&
             (!uid || r.userId === uid);
    }) || null;
  }

  /* ══════════════════════════════════════════
     EXPERT REVIEW BANNER
  ══════════════════════════════════════════ */
  function showExpertReviewBanner(review) {
    var banner = document.getElementById('expertReviewBanner');
    if (!banner) return;
    var sub = document.getElementById('erBannerSub');
    if (sub) {
      sub.textContent = 'By ' + (review.expertName || 'Expert') +
        (review.reviewedAt
          ? ' · ' + new Date(review.reviewedAt).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })
          : '');
    }
    banner.style.display = 'flex';
  }

  function hideExpertReviewBanner() {
    var banner = document.getElementById('expertReviewBanner');
    if (banner) banner.style.display = 'none';
  }

  function initExpertReviewBannerInteractions() {
    var viewBtn   = document.getElementById('erViewBtn');
    var acceptBtn = document.getElementById('erAcceptBtn');
    if (viewBtn) {
      viewBtn.onclick = function () {
        if (activePlanReview) openDietCompSheet(activePlanReview);
      };
    }
    if (acceptBtn) {
      acceptBtn.onclick = function () {
        if (activePlanReview) acceptExpertPlan(activePlanReview);
      };
    }
  }

  function acceptExpertPlan(review) {
    try { localStorage.setItem('zitlas_diet_plan', JSON.stringify(review.reviewedDietPlan)); } catch (_) {}
    /* Mark accepted in expert_plan_reviews */
    var all = safeJSON('expert_plan_reviews', []);
    var idx = all.findIndex(function (r) { return r.id === review.id; });
    if (idx !== -1) {
      all[idx].athleteAccepted = true;
      try { localStorage.setItem('expert_plan_reviews', JSON.stringify(all)); } catch (_) {}
    }
    activePlanReview = Object.assign({}, review, { athleteAccepted: true });
    hideExpertReviewBanner();
    closeDietCompSheet();
    showToast("✅ Expert's plan saved to your diet!");
  }

  /* ══════════════════════════════════════════
     EXPERT CHANGE SUMMARY
  ══════════════════════════════════════════ */
  function renderExpertChangeSummary(review) {
    var container = document.getElementById('expertChangeSummary');
    if (!container) return;

    var history = review.mealChangeHistory || [];
    container.style.display = '';

    if (!history.length) {
      container.innerHTML =
        '<div class="ecs-approved">' +
          '<span class="ecs-approved-icon">✓</span>' +
          '<span class="ecs-approved-text">Expert reviewed your plan and approved it without changes.</span>' +
        '</div>';
      return;
    }

    var count = history.length;
    var listHtml = history.map(function(c) {
      var origFoodsLower = c.oldFoods.map(function(f) { return f.toLowerCase(); });
      var newFoodsLower  = c.newFoods.map(function(f)  { return f.toLowerCase(); });
      var added   = c.newFoods.filter(function(f) { return origFoodsLower.indexOf(f.toLowerCase()) === -1; });
      var removed = c.oldFoods.filter(function(f) { return newFoodsLower.indexOf(f.toLowerCase())  === -1; });
      var changed = origFoodsLower.join(',') !== newFoodsLower.join(',');

      var detailHtml = '';
      if (removed.length) {
        detailHtml += '<div class="ecs-diff ecs-diff--removed"><span class="ecs-diff-icon">➖</span><span>Removed: ' + esc(removed.join(', ')) + '</span></div>';
      }
      if (added.length) {
        detailHtml += '<div class="ecs-diff ecs-diff--added"><span class="ecs-diff-icon">➕</span><span>Added: ' + esc(added.join(', ')) + '</span></div>';
      }
      if (!removed.length && !added.length && (c.oldCalories !== c.newCalories || c.oldProtein !== c.newProtein)) {
        if (c.oldCalories !== c.newCalories) {
          detailHtml += '<div class="ecs-diff ecs-diff--macro"><span class="ecs-diff-icon">⚡</span><span>Calories: ' + c.oldCalories + ' → ' + c.newCalories + ' kcal</span></div>';
        }
        if (c.oldProtein !== c.newProtein) {
          detailHtml += '<div class="ecs-diff ecs-diff--macro"><span class="ecs-diff-icon">💪</span><span>Protein: ' + c.oldProtein + 'g → ' + c.newProtein + 'g</span></div>';
        }
      }
      if (!detailHtml) {
        detailHtml = '<div class="ecs-diff"><span class="ecs-diff-icon">✏️</span><span>Meal updated by expert</span></div>';
      }
      if (c.reason) {
        detailHtml += '<div class="ecs-reason"><span class="ecs-reason-label">Reason:</span> ' + esc(c.reason) + '</div>';
      }

      var date = c.modifiedAt ? new Date(c.modifiedAt).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }) : '';
      return '<div class="ecs-item">' +
        '<div class="ecs-item-header">' +
          '<span class="ecs-meal-name">' + esc(c.mealName) + '</span>' +
          '<span class="ecs-item-meta">' + esc(c.dayLabel) + (date ? ' · ' + date : '') + '</span>' +
        '</div>' +
        detailHtml +
      '</div>';
    }).join('');

    container.innerHTML =
      '<button class="ecs-toggle" id="ecsToggle">' +
        '<span class="ecs-toggle-text">🔄 Changes Made By Expert (' + count + ')</span>' +
        '<svg class="ecs-chevron" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>' +
      '</button>' +
      '<div class="ecs-list" id="ecsList" style="display:none">' + listHtml + '</div>';

    var toggle = container.querySelector('#ecsToggle');
    var list   = container.querySelector('#ecsList');
    if (toggle && list) {
      toggle.addEventListener('click', function() {
        var open = list.style.display !== 'none';
        list.style.display = open ? 'none' : '';
        toggle.classList.toggle('ecs-toggle--open', !open);
      });
    }
  }

  /* Look up the change record for a specific meal (by dayIndex + mealIndex or mealName) */
  function getChangeForMeal(dayIndex, mi, mealName) {
    if (!activePlanReview || !Array.isArray(activePlanReview.mealChangeHistory)) return null;
    return activePlanReview.mealChangeHistory.find(function(c) {
      return c.dayIndex === dayIndex && (c.mealIndex === mi || c.mealName === mealName);
    }) || null;
  }

  /* Build foods HTML for an expert-modified meal (diff view) */
  function buildChangeFoodsHtml(change) {
    var origFoodsLower = change.oldFoods.map(function(f) { return f.toLowerCase(); });
    var newFoodsLower  = change.newFoods.map(function(f)  { return f.toLowerCase(); });
    var removed = change.oldFoods.filter(function(f) { return newFoodsLower.indexOf(f.toLowerCase())  === -1; });
    var added   = change.newFoods.filter(function(f) { return origFoodsLower.indexOf(f.toLowerCase()) === -1; });
    var kept    = change.newFoods.filter(function(f) { return origFoodsLower.indexOf(f.toLowerCase()) !== -1; });

    var html = '<div class="meal-change-detail">';
    /* Attribution */
    html += '<div class="meal-change-by">✏️ Modified by ' + esc(change.modifiedBy || 'Expert') + '</div>';
    /* Kept foods (just show normally) */
    if (kept.length) {
      html += '<span class="meal-foods">' + esc(kept.join(', ')) + '</span>';
    }
    /* Removed */
    if (removed.length) {
      html += '<div class="meal-change-row meal-change-row--removed"><span class="meal-change-icon">➖</span><span class="meal-change-label">Removed:</span><span class="meal-change-val">' + esc(removed.join(', ')) + '</span></div>';
    }
    /* Added */
    if (added.length) {
      html += '<div class="meal-change-row meal-change-row--added"><span class="meal-change-icon">➕</span><span class="meal-change-label">Added:</span><span class="meal-change-val">' + esc(added.join(', ')) + '</span></div>';
    }
    /* Macro changes */
    if (change.oldCalories !== change.newCalories) {
      html += '<div class="meal-change-row meal-change-row--macro"><span class="meal-change-icon">⚡</span><span class="meal-change-label">Calories:</span><span class="meal-change-val">' + change.oldCalories + ' → <strong>' + change.newCalories + ' kcal</strong></span></div>';
    }
    if (change.oldProtein !== change.newProtein) {
      html += '<div class="meal-change-row meal-change-row--macro"><span class="meal-change-icon">💪</span><span class="meal-change-label">Protein:</span><span class="meal-change-val">' + change.oldProtein + 'g → <strong>' + change.newProtein + 'g</strong></span></div>';
    }
    /* Reason */
    if (change.reason) {
      html += '<div class="meal-change-reason"><span class="meal-change-reason-label">Reason:</span> ' + esc(change.reason) + '</div>';
    }
    html += '</div>';
    return html;
  }

  /* ══════════════════════════════════════════
     DIET COMPARISON SHEET
  ══════════════════════════════════════════ */
  var _dcActiveDay = 0;
  var _dcActiveTab = 'reviewed';

  function openDietCompSheet(review) {
    var sheet = document.getElementById('dcSheet');
    if (!sheet) return;

    _dcActiveDay = 0;
    _dcActiveTab = 'reviewed';

    /* Build day pills */
    var pillsEl  = document.getElementById('dcDayPills');
    if (pillsEl) {
      var dayNames    = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      var origDays    = (review.planData && review.planData.days) ? review.planData.days : [];
      var reviewedDays = review.reviewedDietPlan ? review.reviewedDietPlan.days : [];
      var numDays     = Math.max(origDays.length, reviewedDays.length);
      pillsEl.innerHTML = '';
      for (var di = 0; di < numDays; di++) {
        (function (dayIdx) {
          var pill = document.createElement('button');
          pill.className   = 'dc-day-pill' + (dayIdx === 0 ? ' dc-day-pill--active' : '');
          pill.textContent = dayNames[dayIdx] || ('Day ' + (dayIdx + 1));
          pill.onclick = function () {
            _dcActiveDay = dayIdx;
            pillsEl.querySelectorAll('.dc-day-pill').forEach(function (p) { p.classList.remove('dc-day-pill--active'); });
            pill.classList.add('dc-day-pill--active');
            renderDcPanes(review);
          };
          pillsEl.appendChild(pill);
        })(di);
      }
    }

    /* Wire tabs */
    var tabOrig     = document.getElementById('dcTabOriginal');
    var tabReviewed = document.getElementById('dcTabReviewed');
    var pOrig       = document.getElementById('dcPaneOriginal');
    var pRev        = document.getElementById('dcPaneReviewed');
    if (tabOrig) {
      tabOrig.className = 'dc-tab';
      tabOrig.onclick = function () {
        _dcActiveTab = 'original';
        tabOrig.className     = 'dc-tab dc-tab--active';
        tabReviewed.className = 'dc-tab';
        if (pOrig) pOrig.style.display = '';
        if (pRev)  pRev.style.display  = 'none';
      };
    }
    if (tabReviewed) {
      tabReviewed.className = 'dc-tab dc-tab--active';
      tabReviewed.onclick = function () {
        _dcActiveTab = 'reviewed';
        tabReviewed.className = 'dc-tab dc-tab--active';
        tabOrig.className     = 'dc-tab';
        if (pOrig) pOrig.style.display = 'none';
        if (pRev)  pRev.style.display  = '';
      };
    }

    /* Close + Accept btns */
    var closeBtn  = document.getElementById('dcCloseBtn');
    var acceptBtn = document.getElementById('dcAcceptBtn');
    if (closeBtn)  closeBtn.onclick  = closeDietCompSheet;
    if (acceptBtn) acceptBtn.onclick = function () { acceptExpertPlan(review); };

    /* Initial render — start on Reviewed tab */
    if (pOrig) pOrig.style.display = 'none';
    if (pRev)  pRev.style.display  = '';
    renderDcPanes(review);

    sheet.style.display = 'flex';
    requestAnimationFrame(function () { sheet.classList.add('dc-open'); });
  }

  function closeDietCompSheet() {
    var sheet = document.getElementById('dcSheet');
    if (!sheet) return;
    sheet.classList.remove('dc-open');
    setTimeout(function () { sheet.style.display = 'none'; }, 300);
  }

  function renderDcPanes(review) {
    var origDays     = (review.planData && review.planData.days) ? review.planData.days : [];
    var reviewedDays = review.reviewedDietPlan ? review.reviewedDietPlan.days : [];
    var pOrig        = document.getElementById('dcPaneOriginal');
    var pRev         = document.getElementById('dcPaneReviewed');

    if (pOrig) {
      var origDay = origDays[_dcActiveDay];
      pOrig.innerHTML = origDay
        ? buildDcDayHTML(origDay.meals || [], null, false)
        : '<p class="dc-no-data">No data for this day.</p>';
    }
    if (pRev) {
      var revDay   = reviewedDays[_dcActiveDay];
      var origDay2 = origDays[_dcActiveDay];
      pRev.innerHTML = revDay
        ? buildDcDayHTML(revDay.meals || [], origDay2 ? origDay2.meals : null, true)
        : '<p class="dc-no-data">No expert changes for this day.</p>';
    }
  }

  function buildDcDayHTML(meals, origMeals, showDiff) {
    var html = '';
    meals.forEach(function (meal, mi) {
      var origMeal = origMeals ? (origMeals[mi] || null) : null;
      var edited   = meal._edited;
      html += '<div class="dc-meal' + (edited ? ' dc-meal--edited' : '') + '">';
      html += '<div class="dc-meal-header">';
      html += '<span class="dc-meal-name">' + esc(meal.meal_name || 'Meal ' + (mi + 1)) + '</span>';
      if (meal.time) html += '<span class="dc-meal-time">' + esc(meal.time) + '</span>';
      if (edited && showDiff) html += '<span class="dc-edited-badge">✏ Edited by Expert</span>';
      html += '</div>';

      if (showDiff && origMeal) {
        var origFoods = normalizeFoods(origMeal.foods);
        var newFoods  = normalizeFoods(meal.foods);
        var diff      = diffFoods(origFoods, newFoods);
        html += '<ul class="dc-foods-list">';
        diff.removed.forEach(function (f) {
          html += '<li class="dc-food dc-food--removed"><span class="dc-diff-icon">−</span>' + esc(f) + '</li>';
        });
        diff.kept.forEach(function (f) {
          html += '<li class="dc-food dc-food--kept">' + esc(f) + '</li>';
        });
        diff.added.forEach(function (f) {
          html += '<li class="dc-food dc-food--added"><span class="dc-diff-icon">+</span>' + esc(f) + '</li>';
        });
        html += '</ul>';
        /* Macro changes */
        var origKcal = origMeal.calories  || 0;
        var newKcal  = meal.calories      || 0;
        var origProt = origMeal.protein_g || 0;
        var newProt  = meal.protein_g     || 0;
        if (origKcal !== newKcal || origProt !== newProt) {
          html += '<div class="dc-macro-diff">';
          if (origKcal !== newKcal) {
            html += '<span class="dc-macro-item">' +
              '<span class="dc-macro-label">Calories</span>' +
              '<span class="dc-macro-old">' + origKcal + ' kcal</span>' +
              '<span class="dc-macro-arrow">→</span>' +
              '<span class="dc-macro-new">' + newKcal + ' kcal</span>' +
            '</span>';
          }
          if (origProt !== newProt) {
            html += '<span class="dc-macro-item">' +
              '<span class="dc-macro-label">Protein</span>' +
              '<span class="dc-macro-old">' + origProt + 'g</span>' +
              '<span class="dc-macro-arrow">→</span>' +
              '<span class="dc-macro-new">' + newProt + 'g</span>' +
            '</span>';
          }
          html += '</div>';
        }
      } else {
        var foods = normalizeFoods(meal.foods);
        if (foods.length) {
          html += '<ul class="dc-foods-list">';
          foods.forEach(function (f) {
            html += '<li class="dc-food dc-food--kept">' + esc(f) + '</li>';
          });
          html += '</ul>';
        }
      }

      if (meal.notes) {
        html += '<div class="dc-meal-notes">' + esc(meal.notes) + '</div>';
      }
      if (meal.calories || meal.protein_g) {
        html += '<div class="dc-meal-meta">';
        if (meal.calories)  html += '<span>' + meal.calories  + ' kcal</span>';
        if (meal.protein_g) html += '<span>' + meal.protein_g + 'g protein</span>';
        html += '</div>';
      }
      html += '</div>';
    });
    return html || '<p class="dc-no-data">No meals for this day.</p>';
  }

  function normalizeFoods(foods) {
    if (!foods) return [];
    if (typeof foods === 'string') {
      return foods.split(/[,\n]/).map(function (f) { return f.trim(); }).filter(Boolean);
    }
    if (Array.isArray(foods)) {
      return foods.map(function (f) {
        if (typeof f === 'string') return f.trim();
        if (f && f.name) return f.name.trim();
        return String(f).trim();
      }).filter(Boolean);
    }
    return [];
  }

  function diffFoods(origFoods, newFoods) {
    var origLower = origFoods.map(function (f) { return f.toLowerCase(); });
    var newLower  = newFoods.map(function (f)  { return f.toLowerCase(); });
    return {
      removed: origFoods.filter(function (f) { return newLower.indexOf(f.toLowerCase())  === -1; }),
      kept:    newFoods.filter(function (f)  { return origLower.indexOf(f.toLowerCase()) !== -1; }),
      added:   newFoods.filter(function (f)  { return origLower.indexOf(f.toLowerCase()) === -1; }),
    };
  }

  /* ══════════════════════════════════════════
     BOOT
  ══════════════════════════════════════════ */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
