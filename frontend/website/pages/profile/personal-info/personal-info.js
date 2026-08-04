/* =============================================
   ZITLAS Personal Information — personal-info.js
   ============================================= */

(function () {
  'use strict';

  var THEME_KEY   = 'zitlas_theme';
  var STORAGE_KEY = 'zitlas_personal_info';
  var SURVEY_KEY  = 'zitlas_survey';
  var html        = document.documentElement;

  /* ---- Unit conversion helpers ---- */
  function _cmToFtIn(cm) {
    var totalIn = cm / 2.54;
    var ft      = Math.floor(totalIn / 12);
    var inches  = Math.round(totalIn - ft * 12);
    if (inches === 12) { ft++; inches = 0; }
    return { ft: Math.max(3, Math.min(8, ft)), inches: Math.max(0, Math.min(11, inches)) };
  }
  function _ftInToCm(ft, inches) { return Math.round(ft * 30.48 + inches * 2.54); }
  function _kgToLbs(kg)          { return Math.round(kg * 2.20462); }
  function _lbsToKg(lbs)         { return Math.round(lbs * 0.45359237 * 10) / 10; }

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
      '<rect width="96" height="96" rx="48" fill="var(--primary)"/>' +
      '<text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" ' +
      'font-size="36" font-weight="bold" fill="white" font-family="system-ui">' +
      initials + '</text></svg>'
    );
  }

  function loadFormData() {
    var raw  = localStorage.getItem(STORAGE_KEY);
    var data = raw ? JSON.parse(raw) : {};

    /* Phase 7 — Pre-populate name/email from zitlas_user (Google sign-in) if not yet saved locally */
    try {
      var zUser = JSON.parse(localStorage.getItem('zitlas_user') || '{}');
      if (!data.fullName && zUser.name)  data.fullName = zUser.name;
      if (!data.email    && zUser.email) data.email    = zUser.email;
    } catch (_) {}

    /* Photo — prefer saved base64 photo, then Google photo URL, then initials fallback */
    var photoImg = document.getElementById('photoImg');
    if (photoImg) {
      var googlePhoto = '';
      try {
        var _zu = JSON.parse(localStorage.getItem('zitlas_user') || '{}');
        googlePhoto = _zu.photo || '';
      } catch (_) {}

      if (data.photo && data.photo.startsWith('data:')) {
        photoImg.src = data.photo;
      } else if (googlePhoto && googlePhoto.startsWith('http')) {
        photoImg.src = googlePhoto;
        photoImg.addEventListener('error', function () {
          photoImg.src = avatarFallback(
            data.fullName
              ? data.fullName.trim().split(/\s+/).slice(0, 2).map(function (w) { return w[0]; }).join('').toUpperCase()
              : 'ZT'
          );
        }, { once: true });
      } else {
        photoImg.src = avatarFallback(
          data.fullName
            ? data.fullName.trim().split(/\s+/).slice(0, 2).map(function (w) { return w[0]; }).join('').toUpperCase()
            : 'ZT'
        );
      }
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
      reader.onload = function (ev) {
        /* Compress to an avatar-sized thumbnail (max 512px JPEG) so the
           photo fits in the Firestore personalInfo sync and every device
           on this account shows it — a raw camera photo as base64 would
           exceed the 1 MiB document cap and stay stuck on this device. */
        if (typeof ZitlasCloudSync !== 'undefined' && ZitlasCloudSync.compressImage) {
          ZitlasCloudSync.compressImage(ev.target.result, 512, 0.8)
            .then(function (small) { photoImg.src = small; })
            .catch(function () { photoImg.src = ev.target.result; });
        } else {
          photoImg.src = ev.target.result;
        }
      };
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

  /* ---- Body Metrics helpers ---- */
  function _showHeightUnit(unit, heightCm) {
    var cmWrap = document.getElementById('piHeightCmWrap');
    var ftWrap = document.getElementById('piHeightFtWrap');
    if (!cmWrap || !ftWrap) return;
    if (unit === 'cm') {
      cmWrap.style.display = '';
      ftWrap.style.display = 'none';
      var el = document.getElementById('piHeightCm');
      if (el && heightCm) el.value = Math.round(heightCm);
    } else {
      cmWrap.style.display = 'none';
      ftWrap.style.display = '';
      if (heightCm) {
        var cv = _cmToFtIn(heightCm);
        var ft = document.getElementById('piHeightFt');
        var inches = document.getElementById('piHeightIn');
        if (ft) ft.value = cv.ft;
        if (inches) inches.value = cv.inches;
      }
    }
  }

  function _showWeightUnit(unit, weightKg) {
    var kgWrap  = document.getElementById('piWeightKgWrap');
    var lbsWrap = document.getElementById('piWeightLbsWrap');
    if (!kgWrap || !lbsWrap) return;
    if (unit === 'kg') {
      kgWrap.style.display  = '';
      lbsWrap.style.display = 'none';
      var el = document.getElementById('piWeightKg');
      if (el && weightKg) el.value = Math.round(weightKg);
    } else {
      kgWrap.style.display  = 'none';
      lbsWrap.style.display = '';
      if (weightKg) {
        var el = document.getElementById('piWeightLbs');
        if (el) el.value = _kgToLbs(weightKg);
      }
    }
  }

  function _getCurHeightCm() {
    var cmWrap = document.getElementById('piHeightCmWrap');
    if (cmWrap && cmWrap.style.display !== 'none') {
      var v = parseFloat(document.getElementById('piHeightCm') ? document.getElementById('piHeightCm').value : '');
      return isNaN(v) ? null : v;
    }
    var ft = parseInt(document.getElementById('piHeightFt') ? document.getElementById('piHeightFt').value : '', 10);
    var inches = parseInt(document.getElementById('piHeightIn') ? document.getElementById('piHeightIn').value : '', 10);
    return (!isNaN(ft) && !isNaN(inches)) ? _ftInToCm(ft, inches) : null;
  }

  function _getCurWeightKg() {
    var kgWrap = document.getElementById('piWeightKgWrap');
    if (kgWrap && kgWrap.style.display !== 'none') {
      var v = parseFloat(document.getElementById('piWeightKg') ? document.getElementById('piWeightKg').value : '');
      return isNaN(v) ? null : v;
    }
    var lbs = parseFloat(document.getElementById('piWeightLbs') ? document.getElementById('piWeightLbs').value : '');
    return isNaN(lbs) ? null : _lbsToKg(lbs);
  }

  function loadBodyMetrics() {
    var surveyRaw = localStorage.getItem(SURVEY_KEY);
    var survey    = surveyRaw ? JSON.parse(surveyRaw) : {};
    var infoRaw   = localStorage.getItem(STORAGE_KEY);
    var info      = infoRaw  ? JSON.parse(infoRaw)   : {};

    var heightCm   = parseFloat(survey.height_cm || info.height_cm)   || null;
    var weightKg   = parseFloat(survey.weight_kg  || info.weight_kg)   || null;
    var heightUnit = survey.preferred_height_unit || info.preferred_height_unit || 'cm';
    var weightUnit = survey.preferred_weight_unit || info.preferred_weight_unit || 'kg';

    var btnCmH  = document.getElementById('piHeightUnitCm');
    var btnFtH  = document.getElementById('piHeightUnitFt');
    var btnKgW  = document.getElementById('piWeightUnitKg');
    var btnLbsW = document.getElementById('piWeightUnitLbs');
    if (btnCmH && btnFtH) {
      btnCmH.classList.toggle('active', heightUnit === 'cm');
      btnFtH.classList.toggle('active', heightUnit !== 'cm');
    }
    if (btnKgW && btnLbsW) {
      btnKgW.classList.toggle('active', weightUnit === 'kg');
      btnLbsW.classList.toggle('active', weightUnit !== 'kg');
    }
    _showHeightUnit(heightUnit, heightCm);
    _showWeightUnit(weightUnit, weightKg);
  }

  function initBodyMetricsToggles() {
    var btnCmH  = document.getElementById('piHeightUnitCm');
    var btnFtH  = document.getElementById('piHeightUnitFt');
    var btnKgW  = document.getElementById('piWeightUnitKg');
    var btnLbsW = document.getElementById('piWeightUnitLbs');

    function onHeightToggle(unit) {
      var curCm = _getCurHeightCm();
      if (btnCmH) btnCmH.classList.toggle('active', unit === 'cm');
      if (btnFtH) btnFtH.classList.toggle('active', unit !== 'cm');
      _showHeightUnit(unit, curCm);
    }
    function onWeightToggle(unit) {
      var curKg = _getCurWeightKg();
      if (btnKgW)  btnKgW.classList.toggle('active', unit === 'kg');
      if (btnLbsW) btnLbsW.classList.toggle('active', unit !== 'kg');
      _showWeightUnit(unit, curKg);
    }

    if (btnCmH) btnCmH.addEventListener('click', function () { onHeightToggle('cm'); });
    if (btnFtH) btnFtH.addEventListener('click', function () { onHeightToggle('ftin'); });
    if (btnKgW)  btnKgW.addEventListener('click',  function () { onWeightToggle('kg'); });
    if (btnLbsW) btnLbsW.addEventListener('click', function () { onWeightToggle('lbs'); });
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

      var btnFtH  = document.getElementById('piHeightUnitFt');
      var btnLbsW = document.getElementById('piWeightUnitLbs');
      var heightUnit = (btnFtH  && btnFtH.classList.contains('active'))  ? 'ftin' : 'cm';
      var weightUnit = (btnLbsW && btnLbsW.classList.contains('active')) ? 'lbs'  : 'kg';
      var heightCm = _getCurHeightCm();
      var weightKg = _getCurWeightKg();

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
        preferred_height_unit: heightUnit,
        preferred_weight_unit: weightUnit,
        height_cm: heightCm !== null ? heightCm : (existing.height_cm || null),
        weight_kg: weightKg !== null ? weightKg : (existing.weight_kg || null),
      });

      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
        console.log('[PROFILE] Saved image:', photoToStore ? 'base64 upload (' + photoToStore.length + ' chars)' : 'none');
        var surveyRaw = localStorage.getItem(SURVEY_KEY);
        var survey    = surveyRaw ? JSON.parse(surveyRaw) : {};
        if (heightCm !== null) survey.height_cm = heightCm;
        if (weightKg !== null) survey.weight_kg = weightKg;
        survey.preferred_height_unit = heightUnit;
        survey.preferred_weight_unit = weightUnit;
        localStorage.setItem(SURVEY_KEY, JSON.stringify(survey));

        /* Cross-device sync — every OTHER device on this account must see
           this same name/photo/age/height/weight/etc. The photo is
           compressed at pick time (initPhotoUpload), so it fits in the
           personalInfo doc; only a pathological/legacy oversized photo is
           stripped and stays local (same behavior as before this feature). */
        if (typeof ZitlasCloudSync !== 'undefined') {
          var _cloudData = Object.assign({}, data);
          var _photoCap = ZitlasCloudSync.PHOTO_SYNC_MAX_CHARS || 180000;
          if (_cloudData.photo && _cloudData.photo.length > _photoCap) {
            delete _cloudData.photo;
          }
          ZitlasCloudSync.saveCloudOnly('personalInfo', _cloudData);
          ZitlasCloudSync.save('survey', survey);
        }
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
    loadBodyMetrics();
    initPhotoUpload();
    initDobAge();
    initBodyMetricsToggles();
    initSaveBtn();
    requestAnimationFrame(initEntranceAnimations);
  }

  /* Hydrate from Firestore before the form's first paint, so opening this
     page on a second device shows the latest name/age/height/weight/etc.
     No realtime re-render here on purpose — this is an active edit form,
     and silently rewriting fields out from under someone mid-edit would
     be worse than a stale value until they reopen the page. */
  function boot() {
    if (typeof ZitlasAuth === 'undefined' || typeof ZitlasCloudSync === 'undefined') { init(); return; }
    ZitlasAuth.onAuthStateChanged(function (user) {
      if (!user) { init(); return; }
      ZitlasCloudSync.hydrateOnLoad(user.uid).then(init);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

})();
