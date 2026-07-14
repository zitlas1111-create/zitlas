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
      color: 'var(--primary)',
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
      color: 'var(--success)',
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
      color: 'var(--ai-accent)',
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
    var fallback = (typeof IS_DEMO_MODE !== 'undefined' && IS_DEMO_MODE) ? MOCK_NUTRITIONISTS : [];
    renderNutritionistCards(Array.isArray(data) && data.length ? data : fallback);
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

    /* Load from localStorage; no mock fallback in production */
    var data = safeJSON('zitlas_nutritionists', null);
    var fallback = (typeof IS_DEMO_MODE !== 'undefined' && IS_DEMO_MODE) ? MOCK_NUTRITIONISTS : [];
    renderNutritionistCards(Array.isArray(data) && data.length ? data : fallback);
  }

  /* ══════════════════════════════════════════
     STATE
  ══════════════════════════════════════════ */
  let weeklyPlan        = null;   /* { days: [...], nutrition_focus, hydration_daily_target, weekly_notes } */
  let currentDay        = 0;      /* 0 = Monday */
  let dietRejectedFoods    = [];   /* kept for backward-compat; no longer used in rejected_foods */
  let _mealSwapHistories   = {};   /* per-meal accepted swap history { mealKey: [[foods], …] } */
  let expertReview         = null; /* zitlas_expert_review — set when APPROVED plan exists */
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
     DIET PLAN STORAGE — new schema
     {originalDietPlan, currentDietPlan, expertModifications}

     expertModifications shape:
     { "<dayIndex>": { "<mealKey>": { modified, modifiedBy, modifiedAt, oldMeal, newMeal } } }

     Legacy shape (backward-compat): {days: [...]}
  ══════════════════════════════════════════ */
  function _mealKey(mealName) {
    return (mealName || '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '_');
  }

  /* Expert review save flow has two producers (expert-dashboard.js's editor,
     which is array-based, and modify-diet.js, which used to save an object
     keyed by meal name). Normalize to array here so the athlete-side accept
     flow works for both current data and any review saved before the
     modify-diet.js fix. */
  function _mealsToArray(meals) {
    if (Array.isArray(meals)) return meals;
    if (meals && typeof meals === 'object') return Object.values(meals);
    return [];
  }

  function _findMealByKey(meals, mealKey) {
    var arr = _mealsToArray(meals);
    for (var i = 0; i < arr.length; i++) {
      var m = arr[i];
      if ((m._mealKey || _mealKey(m.meal_name || m.name)) === mealKey) return m;
    }
    return null;
  }

  function isNewDietSchema(obj) {
    return !!(obj && obj.originalDietPlan && obj.currentDietPlan);
  }

  function loadDietStorage() {
    var raw = safeJSON('zitlas_diet_plan', null);
    if (!raw) return null;
    if (isNewDietSchema(raw)) return raw;
    /* Auto-migrate legacy flat plan {days:[...]} into new schema and persist immediately
       so every subsequent read (from any page) sees the correct structure. */
    if (raw.days) {
      var _migrated = {
        originalDietPlan:    raw,
        currentDietPlan:     raw,
        expertModifications: {},
        isExpertPlan:        false,
        expertName:          null,
        reviewedAt:          null,
      };
      saveDietStorage(_migrated);
      return _migrated;
    }
    return null;
  }

  function saveDietStorage(storage) {
    try { localStorage.setItem('zitlas_diet_plan', JSON.stringify(storage)); } catch (_) {}
  }

  /* Apply expertModifications on top of currentDietPlan, returns deep-cloned effective plan */
  function buildEffectivePlan(storage) {
    if (!storage) return null;
    console.log(storage);
    console.log(storage.expertModifications);
    var base = storage.currentDietPlan || storage.originalDietPlan;
    if (!base || !base.days) return base;
    var mods      = storage.expertModifications || {};
    var effective = JSON.parse(JSON.stringify(base));

    effective.days.forEach(function (day, dayIdx) {
      var dayMods = mods[String(dayIdx)];
      console.log("[BUILD day]", dayIdx);
      if (!dayMods) return;
      console.log("[BUILD dayMods keys]", Object.keys(dayMods));
      (day.meals || []).forEach(function (meal) {
        var rawName = meal.meal_name || meal.name;
        var mealKey = _mealKey(rawName);
        var mod     = dayMods[mealKey];
        console.log("[BUILD meal]", meal.meal_name, meal._expertModified, meal._modifiedBy);
        console.log("[BUILD mealKey]", mealKey, "mod found:", !!mod);
        if (!mod || !mod.modified) return;
        if (mod.newMeal) {
          if (mod.newMeal.foods)     meal.foods     = mod.newMeal.foods;
          if (mod.newMeal.calories)  meal.calories  = mod.newMeal.calories;
          if (mod.newMeal.protein_g) meal.protein_g = mod.newMeal.protein_g;
        }
        meal._expertModified = true;
        meal._modifiedBy     = mod.modifiedBy || 'Expert';
        meal._modifiedAt     = mod.modifiedAt || null;
        console.log(meal);
        console.log(meal._expertModified);
        console.log(meal._modifiedBy);
      });
    });
    return effective;
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

  /* Fills an empty sibling <span id="elId"> with the reviewing/coaching
     expert's ZitlasBadge, once their verification status resolves.
     Shared by every "Reviewed by <name>" surface on this page so they
     don't each re-implement the same fetch-then-render dance. */
  function _paintExpertBadge(elId, expertId, size) {
    var el = document.getElementById(elId);
    if (!el || typeof ZitlasBadge === 'undefined' || !expertId) return;
    ZitlasBadge.fetchVerification(expertId).then(function (v) {
      el.innerHTML = ZitlasBadge.render(v, { size: size || 'sm' });
    });
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

    /* Dynamic goal tag — read from zitlas_goal, never hardcode */
    var _goalFc   = safeJSON('zitlas_goal', null);
    var _goalType = _goalFc ? (_goalFc.type || 'Weight Loss') : 'Weight Loss';
    var _TAG_LABELS = {
      'Weight Loss':     'Your Weight-Loss Plan',
      'Muscle Gain':     'Your Muscle Gain Plan',
      'General Fitness': 'Your General Fitness Plan',
      'Transformation':  'Your Transformation Plan',
    };
    if (tagEl)   tagEl.textContent   = _TAG_LABELS[_goalType] || ('Your ' + _goalType + ' Plan');
    if (titleEl) titleEl.textContent = plan.plan_name || (_goalType + ' Plan');
    if (descEl)  descEl.innerHTML    = esc(plan.nutrition_focus || '');
    if (pctEl)   pctEl.textContent   = nutritionScore ? nutritionScore + '%' : '—';

    /* Focus ring — animate to nutrition score */
    if (nutritionScore) {
      animateRing(document.getElementById('focusRing'), nutritionScore, 314.159, 300);
    }

    /* Hydration target */
    const hydrSection = document.getElementById('hydrationSection');
    const hydrVal     = document.getElementById('hydrationTarget');
    if (plan.hydration_daily_target && hydrSection && hydrVal) {
      hydrVal.textContent       = plan.hydration_daily_target;
      hydrSection.style.display = 'block';
    }

    /* Weekly notes */
    const notesSection = document.getElementById('weeklyNotesSection');
    const notesText    = document.getElementById('weeklyNotesText');
    if (plan.weekly_notes && notesSection && notesText) {
      notesText.textContent       = plan.weekly_notes;
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
        _paintExpertBadge('epiNameBadge', activePlanReview.expertId);
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

    let meals = dayData.meals || [];

    /* Health-status recovery override — replaces ONLY today's meals with
       the deterministic recovery template chosen on the dashboard
       (assets/js/health-status.js → zitlas_health_today). Never touches
       other days, never overrides an active coach-authored plan (the coach
       is alerted instead and adjusts it themselves). */
    var _hsToday = safeJSON('zitlas_health_today', null);
    var _hsApplies = _hsToday &&
      _hsToday.date === new Date().toISOString().slice(0, 10) &&
      _hsToday.diet && _hsToday.diet.meals && _hsToday.diet.meals.length &&
      (dayData.day || dayData.day_type) === _pcTodayName() &&
      planSource !== 'coach';
    if (_hsApplies) meals = _hsToday.diet.meals;

    var _hsBanner = document.getElementById('hsDietBanner');
    if (_hsApplies) {
      if (!_hsBanner) {
        _hsBanner = document.createElement('div');
        _hsBanner.id = 'hsDietBanner';
        _hsBanner.className = 'cw-readonly-note';
        _hsBanner.style.margin = '0 16px 12px';
        mealList.parentNode.insertBefore(_hsBanner, mealList);
      }
      _hsBanner.innerHTML = '🛟 <b>&nbsp;Recovery meals for today&nbsp;</b> — ' +
        esc(_hsToday.diet.focus || 'adjusted for how you’re feeling') +
        '. Your normal plan resumes tomorrow.';
      _hsBanner.style.display = '';
    } else if (_hsBanner) {
      _hsBanner.style.display = 'none';
    }

    const swapSvg = `<svg width="17" height="17" viewBox="0 0 24 24" fill="none"
      stroke="var(--primary)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="17 1 21 5 17 9"/>
      <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
      <polyline points="7 23 3 19 7 15"/>
      <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
    </svg>`;

    /* Recovery meals are a fixed, health-safe template for today only —
       swap stays visible (not silently removed) but locked, with a toast
       explaining why on tap. See wireSwapButtons(). */
    const lockSvg = `<svg width="17" height="17" viewBox="0 0 24 24" fill="none"
      stroke="var(--text-muted)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <rect x="5" y="11" width="14" height="10" rx="2"/>
      <path d="M8 11V7a4 4 0 0 1 8 0v4"/>
    </svg>`;

    const isExpertActive  = expertReview && expertReview.status === 'APPROVED';
    const isNewExpertPlan = planSource === 'expert';
    const reviewedBy      = isExpertActive ? (expertReview.reviewedBy || 'Expert') : '';

    mealList.innerHTML = meals.map((meal, i) => {
      const isLast     = i === meals.length - 1;
      const color      = esc(meal.color || 'var(--primary)');
      const bg         = hexToRgba(meal.color || 'var(--primary)', 0.13);
      const isModified = isExpertActive && meal._modified;

      /* Persistent expert modification stored in new schema (survives page reload) */
      console.log(meal);
      console.log(meal._expertModified);
      console.log(meal._modifiedBy);
      console.log("[RENDER]", meal.meal_name, meal.foods, meal._expertModified, meal._modifiedBy);
      const isPersistMod = !!meal._expertModified || !!meal._modifiedBy;

      /* Build foods display */
      let foodsHtml;
      if (isPersistMod) {
        /* New schema — expert modification persisted in zitlas_diet_plan */
        const foods = (meal.foods || []).join(', ');
        foodsHtml =
          `<span class="meal-foods">${esc(foods)}</span>` +
          `<span class="meal-expert-note">✏️ Modified by ${esc(meal._modifiedBy || 'Expert')}</span>` +
          `<span class="meal-expert-note meal-expert-note--reviewed">✓ Reviewed by expert</span>`;
      } else if (isModified) {
        /* Legacy old-system expert modification */
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

      /* Small attribution note for new-system expert-edited meals (pending acceptance) */
      const isExpertEdited = isNewExpertPlan && meal._edited && !isPersistMod;
      const expertName     = (activePlanReview && activePlanReview.expertName) || 'Expert';
      const mealLabel      = esc(translateMealName(meal.meal_name || 'meal'));
      const expertNote     = isExpertEdited
        ? `<span class="meal-expert-note">✏️ ${esc(expertName)} changed your ${mealLabel}.</span>`
        : '';

      return `
        <article class="meal-card${isLast ? ' meal-card--last' : ''}${isModified || isPersistMod ? ' meal-card--expert' : ''}">
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
          ${meal._recovery
            ? `<button class="swap-btn swap-btn--locked" data-meal="${esc(meal.meal_name || '')}" data-recovery-locked="1" aria-label="Swap locked — recovery meal">
                ${lockSvg}
                <span class="swap-label">Recovery<br>meal</span>
              </button>`
            : `<button class="swap-btn" data-meal="${esc(meal.meal_name || '')}" aria-label="Swap ${esc(meal.meal_name || '')}">
                ${swapSvg}
                <span class="swap-label">Can't eat<br>this?</span>
              </button>`}
        </article>` + buildCoachMealRow(meal, dayData.day || dayData.day_type)
                     + buildSnapMealRow(meal, dayData.day || dayData.day_type);
    }).join('');

    /* Daily Meal Compliance score — only appears once today has at least
       one coach-reviewed meal (never a fabricated 0/0). */
    var dailyScoreWrap = document.getElementById('pcDailyScore');
    var dailyScoreHtml = buildDailyScoreHtml(dayData);
    if (dailyScoreHtml) {
      if (!dailyScoreWrap) {
        dailyScoreWrap = document.createElement('div');
        dailyScoreWrap.id = 'pcDailyScore';
        mealList.parentNode.insertBefore(dailyScoreWrap, mealList);
      }
      dailyScoreWrap.innerHTML = dailyScoreHtml;
    } else if (dailyScoreWrap) {
      dailyScoreWrap.innerHTML = '';
    }

    /* Re-wire swap buttons for newly rendered cards */
    wireSwapButtons();
    wireCoachCheckinButtons();
    wireSnapMealButtons();

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
    if (!result) return `rgba(var(--primary-rgb),${alpha})`;
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
      // Calculate navbar clearance so the sheet stops above the navbar
      const navbar = document.getElementById('zitlas-navbar');
      if (navbar) {
        const navOffset = window.innerHeight - navbar.getBoundingClientRect().top;
        modal.style.setProperty('--modal-nav-offset', navOffset + 'px');
      }
      modal.classList.add('open');
      document.body.style.overflow = 'hidden';
    }
  }

  function closeSwapModal() {
    const modal = document.getElementById('swapModal');
    if (modal) {
      modal.classList.remove('open');
      modal.style.removeProperty('--modal-nav-offset');
    }
    document.body.style.overflow = '';
    showSwapPhase('swapPhaseA');
  }

  async function callSwapMealApi(reason) {
    const athleteProfile = safeJSON('athlete_profile', {});
    const lifestyleData  = safeJSON('lifestyle_data', {});

    /* Geo-Aware Food Intelligence: optional, only present once the user has
       granted location permission. Absent -> lifestyleData.location stays
       unset -> backend behaves exactly as before. */
    const _savedLoc = safeJSON('zitlas_location', null);
    if (_savedLoc && typeof _savedLoc === 'object') {
      lifestyleData.location = _savedLoc;
    }

    /* Supplement preference lives on the assessment (new flow) — merge it in
       so swap suggestions also respect "no supplements" (backend reads
       user_profile.uses_supplements; absent = old behavior). */
    const _assess = safeJSON('zitlas_assessment', {});
    if (_assess && _assess.uses_supplements && !athleteProfile.uses_supplements) {
      athleteProfile.uses_supplements = _assess.uses_supplements;
    }

    /* Diet type / living situation / budget also live on the assessment
       (as diet_preference/living_situation/budget) — without this merge the
       backend swap engine saw diet_type: N/A and could offer non-veg swaps
       to a vegetarian (the layer that actually picks the food never knew).
       lifestyle_data's own values win when both exist. */
    if (_assess) {
      if (_assess.diet_preference  && lifestyleData.diet_type        == null) lifestyleData.diet_type        = _assess.diet_preference;
      if (_assess.living_situation && lifestyleData.living_situation == null) lifestyleData.living_situation = _assess.living_situation;
      if (_assess.budget           && lifestyleData.daily_budget     == null) lifestyleData.daily_budget     = _assess.budget;
      if (Array.isArray(_assess.disliked_foods) && lifestyleData.disliked_foods == null) lifestyleData.disliked_foods = _assess.disliked_foods;
    }

    /* rejected_foods = ONLY the current meal's foods + this specific meal's prior swap
       suggestions (max 15). Never includes foods from other meals, other days, or the
       full weekly plan — that's what was causing the list to grow until nothing was valid. */
    const _swapMealKey      = _mealKey(_swapMealName);
    const _persistedHistory = _mealSwapHistories[_swapMealKey] || [];
    const _historyFoods     = [...new Set(_persistedHistory.flat())];
    const effectiveRejected = [...new Set([..._swapMealFoods, ..._historyFoods])].slice(0, 15);

    const fitnessGoal = athleteProfile.fitness_goal || 'general_fitness';

    console.log('Current meal:', _swapMealFoods);
    console.log('Meal swap history:', _persistedHistory);
    console.log('Rejected foods sent to API:', effectiveRejected);
    console.log('[SWAP] Fitness Goal:', fitnessGoal);

    /* Substrings that indicate the LLM leaked prompt instructions into a food string */
    const _MALFORMED = ['is forbidden', 'previously suggested', 'using'];

    const MAX_RETRIES = 2;
    let lastError = null;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      /* Network/response-shape problems (a slow or momentarily-flaky LLM
         round-trip, a dropped connection, a malformed one-off JSON body)
         are transient the same way a malformed-food or rejected-food
         retry is — they must consume a retry attempt, not escape the loop
         and fail the whole swap on the very first hiccup. Previously a
         bare `throw` here skipped the rest of this for-loop entirely, so
         a single flaky attempt (even though the backend's own provider
         chain — Groq → Gemini → OpenRouter → offline — usually succeeds
         moments later) showed the fallback toast despite the API being
         perfectly healthy. */
      try {
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
            fitness_goal:         fitnessGoal,
          }),
        });

        if (!resp.ok) throw new Error('API error ' + resp.status);
        const data = await resp.json();
        console.log('[SWAP API]', data);

        /* Accept both {structured:{swap:…}} and direct {swap:…} response shapes */
        const meal = data.structured || (data.swap ? data : null);
        if (!meal) throw new Error('No result');
        console.log('[SWAP PARSED]', meal);

        if (!meal.swap) throw new Error('No swap in result');

        /* Remove food strings where the LLM leaked forbidden-food instructions into the name */
        const rawFoods   = meal.swap.foods || [];
        const cleanFoods = rawFoods.filter(f => !_MALFORMED.some(p => f.toLowerCase().includes(p)));

        if (cleanFoods.length === 0 && rawFoods.length > 0) {
          /* Every food item was malformed — force a retry without counting as a valid suggestion */
          console.warn('[SWAP] All foods malformed (attempt ' + (attempt + 1) + '/' + (MAX_RETRIES + 1) + ') — retrying');
          _swapHistory.push(rawFoods);
          continue;
        }

        meal.swap.foods = cleanFoods;

        const swapFoods      = cleanFoods;
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
      } catch (_networkErr) {
        lastError = _networkErr;
        console.warn(`[SWAP] Attempt ${attempt + 1}/${MAX_RETRIES + 1} failed (${_networkErr.message}) — retrying...`);
      }
    }

    throw lastError || new Error('Could not generate a valid swap after retries');
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
        /* Clear persistent expert modification flag since athlete chose their own replacement */
        _expertModified: false,
        _modifiedBy:     undefined,
        _modifiedAt:     undefined,
      });
    }

    /* Persist swap in new storage schema */
    var _swapStorage = loadDietStorage();
    if (_swapStorage) {
      /* Update currentDietPlan (the base without expert mods) with the athlete's swap */
      var _basePlan = _swapStorage.currentDietPlan || _swapStorage.originalDietPlan;
      if (_basePlan && _basePlan.days && _basePlan.days[currentDay]) {
        var _baseMeals = _basePlan.days[currentDay].meals || [];
        var _baseIdx   = _baseMeals.findIndex(function (m) {
          return (m.meal_name || '').toLowerCase() === (_swapMealName || '').toLowerCase();
        });
        if (_baseIdx !== -1) {
          var _s = (swappedMeal && swappedMeal.swap) || swappedMeal;
          _baseMeals[_baseIdx] = Object.assign({}, _baseMeals[_baseIdx], {
            foods:   _s.foods   || _baseMeals[_baseIdx].foods,
            purpose: _s.reason  || _s.purpose || _baseMeals[_baseIdx].purpose,
          });
        }
      }
      /* Remove expert modification only for the swapped meal — leave all others intact */
      var _dk = String(currentDay);
      var _mk = _mealKey(_swapMealName);
      if (_swapStorage.expertModifications && _swapStorage.expertModifications[_dk]) {
        delete _swapStorage.expertModifications[_dk][_mk];
        if (Object.keys(_swapStorage.expertModifications[_dk]).length === 0) {
          delete _swapStorage.expertModifications[_dk];
        }
      }
      /* Update planSource badge if all expert mods for all days are now cleared */
      var _remainingMods = _swapStorage.expertModifications || {};
      if (Object.keys(_remainingMods).length === 0) planSource = 'ai';
      saveDietStorage(_swapStorage);
    } else {
      /* No storage existed — wrap the in-memory plan in the new schema so all future
         reads and writes use the correct structure. */
      saveDietStorage({
        originalDietPlan:    weeklyPlan,
        currentDietPlan:     weeklyPlan,
        expertModifications: {},
        isExpertPlan:        false,
      });
    }

    /* Invalidate old-system expert review (if active) — the plan is now athlete-modified */
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
        /* Recovery-day meals are a fixed, health-safe template for today
           only — never opens the swap modal, just explains why. */
        if (btn.dataset.recoveryLocked) {
          showToast('🛟 Recovery meals are fixed for today to keep you safe while you recover — your normal plan resumes tomorrow.');
          return;
        }
        const mealName = btn.dataset.meal || '';
        /* Find the foods for this meal from the current day plan */
        const day   = weeklyPlan && weeklyPlan.days && weeklyPlan.days[currentDay];
        const meals = day && day.meals ? day.meals : [];
        const meal  = meals.find((m) => (m.meal_name || '') === mealName);
        /* Coach-managed meal → coach's predefined options ONLY; the AI swap
           modal (global food dataset) must never open in coach mode. */
        if (meal && meal._coach) { openCoachOptionSheet(meal); return; }
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
          console.error('[SWAP ERROR]', _e);
          console.error(_e.stack);
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
          /* Persist the accepted swap's foods to per-meal history so future swaps for THIS
             meal avoid them. Capped at 5 entries per meal (≈ 15 foods max). */
          const _mk       = _mealKey(_swapMealName);
          const _newFoods = (_swapResult.swap && _swapResult.swap.foods) || [];
          if (_newFoods.length) {
            if (!_mealSwapHistories[_mk]) _mealSwapHistories[_mk] = [];
            _mealSwapHistories[_mk].push(_newFoods);
            if (_mealSwapHistories[_mk].length > 5) {
              _mealSwapHistories[_mk] = _mealSwapHistories[_mk].slice(-5);
            }
            try { localStorage.setItem('zitlas_meal_swap_history', JSON.stringify(_mealSwapHistories)); } catch (_) {}
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
          console.error('[SWAP ERROR]', _e);
          console.error(_e.stack);
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

    /* Ask Nutritionist → Ask My Coach. Personal-Coaching-only: with an
       active coach the question goes ONLY to the assigned coach (never a
       generic expert lookup); without one the option is disabled. */
    const nutriBtn = document.getElementById('swapNutriBtn');
    if (nutriBtn) {
      nutriBtn.addEventListener('click', () => {
        if (_pcRel && _pcRel.status === 'active') {
          closeSwapModal();
          _pcOpenAskCoachSheet(_swapMealName, _swapMealFoods);
        } else {
          showToast('Available only with Personal Coaching — hire a coach from the Experts page.');
        }
      });
    }
    _pcUpdateAskCoachUi();
  }

  /* Rewrites the swap-modal coach option to reflect the coaching state */
  function _pcUpdateAskCoachUi() {
    var btn = document.getElementById('swapNutriBtn');
    if (!btn) return;
    var title = btn.querySelector('.swap-opt-title');
    var desc  = btn.querySelector('.swap-opt-desc');
    if (_pcRel && _pcRel.status === 'active') {
      if (title) title.textContent = 'Ask My Coach';
      if (desc)  desc.textContent  = 'Send this meal question to ' + (_pcRel.coachName || 'your coach');
      btn.style.opacity = '';
    } else {
      if (title) title.textContent = 'Ask My Coach';
      if (desc)  desc.textContent  = 'Available only with Personal Coaching';
      btn.style.opacity = '0.5';
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

    var nutriSource = (typeof IS_DEMO_MODE !== 'undefined' && IS_DEMO_MODE) ? MOCK_NUTRITIONISTS : [];
    var realData = safeJSON('zitlas_nutritionists', null);
    if (Array.isArray(realData) && realData.length) nutriSource = realData;

    if (!nutriSource.length) {
      list.innerHTML = '<div style="text-align:center;padding:32px 16px;color:var(--text-secondary);font-size:14px;">No nutritionists available yet.<br>Check back soon.</div>';
      return;
    }

    list.innerHTML = nutriSource.map(function (n) {
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
        var _nutriPool = safeJSON('zitlas_nutritionists', null) || ((typeof IS_DEMO_MODE !== 'undefined' && IS_DEMO_MODE) ? MOCK_NUTRITIONISTS : []);
        var nutri    = _nutriPool.find(function (n) { return n.id === nutriId; });
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

  function _getSponsoredExperts() {
    try {
      var data = JSON.parse(localStorage.getItem('zitlas_nutritionists') || 'null');
      if (Array.isArray(data) && data.length) return data;
    } catch (_) {}
    return [];
  }

  function _vnStars(rating) {
    var full = Math.floor(rating);
    var html = '';
    for (var i = 0; i < 5; i++) {
      var c = i < full ? 'var(--primary)' : 'var(--border)';
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

    var _vnExperts = _getSponsoredExperts();
    if (_vnExperts.length === 0) {
      rail.innerHTML = '<div style="padding:1.25rem;text-align:center;color:var(--text-muted);font-size:.85rem;">No experts available for plan verification yet. <a href="../coaches/coaches.html" style="color:var(--primary);">Browse Experts</a></div>';
      section.style.display = '';
      return;
    }

    rail.innerHTML = _vnExperts.map(function(n) {
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
    }).join('');  /* end _vnExperts.map */

    rail.querySelectorAll('.vn-btn--primary[data-vn-expert]').forEach(function(btn) {
      btn.addEventListener('click', function() {
        if (btn.disabled) return;
        submitVerifyRequest(btn.dataset.vnExpert);
      });
    });

    section.style.display = '';
  }

  function submitVerifyRequest(expertId) {
    var expert     = _getSponsoredExperts().find(function(n) { return n.id === expertId; });
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
      var expert = _getSponsoredExperts().find(function(n) { return n.id === req.expertId; });
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
      _paintExpertBadge('vnVerifiedBadge', review.expertId);
    }
    banner.style.display = 'flex';
  }

  /* ══════════════════════════════════════════
     MAIN INIT
  ══════════════════════════════════════════ */
  /* ══════════════════════════════════════════
     PERSONAL COACHING MODE
     With an active (or ended-but-kept) Personal Coaching relationship that
     includes diet permission, the coach-authored plan in
     coaching_plans/{uid} REPLACES the AI plan on this page. Swapping a meal
     offers ONLY the coach's predefined options — the AI swap flow and the
     global food dataset are never queried while a coach plan is shown.
     Everything below is inert when Firebase isn't loaded or no relationship
     exists, so the AI diet path is untouched.
  ══════════════════════════════════════════ */
  var _pcRel     = null;   /* personal_coaching/{uid} */
  var _pcPlanDoc = null;   /* coaching_plans/{uid} */
  var _pcActive  = false;  /* coach plan currently rendered */

  function _pcUid() {
    try {
      var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || 'null');
      return fb && fb.uid;
    } catch (_) { return null; }
  }
  /* Render eligibility: active OR ended (athlete keeps the last coach plan).
     Interactive requests (Ask Expert) additionally require active. */
  function _pcShowsCoachPlan() {
    return !!(_pcRel && (_pcRel.status === 'active' || _pcRel.status === 'ended') &&
      (_pcRel.planType === 'diet' || _pcRel.planType === 'complete'));
  }

  function initCoachDietMode() {
    if (typeof ZitlasDB === 'undefined') return;
    var uid = _pcUid();
    if (!uid) return;
    ZitlasDB.collection('personal_coaching').doc(uid).onSnapshot(function (snap) {
      _pcRel = snap.exists ? snap.data() : null;
      console.log('[DIET COACH] relationship:', _pcRel ? _pcRel.status + '/' + _pcRel.planType : 'none');
      if (_pcShowsCoachPlan() && !initCoachDietMode._planAttached) {
        initCoachDietMode._planAttached = true;
        ZitlasDB.collection('coaching_plans').doc(uid).onSnapshot(function (ps) {
          _pcPlanDoc = ps.exists ? ps.data() : null;
          applyCoachDiet();
        }, function (e) { console.warn('[DIET COACH] plan listener error', e); });
      }
      if (_pcRel && _pcRel.status === 'active') {
        /* Meal check-ins + Ask My Coach are coaching features, live even
           before the coach publishes a plan (AI meals still render). */
        _pcAttachCheckinsListener();
        renderDay(currentDay); /* inject Snap Meal rows into the AI view */
        _pcUpdateAskCoachUi();
      }
      applyCoachDiet();
    }, function (e) { console.warn('[DIET COACH] rel listener error', e); });
  }

  var _PC_EMOJI = { breakfast: '🍳', lunch: '🍛', snacks: '🍎', snack: '🍎', dinner: '🥗' };

  function applyCoachDiet() {
    var coachDiet = _pcPlanDoc && _pcPlanDoc.diet;
    if (!_pcShowsCoachPlan() || !coachDiet || !coachDiet.days || !coachDiet.days.length) {
      /* Not eligible / no coach plan — leave the AI flow exactly as-is.
         If we had been showing a coach plan and it disappeared, reload to
         restore the pristine AI pipeline rather than half-reverting state. */
      if (_pcActive) { _pcActive = false; window.location.reload(); }
      return;
    }
    var selections = _pcPlanDoc.dietSelections || {};
    weeklyPlan = {
      plan_name: 'Coach Plan',
      days: coachDiet.days.map(function (d) {
        return {
          day: d.day,
          theme: '👨‍🏫 Coached by ' + (_pcPlanDoc.coachName || 'your expert'),
          day_type: d.day,
          meals: (d.meals || []).map(function (m) {
            var opts = (m.options || []).filter(function (o) { return o && o.name; });
            var key = d.day + ':' + m.id;
            var selIdx = Math.min(selections[key] || 0, Math.max(0, opts.length - 1));
            var opt = opts[selIdx] || {};
            return {
              meal_name: m.name || 'Meal',
              time: m.time || '',
              foods: [opt.name || '— (coach hasn’t filled this meal yet)'],
              calories: opt.calories || null,
              purpose: [opt.calories ? opt.calories + ' kcal' : '', opt.protein ? opt.protein + 'g protein' : '', opt.notes || '']
                .filter(Boolean).join(' · '),
              emoji: _PC_EMOJI[(m.name || '').toLowerCase()] || '🍽️',
              color: '#6BA539',
              _coach: { day: d.day, mealId: m.id, mealName: m.name || 'Meal', options: opts, selIdx: selIdx },
            };
          }),
        };
      }),
    };
    planSource = 'coach';
    _pcActive = true;
    _pcAttachCheckinsListener();
    showLoading(false);
    _pcRenderBanner();
    try { renderFocusCard(weeklyPlan, null); } catch (_) {}
    if (currentDay >= weeklyPlan.days.length) currentDay = 0;
    renderDay(currentDay);
    console.log('[DIET COACH] coach plan rendered —', weeklyPlan.days.length, 'days');
  }

  function _pcRenderBanner() {
    var mealList = document.getElementById('mealList');
    if (!mealList) return;
    var banner = document.getElementById('pcCoachBanner');
    if (!banner) {
      banner = document.createElement('div');
      banner.id = 'pcCoachBanner';
      banner.className = 'cw-readonly-note';
      banner.style.margin = '0 16px 12px';
      mealList.parentNode.insertBefore(banner, mealList);
    }
    var coachName = esc(_pcPlanDoc.coachName || 'your coach');
    function paint(verification) {
      var badge = (typeof ZitlasBadge !== 'undefined') ? ZitlasBadge.render(verification, { size: 'sm' }) : '';
      banner.innerHTML = _pcRel.status === 'active'
        ? (badge
            ? '👨‍🏫 Your Verified Coach: <b>&nbsp;' + coachName + '</b>' + badge + '&nbsp;— swaps use your coach’s options only.'
            : '👨‍🏫 Diet managed by <b>&nbsp;' + coachName + '</b>&nbsp;— swaps use your coach’s options only.')
        : '👨‍🏫 Coaching ended — you’re keeping your coach’s last diet plan.';
    }
    paint(null);
    if (typeof ZitlasBadge !== 'undefined' && _pcRel.coachId) {
      ZitlasBadge.fetchVerification(_pcRel.coachId).then(paint);
    }
  }

  /* Coach-option picker (replaces the AI swap flow in coach mode).
     Styled by assets/css/coaching-workspace.css (cw-*). */
  function _pcEnsureSheet() {
    var bd = document.getElementById('pcSheetBackdrop');
    if (bd) return bd;
    bd = document.createElement('div');
    bd.id = 'pcSheetBackdrop';
    bd.className = 'cw-sheet-backdrop';
    bd.innerHTML = '<div class="cw-sheet" id="pcSheet"></div>';
    document.body.appendChild(bd);
    bd.addEventListener('click', function (e) { if (e.target === bd) _pcCloseSheet(); });
    return bd;
  }
  function _pcOpenSheet(html) {
    var bd = _pcEnsureSheet();
    document.getElementById('pcSheet').innerHTML = html;
    bd.style.display = 'flex';
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { bd.classList.add('open'); });
    });
  }
  function _pcCloseSheet() {
    var bd = document.getElementById('pcSheetBackdrop');
    if (!bd) return;
    bd.classList.remove('open');
    setTimeout(function () { bd.style.display = 'none'; }, 200);
  }

  function openCoachOptionSheet(meal) {
    var c = meal._coach;
    var canAsk = _pcRel && _pcRel.status === 'active';
    var optsHtml = c.options.length ? c.options.map(function (o, i) {
      var meta = [];
      if (o.calories) meta.push(o.calories + ' kcal');
      if (o.protein) meta.push(o.protein + 'g protein');
      return '<button class="cw-opt-choice' + (i === c.selIdx ? ' selected' : '') + '" data-pc-pick="' + i + '">' +
        '<span class="cw-opt-choice-label">Option ' + (i + 1) + (i === c.selIdx ? ' · current' : '') + '</span>' +
        '<span class="cw-opt-choice-name">' + esc(o.name) + '</span>' +
        (meta.length || o.notes
          ? '<span class="cw-opt-choice-meta">' + esc(meta.join(' · ')) + (o.notes ? (meta.length ? ' · ' : '') + esc(o.notes) : '') + '</span>'
          : '') +
        '</button>';
    }).join('') : '<p class="cw-sheet-sub">Your coach hasn’t added alternatives for this meal yet.</p>';

    _pcOpenSheet(
      '<p class="cw-sheet-title">Swap ' + esc(c.mealName) + '</p>' +
      '<p class="cw-sheet-sub">' + esc(c.day) + ' — choose one of your coach’s options.</p>' +
      optsHtml +
      (canAsk ? '<button class="cw-ghost-btn" style="width:100%;margin-top:6px" id="pcAskExpert">💬 Ask Expert for new options</button>' : '')
    );

    var sheet = document.getElementById('pcSheet');
    sheet.querySelectorAll('[data-pc-pick]').forEach(function (b) {
      b.addEventListener('click', function () {
        var idx = parseInt(b.dataset.pcPick, 10) || 0;
        /* set+merge (not update) — the key contains ':' which is illegal in
           a string field path but fine as a map key under merge. */
        var sel = {};
        sel[c.day + ':' + c.mealId] = idx;
        ZitlasDB.collection('coaching_plans').doc(_pcUid()).set({ dietSelections: sel }, { merge: true })
          .then(function () {
            _pcCloseSheet();
            showToast('✅ ' + c.mealName + ' swapped to Option ' + (idx + 1));
          })
          .catch(function (e) { console.warn('[DIET COACH] swap failed', e); showToast('Swap failed — try again.'); });
      });
    });
    var askBtn = document.getElementById('pcAskExpert');
    if (askBtn) askBtn.addEventListener('click', function () { _pcAskExpert(c); });
  }

  function _pcAthleteName() {
    try {
      var fb = JSON.parse(localStorage.getItem('zitlas_firebase_user') || 'null');
      return (fb && fb.displayName) || (fb && fb.name) || 'Athlete';
    } catch (_) { return 'Athlete'; }
  }

  function _pcAskExpert(c) {
    var uid = _pcUid();
    var id = 'CMR_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
    var athleteName = _pcAthleteName();
    var req = {
      requestId: id, athleteId: uid, athleteName: athleteName,
      coachId: _pcRel.coachId,
      day: c.day, mealId: c.mealId, mealName: c.mealName,
      note: '', status: 'pending', createdAt: new Date().toISOString(),
    };
    console.log('[DIET COACH] ask-expert', req);
    ZitlasDB.collection('coaching_meal_requests').doc(id).set(req)
      .then(function () {
        var nid = 'CN_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
        return ZitlasDB.collection('coaching_notifications').doc(nid).set({
          id: nid, toId: _pcRel.coachId, fromId: uid, fromName: athleteName,
          text: '🍽 ' + athleteName + ' requested alternatives for ' + c.day + ' ' + c.mealName + '.',
          type: 'meal_request', createdAt: new Date().toISOString(), read: false,
        });
      })
      .then(function () {
        if (typeof ZitlasNotify !== 'undefined') {
          ZitlasNotify.send(_pcRel.coachId, {
            title: '🍽 ' + athleteName + ' requested alternatives',
            message: c.day + ' ' + c.mealName, category: 'expert',
            type: 'meal_request', action: 'expert_dashboard',
          });
        }
      })
      .then(function () {
        _pcCloseSheet();
        showToast('📨 Request sent — your coach will reply with new options.');
      })
      .catch(function (e) { console.warn('[DIET COACH] ask failed', e); showToast('Could not send — try again.'); });
  }

  /* ══════════════════════════════════════════
     ASK MY COACH — meal question straight to the assigned Personal Coach.
     Writes a coaching_meal_requests doc (drives the coach's Provide-
     Alternatives banner in the workspace Diet editor) AND mirrors the
     question into the coaching chat so the coach can simply Reply there.
  ══════════════════════════════════════════ */
  function _pcSendChatToCoach(text) {
    var uid = _pcUid();
    if (!uid || !_pcRel || typeof ZitlasDB === 'undefined') return Promise.resolve();
    var chatId = 'chat_' + uid + '_' + _pcRel.coachId;
    var msg = {
      id: 'msg_' + Date.now() + '_' + Math.random().toString(36).slice(2, 5),
      conversationId: chatId,
      senderId: uid, senderType: 'athlete',
      text: text, type: 'text', imageUrl: null,
      timestamp: new Date().toISOString(),
    };
    var roomDoc = {
      participants: [uid, _pcRel.coachId],
      athleteId: uid, athleteName: _pcAthleteName(),
      expertId: _pcRel.coachId, expertName: _pcRel.coachName || 'Coach',
      lastMessage: text, lastMessageAt: msg.timestamp,
    };
    return ZitlasDB.collection('chat_rooms').doc(chatId).set(roomDoc, { merge: true })
      .then(function () {
        return ZitlasDB.collection('chat_rooms').doc(chatId).collection('messages').doc(msg.id).set(msg);
      });
  }

  function _pcOpenAskCoachSheet(mealName, mealFoods) {
    var day = _pcTodayName();
    var examples = 'e.g. “I don’t like today’s breakfast”, “I feel hungry after lunch”, ' +
      '“Can I replace eggs?”, “I have acidity today”, “I’m travelling”, “Hostel didn’t serve this meal”';
    _pcOpenSheet(
      '<p class="cw-sheet-title">💬 Ask ' + esc(_pcRel.coachName || 'My Coach') + '</p>' +
      '<p class="cw-sheet-sub">' + esc(day) + (mealName ? ' · ' + esc(mealName) : '') +
        (mealFoods && mealFoods.length ? ' — ' + esc(mealFoods.join(', ')) : '') + '</p>' +
      '<textarea class="cw-textarea" id="pcAskCoachText" rows="3" placeholder="Describe your problem…"></textarea>' +
      '<p class="cw-sheet-sub" style="margin-top:8px">' + esc(examples) + '</p>' +
      '<div class="cw-save-bar" style="position:static;background:none;padding-top:10px">' +
        '<button class="cw-ghost-btn" id="pcAskCoachCancel">Cancel</button>' +
        '<button class="cw-save-btn" id="pcAskCoachSend">Send to Coach</button>' +
      '</div>'
    );
    document.getElementById('pcAskCoachCancel').addEventListener('click', _pcCloseSheet);
    document.getElementById('pcAskCoachSend').addEventListener('click', function () {
      var q = (document.getElementById('pcAskCoachText').value || '').trim();
      if (!q) { showToast('Describe your problem first.'); return; }
      var btn = document.getElementById('pcAskCoachSend');
      btn.disabled = true; btn.textContent = 'Sending…';

      var uid = _pcUid();
      var id = 'CMR_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
      var req = {
        requestId: id, athleteId: uid, athleteName: _pcAthleteName(),
        coachId: _pcRel.coachId,
        day: day, mealId: null,
        mealType: (mealName || 'meal').toLowerCase(), mealName: mealName || 'Meal',
        mealFoods: mealFoods || [],
        question: q, note: q,
        status: 'pending', createdAt: new Date().toISOString(),
      };
      console.log('[ASK COACH] request', req);
      ZitlasDB.collection('coaching_meal_requests').doc(id).set(req)
        .then(function () {
          return _pcSendChatToCoach(
            '🍽 NEW QUESTION — ' + day + ' ' + (mealName || 'Meal') +
            (mealFoods && mealFoods.length ? ' (' + mealFoods.join(', ') + ')' : '') +
            ':\n' + q);
        })
        .then(function () {
          var nid = 'CN_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
          return ZitlasDB.collection('coaching_notifications').doc(nid).set({
            id: nid, toId: _pcRel.coachId, fromId: uid, fromName: _pcAthleteName(),
            text: '🍽 ' + _pcAthleteName() + ' has a question about ' + day + ' ' + (mealName || 'a meal') + '.',
            type: 'meal_question', createdAt: new Date().toISOString(), read: false,
          });
        })
        .then(function () {
          if (typeof ZitlasNotify !== 'undefined') {
            ZitlasNotify.send(_pcRel.coachId, {
              title: '💬 ' + _pcAthleteName() + ' has a question',
              message: day + ' ' + (mealName || 'a meal') + ': ' + q,
              category: 'expert', type: 'meal_question', action: 'expert_dashboard',
            });
          }
        })
        .then(function () {
          _pcCloseSheet();
          showToast('📨 Sent to ' + (_pcRel.coachName || 'your coach') + ' — they’ll reply in chat or update your options.');
        })
        .catch(function (e) {
          console.error('[ASK COACH] failed', e);
          showToast('Could not send — try again.');
          btn.disabled = false; btn.textContent = 'Send to Coach';
        });
    });
  }

  /* ══════════════════════════════════════════
     DAILY MEAL COMPLIANCE — 📸 Send Meal to Coach
     Only ever shown/wired when Personal Coaching is ACTIVE (_pcRel.status
     === 'active'). Photo goes through the same validated upload pipeline
     chat images use (assets/js/chat-attachments.js → /api/chat/upload) —
     no separate Firebase Storage integration exists in this project, so
     this reuses the one already proven in production instead of adding an
     unconfigured/untested new upload path.
     Firestore: meal_checkins/{id} — schema also carries null placeholder
     fields (estimatedCalories/Protein/Carbs/Fat, foodRecognition,
     confidenceScore) so future AI recognition can populate them later
     without a schema change.
  ══════════════════════════════════════════ */
  var _pcCheckins = [];
  var PC_REACTION_LABEL = {
    perfect: '🟢 Perfect', great: '🟢 Great', good: '🟡 Good',
    needs_improvement: '🟠 Needs Improvement', not_recommended: '🔴 Not Recommended',
  };

  function _pcTodayName() {
    return ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][new Date().getDay()];
  }
  function _pcCheckinFor(day, mealType) {
    var matches = _pcCheckins.filter(function (c) { return c.day === day && c.mealType === mealType; });
    matches.sort(function (a, b) { return (b.timestamp || '') < (a.timestamp || '') ? -1 : 1; });
    return matches[0] || null;
  }

  function _pcAttachCheckinsListener() {
    if (_pcAttachCheckinsListener._attached || typeof ZitlasDB === 'undefined') return;
    _pcAttachCheckinsListener._attached = true;
    var uid = _pcUid();
    ZitlasDB.collection('meal_checkins').where('athleteId', '==', uid)
      .onSnapshot(function (snap) {
        _pcCheckins = snap.docs.map(function (d) { return d.data(); })
          .filter(function (c) { return c.coachId === _pcRel.coachId; });
        console.log('[MEAL CHECKIN] snapshot —', _pcCheckins.length, 'total');
        renderDay(currentDay); /* re-render in BOTH AI and coach-plan mode */
      }, function (e) { console.warn('[MEAL CHECKIN] listener error', e); });
  }

  /* ══════════════════════════════════════════
     STANDALONE AI SNAP MEAL — for athletes WITHOUT an active Personal
     Coach (mirror image of buildCoachMealRow above: exactly one of the two
     ever renders per meal, per the AI-only vs Personal-Coaching mode
     split). Same AI nutrition-estimation call (backend/routes/meal_ai.py)
     as the coach-checkin flow, but a purely personal log — no coach, no
     notification, no meal_checkins doc. Firestore:
     meal_snap_logs/{uid}/{dateKey}/{id} — {imageUrl, calories, protein,
     carbs, fat, foodRecognition, confidenceScore, loggedAt}.
  ══════════════════════════════════════════ */
  var _snapLogs = {}; /* 'day:mealType' -> latest log doc, today only */

  function _snapDateKey() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function _snapLogFor(day, mealType) { return _snapLogs[day + ':' + mealType] || null; }

  function _snapAttachListener() {
    if (_snapAttachListener._attached || typeof ZitlasDB === 'undefined') return;
    _snapAttachListener._attached = true;
    var uid = _pcUid();
    if (!uid) return;
    ZitlasDB.collection('meal_snap_logs').doc(uid).collection(_snapDateKey())
      .onSnapshot(function (snap) {
        var byKey = {};
        snap.docs.forEach(function (d) {
          var log = d.data();
          var key = log.day + ':' + log.mealType;
          if (!byKey[key] || (log.loggedAt || '') > (byKey[key].loggedAt || '')) byKey[key] = log;
        });
        _snapLogs = byKey;
        console.log('[SNAP MEAL] snapshot —', Object.keys(_snapLogs).length, 'today');
        renderDay(currentDay);
      }, function (e) { console.warn('[SNAP MEAL] listener error', e); });
  }

  function buildSnapMealRow(meal, dayName) {
    /* Mutually exclusive with buildCoachMealRow — only render the
       standalone AI-only flow when there's no active coach. */
    if (typeof ZitlasCoachingGate !== 'undefined' && _pcRel && ZitlasCoachingGate.evaluate(_pcRel).active) return '';
    if (dayName !== _pcTodayName()) return '';
    var mealType = (meal.meal_name || 'meal').toLowerCase();
    var log = _snapLogFor(dayName, mealType);

    if (!log) {
      return '<div class="meal-coach-row">' +
        '<button class="cw-meal-btn cw-meal-btn--swap snap-meal-btn" data-snap-meal="' + esc(meal.meal_name || '') + '">📷 Snap Meal</button>' +
        '</div>';
    }
    return '<div class="meal-coach-row meal-coach-row--reviewed">' +
      '<img class="meal-checkin-thumb" src="' + esc(log.imageUrl) + '" alt="Snapped meal">' +
      '<div class="meal-checkin-feedback">' +
        '<span class="meal-checkin-status">' +
          (log.calories != null
            ? '🍽 ~' + log.calories + ' kcal · ' + log.protein + 'g protein · ' + log.carbs + 'g carbs · ' + log.fat + 'g fat'
            : 'Estimating nutrition…') +
        '</span>' +
      '</div>' +
    '</div>';
  }

  function wireSnapMealButtons() {
    document.querySelectorAll('[data-snap-meal]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var mealName = btn.dataset.snapMeal;
        var day = weeklyPlan && weeklyPlan.days && weeklyPlan.days[currentDay];
        var meals = day && day.meals ? day.meals : [];
        var meal = meals.find(function (m) { return (m.meal_name || '') === mealName; });
        if (meal) _snapOpenCamera(meal);
      });
    });
  }

  function _snapOpenCamera(meal) {
    var input = document.getElementById('snapCameraInput');
    if (!input) {
      input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.capture = 'environment';
      input.id = 'snapCameraInput';
      input.style.display = 'none';
      document.body.appendChild(input);
    }
    input.onchange = function () {
      var file = input.files && input.files[0];
      input.value = '';
      if (file) _snapSend(file, meal);
    };
    input.click();
  }

  function _snapSend(file, meal) {
    if (typeof ZitlasChatAttach === 'undefined') { showToast('Upload unavailable — please retry.'); return; }
    var uid = _pcUid();
    if (!uid) { showToast('Please sign in first.'); return; }
    var day = _pcTodayName();
    var mealType = (meal.meal_name || 'meal').toLowerCase();

    showToast('📷 Analyzing your meal…');
    Promise.all([ZitlasChatAttach.upload(file), _pcEstimateNutrition(file)]).then(function (results) {
      var url = results[0];
      var estimate = results[1];
      var id = 'MSL_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
      var doc = {
        id: id, athleteId: uid, day: day, mealType: mealType, mealName: meal.meal_name || 'Meal',
        imageUrl: url, loggedAt: new Date().toISOString(),
        calories: estimate ? estimate.estimatedCalories : null,
        protein:  estimate ? estimate.estimatedProtein  : null,
        carbs:    estimate ? estimate.estimatedCarbs    : null,
        fat:      estimate ? estimate.estimatedFat      : null,
        foodRecognition: estimate ? estimate.foodRecognition : null,
        confidenceScore: estimate ? estimate.confidenceScore : null,
      };
      return ZitlasDB.collection('meal_snap_logs').doc(uid).collection(_snapDateKey()).doc(id).set(doc)
        .then(function () { return !!estimate; });
    }).then(function (hadEstimate) {
      showToast(hadEstimate ? '✅ Meal logged and analyzed.' : '📷 Meal logged — nutrition estimate unavailable.');
    }).catch(function (e) {
      console.error('[SNAP MEAL] failed', e);
      showToast('Could not log meal — try again.');
    });
  }

  /* Compact per-meal row: camera button (nothing sent yet) OR the photo +
     coach feedback / pending state (already sent). Gated ONLY on an active
     coaching relationship — NOT on the coach having published a diet plan,
     so it works on AI-generated meals too (that gating bug hid the button
     entirely until the coach built a plan). Only rendered for TODAY —
     check-ins are a real-time compliance signal, not a historical editor
     (history stays visible via the workspace Meal Reviews tab). */
  function buildCoachMealRow(meal, dayName) {
    /* Canonical gate (assets/js/coaching-gate.js) — this used to check
       _pcRel.status only, which kept "Send Meal to Coach" visible after the
       relationship's endDate passed but before the backend sweep or a
       refresh caught up. */
    if (!_pcRel || typeof ZitlasCoachingGate === 'undefined' || !ZitlasCoachingGate.evaluate(_pcRel).active) return '';
    if (dayName !== _pcTodayName()) return '';
    var mealType = (meal.meal_name || 'meal').toLowerCase();
    var checkin = _pcCheckinFor(dayName, mealType);

    if (!checkin) {
      return '<div class="meal-coach-row">' +
        '<button class="cw-meal-btn cw-meal-btn--swap pc-checkin-btn" data-pc-checkin="' + esc(meal.meal_name || '') + '">📸 Send Meal to Coach</button>' +
        '</div>';
    }
    var feedback = checkin.status === 'reviewed'
      ? '<div class="pc-checkin-feedback">' +
          '<span class="pc-checkin-reaction">' + esc(PC_REACTION_LABEL[checkin.reaction] || 'Reviewed') + '</span>' +
          (checkin.score != null ? '<span class="pc-checkin-score">' + esc(checkin.score) + '/10</span>' : '') +
          (checkin.comment ? '<p class="pc-checkin-comment">' + esc(checkin.comment) + '</p>' : '') +
        '</div>'
      : '<div class="pc-checkin-pending">⏳ Sent — waiting for your coach’s review</div>';
    return '<div class="meal-coach-row">' +
      '<img class="pc-checkin-thumb" src="' + esc(checkin.imageUrl) + '" alt="Your ' + esc(meal.meal_name || 'meal') + ' photo">' +
      feedback +
      '</div>';
  }

  /* Today's real, computed compliance line — omitted entirely (no "0/0")
     when nothing has been reviewed yet, per "do not fake data". */
  function buildDailyScoreHtml(dayData) {
    var dayName = dayData.day || dayData.day_type;
    if (!_pcRel || _pcRel.status !== 'active' || dayName !== _pcTodayName()) return '';
    var reviewed = (dayData.meals || [])
      .map(function (m) { return _pcCheckinFor(dayName, (m.meal_name || '').toLowerCase()); })
      .filter(function (c) { return c && c.status === 'reviewed' && c.score != null; });
    if (!reviewed.length) return '';
    var sum = reviewed.reduce(function (s, c) { return s + c.score; }, 0);
    var max = reviewed.length * 10;
    return '<div class="cw-daily-score"><span>Today’s Meal Score</span><b>' +
      sum + '/' + max + ' · ' + Math.round((sum / max) * 100) + '%</b></div>';
  }

  function wireCoachCheckinButtons() {
    document.querySelectorAll('[data-pc-checkin]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var mealName = btn.dataset.pcCheckin;
        var day = weeklyPlan && weeklyPlan.days && weeklyPlan.days[currentDay];
        var meals = day && day.meals ? day.meals : [];
        var meal = meals.find(function (m) { return (m.meal_name || '') === mealName; });
        if (meal) openMealCheckinCamera(meal);
      });
    });
  }

  /* capture="environment" opens the device camera directly on mobile
     (no gallery step); desktop browsers fall back to their file picker,
     which is the closest the web platform allows. */
  function openMealCheckinCamera(meal) {
    var input = document.getElementById('pcCameraInput');
    if (!input) {
      input = document.createElement('input');
      input.type = 'file';
      input.accept = 'image/*';
      input.capture = 'environment';
      input.id = 'pcCameraInput';
      input.style.display = 'none';
      document.body.appendChild(input);
    }
    input.onchange = function () {
      var f = input.files && input.files[0];
      input.value = '';
      if (f) _pcOpenCheckinPreview(f, meal);
    };
    input.click();
  }

  function _pcOpenCheckinPreview(file, meal) {
    var url = URL.createObjectURL(file);
    _pcOpenSheet(
      '<p class="cw-sheet-title">Send ' + esc(meal.meal_name || 'Meal') + ' to Coach</p>' +
      '<img src="' + url + '" class="cw-review-img-lg" alt="Meal preview">' +
      '<div class="cw-save-bar" style="position:static;background:none">' +
        '<button class="cw-ghost-btn" id="pcRetake">Retake</button>' +
        '<button class="cw-save-btn" id="pcSendCheckin">Send</button>' +
      '</div>'
    );
    document.getElementById('pcRetake').addEventListener('click', function () {
      URL.revokeObjectURL(url);
      openMealCheckinCamera(meal);
    });
    document.getElementById('pcSendCheckin').addEventListener('click', function () {
      _pcSendCheckin(file, meal, url);
    });
  }

  /* AI nutrition estimate (backend/routes/meal_ai.py) runs ALONGSIDE the
     photo upload — never blocks or fails the checkin send if it errors or
     times out; the athlete's send is what matters, the estimate is a bonus
     enrichment of fields meal_checkins already reserved for this. */
  function _pcEstimateNutrition(file) {
    if (typeof getIdToken !== 'function') return Promise.resolve(null);
    return getIdToken().then(function (token) {
      var fd = new FormData();
      fd.append('file', file);
      return fetch('/api/meal/estimate-nutrition', {
        method: 'POST', headers: { 'Authorization': 'Bearer ' + token }, body: fd,
      }).then(function (res) { return res.ok ? res.json() : null; });
    }).catch(function (e) { console.warn('[MEAL CHECKIN] nutrition estimate failed (non-fatal)', e); return null; });
  }

  function _pcSendCheckin(file, meal, previewUrl) {
    var btn = document.getElementById('pcSendCheckin');
    if (btn) { btn.disabled = true; btn.textContent = 'Uploading…'; }
    if (typeof ZitlasChatAttach === 'undefined') { showToast('Upload unavailable — please retry.'); return; }

    Promise.all([ZitlasChatAttach.upload(file), _pcEstimateNutrition(file)]).then(function (results) {
      var url = results[0];
      var estimate = results[1];
      var uid = _pcUid();
      var athleteName = _pcAthleteName();
      var id = 'MCI_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
      var doc = {
        checkinId: id, athleteId: uid, athleteName: athleteName, coachId: _pcRel.coachId,
        day: _pcTodayName(), mealType: (meal.meal_name || 'meal').toLowerCase(), mealName: meal.meal_name || 'Meal',
        imageUrl: url, timestamp: new Date().toISOString(), status: 'pending',
        reaction: null, score: null, comment: null, reviewedAt: null, reviewedBy: null,
        /* Populated when the AI estimate above succeeds; null if it failed
           or timed out — never blocks the checkin either way. */
        estimatedCalories: estimate ? estimate.estimatedCalories : null,
        estimatedProtein:  estimate ? estimate.estimatedProtein  : null,
        estimatedCarbs:    estimate ? estimate.estimatedCarbs    : null,
        estimatedFat:      estimate ? estimate.estimatedFat      : null,
        foodRecognition:   estimate ? estimate.foodRecognition   : null,
        confidenceScore:   estimate ? estimate.confidenceScore   : null,
      };
      console.log('[MEAL CHECKIN] submitting', doc);
      return ZitlasDB.collection('meal_checkins').doc(id).set(doc).then(function () {
        var nid = 'CN_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6);
        return ZitlasDB.collection('coaching_notifications').doc(nid).set({
          id: nid, toId: _pcRel.coachId, fromId: uid, fromName: athleteName,
          text: '📸 ' + athleteName + ' submitted ' + doc.mealName + ' for review.',
          type: 'meal_checkin', createdAt: new Date().toISOString(), read: false,
        });
      }).then(function () {
        if (typeof ZitlasNotify !== 'undefined') {
          ZitlasNotify.send(_pcRel.coachId, {
            title: '📷 ' + athleteName + ' submitted a meal',
            message: doc.mealName + ' — ' + doc.day, category: 'meal_snap',
            type: 'meal_checkin', action: 'expert_dashboard',
          });
        }
      });
    }).then(function () {
      URL.revokeObjectURL(previewUrl);
      _pcCloseSheet();
      showToast('✅ Sent to your coach for review.');
    }).catch(function (e) {
      console.error('[MEAL CHECKIN] failed', e);
      showToast(e && e.message ? e.message : 'Could not send — try again.');
      if (btn) { btn.disabled = false; btn.textContent = 'Send'; }
    });
  }

  async function init() {
    // Set --nav-height to actual navbar dimensions so body padding-bottom is correct
    const _navbar = document.getElementById('zitlas-navbar');
    if (_navbar) {
      const _navHeight = window.innerHeight - _navbar.getBoundingClientRect().top;
      document.documentElement.style.setProperty('--nav-height', _navHeight + 'px');
    }

    loadTheme();

    renderPrecautions();
    renderLocationNote();
    initDaySelector();
    initSwapModal();
    initNutriSelectModal();
    initHeader();

    /* Personal Coaching: attach realtime listeners early — if an active
       coach relationship with a published diet exists, it overrides the AI
       plan below the moment its snapshot arrives (no refresh needed). */
    initCoachDietMode();
    /* Standalone AI Snap Meal — runs for EVERY athlete regardless of
       coaching status (buildSnapMealRow itself decides whether to render,
       mutually exclusive with the coach-checkin row above). */
    _snapAttachListener();

    /* Real-time refresh when an expert's completed review reaches this
       device. Two triggers for the same handler:
         - 'zitlas-review-updated'  (review-sync.js merged fresh Firestore
           docs IN THIS TAB — storage events never fire in the writing tab)
         - 'storage'                (another tab wrote expert_plan_reviews) */
    function _onReviewsUpdated() {
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
      }
      showToast('👨‍⚕️ Your nutritionist has reviewed your plan!', 4000);
    }
    window.addEventListener('zitlas-review-updated', _onReviewsUpdated);
    window.addEventListener('storage', function (e) {
      if (e.key === 'expert_plan_reviews') _onReviewsUpdated();
    });

    /* Load persisted food restrictions */
    dietRejectedFoods  = safeJSON('diet_rejected_foods', []);
    _mealSwapHistories = safeJSON('zitlas_meal_swap_history', {});

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

    /* ── New schema: zitlas_diet_plan with {originalDietPlan, currentDietPlan, expertModifications}
          This takes priority over expert_plan_reviews so that athlete-accepted + possibly-swapped
          plans are never overwritten by a stale review on reload.
          (Legacy flat {days:[...]} falls through to the bottom of init.) ── */
    var _rawDietStr = localStorage.getItem('zitlas_diet_plan');
    if (_rawDietStr) {
      var _isStaleNew = _STALE_MARKERS.some(function (m) { return _rawDietStr.toLowerCase().indexOf(m) !== -1; });
      if (_isStaleNew) {
        localStorage.removeItem('zitlas_diet_plan');
        _rawDietStr = null;
      }
    }
    if (_rawDietStr) {
      console.log("[DIET INIT]", JSON.parse(localStorage.getItem("zitlas_diet_plan")));
      var _parsedDiet = null;
      try { _parsedDiet = JSON.parse(_rawDietStr); } catch (_) {}
      if (_parsedDiet && (_parsedDiet.currentDietPlan !== undefined || _parsedDiet.originalDietPlan !== undefined)) {
        console.log("[DIET expertModifications]", _parsedDiet.expertModifications);
        var _effective = buildEffectivePlan(_parsedDiet);
        if (_effective && _effective.days && _effective.days.length) {
          var _hasMods = _parsedDiet.expertModifications && Object.keys(_parsedDiet.expertModifications).length > 0;
          if (_hasMods || _parsedDiet.isExpertPlan) planSource = 'expert';
          console.log(planSource);
          console.log("[ALL REVIEWS]", JSON.parse(localStorage.getItem("expert_plan_reviews")));
          console.log("[DIET STORAGE]", JSON.parse(localStorage.getItem("zitlas_diet_plan")));
          weeklyPlan = normalizePlan(_effective);
          showLoading(false);
          renderPlanMeta();
          renderFocusCard(weeklyPlan, null);
          renderDay(currentDay);
          renderVerifyNutriSection();
          /* Check for a pending expert review even when the plan is already in new schema.
             Without this, getCompletedPlanReview() is never reached and the accept banner
             is never wired — so acceptExpertPlan() can never be called. */
          var _pendingReview = getCompletedPlanReview();
          console.log("[NEW SCHEMA] pending review", _pendingReview);
          if (_pendingReview && !_pendingReview.athleteAccepted) {
            activePlanReview = _pendingReview;
            showExpertReviewBanner(_pendingReview);
          }
          return;
        }
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
    console.log("[APPROVED REVIEW FOUND]", _newReview);
    if (_newReview && _newReview.reviewedDietPlan && _newReview.reviewedDietPlan.days) {
      console.log("[USING REVIEW]", _newReview.reviewedDietPlan);
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
      }
      return;
    }

    /* ── Load plan from canonical key — legacy flat format {days:[...]} ── */
    /* _rawDietStr and _parsedDiet were already read and stale-checked above */
    var _flatCached = null;
    if (_rawDietStr) {
      try { _flatCached = JSON.parse(_rawDietStr); } catch (_) {}
    }

    if (_flatCached && _flatCached.days && _flatCached.days.length) {
      console.log('Active Diet', _flatCached);
      console.log('Current Goal', _goalData);
      console.log('[DIET CACHE] Found legacy flat diet plan — days:', _flatCached.days.length);
      /* Migrate flat plan to new schema immediately so every future read uses the correct format */
      saveDietStorage({
        originalDietPlan:    _flatCached,
        currentDietPlan:     _flatCached,
        expertModifications: {},
        isExpertPlan:        false,
        expertName:          null,
        reviewedAt:          null,
      });
      weeklyPlan = normalizePlan(_flatCached);
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
     TODAY'S PRECAUTIONS — medical-condition safety guidance
     Deterministic, server-computed (backend/services/medical_conditions.py),
     never LLM-generated. Absent entirely for users with no reported
     condition — zitlas_precautions is only ever written when non-empty.
  ══════════════════════════════════════════ */
  function renderPrecautions() {
    var wrap = document.getElementById('precautionsCard');
    if (!wrap) return;
    var raw = safeJSON('zitlas_precautions', null);
    if (!raw || !raw.precautions || !raw.precautions.length) {
      wrap.style.display = 'none';
      wrap.innerHTML = '';
      return;
    }
    var condLabel = (raw.conditions || []).join(', ');
    wrap.innerHTML =
      '<div class="cw-card" style="margin:0 16px 14px">' +
        '<p class="cw-card-title">⚠️ Today’s Precautions' + (condLabel ? ' — ' + esc(condLabel) : '') + '</p>' +
        '<ul style="margin:0;padding-left:18px">' +
          raw.precautions.map(function (p) {
            return '<li style="font-size:13px;color:var(--text-sec);line-height:1.6;margin-bottom:4px">' + esc(p) + '</li>';
          }).join('') +
        '</ul>' +
      '</div>';
    wrap.style.display = 'block';
  }

  /* ══════════════════════════════════════════
     LOCATION-AWARE MEAL NOTE — one-line explanation set by ai-coach.js /
     the weekly-plan fetch whenever the backend's response carried a
     location_note (i.e. the user has a saved location AND it matched a
     known region). Absent entirely for users with no saved location —
     zitlas_location_note is only ever written when non-empty.
  ══════════════════════════════════════════ */
  function renderLocationNote() {
    var wrap = document.getElementById('geoLocationNote');
    if (!wrap) return;
    var note = localStorage.getItem('zitlas_location_note') || '';
    if (!note) {
      wrap.style.display = 'none';
      wrap.innerHTML = '';
      return;
    }
    wrap.innerHTML =
      '<div class="cw-card" style="margin:0 16px 14px;display:flex;align-items:flex-start;gap:8px">' +
        '<span style="font-size:16px;line-height:1.5">📍</span>' +
        '<p style="margin:0;font-size:13px;color:var(--text-sec);line-height:1.6">' + esc(note) + '</p>' +
      '</div>';
    wrap.style.display = 'block';
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
          'nutrition_bottleneck', 'diet_rejected_foods', 'zitlas_meal_swap_history',
          /* Expert review — zitlas_* prefix (current keys) */
          'zitlas_expert_review', 'zitlas_plan_versions', 'zitlas_review_request',
          /* Expert review — new Verify Plan system */
          'expert_plan_reviews',
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

    /* Derive goal-aware label strings so fallbacks match the user's actual goal */
    var _gNorm = safeJSON('zitlas_goal', null);
    var _gType = _gNorm ? (_gNorm.type || 'Weight Loss') : 'Weight Loss';
    var _FOCUS_MAP = {
      'Weight Loss':     'Personalised weight-loss plan designed to help you reach your goal weight.',
      'Muscle Gain':     'Personalised muscle gain plan designed to help you build lean mass and strength.',
      'General Fitness': 'Personalised general fitness plan designed to improve your health and endurance.',
      'Transformation':  'Personalised transformation plan designed to recompose your body and build lean muscle.',
    };
    var _DAY_TYPE_MAP = {
      'Weight Loss':     'Weight Loss Day',
      'Muscle Gain':     'Muscle Gain Day',
      'General Fitness': 'General Fitness Day',
      'Transformation':  'Transformation Day',
    };

    /* Top-level fields */
    plan.nutrition_focus = plan.nutrition_focus
      || plan.summary
      || (_FOCUS_MAP[_gType] || ('Personalised ' + _gType.toLowerCase() + ' plan.'));

    plan.hydration_daily_target = plan.hydration_daily_target
      || (calc.water_target_liters ? calc.water_target_liters + 'L per day' : null);

    plan.weekly_notes = plan.weekly_notes
      || (plan.key_rules && plan.key_rules.length ? plan.key_rules.join(' · ') : null);

    /* Per-day fields */
    var MEAL_COLORS = ['var(--primary)','var(--success)','var(--primary)','var(--ai-accent)','var(--ai-accent)','var(--primary-dark)'];
    var MEAL_EMOJIS = { breakfast:'🌅', 'mid-morning':'🥤', midmorning:'🥤', lunch:'🍽️', 'evening snack':'⚡', 'pre-training':'⚡', dinner:'🫕', recovery:'💪' };

    plan.days.forEach(function (day) {
      day.day_type      = day.day_type      || (_DAY_TYPE_MAP[_gType] || (_gType + ' Day'));
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
        '<h3 style="font-size:18px;font-weight:700;margin-bottom:10px;color:var(--text-primary,var(--text-primary))">Get Your Personalised Diet Plan</h3>' +
        '<p style="font-size:14px;color:var(--text-secondary,var(--text-secondary));line-height:1.6;margin-bottom:24px;max-width:280px;margin-left:auto;margin-right:auto">' +
          'Complete a 4-minute assessment and Zino will build a 7-day weight-loss meal plan tailored to your goals, food preferences, and lifestyle.' +
        '</p>' +
        '<a href="../dashboard/ai-coach/ai-coach.html" ' +
           'style="display:inline-block;padding:16px 32px;background:linear-gradient(135deg,#E07000,var(--primary));' +
           'color:var(--text-primary);font-weight:700;font-size:15px;border-radius:14px;text-decoration:none;' +
           'box-shadow:0 4px 20px rgba(var(--primary-rgb),0.35);">' +
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
      stroke="var(--primary)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <polyline points="17 1 21 5 17 9"/>
      <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
      <polyline points="7 23 3 19 7 15"/>
      <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
    </svg>`;

    const staticMeals = [
      { emoji:'🌅', color:'var(--primary)', bg:'rgba(var(--primary-rgb),0.15)', name:'Breakfast',      time:'7:30 AM', foods:'Oats, Banana, Almonds, Milk'               },
      { emoji:'🥤', color:'var(--success)', bg:'rgba(var(--success-rgb),0.15)', name:'Mid-Morning',    time:'10:30 AM',foods:'Greek Yogurt, Honey, Walnuts'              },
      { emoji:'🍽️', color:'var(--primary)', bg:'rgba(249,115,22,0.15)',name:'Lunch',          time:'1:00 PM', foods:'Rice, Dal, Chicken, Salad'                 },
      { emoji:'⚡',  color:'var(--primary-dark)', bg:'rgba(239,68,68,0.15)', name:'Pre-Training',  time:'4:30 PM', foods:'Banana, Peanut Butter Toast'               },
      { emoji:'💪', color:'var(--ai-accent)', bg:'rgba(var(--ai-rgb),0.15)',name:'Recovery',       time:'7:00 PM', foods:'Paneer, Roti, Curd, Vegetables'            },
      { emoji:'🫕', color:'var(--ai-accent)', bg:'rgba(var(--ai-rgb),0.15)',name:'Dinner',         time:'8:30 PM', foods:'Khichdi / Sabzi, Roti, Salad'              },
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

    /* Only match reviews whose planId aligns with the currently active plan.
       If the active plan has an ID and the review carries a different (or absent)
       ID, the review is stale and must not be shown. */
    var activePlanId = localStorage.getItem('zitlas_plan_id') || null;

    /* Anchor to the ACTIVE review request (submitVerifyRequest() writes this
       the moment the athlete asks a specific expert for a review — its `id`
       is the exact same id every review document is keyed by, all the way
       through Firestore's review_requests/{id} and expert_plan_reviews).
       Without this anchor, "any completed diet review for this user" can
       return a stale, never-accepted review from a DIFFERENT expert the
       athlete reviewed with previously (e.g. Pratik) while they're actually
       waiting on a brand-new request to a different expert (e.g. Srujan) —
       the exact production bug this filter closes. A review only qualifies
       if it IS the active request, identified by id first (authoritative)
       and cross-checked by expertId when both are present. */
    var activeRequest = safeJSON('zitlas_review_request', null);

    var candidates = all.slice().reverse().filter(function (r) {
      var isCompleted    = r.status === 'review_completed' || r.status === 'completed';
      var planIdMismatch = activePlanId && r.planId && r.planId !== activePlanId;
      var _rtype = r.reviewType || r.planReviewType || 'diet';
      return _rtype === 'diet' &&
             isCompleted &&
             r.reviewedDietPlan &&
             (!uid || r.userId === uid) &&
             !planIdMismatch;
    });

    /* No active request on this device -> nothing to anchor to. Falling
       back to "the newest qualifying review" is exactly the bug being
       fixed here (it can resurface a stale, unaccepted review from a
       different, earlier expert) — showing no banner is always safer
       than showing the wrong one. */
    if (!activeRequest || !activeRequest.id) {
      console.log("[REVIEW MATCH] no active review request on this device — no banner shown");
      return null;
    }

    var forActiveRequest = candidates.find(function (r) {
      var expertMatches = !r.expertId || !activeRequest.expertId || r.expertId === activeRequest.expertId;
      return r.id === activeRequest.id && expertMatches;
    });
    console.log("[REVIEW MATCH] active request:", activeRequest.id, activeRequest.expertId,
      "-> matched:", forActiveRequest ? forActiveRequest.id : null);
    return forActiveRequest || null;
  }

  /* ══════════════════════════════════════════
     EXPERT REVIEW BANNER
  ══════════════════════════════════════════ */
  function showExpertReviewBanner(review) {
    console.log("showExpertReviewBanner called", review);
    var banner = document.getElementById('expertReviewBanner');
    if (!banner) {
      console.warn("showExpertReviewBanner: #expertReviewBanner not found in DOM");
      return;
    }
    var sub = document.getElementById('erBannerSub');
    if (sub) {
      sub.textContent = 'By ' + (review.expertName || 'Expert') +
        (review.reviewedAt
          ? ' · ' + new Date(review.reviewedAt).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' })
          : '');
    }
    _paintExpertBadge('erBannerBadge', review.expertId);
    banner.style.display = 'flex';
    /* Wire interactions here so the button is always ready immediately after the banner appears,
       regardless of which code path called showExpertReviewBanner. */
    initExpertReviewBannerInteractions();
  }

  function hideExpertReviewBanner() {
    var banner = document.getElementById('expertReviewBanner');
    if (banner) banner.style.display = 'none';
  }

  function initExpertReviewBannerInteractions() {
    console.log("initExpertReviewBannerInteractions called");
    var viewBtn   = document.getElementById('erViewBtn');
    var acceptBtn = document.getElementById('erAcceptBtn');
    console.log("acceptBtn", acceptBtn);
    console.log("acceptBtn.onclick", acceptBtn ? acceptBtn.onclick : 'N/A (null element)');
    if (viewBtn) {
      viewBtn.onclick = function () {
        if (activePlanReview) openDietCompSheet(activePlanReview);
      };
    }
    if (acceptBtn) {
      acceptBtn.onclick = function () {
        console.log("ACCEPT BUTTON CLICKED");
        if (activePlanReview) acceptExpertPlan(activePlanReview);
      };
    }
  }

  function acceptExpertPlan(review) {
    console.log("ACCEPT EXPERT PLAN CALLED");
    console.log(review);

    /* Build expertModifications — support multiple field name conventions from expert dashboard */
    var _mods    = {};
    var _history = review.mealChangeHistory || review.meal_change_history || review.changeHistory || review.changes || [];
    var _expName = review.expertName || review.expert_name || 'Expert';

    console.log("[REVIEW HISTORY]", review.mealChangeHistory);
    console.log("[REVIEWED PLAN]", review.reviewedDietPlan);
    console.log("_history", _history);

    _history.forEach(function (change) {
      /* Support both camelCase and snake_case field names */
      var _rawDayIdx = change.dayIndex != null ? change.dayIndex : (change.day_index != null ? change.day_index : 0);
      var _dk        = String(_rawDayIdx);
      var _rawName   = change.mealName || change.meal_name || change.name || '';
      var _mk        = _mealKey(_rawName);
      if (!_mods[_dk]) _mods[_dk] = {};
      _mods[_dk][_mk] = {
        modified:   true,
        modifiedBy: change.modifiedBy || change.modified_by || _expName,
        modifiedAt: change.modifiedAt || change.modified_at || review.reviewedAt || new Date().toISOString(),
        oldMeal: {
          foods:     change.oldFoods  || change.old_foods  || [],
          calories:  change.oldCalories  || change.old_calories  || null,
          protein_g: change.oldProtein   || change.old_protein   || null,
        },
        newMeal: {
          foods:     change.newFoods  || change.new_foods  || [],
          calories:  change.newCalories || change.new_calories || null,
          protein_g: change.newProtein  || change.new_protein  || null,
        },
      };
    });

    console.log("[MODS GENERATED]", _mods);

    /* originalDietPlan = plan before expert touched it.
       Prefer: existing stored original → review.planData → review.context.diet_plan (unwrap if new schema) */
    var _existingStorage = loadDietStorage();
    /* review.context.diet_plan may be in new-schema format — unwrap it */
    var _contextRaw  = review.planData || (review.context && review.context.diet_plan) || null;
    var _contextPlan = _contextRaw;
    if (_contextRaw && (_contextRaw.originalDietPlan || _contextRaw.currentDietPlan)) {
      _contextPlan = _contextRaw.originalDietPlan || _contextRaw.currentDietPlan;
    }
    var _originalPlan = (_existingStorage && _existingStorage.originalDietPlan)
                     || (_existingStorage && _existingStorage.currentDietPlan)
                     || _contextPlan
                     || null;

    /* Always scan reviewedDietPlan for _edited meals.
       - Creates entries for meals missed by mealChangeHistory (history empty or key mismatch)
       - Fixes entries where newFoods arrived empty from history (reviewedDietPlan is authoritative for foods) */
    if (review.reviewedDietPlan) {
      var reviewedPlan = review.reviewedDietPlan;
      console.log('[REVIEWED PLAN]', reviewedPlan);
      var _revDays  = reviewedPlan.days || [];
      var _origDays = _originalPlan ? (_originalPlan.days || []) : [];
      _revDays.forEach(function (revDay, dayIdx) {
        console.log('[DAY]', revDay);
        console.log('[MEALS]', revDay.meals);
        console.log('[TYPE]', typeof revDay.meals);
        console.log('[IS ARRAY]', Array.isArray(revDay.meals));
        var _revMealsArr = _mealsToArray(revDay.meals);
        _revMealsArr.forEach(function (revMeal) {
          if (!revMeal._edited) return;
          var _mealName = revMeal.meal_name || revMeal.name || '';
          var _dk       = String(dayIdx);
          var _mk       = revMeal._mealKey || _mealKey(_mealName);
          var _origDay  = _origDays[dayIdx];
          var _origMeal = _origDay ? _findMealByKey(_origDay.meals, _mk) : null;
          if (!_mods[_dk]) _mods[_dk] = {};
          if (!_mods[_dk][_mk]) {
            /* Entry not built from history — create it from _edited flag */
            _mods[_dk][_mk] = {
              modified:   true,
              modifiedBy: _expName,
              modifiedAt: review.reviewedAt || new Date().toISOString(),
              oldMeal: _origMeal
                ? { foods: _origMeal.foods || [], calories: _origMeal.calories || null, protein_g: _origMeal.protein_g || null }
                : { foods: [] },
              newMeal: { foods: revMeal.foods || [], calories: revMeal.calories || null, protein_g: revMeal.protein_g || null },
            };
          } else {
            /* Entry exists from history — fix foods if history had empty newFoods */
            if (!_mods[_dk][_mk].newMeal) _mods[_dk][_mk].newMeal = {};
            if (!_mods[_dk][_mk].newMeal.foods || !_mods[_dk][_mk].newMeal.foods.length) {
              _mods[_dk][_mk].newMeal.foods = revMeal.foods || [];
            }
            if (!_mods[_dk][_mk].newMeal.calories && revMeal.calories) {
              _mods[_dk][_mk].newMeal.calories = revMeal.calories;
            }
            if (!_mods[_dk][_mk].newMeal.protein_g && revMeal.protein_g) {
              _mods[_dk][_mk].newMeal.protein_g = revMeal.protein_g;
            }
          }
        });
      });
    }

    console.log("_mods before save", _mods);
    console.log("[FINAL MODS]", _mods);

    saveDietStorage({
      originalDietPlan:    _originalPlan || review.reviewedDietPlan,
      currentDietPlan:     _originalPlan || review.reviewedDietPlan,
      expertModifications: _mods,
      isExpertPlan:        true,
      expertName:          _expName,
      reviewedAt:          review.reviewedAt || new Date().toISOString(),
    });
    console.log("AFTER SAVE", JSON.parse(localStorage.getItem("zitlas_diet_plan")));

    /* Immediately rebuild in-memory plan so the UI reflects expert changes without a refresh */
    var _acceptedStorage = loadDietStorage();
    console.log("[ACCEPT] Storage", _acceptedStorage);
    weeklyPlan = normalizePlan(buildEffectivePlan(_acceptedStorage));
    planSource = 'expert';
    console.log("[ACCEPT] WeeklyPlan", weeklyPlan);
    console.log("[ACCEPT] Day", weeklyPlan && weeklyPlan.days && weeklyPlan.days[currentDay]);

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
    renderFocusCard(weeklyPlan, null);
    renderDay(currentDay);
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
        ? buildDcDayHTML(_mealsToArray(origDay.meals), null, false)
        : '<p class="dc-no-data">No data for this day.</p>';
    }
    if (pRev) {
      var revDay   = reviewedDays[_dcActiveDay];
      var origDay2 = origDays[_dcActiveDay];
      pRev.innerHTML = revDay
        ? buildDcDayHTML(_mealsToArray(revDay.meals), origDay2 ? _mealsToArray(origDay2.meals) : null, true)
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

  /* Re-render (never re-init — init() wires modals/listeners that must not
     be double-attached) when another device changes the AI diet plan
     while this page stays open. Reuses the exact same pure load/build/
     normalize pipeline init() itself uses, so behavior is identical.
     Coach-mode rendering owns the screen while a coach is active — this
     only applies to the base AI plan. */
  function _reloadAndRenderPlan() {
    if (planSource === 'coach') return;
    var storage = loadDietStorage();
    var effective = storage ? buildEffectivePlan(storage) : null;
    if (!effective || !effective.days || !effective.days.length) return;
    var hasMods = storage.expertModifications && Object.keys(storage.expertModifications).length > 0;
    planSource = (hasMods || storage.isExpertPlan) ? 'expert' : 'ai';
    weeklyPlan = normalizePlan(effective);
    if (currentDay >= weeklyPlan.days.length) currentDay = 0;
    renderPlanMeta();
    renderFocusCard(weeklyPlan, null);
    renderDay(currentDay);
    console.log('[CLOUD SYNC] diet plan re-rendered from a remote change');
  }

  /* ══════════════════════════════════════════
     BOOT
     Cross-device sync: hydrate this device's cache from Firestore BEFORE
     the first render, then re-render (not re-init) on remote changes.
  ══════════════════════════════════════════ */
  function boot() {
    if (typeof ZitlasAuth === 'undefined' || typeof ZitlasCloudSync === 'undefined') { init(); return; }
    ZitlasAuth.onAuthStateChanged(function (user) {
      if (!user) { init(); return; }
      ZitlasCloudSync.hydrateOnLoad(user.uid).then(function () {
        init();
        ZitlasCloudSync.attachRealtime(user.uid, _reloadAndRenderPlan);
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
