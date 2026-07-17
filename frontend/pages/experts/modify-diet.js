(function () {
  'use strict';

  var reviewId   = new URLSearchParams(window.location.search).get('reviewId');
  var expert     = null;
  var review     = null;
  var origDays   = [];   /* original plan days array */

  var MEAL_KEYS   = ['breakfast', 'morning_snack', 'lunch', 'afternoon_snack', 'dinner', 'snacks'];
  var MEAL_EMOJIS = { breakfast: '🌅', morning_snack: '🍎', lunch: '☀️', afternoon_snack: '🥜', dinner: '🌙', snacks: '🍌' };

  /* ── Helpers ── */

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function getExpert() {
    try { return JSON.parse(sessionStorage.getItem('zitlas_modify_expert') || 'null'); } catch (_) { return null; }
  }

  function getReview(id) {
    try {
      var all = JSON.parse(localStorage.getItem('expert_plan_reviews') || '[]');
      return all.find(function (r) { return r.id === id; }) || null;
    } catch (_) { return null; }
  }

  function patchReview(id, fields) {
    try {
      var all = JSON.parse(localStorage.getItem('expert_plan_reviews') || '[]');
      var idx = all.findIndex(function (r) { return r.id === id; });
      if (idx !== -1) {
        all[idx] = Object.assign({}, all[idx], fields);
        localStorage.setItem('expert_plan_reviews', JSON.stringify(all));
      }
    } catch (_) {}
  }

  function extractDays(planData) {
    if (!planData) return [];
    if (planData.originalDietPlan || planData.currentDietPlan) {
      var inner = planData.currentDietPlan || planData.originalDietPlan;
      return inner.days || [];
    }
    return planData.days || [];
  }

  function normalizeFoods(foods) {
    if (!foods) return [];
    if (Array.isArray(foods)) return foods.map(function (f) { return typeof f === 'string' ? f : (f.name || f.item || String(f)); });
    if (typeof foods === 'string') return foods.split('\n').filter(Boolean);
    return [];
  }

  function mealKeyName(key) {
    return key.replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  /* Mirrors diet.js's _mealKey() exactly — must produce identical keys so
     the athlete-side accept flow can match meals by key. */
  function _mealKeyOf(name) {
    return (name || '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '_');
  }

  function showToast(msg) {
    var t = document.getElementById('mpToast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(function () { t.classList.remove('show'); }, 2600);
  }

  /* ── Render ── */

  function getMealsFromDay(day) {
    /* Canonical schema (AI plan + expert-dashboard.js editor) stores
       days[].meals as an ARRAY of meal objects, not an object keyed by
       meal name. Normalize to a keyed object here for internal
       rendering/diffing regardless of which shape the source data is in —
       older reviews saved before this fix may still be object-shaped. */
    var meals = day.meals || day;
    if (Array.isArray(meals)) {
      var keyed = {};
      meals.forEach(function (m) {
        keyed[m._mealKey || _mealKeyOf(m.meal_name || m.name)] = m;
      });
      return keyed;
    }
    return meals;
  }

  /* ── Athlete context panel ──
     Renders everything the ZITLAS assessment knows about this athlete so
     the expert reviews the plan in context (who is this person, what's
     their goal, what are their restrictions/targets) instead of editing
     meals blind. Data comes from the snapshot the request itself carries:
     profileBasics + assessmentData (paid cprofile flow) or context
     (diet-page flow) — older requests that predate those fields simply
     render fewer rows. NOTE: deliberately NOT class mp-day-card —
     collectEdited() iterates .mp-day-card and must never see this. */
  function _ctxRow(label, value) {
    if (value == null || value === '' || (Array.isArray(value) && !value.length)) return '';
    var v = Array.isArray(value) ? value.join(', ') : String(value);
    return '<div class="mp-ctx-row"><span class="mp-ctx-label">' + esc(label) + '</span>' +
           '<span class="mp-ctx-value">' + esc(v) + '</span></div>';
  }
  function _ctxSection(title, rowsHtml) {
    if (!rowsHtml) return '';
    return '<div class="mp-ctx-section"><p class="mp-ctx-title">' + esc(title) + '</p>' + rowsHtml + '</div>';
  }
  function _pick(obj, keys) {
    if (!obj) return null;
    for (var i = 0; i < keys.length; i++) {
      var v = obj[keys[i]];
      if (v != null && v !== '') return v;
    }
    return null;
  }

  function buildContextPanel(review) {
    var ad   = review.assessmentData || {};
    var ctx  = review.context || {};
    var assess = ad.assessment || ctx.assessment || {};
    var p    = Object.assign({}, assess, review.profileBasics || {});
    var calc = ad.calculations || ctx.calculations || {};
    var goal = review.goal || {};

    var userRows =
      _ctxRow('Name',   review.athleteName || review.userName || review.athlete_name) +
      _ctxRow('Age',    p.age) +
      _ctxRow('Gender', p.gender) +
      _ctxRow('Height', p.height_cm ? p.height_cm + ' cm' : null) +
      _ctxRow('Weight', p.weight_kg ? p.weight_kg + ' kg' : null) +
      _ctxRow('Goal Weight', p.goal_weight_kg ? p.goal_weight_kg + ' kg' : null) +
      _ctxRow('Occupation', _pick(p, ['occupation', 'living_situation']));

    var goalRows =
      _ctxRow('Goal', goal.type || _pick(p, ['fitness_goal', 'transformation_goal'])) +
      _ctxRow('Current → Target', (goal.currentVal != null && goal.targetVal != null)
        ? goal.currentVal + ' → ' + goal.targetVal + ' ' + (goal.unit || '') : null) +
      _ctxRow('Duration', p.goal_duration_months ? p.goal_duration_months + ' months' : null) +
      _ctxRow('Target Body Fat', p.target_body_fat_pct ? p.target_body_fat_pct + '%' : null) +
      _ctxRow('Biggest Struggle', p.biggest_struggle);

    var assessRows =
      _ctxRow('Activity Level',  p.activity_level) +
      _ctxRow('Fitness Level',   p.fitness_level) +
      _ctxRow('Diet Preference', p.diet_preference) +
      _ctxRow('Workout Preference', p.workout_preference) +
      _ctxRow('Available Time',  p.available_time) +
      _ctxRow('Sleep',  _pick(p, ['sleep_hours', 'sleep', 'sleepHours'])) +
      _ctxRow('Stress Level', p.stress_level) +
      _ctxRow('Budget', _pick(p, ['budget', 'daily_budget'])) +
      _ctxRow('⚕️ Medical Conditions', _pick(p, ['medical_conditions', 'health_conditions']) || 'None reported');

    var targetRows =
      _ctxRow('BMI',  _pick(calc, ['bmi'])) +
      _ctxRow('BMR',  _pick(calc, ['bmr']) ? _pick(calc, ['bmr']) + ' kcal' : null) +
      _ctxRow('TDEE', _pick(calc, ['tdee']) ? _pick(calc, ['tdee']) + ' kcal' : null) +
      _ctxRow('Calorie Target', _pick(calc, ['daily_calories', 'calorie_target', 'target_calories', 'calories'])) +
      _ctxRow('Protein Target', _pick(calc, ['protein_target', 'protein_g', 'daily_protein', 'protein'])) +
      _ctxRow('Water Target',   _pick(calc, ['water_liters', 'water_target', 'hydration_liters'])) +
      _ctxRow('Steps Target',   _pick(calc, ['daily_steps', 'steps_target', 'steps']));

    var html =
      _ctxSection('👤 Athlete Information', userRows) +
      _ctxSection('🎯 Goal Summary', goalRows) +
      _ctxSection('📋 Assessment Summary', assessRows) +
      _ctxSection('🧮 Nutrition Targets', targetRows);
    if (!html) return null;

    var panel = document.createElement('div');
    panel.className = 'mp-ctx-panel';
    panel.innerHTML =
      '<div class="mp-ctx-head">' +
        '<span>Athlete Profile &amp; Assessment</span>' +
        '<button class="mp-ctx-toggle" id="mpCtxToggle" type="button">Hide</button>' +
      '</div>' +
      '<div class="mp-ctx-body" id="mpCtxBody">' + html + '</div>';
    panel.querySelector('#mpCtxToggle').addEventListener('click', function () {
      var b = panel.querySelector('#mpCtxBody');
      var hidden = b.style.display === 'none';
      b.style.display = hidden ? '' : 'none';
      this.textContent = hidden ? 'Hide' : 'Show';
    });
    return panel;
  }

  function buildNotesPanel(review) {
    var wrap = document.createElement('div');
    wrap.className = 'mp-notes-panel';
    wrap.innerHTML =
      '<p class="mp-ctx-title">📝 Review Notes for the Athlete</p>' +
      '<textarea class="mp-notes-input" id="mpNotes" rows="3" ' +
        'placeholder="Optional — explain your changes, add guidance (the athlete sees this with the reviewed plan)…"></textarea>';
    wrap.querySelector('#mpNotes').value = review.expertNotes || '';
    return wrap;
  }
  function getExpertNotes() {
    var el = document.getElementById('mpNotes');
    return el ? el.value.trim() : '';
  }

  function renderPlan(days) {
    var body = document.getElementById('mpBody');
    if (!body) return;
    body.innerHTML = '';

    if (!days.length) {
      body.innerHTML = '<p style="padding:24px;text-align:center;color:var(--text-muted)">No diet days found in this review.</p>';
      return;
    }

    days.forEach(function (day, di) {
      var card = document.createElement('div');
      card.className = 'mp-day-card';
      card.dataset.di = di;

      var dayLabel = day.day || day.date || ('Day ' + (di + 1));
      var meals    = getMealsFromDay(day);

      var mealsHtml = '';
      var mealKeysInDay = MEAL_KEYS.filter(function (k) { return meals[k]; });
      /* Fallback: if no standard keys found, gather any key that looks like a meal */
      if (!mealKeysInDay.length) {
        mealKeysInDay = Object.keys(meals).filter(function (k) { return meals[k] && typeof meals[k] === 'object' && !Array.isArray(meals[k]); });
      }

      mealKeysInDay.forEach(function (mealKey, mi) {
        var meal  = meals[mealKey] || {};
        var emoji = MEAL_EMOJIS[mealKey] || '🍽️';
        var name  = meal.meal_name || mealKeyName(mealKey);
        var foods = normalizeFoods(meal.foods);

        var foodRows = foods.map(function (food) {
          return '<div class="mp-food-row">' +
            '<input class="mp-food-input" placeholder="Food item" value="' + esc(food) + '"/>' +
            '<button class="mp-food-remove" aria-label="Remove">✕</button>' +
            '</div>';
        }).join('');

        mealsHtml +=
          '<div class="mp-meal-block" data-meal-key="' + esc(mealKey) + '">' +
            '<div class="mp-meal-header">' +
              '<span class="mp-meal-emoji">' + emoji + '</span>' +
              '<input class="mp-meal-name-input" data-field="meal_name" placeholder="Meal name" value="' + esc(name) + '"/>' +
            '</div>' +
            '<div class="mp-foods-list">' + foodRows + '</div>' +
            '<button class="mp-add-food">+ Add food</button>' +
            (mi < mealKeysInDay.length - 1 ? '<div class="mp-meal-divider"></div>' : '') +
          '</div>';
      });

      card.innerHTML = '<div class="mp-day-label">' + esc(dayLabel) + '</div>' + mealsHtml;

      /* Wire remove food buttons */
      card.querySelectorAll('.mp-food-remove').forEach(function (btn) {
        btn.addEventListener('click', function () { btn.closest('.mp-food-row').remove(); });
      });

      /* Wire add food buttons */
      card.querySelectorAll('.mp-add-food').forEach(function (addBtn) {
        addBtn.addEventListener('click', function () {
          var row = document.createElement('div');
          row.className = 'mp-food-row';
          row.innerHTML =
            '<input class="mp-food-input" placeholder="Food item" value=""/>' +
            '<button class="mp-food-remove" aria-label="Remove">✕</button>';
          row.querySelector('.mp-food-remove').addEventListener('click', function () { row.remove(); });
          addBtn.closest('.mp-meal-block').querySelector('.mp-foods-list').appendChild(row);
          row.querySelector('.mp-food-input').focus();
        });
      });

      body.appendChild(card);
    });
  }

  /* ── Collect form → edited plan ── */

  function collectEdited() {
    var days = [];
    document.querySelectorAll('.mp-day-card').forEach(function (card, di) {
      var origDay = origDays[di] || {};
      var dayLabel = origDay.day || origDay.date || ('Day ' + (di + 1));
      var origMeals = getMealsFromDay(origDay);
      var meals = {};

      card.querySelectorAll('.mp-meal-block').forEach(function (block) {
        var mealKey = block.dataset.mealKey;
        if (!mealKey) return;
        var nameInput = block.querySelector('[data-field="meal_name"]');
        var mealName  = nameInput ? nameInput.value.trim() : mealKeyName(mealKey);
        var origMeal  = origMeals[mealKey] || {};
        var foods     = [];
        block.querySelectorAll('.mp-food-input').forEach(function (inp) {
          var v = inp.value.trim();
          if (v) foods.push(v);
        });

        var edited = JSON.stringify(foods) !== JSON.stringify(normalizeFoods(origMeal.foods)) ||
                     mealName !== (origMeal.meal_name || mealKeyName(mealKey));

        meals[mealKey] = Object.assign({}, origMeal, {
          meal_name: mealName,
          foods:     foods,
          _mealKey:  mealKey,
          _edited:   edited ? true : undefined,
        });
        if (!edited) delete meals[mealKey]._edited;
      });

      /* Canonical schema: days[].meals is an ARRAY (matches the AI-generated
         plan and expert-dashboard.js's editor) — not an object keyed by
         meal name. This is what the athlete-side acceptExpertPlan() and
         _buildDietStorageFromReview() expect; saving an object here was
         the root cause of the "(revDay.meals || []).forEach is not a
         function" crash on accept. */
      var mealsArray = Object.keys(meals).map(function (k) { return meals[k]; });
      days.push(Object.assign({}, origDay, { day: dayLabel, meals: mealsArray }));
    });
    return { days: days };
  }

  /* ── Build mealChangeHistory ── */

  function buildHistory(editedPlan, expertName) {
    var history = [];
    editedPlan.days.forEach(function (newDay, di) {
      var origDay     = origDays[di] || {};
      var origMeals   = getMealsFromDay(origDay);
      var newMealsArr = Array.isArray(newDay.meals) ? newDay.meals : [];

      newMealsArr.forEach(function (newMeal) {
        if (!newMeal._edited) return;
        var mealKey  = newMeal._mealKey || _mealKeyOf(newMeal.meal_name);
        var origMeal = origMeals[mealKey] || {};
        history.push({
          dayIndex:   di,
          dayName:    newDay.day || ('Day ' + (di + 1)),
          mealKey:    mealKey,
          mealName:   newMeal.meal_name || mealKeyName(mealKey),
          modifiedBy: expertName || 'Expert',
          modifiedAt: new Date().toISOString(),
          oldMeal:    origMeal,
          newMeal:    newMeal,
        });
      });
    });
    return history;
  }

  /* ── Init ── */

  function init() {
    if (!reviewId) {
      document.body.innerHTML = '<p style="padding:32px;color:var(--text-muted)">No review ID in URL.</p>';
      return;
    }

    expert = getExpert();
    review = getReview(reviewId);

    if (!review) {
      document.body.innerHTML = '<p style="padding:32px;color:var(--text-muted)">Review not found.</p>';
      return;
    }

    var athleteEl = document.getElementById('mpAthleteName');
    if (athleteEl) athleteEl.textContent = review.athleteName || review.userName || 'Athlete';

    origDays = extractDays(review.planData);

    /* If expert already saved, use their saved version */
    if (review.reviewedDietPlan && review.reviewedDietPlan.days) {
      origDays = review.reviewedDietPlan.days;
    }

    renderPlan(origDays);

    /* Athlete context above the plan, Review Notes below it — both inside
       the scroll container, both outside collectEdited()'s .mp-day-card
       query so plan collection is untouched. */
    var _mpBody = document.getElementById('mpBody');
    if (_mpBody) {
      var _ctxPanel = buildContextPanel(review);
      if (_ctxPanel) _mpBody.insertBefore(_ctxPanel, _mpBody.firstChild);
      _mpBody.appendChild(buildNotesPanel(review));
    }

    document.getElementById('mpBack').addEventListener('click', function () {
      window.location.href = 'expert-dashboard.html';
    });

    var saveBtn     = document.getElementById('mpSave');
    var completeBtn = document.getElementById('mpComplete');

    /* Save Changes */
    saveBtn.addEventListener('click', function () {
      var expertName  = (expert && expert.name) || 'Expert';
      var edited      = collectEdited();
      var history     = buildHistory(edited, expertName);

      patchReview(reviewId, {
        reviewedDietPlan:   edited,
        mealChangeHistory:  history,
        expertNotes:        getExpertNotes(),
        savedAt:            new Date().toISOString(),
      });

      if (typeof ZitlasDB !== 'undefined') {
        ZitlasDB.collection('review_requests').doc(reviewId).update({
          reviewedDietPlan:  edited,
          mealChangeHistory: history,
          expertNotes:       getExpertNotes(),
          savedAt:           new Date().toISOString(),
        }).catch(function (e) { console.warn('[MODIFY-DIET] Firestore save sync failed:', e); });
      }

      showToast('Changes saved!');
      saveBtn.style.display     = 'none';
      completeBtn.style.display = 'block';
    });

    /* Complete Review */
    completeBtn.addEventListener('click', function () {
      console.log('[COMPLETE REVIEW] button clicked');
      var expertName  = (expert && expert.name) || 'Expert';
      var expertId    = (expert && expert.id) || review.expertId || '';
      var convId      = (expert && expert.id) || '';
      var athleteName = review.athleteName || review.userName || 'Athlete';
      var nowIso      = new Date().toISOString();

      var _latest = getReview(reviewId) || review;

      patchReview(reviewId, {
        status:          'review_completed',
        reviewedAt:      nowIso,
        completedAt:     nowIso,
        expertName:      expertName,
        expertId:        expertId,
        expertNotes:     getExpertNotes(),
        athleteAccepted: false,
      });

      if (typeof ZitlasDB !== 'undefined') {
        var _fsPayload = {
          status:            'review_completed',
          reviewedAt:        nowIso,
          completedAt:       nowIso,
          expertName:        expertName,
          expertId:          expertId,
          expertNotes:       getExpertNotes(),
          reviewedDietPlan:  _latest.reviewedDietPlan  || null,
          mealChangeHistory: _latest.mealChangeHistory || [],
        };
        console.log('[COMPLETE REVIEW] reviewId', reviewId);
        console.log('[COMPLETE REVIEW] payload', _fsPayload);
        console.log('[COMPLETE REVIEW] before firestore update');
        ZitlasDB.collection('review_requests').doc(reviewId).update(_fsPayload)
          .then(function () { console.log('[COMPLETE REVIEW] firestore update success'); })
          .catch(function (err) {
            console.error('[COMPLETE REVIEW] firestore update failed', err);
            showToast('⚠️ Could not sync to server — athlete may not see this update.');
          });
      } else {
        console.error('[COMPLETE REVIEW] ZitlasDB unavailable — completion saved to localStorage only');
      }

      /* Append system message to chat */
      try {
        var chats = JSON.parse(localStorage.getItem('zitlas_chats') || '{}');
        if (convId && chats[convId]) {
          chats[convId].messages = chats[convId].messages || [];
          chats[convId].messages.push({
            id:         'sys_complete_' + Date.now(),
            senderType: 'system',
            type:       'review_complete',
            text:       '✅ Review Completed — ' + expertName + ' has finished reviewing your diet plan. Open your plan to accept the changes.',
            timestamp:  new Date().toISOString(),
          });
          localStorage.setItem('zitlas_chats', JSON.stringify(chats));
        }
      } catch (_) {}

      try {
        sessionStorage.setItem('ed_open_chat', JSON.stringify({ convId: convId, athleteName: athleteName }));
      } catch (_) {}

      showToast('✅ Review sent to athlete!');
      setTimeout(function () { window.location.href = 'expert-dashboard.html'; }, 1200);
    });
  }

  document.addEventListener('DOMContentLoaded', init);
})();
