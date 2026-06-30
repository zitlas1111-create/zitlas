/* =============================================
   ZITLAS Profile Page — profile.js
   ============================================= */

(function () {
  'use strict';

  /* ---- Theme Management ---- */
  const THEME_KEY = 'zitlas_theme';
  const html = document.documentElement;

  function getSystemTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(preference) {
    const resolved = preference === 'system' ? getSystemTheme() : preference;
    html.setAttribute('data-theme', resolved);
    updateThemeChecks(preference);
  }

  function saveTheme(preference) {
    localStorage.setItem(THEME_KEY, preference);
    applyTheme(preference);
  }

  function loadTheme() {
    const saved = localStorage.getItem(THEME_KEY) || 'dark';
    applyTheme(saved);
    return saved;
  }

  function updateThemeChecks(selected) {
    ['dark', 'light', 'system'].forEach(t => {
      const btn = document.querySelector(`.theme-option[data-theme="${t}"]`);
      if (btn) btn.classList.toggle('selected', t === selected);
    });
  }

  /* ---- Modal Helpers ---- */
  function openModal(el) {
    el.classList.add('open');
    document.body.style.overflow = 'hidden';
    const firstFocusable = el.querySelector('button');
    if (firstFocusable) firstFocusable.focus();
  }

  function closeModal(el) {
    el.classList.remove('open');
    document.body.style.overflow = '';
  }

  function closeOnBackdrop(e, modal) {
    if (e.target === modal) closeModal(modal);
  }

  /* ---- Toast ---- */
  let toastTimer = null;
  function showToast(message, duration = 2600) {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), duration);
  }

  /* ---- Appearance Modal ---- */
  function initAppearanceModal() {
    const openBtn = document.getElementById('appearanceBtn');
    const modal = document.getElementById('appearanceModal');
    const closeBtn = document.getElementById('modalClose');
    if (!openBtn || !modal || !closeBtn) return;

    openBtn.addEventListener('click', () => {
      updateThemeChecks(localStorage.getItem(THEME_KEY) || 'dark');
      openModal(modal);
    });

    closeBtn.addEventListener('click', () => closeModal(modal));
    modal.addEventListener('click', (e) => closeOnBackdrop(e, modal));
    modal.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeModal(modal); });

    modal.querySelectorAll('.theme-option').forEach(btn => {
      btn.addEventListener('click', () => {
        const chosen = btn.dataset.theme;
        saveTheme(chosen);
        const names = {
          dark:   window.ZitlasLang ? ZitlasLang.t('theme_dark')   : 'Dark',
          light:  window.ZitlasLang ? ZitlasLang.t('theme_light')  : 'Light',
          system: window.ZitlasLang ? ZitlasLang.t('theme_system') : 'System',
        };
        showToast('Theme: ' + names[chosen]);
        setTimeout(() => closeModal(modal), 420);
      });
    });
  }

  /* ---- Language Modal ---- */
  function initLanguageModal() {
    var modal   = document.getElementById('languageModal');
    var closeBtn = document.getElementById('langModalClose');
    var langItem = document.querySelector('.settings-item[data-action="language"]');
    if (!modal || !closeBtn) return;

    function updateLangChecks(lang) {
      modal.querySelectorAll('.lang-option').forEach(function (btn) {
        btn.classList.toggle('selected', btn.dataset.lang === lang);
      });
    }

    if (langItem) {
      langItem.addEventListener('click', function () {
        updateLangChecks(window.ZitlasLang ? ZitlasLang.getLang() : 'en');
        openModal(modal);
      });
    }

    closeBtn.addEventListener('click', function () { closeModal(modal); });
    modal.addEventListener('click', function (e) { closeOnBackdrop(e, modal); });
    modal.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeModal(modal); });

    modal.querySelectorAll('.lang-option').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var lang = btn.dataset.lang;
        if (window.ZitlasLang) {
          ZitlasLang.setLang(lang);
          updateLangChecks(lang);
          showToast(lang === 'hi' ? ZitlasLang.t('toast_lang_hi') : ZitlasLang.t('toast_lang_en'));
        }
        setTimeout(function () { closeModal(modal); }, 420);
      });
    });
  }

  /* ---- Settings Items ---- */
  function initSettingsItems() {
    document.querySelectorAll('.settings-item[data-action], .quick-action-item[data-action]').forEach(btn => {
      const action = btn.dataset.action;
      if (action === 'appearance' || action === 'language') return;

      btn.addEventListener('click', () => {
        if (action === 'personal') {
          window.location.href = './personal-info/personal-info.html';
          return;
        }
        if (action === 'help') {
          window.location.href = './help-support/help-support.html';
          return;
        }
        if (action === 'subscription') {
          window.location.href = './membership/membership.html';
          return;
        }
        const t = window.ZitlasLang ? ZitlasLang.t.bind(ZitlasLang) : (k => k);
        showToast(t('toast_coming_soon'));
      });
    });
  }

  /* ---- Logout Modal ---- */
  function initLogoutModal() {
    const logoutBtn  = document.getElementById('logoutBtn');
    const modal      = document.getElementById('logoutModal');
    const cancelBtn  = document.getElementById('logoutCancel');
    const confirmBtn = document.getElementById('logoutConfirm');
    if (!logoutBtn || !modal || !cancelBtn || !confirmBtn) return;

    logoutBtn.addEventListener('click', () => openModal(modal));
    cancelBtn.addEventListener('click', () => closeModal(modal));
    modal.addEventListener('click', (e) => closeOnBackdrop(e, modal));

    confirmBtn.addEventListener('click', async () => {
      confirmBtn.textContent = 'Logging out…';
      confirmBtn.disabled = true;

      /* Firebase sign-out (no-op if not configured) */
      try {
        if (typeof ZitlasAuth !== 'undefined') await ZitlasAuth.signOut();
      } catch (e) { console.warn('[ZITLAS] signOut error:', e); }

      /* Phase 9 — clear all session keys including new ones */
      ['zitlas_token','zitlas_user','zitlas_firebase_user','zitlas_user_role',
       'zitlas_expert_id','loggedIn','user','zitlas_expert_profile','currentUser',
       'zitlas_expert_applied','zitlas_experts'].forEach(k => localStorage.removeItem(k));
      console.log('[LOCAL STORAGE CLEARED]');
      ['zitlas_guest','zitlas_pending_action','user'].forEach(k => sessionStorage.removeItem(k));

      window.location.replace('../login/login.html');
    });

    modal.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeModal(modal); });
  }

  /* ---- Share Profile ---- */
  function initShareProfile() {
    const btn = document.getElementById('shareProfileBtn');
    if (!btn) return;

    btn.addEventListener('click', async () => {
      const t = window.ZitlasLang ? ZitlasLang.t.bind(ZitlasLang) : (k => k);
      const shareData = {
        title: 'My ZITLAS Weight-Loss Profile',
        text: 'Check out my ZITLAS Weight-Loss Profile! | Pune, India',
        url: window.location.href,
      };

      if (navigator.share) {
        try {
          await navigator.share(shareData);
        } catch (err) {
          if (err.name !== 'AbortError') showToast(t('toast_share_fail'));
        }
      } else if (navigator.clipboard) {
        try {
          await navigator.clipboard.writeText(shareData.url);
          showToast(t('toast_link_copied'));
        } catch {
          showToast('Profile link: ' + shareData.url);
        }
      } else {
        showToast(t('toast_no_share'));
      }
    });
  }

  /* ---- Edit Profile ---- */
  function initEditProfile() {
    const btn = document.getElementById('editProfileBtn');
    if (!btn) return;
    btn.addEventListener('click', () => {
      window.location.href = './personal-info/personal-info.html';
    });
  }

  /* ---- System theme watcher ---- */
  function initSystemThemeWatcher() {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    mq.addEventListener('change', () => {
      if ((localStorage.getItem(THEME_KEY) || 'dark') === 'system') applyTheme('system');
    });
  }

  /* ---- Bottom nav ---- */
  function initNavItems() {
    document.querySelectorAll('.nav-item:not(.active)').forEach(item => {
      const href = item.getAttribute('href');
      if (!href || href === '#') {
        item.addEventListener('click', (e) => {
          e.preventDefault();
          showToast('Navigation — coming soon');
        });
      }
    });
  }

  /* ---- Load Athlete Profile from localStorage ---- */
  function loadAthleteProfile() {
    var info = {};
    try { info = JSON.parse(localStorage.getItem('zitlas_personal_info') || '{}'); } catch (_) {}
    var zUser = {};
    try { zUser = JSON.parse(localStorage.getItem('zitlas_user') || '{}'); } catch (_) {}
    var fbUser = {};
    try { fbUser = JSON.parse(localStorage.getItem('zitlas_firebase_user') || '{}'); } catch (_) {}
    var survey = {};
    try { survey = JSON.parse(localStorage.getItem('zitlas_survey') || '{}'); } catch (_) {}

    var name = (info.fullName || zUser.name || fbUser.displayName || fbUser.name || '').trim();
    var photo = info.photo || zUser.photo || fbUser.photoURL || fbUser.photo || null;

    var nameEl = document.querySelector('.player-name');
    if (nameEl && name) nameEl.textContent = name;

    var avatarImg = document.getElementById('avatarImg');
    if (avatarImg) {
      if (photo && (photo.startsWith('data:') || photo.startsWith('http'))) {
        avatarImg.src = photo;
        avatarImg.onerror = function () {
          if (!name) return;
          var _ini = name.split(/\s+/).slice(0, 2).map(function (w) { return w[0] || ''; }).join('').toUpperCase() || name[0].toUpperCase();
          avatarImg.onerror = null;
          avatarImg.src = 'data:image/svg+xml,' + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">' +
            '<rect width="120" height="120" rx="60" fill="#FF8C00"/>' +
            '<text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" font-size="48" font-weight="bold" fill="white" font-family="system-ui">' + _ini + '</text></svg>'
          );
        };
      } else if (name) {
        var initials = name.split(/\s+/).slice(0, 2).map(function (w) { return w[0] || ''; }).join('').toUpperCase() || name[0].toUpperCase();
        avatarImg.src = 'data:image/svg+xml,' + encodeURIComponent(
          '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">' +
          '<rect width="120" height="120" rx="60" fill="#FF8C00"/>' +
          '<text x="50%" y="50%" dominant-baseline="central" text-anchor="middle" font-size="48" font-weight="bold" fill="white" font-family="system-ui">' + initials + '</text></svg>'
        );
      }
    }

    var goalData = {};
    try { goalData = JSON.parse(localStorage.getItem('zitlas_goal') || '{}'); } catch (_) {}
    var goalType = (goalData.type || survey.fitness_goal || '').replace(/_/g, ' ');
    var aiLabel = document.querySelector('.ai-label');
    if (aiLabel && goalType) {
      aiLabel.textContent = 'AI ' + goalType.replace(/\b\w/g, function (c) { return c.toUpperCase(); }) + ' Member';
    }

    /* Update membership badge and subscription item subtitle */
    var membership = {};
    try { membership = JSON.parse(localStorage.getItem('zitlas_membership') || '{}'); } catch (_) {}
    var isPremium = membership.plan === 'premium';

    var roleBadge = document.querySelector('.role-badge');
    if (roleBadge) {
      roleBadge.innerHTML = isPremium
        ? '<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.09 6.26L20 9.27l-4.91 4.79L16.18 21 12 17.27 7.82 21l1.09-6.94L4 9.27l5.91-.01z"/></svg>Premium Member'
        : '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>Basic Member';
    }

    var subItem = document.querySelector('.settings-item[data-action="subscription"]');
    if (subItem) {
      var label = subItem.querySelector('.settings-label');
      if (label) {
        var existingSubtitle = label.querySelector('.settings-subtitle');
        if (!existingSubtitle) {
          existingSubtitle = document.createElement('span');
          existingSubtitle.className = 'settings-subtitle';
          label.style.cssText = 'flex:1;display:flex;flex-direction:column;gap:2px;';
          label.appendChild(existingSubtitle);
        }
        existingSubtitle.textContent = 'Current Plan: ' + (isPremium ? 'Premium' : 'Basic');
      }
    }
  }

  /* ---- Avatar fallback ---- */
  function initAvatarFallback() {
    const img = document.getElementById('avatarImg');
    if (!img) return;
    img.addEventListener('error', () => {
      img.src = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120"%3E%3Crect width="120" height="120" rx="60" fill="%23FF8A00"/%3E%3Ctext x="50%25" y="50%25" dominant-baseline="central" text-anchor="middle" font-size="48" font-weight="bold" fill="white" font-family="system-ui"%3EAP%3C/text%3E%3C/svg%3E';
    });
  }

  /* ---- Expert Application Pending Banner ---- */
  function initExpertAppliedBanner() {
    var applied = localStorage.getItem('zitlas_expert_applied');
    if (!applied) return;
    var banner = document.getElementById('expertAppliedBanner');
    if (banner) banner.style.display = 'flex';
  }

  /* ---- INIT ---- */
  function init() {
    var _nb = document.getElementById('zitlas-navbar');
    if (_nb) document.documentElement.style.setProperty('--nav-height', (window.innerHeight - _nb.getBoundingClientRect().top) + 'px');

    loadTheme();
    initSystemThemeWatcher();
    loadAthleteProfile();
    initAppearanceModal();
    initLanguageModal();
    initSettingsItems();
    initLogoutModal();
    initShareProfile();
    initEditProfile();
    initNavItems();
    initAvatarFallback();
    initExpertAppliedBanner();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
