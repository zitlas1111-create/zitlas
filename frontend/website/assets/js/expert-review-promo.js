/*!
 * ZITLAS — Expert Review Promo Card (assets/js/expert-review-promo.js)
 *
 * "Get Expert Review — ₹149" premium card on the Home Dashboard. Self-
 * mounting: looks for #expertReviewPromoMount and renders itself there —
 * dashboard.js is untouched, same pattern as health-status.js.
 *
 * Replaces the mandatory nutritionist-upsell screen that used to interrupt
 * onboarding (ai-coach.js S8→S9) — this card only ever appears AFTER the
 * user already has an AI plan, and only while there's nothing to upsell:
 * hidden entirely if the user has no plan yet, already has an active/
 * completed review, or is in an active Personal Coaching relationship.
 * Dismissible — closing it snoozes the card for 7 days, not just today.
 */
(function (win) {
  'use strict';

  var DISMISS_KEY = 'zitlas_expert_promo_dismissed_at';
  var SNOOZE_DAYS = 7;

  function $(id) { return document.getElementById(id); }
  function safeJSON(key) {
    try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch (_) { return null; }
  }
  function uid() {
    var fb = safeJSON('zitlas_firebase_user');
    return fb && fb.uid;
  }

  function hasAiPlan() {
    var diet = safeJSON('zitlas_diet_plan');
    var workout = safeJSON('zitlas_workout_plan');
    return !!(diet || workout);
  }

  /* Already-expert-modified plans (isNewDietSchema's isExpertPlan / legacy
     expertName) mean the user already engaged a review for THIS plan —
     don't pitch the same thing again. */
  function alreadyHasExpertPlan() {
    var diet = safeJSON('zitlas_diet_plan');
    var workout = safeJSON('zitlas_workout_plan');
    return !!((diet && diet.isExpertPlan) || (workout && workout.isExpertPlan));
  }

  function isSnoozed() {
    var ts = localStorage.getItem(DISMISS_KEY);
    if (!ts) return false;
    var days = (Date.now() - Number(ts)) / 86400000;
    return days < SNOOZE_DAYS;
  }

  function baseEligible() {
    return hasAiPlan() && !alreadyHasExpertPlan() && !isSnoozed();
  }

  function render() {
    var mount = $('expertReviewPromoMount');
    if (!mount) return;
    if (!baseEligible()) { mount.innerHTML = ''; return; }

    mount.innerHTML =
      '<section class="erp-card" id="erpCard">' +
        '<button class="erp-close" id="erpClose" aria-label="Dismiss">✕</button>' +
        '<div class="erp-head">' +
          '<span class="erp-icon">🩺</span>' +
          '<div class="erp-headtext">' +
            '<span class="erp-title">Get Expert Review</span>' +
            '<span class="erp-sub">A certified expert reviews and personalises your AI plan.</span>' +
          '</div>' +
          '<span class="erp-price">₹149</span>' +
        '</div>' +
        '<ul class="erp-benefits">' +
          '<li><span class="erp-tick">✔</span> Personalised diet adjustments</li>' +
          '<li><span class="erp-tick">✔</span> Workout corrections &amp; form fixes</li>' +
          '<li><span class="erp-tick">✔</span> 30-minute 1-on-1 consultation</li>' +
        '</ul>' +
        '<button class="erp-cta" id="erpCta">Get Expert Review — ₹149 →</button>' +
      '</section>';

    var closeBtn = $('erpClose');
    if (closeBtn) closeBtn.addEventListener('click', function () {
      localStorage.setItem(DISMISS_KEY, String(Date.now()));
      mount.innerHTML = '';
    });
    var ctaBtn = $('erpCta');
    if (ctaBtn) ctaBtn.addEventListener('click', function () {
      window.location.href = '../coaches/coaches.html';
    });
  }

  /* Optional refinement once Firestore is available: an active Personal
     Coaching relationship already covers plan review, so don't also pitch
     a one-off ₹149 review on top of it. Purely additive — render() above
     already handles every case correctly without this running at all. */
  function refineWithCoachingStatus() {
    if (typeof ZitlasDB === 'undefined') return;
    var myUid = uid();
    if (!myUid) return;
    ZitlasDB.collection('personal_coaching').doc(myUid).get().then(function (snap) {
      var rel = snap.exists ? snap.data() : null;
      if (rel && rel.status === 'active') {
        var mount = $('expertReviewPromoMount');
        if (mount) mount.innerHTML = '';
      }
    }).catch(function () {});
  }

  function init() {
    render();
    refineWithCoachingStatus();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  win.ZitlasExpertReviewPromo = { refresh: render };
})(window);
