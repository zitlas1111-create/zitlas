(function () {
  'use strict';

  var reviewId = new URLSearchParams(window.location.search).get('reviewId');
  var expert   = null;
  var review   = null;
  var origWeekly = [];  /* original weekly_plan array */

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

  function extractWeekly(planData) {
    if (!planData) return [];
    if (planData.currentWorkoutPlan || planData.originalWorkoutPlan) {
      var inner = planData.currentWorkoutPlan || planData.originalWorkoutPlan;
      return inner.weekly_plan || inner.days || [];
    }
    return planData.weekly_plan || planData.days || [];
  }

  function showToast(msg) {
    var t = document.getElementById('mpToast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(function () { t.classList.remove('show'); }, 2600);
  }

  /* ── Render ── */

  function renderPlan(weeklyPlan) {
    var body = document.getElementById('mpBody');
    if (!body) return;
    body.innerHTML = '';

    if (!weeklyPlan.length) {
      body.innerHTML = '<p style="padding:24px;text-align:center;color:var(--text-muted)">No workout days found in this review.</p>';
      return;
    }

    weeklyPlan.forEach(function (day, di) {
      var card = document.createElement('div');
      card.className = 'mp-day-card';
      card.dataset.di = di;

      var exRows = (day.exercises || []).map(function (ex) {
        return '<div class="mp-ex-row">' +
          '<input class="mp-input mp-ex-name" placeholder="Exercise name" value="' + esc(ex.name) + '"/>' +
          '<input class="mp-input mp-ex-sets" type="number" min="1" placeholder="Sets" value="' + esc(ex.sets) + '"/>' +
          '<input class="mp-input mp-ex-reps" placeholder="Reps / Duration" value="' + esc(ex.reps_or_duration) + '"/>' +
          '<button class="mp-ex-remove" aria-label="Remove exercise">✕</button>' +
          '</div>';
      }).join('');

      card.innerHTML =
        '<div class="mp-day-label">' + esc(day.day || ('Day ' + (di + 1))) + '</div>' +
        '<div class="mp-field-row">' +
          '<span class="mp-label">Focus</span>' +
          '<input class="mp-input mp-focus" placeholder="e.g. Upper Body" value="' + esc(day.focus) + '"/>' +
        '</div>' +
        '<div class="mp-field-row">' +
          '<span class="mp-label">Duration</span>' +
          '<input class="mp-input mp-input--short mp-duration" type="number" min="1" placeholder="45" value="' + esc(day.duration_minutes) + '"/>' +
          '<span style="font-size:12px;color:var(--text-muted);margin-left:4px">min</span>' +
        '</div>' +
        '<div class="mp-exercises-label">Exercises</div>' +
        '<div class="mp-ex-cols">' +
          '<span class="mp-ex-col-label">Name</span>' +
          '<span class="mp-ex-col-label">Sets</span>' +
          '<span class="mp-ex-col-label">Reps / Duration</span>' +
          '<span></span>' +
        '</div>' +
        '<div class="mp-ex-list">' + exRows + '</div>' +
        '<button class="mp-add-ex">+ Add Exercise</button>';

      /* Remove buttons */
      card.querySelectorAll('.mp-ex-remove').forEach(function (btn) {
        btn.addEventListener('click', function () { btn.closest('.mp-ex-row').remove(); });
      });

      /* Add exercise */
      card.querySelector('.mp-add-ex').addEventListener('click', function () {
        var row = document.createElement('div');
        row.className = 'mp-ex-row';
        row.innerHTML =
          '<input class="mp-input mp-ex-name" placeholder="Exercise name" value=""/>' +
          '<input class="mp-input mp-ex-sets" type="number" min="1" placeholder="Sets" value=""/>' +
          '<input class="mp-input mp-ex-reps" placeholder="Reps / Duration" value=""/>' +
          '<button class="mp-ex-remove" aria-label="Remove exercise">✕</button>';
        row.querySelector('.mp-ex-remove').addEventListener('click', function () { row.remove(); });
        card.querySelector('.mp-ex-list').appendChild(row);
        row.querySelector('.mp-ex-name').focus();
      });

      body.appendChild(card);
    });
  }

  /* ── Collect form → edited plan ── */

  function collectEdited() {
    var days = [];
    document.querySelectorAll('.mp-day-card').forEach(function (card, di) {
      var orig      = origWeekly[di] || {};
      var focus     = (card.querySelector('.mp-focus')    || {}).value    || '';
      var durStr    = (card.querySelector('.mp-duration') || {}).value    || '';
      var exercises = [];
      card.querySelectorAll('.mp-ex-row').forEach(function (row) {
        var name = ((row.querySelector('.mp-ex-name') || {}).value || '').trim();
        var sets = ((row.querySelector('.mp-ex-sets') || {}).value || '').trim();
        var reps = ((row.querySelector('.mp-ex-reps') || {}).value || '').trim();
        if (name) {
          exercises.push({ name: name, sets: sets ? parseInt(sets) : 0, reps_or_duration: reps });
        }
      });
      days.push({
        day:              orig.day || ('Day ' + (di + 1)),
        focus:            focus.trim() || orig.focus || '',
        duration_minutes: durStr ? parseInt(durStr) : (orig.duration_minutes || 0),
        exercises:        exercises,
      });
    });
    return { weekly_plan: days };
  }

  /* ── Build workoutChangeHistory ── */

  function buildHistory(editedPlan, expertName) {
    var history = [];
    editedPlan.weekly_plan.forEach(function (newDay, i) {
      var oldDay  = origWeekly[i] || {};
      var changed = newDay.focus !== (oldDay.focus || '') ||
        String(newDay.duration_minutes) !== String(oldDay.duration_minutes || '') ||
        JSON.stringify(newDay.exercises) !== JSON.stringify(oldDay.exercises || []);
      if (changed) {
        history.push({
          dayIndex:   i,
          dayName:    newDay.day,
          modifiedBy: expertName || 'Expert',
          modifiedAt: new Date().toISOString(),
          oldWorkout: {
            focus:              oldDay.focus || '',
            duration_minutes:   oldDay.duration_minutes || 0,
            exercises:          oldDay.exercises || [],
          },
          newWorkout: {
            focus:              newDay.focus,
            duration_minutes:   newDay.duration_minutes,
            exercises:          newDay.exercises,
          },
        });
      }
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

    /* Show athlete name */
    var athleteEl = document.getElementById('mpAthleteName');
    if (athleteEl) athleteEl.textContent = review.athleteName || review.userName || 'Athlete';

    /* Extract original plan */
    origWeekly = extractWeekly(review.planData);

    /* If expert already saved once, show their saved version */
    if (review.reviewedWorkoutPlan && review.reviewedWorkoutPlan.weekly_plan) {
      origWeekly = review.reviewedWorkoutPlan.weekly_plan;
    }

    renderPlan(origWeekly);

    /* Back */
    document.getElementById('mpBack').addEventListener('click', function () {
      window.location.href = 'expert-dashboard.html';
    });

    var saveBtn     = document.getElementById('mpSave');
    var completeBtn = document.getElementById('mpComplete');

    /* Save Changes */
    saveBtn.addEventListener('click', function () {
      var edited      = collectEdited();
      var expertName  = (expert && expert.name) || 'Expert';
      var history     = buildHistory(edited, expertName);

      patchReview(reviewId, {
        reviewedWorkoutPlan:  edited,
        workoutChangeHistory: history,
        savedAt:              new Date().toISOString(),
      });

      if (typeof ZitlasDB !== 'undefined') {
        ZitlasDB.collection('review_requests').doc(reviewId).update({
          reviewedWorkoutPlan:  edited,
          workoutChangeHistory: history,
          savedAt:              new Date().toISOString(),
        }).catch(function (e) { console.warn('[MODIFY-WORKOUT] Firestore save sync failed:', e); });
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
        status:               'review_completed',
        reviewedAt:           nowIso,
        completedAt:          nowIso,
        expertName:           expertName,
        expertId:             expertId,
        athleteAccepted:      false,
      });

      if (typeof ZitlasDB !== 'undefined') {
        var _fsPayload = {
          status:               'review_completed',
          reviewedAt:           nowIso,
          completedAt:          nowIso,
          expertName:           expertName,
          expertId:             expertId,
          reviewedWorkoutPlan:  _latest.reviewedWorkoutPlan  || null,
          workoutChangeHistory: _latest.workoutChangeHistory || [],
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
            text:       '✅ Review Completed — ' + expertName + ' has finished reviewing your workout plan. Open your plan to accept the changes.',
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
