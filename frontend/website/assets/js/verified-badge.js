/*!
 * ZITLAS — Verified Expert Badge (assets/js/verified-badge.js)
 *
 * Single shared component for the badge that appears next to a verified
 * expert's name everywhere: Experts listing, profile header, chat headers,
 * personal-coach banners, diet/workout review banners, notifications.
 *
 * SOURCE OF TRUTH: this module NEVER decides who is verified. It only
 * renders whatever experts/{uid}.verification says (computed server-side*
 * — *this app has no Admin SDK, so "server-side" here means the one
 * function that's allowed to write it: certificate-manager.js's
 * recomputeVerifiedFlag(), triggered only by a new certificate upload or
 * an admin approve/reject action, never by arbitrary frontend code).
 * Shape: { isVerified, verificationLevel, verifiedAt, verifiedCertificates }.
 *
 * FUTURE BADGE LEVELS (gold/elite/medical/founder/...): add an entry to
 * LEVELS below. Every render() call already looks the level up by name —
 * no call site, no CSS structure, and no other function in this file
 * needs to change to support a new level appearing in the data.
 *
 * ASSET: assets/verification-badge.png — a cropped, transparent, 256x256
 * export of the original assets/verification.png (which is a full-canvas,
 * opaque-background, 2MB source image not meant to be used directly as a
 * ~16-24px inline icon). Same artwork, prepared for icon use. Never an
 * emoji, FontAwesome glyph, or any other icon.
 */
(function (win) {
  'use strict';

  var BADGE_SRC = '/assets/verification-badge.png';

  var LEVELS = {
    professional: {
      label: 'Verified Expert',
      tooltipTitle: 'Verified by ZITLAS',
      tooltipBody: 'Identity and professional certificates verified.',
    },
    // Future tiers — e.g.:
    // gold:    { label: 'Gold Verified',   tooltipTitle: 'Gold Verified — Top Rated', tooltipBody: '...' },
    // elite:   { label: 'Elite Coach',      tooltipTitle: 'Elite Coach',               tooltipBody: '...' },
    // medical: { label: 'Medical Verified', tooltipTitle: 'Medical Verified',          tooltipBody: '...' },
    // founder: { label: 'Founder Verified', tooltipTitle: 'Founder Verified',          tooltipBody: '...' },
  };
  var DEFAULT_LEVEL = 'professional';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* Accepts: a verification object itself, a doc/card-like object with a
     .verification field, a doc/card-like object with only the legacy flat
     .verified boolean (pre-migration experts — see certificate-manager.js's
     comment on why this fallback exists), or nothing. Always returns a
     complete, well-shaped object so callers never need their own guards. */
  function normalize(input) {
    if (!input) return { isVerified: false, verificationLevel: null, verifiedAt: null, verifiedCertificates: 0 };
    if (typeof input.isVerified === 'boolean') {
      return {
        isVerified: input.isVerified,
        verificationLevel: input.verificationLevel || (input.isVerified ? DEFAULT_LEVEL : null),
        verifiedAt: input.verifiedAt || null,
        verifiedCertificates: input.verifiedCertificates || 0,
      };
    }
    if (input.verification) return normalize(input.verification);
    if (input.verified === true) {
      return { isVerified: true, verificationLevel: DEFAULT_LEVEL, verifiedAt: null, verifiedCertificates: 1 };
    }
    return { isVerified: false, verificationLevel: null, verifiedAt: null, verifiedCertificates: 0 };
  }

  function isVerified(input) {
    return normalize(input).isVerified;
  }

  /* Coach/review banners (diet.js, weekly-plan.js, day.js) only have an
     expertId at render time, not the full expert doc. The zitlas_experts
     localStorage key is NOT a reliable cache of every expert (it's only
     ever written with a single self-entry at expert-signup and never
     kept in sync with Firestore by the listing/profile pages), so a
     lookup against it would silently under-report verified coaches —
     worse than just doing the real read. This does the one Firestore
     read per distinct expertId and memoizes it, so N banners about the
     same coach/reviewer cost exactly one network round trip, not N. */
  var _verificationCache = {}; // expertId -> resolved verification object
  function fetchVerification(expertId) {
    if (!expertId) return Promise.resolve(normalize(null));
    if (_verificationCache[expertId]) return Promise.resolve(_verificationCache[expertId]);
    if (typeof ZitlasDB === 'undefined') return Promise.resolve(normalize(null));
    return ZitlasDB.collection('experts').doc(String(expertId)).get()
      .then(function (doc) {
        var v = normalize(doc.exists ? doc.data() : null);
        _verificationCache[expertId] = v;
        return v;
      })
      .catch(function () { return normalize(null); });
  }
  /* Synchronous read of whatever fetchVerification() has already
     resolved for this id, or null if nothing has been fetched yet —
     for call sites that need to build a batch of HTML in one pass
     after pre-fetching every distinct expertId involved. */
  function getCachedVerification(expertId) {
    return (expertId && _verificationCache[expertId]) || null;
  }

  function levelConfig(verification) {
    return LEVELS[verification.verificationLevel] || LEVELS[DEFAULT_LEVEL];
  }

  /* size: 'sm' (16px — chat header, diet/workout review), 'md' (18px —
     listing/search cards), 'lg' (24px — profile header). className: any
     extra classes the caller wants on the wrapper. Returns '' when not
     verified — every call site can unconditionally splice this into HTML
     without an if-check, and nothing renders for a non-verified expert. */
  function render(input, opts) {
    var v = normalize(input);
    if (!v.isVerified) return '';
    opts = opts || {};
    var level = levelConfig(v);
    var size = opts.size || 'md';
    var extra = opts.className ? ' ' + opts.className : '';
    var label = level.tooltipTitle + '. ' + level.tooltipBody;
    return (
      '<span class="zv-badge-wrap zv-badge--' + esc(size) + extra + '" tabindex="0" role="button" ' +
        'data-zv-level="' + esc(v.verificationLevel || DEFAULT_LEVEL) + '" ' +
        'aria-label="' + esc(label) + '">' +
        '<img class="zv-badge-img" src="' + BADGE_SRC + '" alt="Verified Expert" ' +
          'loading="lazy" decoding="async" draggable="false">' +
        '<span class="zv-tooltip" role="tooltip">' +
          '<b>' + esc(level.tooltipTitle) + '</b>' + '<br>' + esc(level.tooltipBody) +
        '</span>' +
      '</span>'
    );
  }

  /* The small "Verified by ZITLAS" green caption under the profile-header
     name (spec section 2) — its own function since nowhere else uses it. */
  function renderCaption(input) {
    var v = normalize(input);
    if (!v.isVerified) return '';
    return '<div class="zv-caption">' + esc(levelConfig(v).tooltipTitle) + '</div>';
  }

  /* ── Mobile bottom sheet (shared, single instance, create-on-demand —
     same pattern as certificate-manager.js's modal) ── */
  function ensureSheet() {
    var bd = document.getElementById('zvSheetBackdrop');
    if (bd) return bd;
    bd = document.createElement('div');
    bd.id = 'zvSheetBackdrop';
    bd.className = 'zv-sheet-backdrop';
    bd.innerHTML =
      '<div class="zv-sheet" id="zvSheet" role="dialog" aria-label="Verified Expert">' +
        '<div class="zv-sheet-handle"></div>' +
        '<div class="zv-sheet-badge"><img src="' + BADGE_SRC + '" alt="Verified Expert" width="48" height="48"></div>' +
        '<p class="zv-sheet-title">Verified Expert</p>' +
        '<div class="zv-sheet-row"><span class="zv-sheet-check">&#10003;</span><span>Identity Verified</span></div>' +
        '<div class="zv-sheet-row"><span class="zv-sheet-check">&#10003;</span><span>Professional Certificates Verified</span></div>' +
        '<p class="zv-sheet-caption">Verified by ZITLAS</p>' +
        '<p class="zv-sheet-desc">This expert has successfully completed our verification process.</p>' +
        '<button class="zv-sheet-close" id="zvSheetCloseBtn">Close</button>' +
      '</div>';
    document.body.appendChild(bd);
    bd.addEventListener('click', function (e) { if (e.target === bd) closeSheet(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeSheet(); });
    return bd;
  }
  function openSheet() {
    var bd = ensureSheet();
    bd.style.display = 'flex';
    requestAnimationFrame(function () { requestAnimationFrame(function () { bd.classList.add('open'); }); });
    document.getElementById('zvSheetCloseBtn').onclick = closeSheet;
  }
  function closeSheet() {
    var bd = document.getElementById('zvSheetBackdrop');
    if (!bd) return;
    bd.classList.remove('open');
    setTimeout(function () { bd.style.display = 'none'; }, 220);
  }

  function isTouchDevice() {
    return window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
  }

  /* A badge on the first card of a list (or anywhere within ~60px of the
     viewport top) has no room for the tooltip to open upward — flip it
     below instead of letting it clip against the browser chrome. Runs on
     hover/focus-in, i.e. only when the tooltip is about to actually show,
     not for every badge on the page up front. */
  function positionTooltip(wrap) {
    var tooltip = wrap.querySelector('.zv-tooltip');
    if (!tooltip) return;
    var spaceAbove = wrap.getBoundingClientRect().top;
    tooltip.classList.toggle('zv-tooltip--below', spaceAbove < 60);
  }

  /* One delegated listener handles EVERY badge on the page, including
     ones injected later via innerHTML from other scripts — no call site
     needs to wire up its own click handler. Desktop hover/focus tooltip
     styling is pure CSS (see verified-badge.css); this owns the flip-
     below positioning check plus the mobile tap -> bottom sheet
     interaction (and Enter/Space for keyboard users on touch-primary
     devices, which don't reliably support :hover). */
  function initDelegatedHandlers() {
    if (win.__zitlasBadgeHandlersAttached) return;
    win.__zitlasBadgeHandlersAttached = true;
    document.addEventListener('mouseover', function (e) {
      var wrap = e.target.closest && e.target.closest('.zv-badge-wrap');
      if (wrap) positionTooltip(wrap);
    });
    document.addEventListener('focusin', function (e) {
      var wrap = e.target.closest && e.target.closest('.zv-badge-wrap');
      if (wrap) positionTooltip(wrap);
    });
    document.addEventListener('click', function (e) {
      var wrap = e.target.closest && e.target.closest('.zv-badge-wrap');
      if (!wrap) return;
      if (isTouchDevice()) {
        e.preventDefault();
        openSheet();
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Enter' && e.key !== ' ') return;
      var wrap = e.target.closest && e.target.closest('.zv-badge-wrap');
      if (!wrap) return;
      e.preventDefault();
      openSheet();
    });
  }

  initDelegatedHandlers();

  /* Warm the browser cache once per page load. Every render() call below
     references the SAME absolute URL, so this is the only network fetch
     for the badge image; every other instance is served from cache. */
  (function preload() { try { new Image().src = BADGE_SRC; } catch (_) {} })();

  win.ZitlasBadge = {
    LEVELS: LEVELS,
    normalize: normalize,
    isVerified: isVerified,
    fetchVerification: fetchVerification,
    getCachedVerification: getCachedVerification,
    render: render,
    renderCaption: renderCaption,
    openSheet: openSheet,
    closeSheet: closeSheet,
  };
})(window);
