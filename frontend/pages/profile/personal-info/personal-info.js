/* =============================================
   ZITLAS Personal Information — personal-info.js
   ============================================= */

(function () {
  'use strict';

  var THEME_KEY   = 'zitlas_theme';
  var STORAGE_KEY = 'zitlas_personal_info';
  var html        = document.documentElement;

  /* ---- Theme ---- */
  function getSystemTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  function loadTheme() {
    var pref     = localStorage.getItem(THEME_KEY) || 'dark';
    var resolved = pref === 'system' ? getSystemTheme() : pref;
    html.setAttribute('data-theme', resolved);
  }
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
    if ((localStorage.getItem(THEME_KEY) || 'dark') === 'system') loadTheme();
  });

  /* ---- Toast ---- */
  var toastTimer = null;
  function showToast(msg, duration) {
    duration = duration || 2800;
    var el = document.getElementById('toast');
    if (!el) return;
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove('show'); }, duration);
  }

  /* ---- Avatar fallback SVG ---- */
  function avatarFallback(initials) {
    initials = initials || 'ZT';
    return 'data:image/svg+xml,' + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">' +
      '<rect width="96" height="96" rx="48" fill="#FF8A00"/>' +
      '<text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" ' +
      'font-size="36" font-weight="bold" fill="white" font-family="system-ui">' +
      initials + '</text></svg>'
    );
  }

  function loadFormData() {
    var raw  = localStorage.getItem(STORAGE_KEY);
    var data = raw ? JSON.parse(raw) : {};

    /* Photo */
    var photoImg = document.getElementById('photoImg');
    if (photoImg) {
      photoImg.src = (data.photo && data.photo.startsWith('data:'))
        ? data.photo
        : avatarFallback(
            data.fullName
              ? data.fullName.trim().split(/\s+/).slice(0, 2).map(function (w) { return w[0]; }).join('').toUpperCase()
              : 'ZT'
          );
      photoImg.addEventListener('error', function () { photoImg.src = avatarFallback('ZT'); });
    }

    /* Text inputs */
    ['fullName', 'email', 'mobile', 'dob', 'age', 'city', 'state'].forEach(function (id) {
      var el = document.getElementById(id);
      if (el && data[id] != null) el.value = data[id];
    });

    /* Selects */
    ['gender'].forEach(function (id) {
      var el = document.getElementById(id);
      if (el && data[id] != null) el.value = data[id];
    });
  }

  /* ---- DOB → Age auto-calc ---- */
  function initDobAge() {
    var dobEl = document.getElementById('dob');
    var ageEl = document.getElementById('age');
    if (!dobEl || !ageEl) return;

    function computeAge(dobValue) {
      if (!dobValue) { ageEl.value = ''; return; }
      var today = new Date();
      var birth = new Date(dobValue);
      if (isNaN(birth.getTime())) { ageEl.value = ''; return; }
      var age = today.getFullYear() - birth.getFullYear();
      var m   = today.getMonth() - birth.getMonth();
      if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) age--;
      ageEl.value = age >= 0 ? age : '';
    }

    dobEl.addEventListener('change', function () { computeAge(dobEl.value); });
    computeAge(dobEl.value);
  }

  function initPhotoUpload() {
    var input    = document.getElementById('photoInput');
    var photoImg = document.getElementById('photoImg');
    if (!input || !photoImg) return;

    input.addEventListener('change', function (e) {
      var file = e.target.files[0];
      if (!file) return;
      if (!file.type.startsWith('image/')) { showToast(window.ZitlasLang ? ZitlasLang.t('toast_select_image') : 'Please select an image file'); return; }
      var reader = new FileReader();
      reader.onload = function (ev) { photoImg.src = ev.target.result; };
      reader.readAsDataURL(file);
    });
  }

  function setError(el) {
    el.classList.add('input-error');
    el.addEventListener('animationend', function () { el.classList.remove('input-error'); }, { once: true });
  }

  function validate() {
    var ok      = true;
    var nameEl  = document.getElementById('fullName');
    var emailEl = document.getElementById('email');

    if (!nameEl || !nameEl.value.trim()) {
      if (nameEl) setError(nameEl);
      ok = false;
    }
    if (emailEl && emailEl.value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailEl.value.trim())) {
      setError(emailEl);
      ok = false;
    }
    return ok;
  }

  function initSaveBtn() {
    var btn = document.getElementById('saveBtn');
    if (!btn) return;

    btn.addEventListener('click', function () {
      if (!validate()) {
        showToast(window.ZitlasLang ? ZitlasLang.t('toast_enter_name') : 'Please enter your full name');
        var nameEl = document.getElementById('fullName');
        if (nameEl) nameEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return;
      }

      var raw      = localStorage.getItem(STORAGE_KEY);
      var existing = raw ? JSON.parse(raw) : {};

      var photoImg     = document.getElementById('photoImg');
      var photoSrc     = photoImg ? photoImg.src : '';
      var photoToStore = photoSrc.startsWith('data:') ? photoSrc : (existing.photo || '');

      function val(id) { var el = document.getElementById(id); return el ? el.value : ''; }

      var data = Object.assign({}, existing, {
        photo:    photoToStore,
        fullName: val('fullName').trim(),
        email:    val('email').trim(),
        mobile:   val('mobile').trim(),
        dob:      val('dob'),
        age:      val('age'),
        gender:   val('gender'),
        city:     val('city').trim(),
        state:    val('state').trim(),
      });

      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
      } catch (_) {
        showToast(window.ZitlasLang ? ZitlasLang.t('toast_storage_full') : 'Could not save — storage full');
        return;
      }

      btn.textContent = window.ZitlasLang ? ZitlasLang.t('btn_saved') : 'Saved!';
      btn.classList.add('save-btn--success');
      setTimeout(function () {
        btn.textContent = window.ZitlasLang ? ZitlasLang.t('btn_save') : 'Save';
        btn.classList.remove('save-btn--success');
      }, 2200);

      showToast(window.ZitlasLang ? ZitlasLang.t('toast_profile_saved') : 'Profile updated successfully');
    });
  }

  /* ---- Scroll-in entrance animations ---- */
  function initEntranceAnimations() {
    var sections = document.querySelectorAll('.form-section');
    if (!sections.length) return;

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          var el  = entry.target;
          var idx = Array.from(sections).indexOf(el);
          el.style.transitionDelay = (idx * 0.06) + 's';
          el.classList.add('visible');
          observer.unobserve(el);
        }
      });
    }, { threshold: 0.06 });

    sections.forEach(function (el) { observer.observe(el); });
  }

  /* ---- INIT ---- */
  function init() {
    loadTheme();
    loadFormData();
    initPhotoUpload();
    initDobAge();
    initSaveBtn();
    requestAnimationFrame(initEntranceAnimations);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
