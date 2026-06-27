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

  function showToast(msg) {
    var t = document.getElementById('mpToast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(function () { t.classList.remove('show'); }, 2600);
  }

  /* ── Render ── */

  function getMealsFromDay(day) {
    /* diet plan days have meals either as day.meals.breakfast or day.breakfast etc. */
    var meals = day.meals || day;
    return meals;
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
          _edited:   edited ? true : undefined,
        });
        if (!edited) delete meals[mealKey]._edited;
      });

      days.push(Object.assign({}, origDay, { day: dayLabel, meals: meals }));
    });
    return { days: days };
  }

  /* ── Build mealChangeHistory ── */

  function buildHistory(editedPlan, expertName) {
    var history = [];
    editedPlan.days.forEach(function (newDay, di) {
      var origDay   = origDays[di] || {};
      var origMeals = getMealsFromDay(origDay);
      var newMeals  = newDay.meals || {};

      Object.keys(newMeals).forEach(function (mealKey) {
        var newMeal = newMeals[mealKey];
        var origMeal = origMeals[mealKey] || {};
        if (newMeal._edited) {
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
        }
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
        savedAt:            new Date().toISOString(),
      });

      showToast('Changes saved!');
      saveBtn.style.display     = 'none';
      completeBtn.style.display = 'block';
    });

    /* Complete Review */
    completeBtn.addEventListener('click', function () {
      var expertName  = (expert && expert.name) || 'Expert';
      var convId      = (expert && expert.id) || '';
      var athleteName = review.athleteName || review.userName || 'Athlete';

      patchReview(reviewId, {
        status:          'completed',
        reviewedAt:      new Date().toISOString(),
        expertName:      expertName,
        athleteAccepted: false,
      });

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

      /* Flag dashboard to auto-open chat on return */
      try {
        sessionStorage.setItem('ed_open_chat', JSON.stringify({ convId: convId, athleteName: athleteName }));
      } catch (_) {}

      showToast('✅ Review sent to athlete!');
      setTimeout(function () { window.location.href = 'expert-dashboard.html'; }, 1200);
    });
  }

  document.addEventListener('DOMContentLoaded', init);
})();
