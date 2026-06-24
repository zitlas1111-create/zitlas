/* =============================================
   ZITLAS — Elite Day Training Plan
   day.js  ·  Reads ?day=N from URL, renders full
              professional coaching plan from roadmap
   ============================================= */

(function () {
  'use strict';

  /* ══════════════════════════════════════════
     INIT
  ══════════════════════════════════════════ */
  function init() {
    const dayIdx = getDayIndex();
    const loaded = loadPlanWithSource();

    console.log('[TRAINING] dayIdx:', dayIdx);
    console.log('[TRAINING] source:', loaded ? loaded.source : 'none');

    if (!loaded) {
      showError();
      return;
    }

    console.log('ACTIVE WORKOUT PLAN', loaded.plan);

    if (loaded.source === 'roadmap') {
      const day = loaded.plan.days[dayIdx];
      console.log('[DAY DATA]', day);
      if (!day) { showError(); return; }
      renderDay(day);
    } else {
      const weekly = normalizeWeeklyPlan(loaded.plan);
      console.log('[TRAINING] weekly days count:', weekly.length, '| dayIdx requested:', dayIdx);
      const day = weekly[dayIdx];
      console.log('[DAY DATA]', day);
      if (!day) { showError(); return; }
      renderFitnessDay(day, dayIdx, loaded.expertReview || null);
    }
  }

  /* ══════════════════════════════════════════
     URL PARAM
  ══════════════════════════════════════════ */
  function getDayIndex() {
    const params = new URLSearchParams(window.location.search);
    const raw    = parseInt(params.get('day') || '0', 10);
    return isNaN(raw) ? 0 : Math.max(0, raw);
  }

  /* ══════════════════════════════════════════
     LOAD PLAN (roadmap — used by renderWeeklyReview)
  ══════════════════════════════════════════ */
  function loadPlan() {
    try {
      return JSON.parse(localStorage.getItem('zitlas_roadmap')) || null;
    } catch { return null; }
  }

  /* ══════════════════════════════════════════
     LOAD PLAN WITH SOURCE — tries both keys
  ══════════════════════════════════════════ */
  function loadPlanWithSource() {
    /* 0. Expert-reviewed workout plan (highest priority) */
    try {
      const er          = JSON.parse(localStorage.getItem('zitlas_expert_review') || 'null');
      const activePlanId = localStorage.getItem('zitlas_plan_id');

      console.log('TRAINING REVIEW FOUND', er);
      console.log('REVIEWED WORKOUT PLAN', er ? er.modifiedWorkoutPlan : null);

      if (er && er.status === 'APPROVED') {
        /* planId guard — reject ONLY when both planIds are present and don't match.
           null/null means planId was never generated; still trust the review. */
        const planIdMismatch = er.planId && activePlanId && (er.planId !== activePlanId);
        const reviewValid    = !planIdMismatch;
        console.log('[TRAINING] planId guard — er.planId:', er.planId, '| activePlanId:', activePlanId, '| mismatch:', planIdMismatch, '| valid:', reviewValid);
        if (!reviewValid) {
          console.log('[TRAINING] Expert review DISCARDED — planId mismatch: review=' + er.planId + ' active=' + activePlanId);
          localStorage.removeItem('zitlas_expert_review');
        } else if (er.modifiedWorkoutPlan && normalizeWeeklyPlan(er.modifiedWorkoutPlan).length) {
          console.log('[TRAINING] zitlas_expert_review modifiedWorkoutPlan found — reviewedBy:', er.reviewedBy);
          console.log('[TRAINING] normalizeWeeklyPlan days:', normalizeWeeklyPlan(er.modifiedWorkoutPlan).length);
          console.log('TRAINING REVIEW FOUND (valid)', er.modifiedWorkoutPlan);
          console.log('REVIEWED WORKOUT', er.modifiedWorkoutPlan);
          console.log('TRAINING PLAN LOADED', er.modifiedWorkoutPlan);
          return { source: 'workout', plan: er.modifiedWorkoutPlan, expertReview: er };
        } else {
          console.log('[TRAINING] Expert review valid but modifiedWorkoutPlan absent or 0 days');
          console.log('[TRAINING] modifiedWorkoutPlan value:', er.modifiedWorkoutPlan);
          console.log('[TRAINING] normalizeWeeklyPlan result:', normalizeWeeklyPlan(er.modifiedWorkoutPlan || {}));
        }
      }
    } catch (_) {}

    /* 1. Sport/roadmap format */
    try {
      const rp = JSON.parse(localStorage.getItem('zitlas_roadmap') || 'null');
      if (rp && rp.days && rp.days.length) {
        console.log('[TRAINING] zitlas_roadmap:', rp.days.length, 'days');
        const result = { source: 'roadmap', plan: rp };
        console.log('TRAINING PLAN LOADED', result.plan);
        return result;
      }
    } catch (_) {}

    /* 2. Fitness workout plan format */
    try {
      const wp = JSON.parse(localStorage.getItem('zitlas_workout_plan') || 'null');
      if (wp && normalizeWeeklyPlan(wp).length) {
        console.log('[TRAINING] zitlas_workout_plan:', normalizeWeeklyPlan(wp).length, 'days');
        const result = { source: 'workout', plan: wp };
        console.log('TRAINING PLAN LOADED', result.plan);
        return result;
      }
    } catch (_) {}

    console.log('[TRAINING] No plan found in storage');
    return null;
  }

  /* ══════════════════════════════════════════
     NORMALIZE — support multiple schema variants
  ══════════════════════════════════════════ */
  function normalizeWeeklyPlan(wp) {
    return wp.weekly_plan     ||
           wp.days            ||
           wp.weekly_schedule ||
           wp.workout_days    ||
           [];
  }

  /* ══════════════════════════════════════════
     RENDER
  ══════════════════════════════════════════ */
  function renderDay(day) {
    console.log('[day.js] primary_skill →', JSON.stringify(day.primarySkill, null, 2));
    console.log('[day.js] secondary_skill →', JSON.stringify(day.secondarySkill, null, 2));
    console.log('[day.js] fitness_session →', JSON.stringify(day.fitnessSession, null, 2));

    el('tpLoading').style.display  = 'none';
    el('tpContent').style.display  = 'block';

    renderHeader(day);
    renderHero(day);
    renderTimeBreakdown(day);
    renderWarmup(day.warmup);
    renderActivation(day.activation);
    renderPrimarySkill(day.primarySkill);
    renderSecondarySkill(day.secondarySkill);
    renderFitnessSession(day.fitnessSession);
    renderMatchSimulation(day.matchSimulation);
    renderMental(day.mentalConditioning);
    renderRecovery(day.recoveryProtocol);
    renderStretching(day.stretching);
    renderHydration(day.hydration);
    renderCoachTip(day.coachTip);
    renderWeeklyReview(day);
  }

  /* ── Header ── */
  function renderHeader(day) {
    const labelEl = el('tpDayLabel');
    const dateEl  = el('tpHeaderDate');
    if (labelEl) labelEl.textContent = 'DAY ' + day.dayNumber;
    if (dateEl)  dateEl.textContent  = formatDate(day.date);
  }

  /* ── Hero ── */
  function renderHero(day) {
    setText('tpHeroIcon',      day.icon   || '🏏');
    setText('tpHeroTheme',     day.theme  || '—');
    setText('tpHeroObjective', day.objective || '—');
    setText('tpTotalTime',     '⏱ ' + (day.totalTime || '—'));
    setText('tpDayName',       day.dayName || '—');

    const badge = el('tpTodayBadge');
    if (badge) {
      if (!day.isToday) badge.classList.add('hidden');
      else badge.classList.remove('hidden');
    }
  }

  /* ── Time Breakdown ── */
  function renderTimeBreakdown(day) {
    const grid = el('tpTimeGrid');
    if (!grid) return;

    const blocks = [
      { val: '10 min',                   label: 'Warmup'         },
      { val: day.skillTime || '—',       label: 'Practice'       },
      { val: day.matchSimulation
          ? day.matchSimulation.duration
          : '12 min',                    label: 'Match Practice' },
      { val: '5 min',                    label: 'Focus'          },
      { val: '8 min',                    label: 'Cool Down'      },
      { val: day.totalTime || '—',       label: 'Total'          },
    ];

    grid.innerHTML = blocks.map(b => `
      <div class="tp-time-chip">
        <span class="tp-time-chip-val">${escHtml(b.val)}</span>
        <span class="tp-time-chip-label">${escHtml(b.label)}</span>
      </div>`).join('');
  }

  /* ── Warmup ── */
  function renderWarmup(warmup) {
    const list = el('tpWarmupList');
    if (!list || !warmup) return;
    list.innerHTML = (warmup || []).map(item => `
      <div class="tp-list-item">
        <div class="tp-list-dot"></div>
        <div class="tp-list-body">
          <p class="tp-list-activity">${escHtml(item.activity)}</p>
          ${item.note ? `<p class="tp-list-note">${escHtml(item.note)}</p>` : ''}
        </div>
      </div>`).join('');
  }

  /* ── Activation ── */
  function renderActivation(activation) {
    const list = el('tpActivationList');
    if (!list || !activation) return;
    list.innerHTML = (activation || []).map(item => `
      <div class="tp-list-item">
        <div class="tp-list-dot tp-list-dot--amber"></div>
        <div class="tp-list-body">
          <p class="tp-list-activity">${escHtml(item.activity)}</p>
          ${item.note ? `<p class="tp-list-note">${escHtml(item.note)}</p>` : ''}
        </div>
      </div>`).join('');
  }

  /* ── Skill session card (shared) ── */
  function renderSkillCard(drill, containerId, durId, accentCls) {
    const card = el(containerId);
    const durEl = el(durId);
    if (!card || !drill) return;

    if (durEl) durEl.textContent = drill.duration || '—';

    /* Equipment */
    const equipment = Array.isArray(drill.equipment) ? drill.equipment.filter(Boolean) : [];
    const equipmentHtml = equipment.length ? `
      <div class="tp-skill-equipment">
        <p class="tp-skill-equipment-label">Equipment Needed</p>
        <div class="tp-skill-equipment-list">
          ${equipment.map(e => `<span class="tp-skill-equipment-chip">${escHtml(e)}</span>`).join('')}
        </div>
      </div>` : '';

    /* Sets / Reps / Rest chips */
    const chips = [];
    if (drill.sets) chips.push(`<span class="tp-skill-chip">${escHtml(String(drill.sets))} sets</span>`);
    if (drill.reps) chips.push(`<span class="tp-skill-chip">${escHtml(String(drill.reps))}</span>`);
    if (drill.rest_between_sets) chips.push(`<span class="tp-skill-chip tp-skill-chip--rest">Rest ${escHtml(drill.rest_between_sets)}</span>`);
    const metaHtml = chips.length ? `<div class="tp-skill-meta">${chips.join('')}</div>` : '';

    /* Steps (new) or instruction (legacy fallback) */
    const steps = Array.isArray(drill.steps) ? drill.steps.filter(Boolean) : [];
    let instructionHtml = '';
    if (steps.length) {
      instructionHtml = `
        <p class="tp-skill-instruction-label">How To Do It</p>
        <div class="tp-skill-steps">
          ${steps.map((s, i) => `
            <div class="tp-skill-step">
              <span class="tp-skill-step-num">${i + 1}</span>
              <p class="tp-skill-step-text">${escHtml(s)}</p>
            </div>`).join('')}
        </div>`;
    } else if (drill.instruction) {
      instructionHtml = `
        <p class="tp-skill-instruction-label">What To Do</p>
        <p class="tp-skill-instruction">${escHtml(drill.instruction)}</p>`;
    }

    card.innerHTML = `
      <p class="tp-skill-name">${escHtml(drill.name || '—')}</p>
      ${equipmentHtml}
      ${metaHtml}
      ${instructionHtml}
      ${drill.cue ? `
        <div class="tp-skill-cue">
          <p class="tp-skill-cue-label">Remember</p>
          <p class="tp-skill-cue-text">${escHtml(drill.cue)}</p>
        </div>
      ` : ''}
      ${drill.target ? `
        <div class="tp-skill-target">
          <p class="tp-skill-target-label">Today's Goal</p>
          <p class="tp-skill-target-text">${escHtml(drill.target)}</p>
        </div>
      ` : ''}`;
  }

  function renderPrimarySkill(drill) {
    renderSkillCard(drill, 'tpPrimaryCard', 'tpPrimaryDur', 'green');
  }

  function renderSecondarySkill(drill) {
    renderSkillCard(drill, 'tpSecondaryCard', 'tpSecondaryDur', 'blue');
  }

  /* ── Fitness Session ── */
  function renderFitnessSession(drill) {
    const card  = el('tpFitnessCard');
    const durEl = el('tpFitnessDur');
    if (!card) return;

    if (!drill) {
      const section = el('tpFitnessSection');
      if (section) section.classList.add('tp-hidden');
      return;
    }

    if (durEl) durEl.textContent = drill.duration || '—';

    /* Equipment */
    const equipment = Array.isArray(drill.equipment) ? drill.equipment.filter(Boolean) : [];
    const equipmentHtml = equipment.length ? `
      <div class="tp-skill-equipment">
        <p class="tp-skill-equipment-label">Equipment Needed</p>
        <div class="tp-skill-equipment-list">
          ${equipment.map(e => `<span class="tp-skill-equipment-chip">${escHtml(e)}</span>`).join('')}
        </div>
      </div>` : '';

    /* Sets / Reps / Rest chips */
    const chips = [];
    if (drill.sets) chips.push(`<span class="tp-skill-chip tp-skill-chip--fitness">${escHtml(String(drill.sets))} sets</span>`);
    if (drill.reps) chips.push(`<span class="tp-skill-chip tp-skill-chip--fitness">${escHtml(String(drill.reps))}</span>`);
    if (drill.rest_between_sets) chips.push(`<span class="tp-skill-chip tp-skill-chip--rest">${escHtml('Rest ' + drill.rest_between_sets)}</span>`);
    const metaHtml = chips.length ? `<div class="tp-skill-meta">${chips.join('')}</div>` : '';

    /* Steps (new) or instruction (legacy fallback) */
    const steps = Array.isArray(drill.steps) ? drill.steps.filter(Boolean) : [];
    let instructionHtml = '';
    if (steps.length) {
      instructionHtml = `
        <p class="tp-skill-instruction-label">How To Do It</p>
        <div class="tp-skill-steps">
          ${steps.map((s, i) => `
            <div class="tp-skill-step">
              <span class="tp-skill-step-num">${i + 1}</span>
              <p class="tp-skill-step-text">${escHtml(s)}</p>
            </div>`).join('')}
        </div>`;
    } else if (drill.instruction) {
      instructionHtml = `
        <p class="tp-skill-instruction-label">What To Do</p>
        <p class="tp-skill-instruction">${escHtml(drill.instruction)}</p>`;
    }

    card.innerHTML = `
      <p class="tp-skill-name">${escHtml(drill.name || '—')}</p>
      ${equipmentHtml}
      ${metaHtml}
      ${instructionHtml}
      ${drill.cue ? `
        <div class="tp-skill-cue tp-skill-cue--fitness">
          <p class="tp-skill-cue-label">Remember</p>
          <p class="tp-skill-cue-text">${escHtml(drill.cue)}</p>
        </div>
      ` : ''}
      ${drill.target ? `
        <div class="tp-skill-target tp-skill-target--fitness">
          <p class="tp-skill-target-label">Today's Goal</p>
          <p class="tp-skill-target-text">${escHtml(drill.target)}</p>
        </div>
      ` : ''}`;
  }

  /* ── Match Simulation ── */
  function renderMatchSimulation(sim) {
    const card  = el('tpMatchCard');
    const durEl = el('tpMatchDur');
    if (!card || !sim) return;
    if (durEl) durEl.textContent = sim.duration || '12 min';

    card.innerHTML = `
      <p class="tp-match-scenario-label">Scenario</p>
      <p class="tp-match-scenario-text">${escHtml(sim.scenario || '—')}</p>
      <p class="tp-match-objective-label" style="margin-top:10px">Your Goal</p>
      <p class="tp-match-objective-text">${escHtml(sim.objective || '—')}</p>
      ${sim.successCriteria ? `
        <div class="tp-match-success" style="margin-top:10px">
          <p class="tp-match-success-label">How To Win</p>
          <p class="tp-match-success-text">${escHtml(sim.successCriteria)}</p>
        </div>
      ` : ''}`;
  }

  /* ── Mental Conditioning ── */
  function renderMental(mental) {
    const card  = el('tpMentalCard');
    const durEl = el('tpMentalDur');
    if (!card || !mental) return;
    if (durEl) durEl.textContent = mental.duration || '5 min';

    card.innerHTML = `
      <p class="tp-mental-type">${escHtml(mental.type || 'Visualization')}</p>
      <p class="tp-mental-instruction">"${escHtml(mental.instruction || '—')}"</p>`;
  }

  /* ── Recovery Protocol ── */
  function renderRecovery(protocol) {
    const list = el('tpRecoveryList');
    if (!list || !protocol) return;
    const items = protocol.items || [];
    list.innerHTML = items.map(item => `
      <div class="tp-recovery-row">
        <p class="tp-recovery-activity">${escHtml(item.activity)}</p>
        <p class="tp-recovery-duration">${escHtml(item.duration)}</p>
      </div>`).join('');
  }

  /* ── Stretching ── */
  function renderStretching(stretches) {
    const list = el('tpStretchList');
    if (!list || !stretches) return;
    list.innerHTML = (stretches || []).map(s => `
      <div class="tp-stretch-row">
        <p class="tp-stretch-name">${escHtml(s.stretch)}</p>
        <p class="tp-stretch-hold">${escHtml(s.hold)}</p>
        ${s.note ? `<p class="tp-stretch-note">${escHtml(s.note)}</p>` : ''}
      </div>`).join('');
  }

  /* ── Hydration ── */
  function renderHydration(hydration) {
    const card  = el('tpHydrationCard');
    const total = el('tpHydrationTotal');
    if (!card || !hydration) return;
    if (total) total.textContent = 'Total: ' + (hydration.total || '—');

    const rows = (hydration.schedule || []).map(row => `
      <div class="tp-hydration-row">
        <p class="tp-hydration-timing">${escHtml(row.timing)}</p>
        <p class="tp-hydration-amount">${escHtml(row.amount)}</p>
      </div>`).join('');

    const noteHtml = hydration.note
      ? `<p class="tp-hydration-note">${escHtml(hydration.note)}</p>`
      : '';

    card.innerHTML = `<div class="tp-hydration-schedule">${rows}</div>${noteHtml}`;
  }

  /* ── Coach's Tip ── */
  function renderCoachTip(tip) {
    const tipEl = el('tpCoachesTipText');
    if (tipEl && tip) tipEl.textContent = tip;
  }

  /* ── Weekly Review (Day 7 only, requires weeklyReview on plan) ── */
  function renderWeeklyReview(day) {
    const plan   = loadPlan();
    const review = plan && plan.weeklyReview ? plan.weeklyReview : null;
    const section = el('tpWeeklyReviewSection');
    const card    = el('tpWeeklyReviewCard');
    if (!section || !card) return;

    /* Only show on Day 7 (day.dayNumber === 7) */
    if (day.dayNumber !== 7 || !review) {
      section.classList.add('tp-hidden');
      return;
    }

    section.classList.remove('tp-hidden');

    const rows = [
      { icon: '🎯', label: 'What To Work On',      value: review.biggest_weakness       || review.biggestWeakness },
      { icon: '💪', label: "What You're Good At",  value: review.biggest_strength        || review.biggestStrength },
      { icon: '📈', label: 'How You Will Improve', value: review.expected_improvement    || review.expectedImprovement },
      { icon: '✅', label: "This Week's Goal",     value: review.weekly_success_criteria || review.weeklySuccessCriteria },
    ].filter(r => r.value);

    const rowsHtml = rows.map(r => `
      <div class="tp-review-row">
        <div class="tp-review-row-hd">
          <span class="tp-review-icon">${escHtml(r.icon)}</span>
          <span class="tp-review-label">${escHtml(r.label)}</span>
        </div>
        <p class="tp-review-value">${escHtml(r.value)}</p>
      </div>`).join('');

    const coachNote = review.coaches_weekly_notes || review.coachesWeeklyNotes;
    const noteHtml  = coachNote ? `
      <div class="tp-review-coach-note">
        <div class="tp-review-coach-note-hd">
          <span class="tp-review-coach-icon">🧢</span>
          <span class="tp-review-coach-label">Trainer's Note</span>
        </div>
        <p class="tp-review-coach-text">${escHtml(coachNote)}</p>
      </div>` : '';

    card.innerHTML = rowsHtml + noteHtml;
  }

  /* ══════════════════════════════════════════
     RENDER FITNESS DAY (zitlas_workout_plan schema)
     Handles: { day, type, focus, exercises[],
                duration_minutes, calories_burned_est,
                daily_tip }
  ══════════════════════════════════════════ */
  function renderFitnessDay(day, dayIdx, expertReview) {
    console.log('RENDERING FRIDAY', day);
    console.log('[TRAINING] day.focus:', day.focus, '| day.type:', day.type, '| day.exercises:', (day.exercises || []).map(function(e){ return e.name; }));

    const isRest    = (day.type || '').toLowerCase().includes('rest') ||
                      (day.type || '').toLowerCase().includes('recovery');
    const exercises = day.exercises || [];

    console.log('[TRAINING] renderFitnessDay — isRest:', isRest, '| exercises:', exercises.length);
    console.log('FRIDAY DATA', day);

    el('tpLoading').style.display = 'none';
    el('tpContent').style.display = 'block';

    /* ── Header ── */
    setText('tpDayLabel',   day.day || ('Day ' + (dayIdx + 1)));
    setText('tpHeaderDate', '');

    /* ── Hero ── */
    setText('tpHeroIcon',      isRest ? '😴' : '💪');
    setText('tpHeroTheme',     day.focus || day.type || 'Training');
    setText('tpHeroObjective', day.daily_tip ||
      (isRest ? 'Rest and recover today.' : 'Complete all exercises with proper form.'));
    setText('tpTotalTime', '⏱ ' + (day.duration_minutes ? day.duration_minutes + ' min' : '—'));
    setText('tpDayName',   day.day || '');
    el('tpTodayBadge')?.classList.add('hidden');

    /* ── Expert review badge + note ── */
    const expertNote  = day._expertNote || '';
    const reviewedBy  = expertReview ? (expertReview.reviewedBy || 'Expert') : '';
    const reviewedAt  = expertReview && expertReview.reviewedAt
      ? new Date(expertReview.reviewedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
      : '';

    /* Inject expert banner after hero, if applicable */
    const heroEl = el('tpHeroTheme') && el('tpHeroTheme').closest('.tp-hero');
    const existingBanner = el('tpExpertBanner');
    if (existingBanner) existingBanner.remove();

    if (expertReview && expertReview.status === 'APPROVED') {
      const banner = document.createElement('div');
      banner.id        = 'tpExpertBanner';
      banner.className = 'tp-expert-banner';
      banner.innerHTML =
        '<span class="tp-expert-banner-icon">✓</span>' +
        '<div class="tp-expert-banner-text">' +
          '<span class="tp-expert-banner-name">✓ Modified by ' + escHtml(reviewedBy) +
            (reviewedAt ? ' · ' + reviewedAt : '') + '</span>' +
          (expertNote ? '<span class="tp-expert-banner-note">' + escHtml(expertNote) + '</span>' : '') +
        '</div>';
      /* Insert before tpWhyText / tpCoachesTip area */
      const content = el('tpContent');
      const timeGrid = el('tpTimeGrid');
      if (content && timeGrid) {
        timeGrid.parentNode.insertBefore(banner, timeGrid.nextSibling);
      } else if (content) {
        content.insertBefore(banner, content.firstChild);
      }
    }

    /* ── Why / Tip strip ── */
    if (day.daily_tip) {
      setText('tpWhyText', day.daily_tip);
    } else {
      const whySec = el('tpWhy');
      if (whySec) whySec.style.display = 'none';
    }

    /* ── Time breakdown chips ── */
    const tGrid = el('tpTimeGrid');
    if (tGrid) {
      const chips = [];
      if (day.duration_minutes)    chips.push({ val: day.duration_minutes + ' min',     label: 'Duration'      });
      if (day.calories_burned_est) chips.push({ val: day.calories_burned_est + ' kcal', label: 'Est. Calories' });
      if (!isRest && exercises.length) chips.push({ val: String(exercises.length),      label: 'Exercises'     });
      tGrid.innerHTML = chips.map(b => `
        <div class="tp-time-chip">
          <span class="tp-time-chip-val">${escHtml(b.val)}</span>
          <span class="tp-time-chip-label">${escHtml(b.label)}</span>
        </div>`).join('');
    }

    /* ── Hide all sport-specific sections ── */
    ['tpWarmupSection','tpActivationSection','tpPrimarySection',
     'tpSecondarySection','tpMatchSection','tpMentalSection',
     'tpRecoverySection','tpStretchSection','tpHydrationSection',
     'tpWeeklyReviewSection'].forEach(id => el(id)?.classList.add('tp-hidden'));

    /* ── Rest / Recovery Day ── */
    if (isRest) {
      el('tpFitnessSection')?.classList.add('tp-hidden');
      const tipWrap = el('tpCoachesTip');
      if (tipWrap) tipWrap.style.display = '';
      setText('tpCoachesTipText', '😴 Rest Day — recover well, stay hydrated, and sleep early.');
      return;
    }

    /* ── Exercises in Fitness Section ── */
    el('tpFitnessSection')?.classList.remove('tp-hidden');
    setText('tpFitnessDur', day.duration_minutes ? day.duration_minutes + ' min' : '—');

    /* Rename section header to workout focus */
    const fitNameEl = el('tpFitnessSection')?.querySelector('.tp-section-name');
    if (fitNameEl) fitNameEl.textContent = day.focus || day.type || 'Workout';

    const fitCard = el('tpFitnessCard');
    if (fitCard) {
      if (!exercises.length) {
        fitCard.innerHTML = '<p style="color:#888;font-size:14px;padding:12px 0">No exercises listed for this session.</p>';
      } else {
        fitCard.innerHTML = exercises.map((ex, i) => {
          const chips = [];
          if (ex.sets)             chips.push(`<span class="tp-skill-chip tp-skill-chip--fitness">${escHtml(String(ex.sets))} sets</span>`);
          if (ex.reps_or_duration) chips.push(`<span class="tp-skill-chip tp-skill-chip--fitness">${escHtml(ex.reps_or_duration)}</span>`);
          if (ex.rest_seconds)     chips.push(`<span class="tp-skill-chip tp-skill-chip--rest">Rest ${escHtml(String(ex.rest_seconds))}s</span>`);
          const metaHtml = chips.length ? `<div class="tp-skill-meta">${chips.join('')}</div>` : '';

          const tipText = ex.tip || ex.notes || '';
          const tipHtml = tipText ? `
            <div class="tp-skill-cue tp-skill-cue--fitness">
              <p class="tp-skill-cue-label">Tip</p>
              <p class="tp-skill-cue-text">${escHtml(tipText)}</p>
            </div>` : '';

          const sep = i > 0
            ? '<hr style="border:none;border-top:1px solid rgba(255,255,255,0.06);margin:14px 0">'
            : '';

          return sep
            + `<p class="tp-skill-name">${escHtml(ex.name || ('Exercise ' + (i + 1)))}</p>`
            + metaHtml
            + tipHtml;
        }).join('');
      }

      /* ── Expert note block — shown directly inside the workout card ── */
      if (expertNote) {
        const noteBlock = document.createElement('div');
        noteBlock.id = 'tpExpertNoteBlock';
        noteBlock.style.cssText =
          'margin-top:14px;padding:12px 14px;border-radius:10px;' +
          'background:rgba(99,102,241,0.08);border:1px solid rgba(99,102,241,0.22)';
        noteBlock.innerHTML =
          '<p style="font-size:11px;font-weight:700;color:#818CF8;' +
              'text-transform:uppercase;letter-spacing:0.06em;margin:0 0 5px 0">' +
            '💬 Expert Note' +
          '</p>' +
          '<p style="font-size:14px;color:var(--text-1,#E5E7EB);margin:0;line-height:1.55">' +
            escHtml(expertNote) +
          '</p>';
        fitCard.appendChild(noteBlock);
      }
    }

    /* ── Coach's Tip ── */
    const tipWrap = el('tpCoachesTip');
    if (day.daily_tip) {
      if (tipWrap) tipWrap.style.display = '';
      setText('tpCoachesTipText', day.daily_tip);
    } else {
      if (tipWrap) tipWrap.style.display = 'none';
    }
  }

  /* ══════════════════════════════════════════
     ERROR STATE
  ══════════════════════════════════════════ */
  function showError() {
    const loadEl = el('tpLoading');
    if (loadEl) loadEl.innerHTML = `
      <span style="font-size:32px">⚠️</span>
      <p style="color:#B5B5B5;font-size:14px">No training plan found.<br>Complete the assessment to generate your plan.</p>
      <button onclick="goBack()" style="margin-top:16px;padding:12px 24px;background:#141414;border:1px solid #262626;border-radius:10px;color:#fff;font-size:14px;font-weight:700;cursor:pointer;">← Go Back</button>`;
  }

  /* ══════════════════════════════════════════
     UTILS
  ══════════════════════════════════════════ */
  function el(id) { return document.getElementById(id); }

  function setText(id, val) {
    const e = el(id);
    if (e) e.textContent = val;
  }

  function formatDate(dateStr) {
    if (!dateStr) return '—';
    try {
      const d = new Date(dateStr);
      return d.toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' });
    } catch { return dateStr; }
  }

  function escHtml(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* ══════════════════════════════════════════
     NAVIGATION
  ══════════════════════════════════════════ */
  window.goBack = function () {
    if (window.history.length > 1) {
      history.back();
    } else {
      window.location.href = '../weekly-plan/weekly-plan.html';
    }
  };

  /* ══════════════════════════════════════════
     BOOT
  ══════════════════════════════════════════ */
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
