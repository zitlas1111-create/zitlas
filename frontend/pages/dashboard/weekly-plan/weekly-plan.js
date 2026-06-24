/* =============================================
   ZITLAS — Weekly Training Plan
   weekly-plan.js

   Reads `zitlas_roadmap` from localStorage and
   renders the full 7-day plan overview page.
   No survey or API calls — pure read + render.
   ============================================= */

(function () {
  'use strict';

  /* ══════════════════════════════════════════
     DAY ACCENT COLOURS
     One colour per day (Mon→Sun). Used only for
     the left accent bar on each day card.
     No hardcoded labels — themes come from the plan.
  ══════════════════════════════════════════ */
  const DAY_COLORS = [
    '#22C55E', /* Day 1 */
    '#3B82F6', /* Day 2 */
    '#F59E0B', /* Day 3 */
    '#FF8A00', /* Day 4 */
    '#EF4444', /* Day 5 */
    '#A855F7', /* Day 6 */
    '#06B6D4', /* Day 7 - Recovery */
  ];

  /* Short day-name abbreviations */
  const DAY_SHORT = { Monday:'MON', Tuesday:'TUE', Wednesday:'WED',
                      Thursday:'THU', Friday:'FRI', Saturday:'SAT', Sunday:'SUN' };

  /* ══════════════════════════════════════════
     BOOT
  ══════════════════════════════════════════ */
  function init() {
    const plan = loadPlan();
    if (!plan || !plan.days || !plan.days.length) {
      showError();
      return;
    }
    render(plan);
  }

  /* ══════════════════════════════════════════
     DATA
  ══════════════════════════════════════════ */
  /* Normalise all workout-plan schema variants to an array of day objects */
  function normalizeWorkoutDays(wp) {
    return (wp && (wp.weekly_plan || wp.days || wp.weekly_schedule || wp.workout_days)) || [];
  }

  function loadPlan() {
    try {
      /* 0. Expert-reviewed workout plan — highest priority */
      const er          = JSON.parse(localStorage.getItem('zitlas_expert_review') || 'null');
      const activePlanId = localStorage.getItem('zitlas_plan_id');
      console.log('WEEKLY EXPERT REVIEW', er);

      /* Load original AI plan for diff computation */
      const originalWp = JSON.parse(localStorage.getItem('zitlas_workout_plan') || 'null');

      if (er && er.status === 'APPROVED' && er.modifiedWorkoutPlan) {
        const planIdMismatch = er.planId && activePlanId && (er.planId !== activePlanId);
        console.log('[WeeklyPlan] Expert review planId check — er.planId:', er.planId, '| active:', activePlanId, '| mismatch:', planIdMismatch);
        if (!planIdMismatch && normalizeWorkoutDays(er.modifiedWorkoutPlan).length) {
          const expertMeta = {
            reviewedBy: er.reviewedBy || 'Expert',
            reviewedAt: er.reviewedAt
              ? new Date(er.reviewedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
              : '',
          };
          console.log('[WeeklyPlan] Loading EXPERT-REVIEWED plan —', normalizeWorkoutDays(er.modifiedWorkoutPlan).length, 'days | reviewer:', expertMeta.reviewedBy);
          return transformWorkoutPlan(er.modifiedWorkoutPlan, originalWp, expertMeta);
        }
      }

      /* 1. Sport/roadmap format */
      const raw  = localStorage.getItem('zitlas_roadmap');
      const plan = raw ? JSON.parse(raw) : null;
      if (plan && plan.days && plan.days.length) {
        console.log('[Zitlas] Key read: zitlas_roadmap | Days:', plan.days.length);
        return plan;
      }

      /* 2. Fitness AI plan */
      if (originalWp && normalizeWorkoutDays(originalWp).length) {
        console.log('[Zitlas] Fallback: zitlas_workout_plan | Days:', normalizeWorkoutDays(originalWp).length);
        return transformWorkoutPlan(originalWp, null, null);
      }

      console.log('[Zitlas] No plan found. Keys:', Object.keys(localStorage).join(', '));
      return null;
    } catch (e) {
      console.error('[Zitlas] Failed to parse plan:', e);
      return null;
    }
  }

  /* originalWp — the raw AI plan (for diff rendering)
     expertMeta  — { reviewedBy, reviewedAt } or null */
  function transformWorkoutPlan(wp, originalWp, expertMeta) {
    const origDays = normalizeWorkoutDays(originalWp || {});

    function iconForType(t) {
      var s = (t || '').toLowerCase();
      if (s.includes('rest'))     return '😴';
      if (s.includes('recovery')) return '🧘';
      if (s.includes('walking'))  return '🚶';
      if (s.includes('cardio'))   return '🏃';
      if (s.includes('upper'))    return '💪';
      if (s.includes('lower'))    return '🦵';
      if (s.includes('hiit'))     return '🔥';
      return '💪';
    }

    return {
      goalLabel:   wp.plan_name || 'Training Plan',
      goal:        'Fitness',
      role:        'Member',
      _expertMeta: expertMeta || null,
      days: normalizeWorkoutDays(wp).map(function (day, i) {
        const origDay    = origDays[i] || {};
        const origTheme  = origDay.focus || origDay.type || '';
        const newTheme   = day.focus || day.type || '';
        /* Only show diff when the day was flagged modified AND both values exist and differ */
        const focusDiff  = !!(day._modified && origTheme && newTheme && origTheme !== newTheme);

        return {
          dayNumber:       i + 1,
          dayName:         day.day || ('Day ' + (i + 1)),
          theme:           newTheme || 'Training Session',
          _originalTheme:  focusDiff ? origTheme : null,
          _expertModified: !!(day._modified),
          icon:            iconForType(day.focus || day.type),
          totalTime:       day.duration_minutes ? (day.duration_minutes + ' min') : '—',
          date:            day.date || '',
          isToday:         false,
          /* primarySkill uses the workout focus so "Primary" shows the reviewed name */
          primarySkill:    { name: newTheme || '' },
          drills:          (day.exercises || []).map(function (ex) {
            return {
              name:        ex.name || 'Exercise',
              cat:         'Fitness',
              duration:    ex.reps_or_duration || '',
              sets:        String(ex.sets || ''),
              reps:        ex.reps_or_duration || '',
              cue:         ex.tip || day.daily_tip || '',
              target:      ex.reps_or_duration || '',
              instruction: ex.tip || '',
            };
          }),
        };
      }),
    };
  }

  /* ══════════════════════════════════════════
     MAIN RENDER
  ══════════════════════════════════════════ */
  function render(plan) {
    el('wpLoading').style.display = 'none';
    el('wpContent').style.display = 'block';

    renderHero(plan);
    renderContextBar(plan);
    renderWeekProgress(plan);
    renderAnalysis(plan);
    renderDayList(plan);
    renderWeeklyReview(plan);
  }

  /* ── PLAN CONTEXT BAR ── */
  function renderContextBar(plan) {
    const wrap = el('wpContextBar');
    if (!wrap) return;

    const goalLabel   = plan.goalLabel  || capitalise(plan.goal  || 'Weight Loss');
    const weeklyFocus = plan.weeklyFocus || goalLabel;
    const improvement = plan.expectedImprovement || null;
    const ambition    = capitalise((plan.ambition || '').replace(/_/g, ' ')) || null;
    const accentColor = plan.metaColor || '#FF8A00';

    const items = [
      { icon: '🎯', label: 'Goal',                value: goalLabel,   always: true  },
      { icon: '🔍', label: 'Weekly Focus',         value: weeklyFocus, always: true  },
      { icon: '📈', label: 'Expected Improvement', value: improvement, always: false },
      { icon: '🏆', label: 'Long-Term Ambition',   value: ambition,    always: false },
    ].filter(r => r.always || r.value);

    wrap.innerHTML = `
      <div class="wp-context" style="--ctx-color: ${accentColor}">
        <div class="wp-context-hd">
          <span class="wp-context-hd-dot"></span>
          <span class="wp-context-hd-title">Your Plan Profile</span>
        </div>
        <div class="wp-context-grid">
          ${items.map(r => `
            <div class="wp-context-item">
              <div class="wp-context-item-hd">
                <span class="wp-context-icon">${r.icon}</span>
                <span class="wp-context-label">${escHtml(r.label)}</span>
              </div>
              <p class="wp-context-value">${escHtml(r.value)}</p>
            </div>`).join('')}
        </div>
      </div>`;
  }

  /* ── WEEK PROGRESS ── */
  function renderWeekProgress(plan) {
    const wrap = el('wpWeekProgress');
    if (!wrap) return;

    const days  = plan.days || [];
    const today = new Date().toISOString().split('T')[0];

    const DAY_NAMES_WP = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    const todayNameWP  = DAY_NAMES_WP[new Date().getDay()];

    /* Find current day index (0-6) */
    let currentIdx = -1;
    days.forEach(function (d, i) {
      if (d.isToday || d.date === today) currentIdx = i;
    });
    /* Fallback when no dates: match by dayName */
    if (currentIdx === -1) {
      const allPast = days.every(d => d.date && d.date < today);
      if (allPast) {
        currentIdx = 7;
      } else {
        days.forEach(function (d, i) {
          if (!d.date && (d.isToday || d.dayName === todayNameWP)) currentIdx = i;
        });
        if (currentIdx === -1) currentIdx = 0;
      }
    }

    /* Progress % = days before today / 7 */
    const completedCount = days.filter(d => d.date && d.date < today).length;
    const progressPct    = Math.round((completedCount / 7) * 100);

    /* Current day label */
    const currentDay = currentIdx < 7 ? days[currentIdx] : null;
    const currentLabel = currentDay
      ? `Day ${currentDay.dayNumber} — ${currentDay.theme || currentDay.dayName}`
      : 'Week Complete';

    /* Dot indicators */
    const dotsHtml = days.map(function (d, i) {
      let cls = 'wp-prog-dot';
      if (d.date && d.date < today)                                                        cls += ' wp-prog-dot--done';
      else if (d.isToday || d.date === today || (!d.date && d.dayName === todayNameWP)) cls += ' wp-prog-dot--active';
      /* else: upcoming, no modifier */
      return `<span class="${cls}" title="${escHtml(d.theme || 'Day ' + (i+1))}"></span>`;
    }).join('');

    const goalLabel   = plan.goalLabel  || capitalise(plan.goal  || 'Weight Loss');
    const improvement = plan.expectedImprovement || null;
    const accentColor = plan.metaColor || '#FF8A00';

    wrap.innerHTML = `
      <div class="wp-week-progress" style="--prog-color: ${accentColor}">
        <div class="wp-prog-hd">
          <span class="wp-prog-hd-icon">📊</span>
          <span class="wp-prog-hd-title">Week Progress</span>
          <span class="wp-prog-pct">${progressPct}% complete</span>
        </div>

        <div class="wp-prog-bar-wrap">
          <div class="wp-prog-bar-track">
            <div class="wp-prog-bar-fill" style="width:${progressPct}%"></div>
          </div>
        </div>

        <div class="wp-prog-dots">${dotsHtml}</div>

        <div class="wp-prog-meta">
          <div class="wp-prog-meta-row">
            <span class="wp-prog-meta-label">Selected Goal</span>
            <span class="wp-prog-meta-value">${escHtml(goalLabel)}</span>
          </div>
          ${improvement ? `
          <div class="wp-prog-meta-row">
            <span class="wp-prog-meta-label">Expected Improvement</span>
            <span class="wp-prog-meta-value wp-prog-meta-value--accent">${escHtml(improvement)}</span>
          </div>` : ''}
          <div class="wp-prog-meta-row">
            <span class="wp-prog-meta-label">Current Session</span>
            <span class="wp-prog-meta-value">${escHtml(currentLabel)}</span>
          </div>
        </div>
      </div>`;
  }

  /* ── HERO ── */
  function renderHero(plan) {
    const hero = el('wpHero');
    if (!hero) return;

    const roleLabel = plan.roleLabel  || capitalise(plan.role  || 'Member');
    const goalLabel = plan.goalLabel  || capitalise(plan.goal  || 'Weight Loss');
    const days      = plan.days || [];

    /* Week date range */
    const firstDate = days[0]  ? formatHeroDate(days[0].date)  : '—';
    const lastDate  = days[6]  ? formatHeroDate(days[6].date)  : '—';
    const dateRange = (firstDate !== '—' && lastDate !== '—') ? `${firstDate} – ${lastDate}` : '';

    /* Total training hours */
    const totalMin = days.reduce((acc, d) => {
      const n = parseInt((d.totalTime || '0').replace(/[^0-9]/g, ''), 10) || 0;
      return acc + n;
    }, 0);
    const totalHrs = totalMin > 0 ? (totalMin / 60).toFixed(1) : '—';

    const isAiEnhanced = days.some(d => d.aiEnhanced);
    const ambitionLabel = capitalise((plan.ambition || '').replace(/_/g, ' ')) || 'Peak Performance';

    hero.innerHTML = `
      <div class="wp-hero-eyebrow">
        <span class="wp-hero-badge">${escHtml(roleLabel)}</span>
        ${isAiEnhanced ? '<span class="wp-ai-badge">🤖 AI Enhanced</span>' : ''}
      </div>
      <h1 class="wp-hero-title">Your 7-Day<br><span>Wellness Plan</span></h1>
      ${dateRange ? `<p class="wp-hero-dates">📅 ${escHtml(dateRange)}</p>` : ''}
      <div class="wp-hero-tags">
        <span class="wp-hero-tag">🎯 ${escHtml(goalLabel)}</span>
        <span class="wp-hero-tag">🏆 ${escHtml(ambitionLabel)}</span>
      </div>
      <div class="wp-hero-stats">
        <div class="wp-hero-stat">
          <span class="wp-hero-stat-num">7</span>
          <span class="wp-hero-stat-label">Sessions</span>
        </div>
        <div class="wp-hero-stat">
          <span class="wp-hero-stat-num">${escHtml(totalHrs)}</span>
          <span class="wp-hero-stat-label">Hours</span>
        </div>
        <div class="wp-hero-stat">
          <span class="wp-hero-stat-num">10</span>
          <span class="wp-hero-stat-label">Sections/Day</span>
        </div>
      </div>`;
  }

  /* ── AI ANALYSIS ── */
  function renderAnalysis(plan) {
    const wrap = el('wpAnalysisWrap');
    if (!wrap) return;

    const analysis = plan.analysis;
    if (!analysis) { wrap.innerHTML = ''; return; }

    const rows = [
      { label: 'Skill Gap',         value: analysis.skill_gap         || analysis.skillGap         },
      { label: 'Goal Feasibility',  value: analysis.goal_feasibility  || analysis.goalFeasibility  },
      { label: 'Training Capacity', value: analysis.training_capacity || analysis.trainingCapacity },
    ].filter(r => r.value);

    if (!rows.length) { wrap.innerHTML = ''; return; }

    wrap.innerHTML = `
      <div class="wp-analysis">
        <div class="wp-analysis-hd">
          <span class="wp-analysis-hd-icon">🧠</span>
          <span class="wp-analysis-hd-title">AI Pre-Analysis</span>
        </div>
        <div class="wp-analysis-row">
          ${rows.map(r => `
            <div class="wp-analysis-item">
              <p class="wp-analysis-item-label">${escHtml(r.label)}</p>
              <p class="wp-analysis-item-text">${escHtml(r.value)}</p>
            </div>`).join('')}
        </div>
      </div>`;
  }

  /* ── 7-DAY LIST ── */
  function renderDayList(plan) {
    const list = el('wpDayList');
    if (!list) return;

    const today    = new Date().toISOString().split('T')[0];
    const DAY_NAMES = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    const todayName = DAY_NAMES[new Date().getDay()];

    list.innerHTML = (plan.days || []).map(function (day, i) {
      console.log('WEEKLY CARD DAY', day);
      const accentColor = DAY_COLORS[i] || DAY_COLORS[0];
      const date        = day.date || '';

      /* ── STATUS ──
         Past day  → Completed
         Today     → In Progress
         Future    → Scheduled
         When no dates, match by dayName instead of defaulting to i===0
      */
      let statusLabel, statusCls;
      if (day.isToday || date === today || (!date && day.dayName === todayName)) {
        statusLabel = 'In Progress';
        statusCls   = 'wp-status-badge--today';
      } else if (date && date < today) {
        statusLabel = 'Completed';
        statusCls   = 'wp-status-badge--done';
      } else {
        statusLabel = 'Scheduled';
        statusCls   = 'wp-status-badge--upcoming';
      }

      /* Short day abbreviation */
      const dayShort  = DAY_SHORT[day.dayName] || (day.dayName || 'DAY').slice(0, 3).toUpperCase();

      /* Formatted date */
      const dateShort = date ? formatCardDate(date) : '';

      /* Primary skill name — from plan data, never hardcoded */
      const primaryName = (day.primarySkill && day.primarySkill.name)
        ? day.primarySkill.name
        : (day.drills && day.drills[0] ? day.drills[0].name : '');
      const primarySnip = primaryName.length > 44
        ? primaryName.slice(0, 41) + '…'
        : primaryName;

      /* Fitness session name */
      const fitnessName = (day.fitnessSession && day.fitnessSession.name)
        ? day.fitnessSession.name
        : '';
      const fitnessSnip = fitnessName.length > 38
        ? fitnessName.slice(0, 35) + '…'
        : fitnessName;

      /* Duration — from plan data */
      const duration = day.totalTime || '—';

      /* Expert badge — shown only on modified days */
      const expertBadgeHtml = (day._expertModified && plan._expertMeta)
        ? `<div class="wp-expert-badge">✓ Modified by ${escHtml(plan._expertMeta.reviewedBy)}${plan._expertMeta.reviewedAt ? ' · ' + escHtml(plan._expertMeta.reviewedAt) : ''}</div>`
        : '';

      /* Theme HTML — show strikethrough diff when focus changed */
      const themeHtml = day._originalTheme
        ? `<span class="wp-day-theme-del">${escHtml(day._originalTheme)}</span> <span class="wp-day-theme-new">✓ ${escHtml(day.theme)}</span>`
        : escHtml(day.theme || 'Training Session');

      return `
        <div class="wp-day-card${day._expertModified ? ' wp-day-card--reviewed' : ''}" data-day="${i}" role="button" tabindex="0"
             style="--i: ${i}" aria-label="${escHtml(day.theme || 'Day ' + day.dayNumber)}">
          <div class="wp-day-card-inner">

            <div class="wp-day-accent" style="background:${accentColor}"></div>

            <div class="wp-day-body">

              <!-- Row 1: Day name + date + status -->
              <div class="wp-day-row-top">
                <div class="wp-day-label-wrap">
                  <span class="wp-day-name">${escHtml(dayShort)}</span>
                  ${dateShort ? `<span class="wp-day-date">${escHtml(dateShort)}</span>` : ''}
                </div>
                <span class="wp-status-badge ${statusCls}">${statusLabel}</span>
              </div>

              <!-- Expert modified badge -->
              ${expertBadgeHtml}

              <!-- Row 2: Icon + theme (with optional strikethrough diff) + arrow -->
              <div class="wp-day-row-theme">
                <div class="wp-day-theme-wrap">
                  <span class="wp-day-icon">${escHtml(day.icon || '💪')}</span>
                  <span class="wp-day-theme">${themeHtml}</span>
                </div>
                <span class="wp-day-arrow">›</span>
              </div>

              <!-- Row 3: Duration only -->
              <div class="wp-day-row-chips">
                <span class="wp-chip">⏱ ${escHtml(duration)}</span>
              </div>

              <!-- Row 4: Primary — uses workout focus for fitness plans -->
              ${primarySnip ? `
                <p class="wp-day-primary">
                  <strong>Primary:</strong> ${escHtml(primarySnip)}
                </p>` : ''}

              <!-- Row 5: Fitness session (sport plans only) -->
              ${fitnessSnip ? `
                <p class="wp-day-fitness">
                  <strong>Fitness:</strong> ${escHtml(fitnessSnip)}
                </p>` : ''}

            </div>
          </div>
        </div>`;
    }).join('');

    /* Click + keyboard handlers */
    list.querySelectorAll('.wp-day-card').forEach(function (card) {
      const dayIdx = parseInt(card.dataset.day, 10);
      card.addEventListener('click', function () { openDay(dayIdx); });
      card.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          openDay(dayIdx);
        }
      });
    });
  }

  /* ── WEEKLY REVIEW ── */
  function renderWeeklyReview(plan) {
    const wrap   = el('wpReviewWrap');
    if (!wrap) return;

    const review = plan.weeklyReview;
    if (!review) { wrap.innerHTML = ''; return; }

    const items = [
      { icon: '🎯', label: 'Biggest Weakness',       value: review.biggest_weakness       || review.biggestWeakness       },
      { icon: '💪', label: 'Biggest Strength',        value: review.biggest_strength        || review.biggestStrength        },
      { icon: '📈', label: 'Expected Improvement',    value: review.expected_improvement    || review.expectedImprovement    },
      { icon: '✅', label: 'Weekly Success Criteria', value: review.weekly_success_criteria || review.weeklySuccessCriteria  },
    ].filter(r => r.value);

    if (!items.length) { wrap.innerHTML = ''; return; }

    const coachNote = review.coaches_weekly_notes || review.coachesWeeklyNotes;

    const itemsHtml = items.map(r => `
      <div class="wp-review-item">
        <div class="wp-review-item-hd">
          <span class="wp-review-item-icon">${r.icon}</span>
          <span class="wp-review-item-label">${escHtml(r.label)}</span>
        </div>
        <p class="wp-review-item-text">${escHtml(r.value)}</p>
      </div>`).join('');

    const noteHtml = coachNote ? `
      <div class="wp-review-notes">
        <div class="wp-review-notes-hd">
          <span class="wp-review-notes-icon">🧢</span>
          <span class="wp-review-notes-label">Trainer's Weekly Notes</span>
        </div>
        <p class="wp-review-notes-text">${escHtml(coachNote)}</p>
      </div>` : '';

    wrap.innerHTML = `
      <div class="wp-review">
        <div class="wp-review-hd">
          <span class="wp-review-hd-icon">📋</span>
          <span class="wp-review-hd-title">Weekly Review</span>
          <span class="wp-review-hd-sub">End-of-week assessment</span>
        </div>
        <div class="wp-review-grid">
          ${itemsHtml}
        </div>
        ${noteHtml}
      </div>`;
  }

  /* ══════════════════════════════════════════
     ERROR STATE
  ══════════════════════════════════════════ */
  function showError() {
    const page = el('wpPage');
    if (!page) return;
    page.innerHTML = `
      <div class="wp-error">
        <span class="wp-error-icon">📋</span>
        <h2 class="wp-error-title">No Plan Found</h2>
        <p class="wp-error-sub">Complete the AI Nutrition assessment with Zino to generate your personalised 7-day plan.</p>
        <button class="wp-error-btn" onclick="goToSurvey()">Start with Zino →</button>
        <button class="wp-cta-btn" style="margin-top:12px;" onclick="goBack()">← Back to Dashboard</button>
      </div>`;
  }

  /* ══════════════════════════════════════════
     NAVIGATION
  ══════════════════════════════════════════ */
  function openDay(dayIndex) {
    window.location.href = '../training/day.html?day=' + dayIndex;
  }

  window.goBack = function () {
    window.location.href = '../dashboard.html';
  };

  window.goToSurvey = function () {
    window.location.href = '../ai-coach/ai-coach.html';
  };

  /* ══════════════════════════════════════════
     UTILS
  ══════════════════════════════════════════ */
  function el(id) { return document.getElementById(id); }

  function escHtml(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function capitalise(str) {
    if (!str) return '';
    return str.charAt(0).toUpperCase() + str.slice(1).replace(/_/g, ' ');
  }

  function formatHeroDate(dateStr) {
    if (!dateStr) return '';
    try {
      const d = new Date(dateStr);
      return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
    } catch { return dateStr; }
  }

  function formatCardDate(dateStr) {
    if (!dateStr) return '';
    try {
      const d = new Date(dateStr);
      return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
    } catch { return dateStr; }
  }

  /* ══════════════════════════════════════════
     INIT NAVIGATION BUTTONS
  ══════════════════════════════════════════ */
  function initButtons() {
    const backBtn = el('wpBackBtn');
    if (backBtn) backBtn.addEventListener('click', goBack);

    const dashBtn = el('wpBackToDash');
    if (dashBtn) dashBtn.addEventListener('click', goBack);
  }

  /* ══════════════════════════════════════════
     BOOT
  ══════════════════════════════════════════ */
  function boot() {
    initButtons();
    init();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
