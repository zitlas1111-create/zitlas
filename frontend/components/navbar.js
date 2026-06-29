/*!
 * ZITLAS — Global Bottom Navigation Component
 * Single source of truth for the 5-tab bottom nav.
 * Injects CSS + HTML. Active tab is auto-detected from window.location.
 * Usage: <script src="../../components/navbar.js"></script>
 */
(function () {
  'use strict';

  /* ── Tab definitions ─────────────────────────────────────────────────── */
  var TABS = [
    {
      id: 'home',
      emoji: '🏠',
      label: 'Home',
      i18n: 'nav_home',
      file: 'dashboard/dashboard.html',
      /* Active only on the dashboard page itself, not on sub-pages like weekly-plan */
      match: function (p) {
        return /\/dashboard\/dashboard(\.html)?(\?[^#]*)?$/.test(p);
      },
    },
    {
      id: 'diet',
      emoji: '🥗',
      label: 'Diet',
      i18n: 'nav_diet',
      file: 'diet/diet.html',
      match: function (p) {
        return /\/diet\/diet(\.html)?/.test(p);
      },
    },
    {
      id: 'training',
      emoji: '💪',
      label: 'Training',
      i18n: 'nav_training',
      file: 'dashboard/weekly-plan/weekly-plan.html',
      match: function (p) {
        return /\/(weekly-plan|training\/day)(\.html)?/.test(p);
      },
    },
    {
      id: 'nutritionists',
      emoji: '🧑‍⚕️',
      label: 'Experts',
      i18n: 'nav_experts',
      file: 'coaches/coaches.html',
      match: function (p) {
        return /\/(coaches|cprofile|dietitian)\//.test(p);
      },
    },
    {
      id: 'profile',
      emoji: '👤',
      label: 'Profile',
      i18n: 'nav_profile',
      file: 'profile/profile.html',
      match: function (p) {
        return /\/profile\/profile(\.html)?/.test(p);
      },
    },
  ];

  /* ── Active tab detection ─────────────────────────────────────────────── */
  function getActiveId() {
    var p = window.location.pathname;
    for (var i = 0; i < TABS.length; i++) {
      if (TABS[i].match(p)) return TABS[i].id;
    }
    return '';
  }

  /* ── Base path for hrefs ──────────────────────────────────────────────── */
  /*
   * Computes how many `../` steps are needed to reach the `pages/` directory.
   * Depth 1 (pages/xxx/xxx.html)  → base = '../'
   * Depth 2 (pages/xxx/yyy/yyy.html) → base = '../../'
   */
  function getBase() {
    var path = window.location.pathname;
    /* Normalise Windows drive letter paths from file:// protocol */
    var pagesIdx = path.indexOf('/pages/');
    if (pagesIdx === -1) return '../';
    var afterPages = path.substring(pagesIdx + 7); /* strip '/pages/' prefix */
    var dirs = afterPages.split('/');
    /* dirs = ['xxx', 'xxx.html'] for depth-1 or ['xxx', 'yyy', 'yyy.html'] for depth-2 */
    var depth = dirs.length - 1; /* number of directory levels below 'pages' */
    var prefix = '';
    for (var i = 0; i < depth; i++) prefix += '../';
    return prefix || '../';
  }

  /* ── CSS (scoped to #zitlas-navbar so it never conflicts with page CSS) ── */
  var NAV_CSS = [
    /* Container */
    '#zitlas-navbar{',
      'position:fixed;bottom:max(20px,env(safe-area-inset-bottom,0px));left:50%;transform:translateX(-50%);',
      'width:calc(100% - 40px);max-width:400px;height:64px;',
      'border-radius:24px;display:flex;align-items:center;justify-content:space-around;',
      'z-index:500;padding:0 6px;',
      'backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);',
      'transition:background .2s,border-color .2s;',
    '}',
    /* Dark (default) */
    'html:not([data-theme="light"]) #zitlas-navbar,',
    '[data-theme="dark"] #zitlas-navbar{',
      'background:rgba(20,20,22,.94);',
      'border:1px solid rgba(var(--white-rgb),.07);',
      'box-shadow:0 8px 32px rgba(var(--black-rgb),.38),0 2px 8px rgba(var(--black-rgb),.22),inset 0 1px 0 rgba(var(--white-rgb),.04);',
    '}',
    /* Light */
    '[data-theme="light"] #zitlas-navbar{',
      'background:rgba(var(--white-rgb),.95);',
      'border:1px solid rgba(var(--black-rgb),.08);',
      'box-shadow:0 8px 32px rgba(var(--black-rgb),.10),0 2px 8px rgba(var(--black-rgb),.06),inset 0 1px 0 rgba(var(--white-rgb),.9);',
    '}',
    /* Nav item base */
    '#zitlas-navbar .nav-item{',
      'position:relative;display:flex;flex-direction:column;align-items:center;gap:2px;',
      'padding:7px 14px;min-width:60px;',
      'color:var(--text-muted);text-decoration:none;border-radius:16px;',
      'transition:color .2s,background .2s,transform .28s;',
      '-webkit-tap-highlight-color:transparent;',
    '}',
    '[data-theme="light"] #zitlas-navbar .nav-item{color:var(--text-muted);}',
    /* Hover */
    '#zitlas-navbar .nav-item:hover{',
      'color:var(--text-secondary);background:rgba(var(--white-rgb),.06);transform:translateY(-2px);',
    '}',
    '[data-theme="light"] #zitlas-navbar .nav-item:hover{',
      'color:var(--border);background:rgba(var(--black-rgb),.04);',
    '}',
    /* Active */
    '#zitlas-navbar .nav-item.active{color:var(--primary);background:rgba(var(--primary-rgb),.12);}',
    '#zitlas-navbar .nav-item.active:hover{background:rgba(var(--primary-rgb),.18);}',
    '#zitlas-navbar .nav-item:active{transform:scale(.88) translateY(0)!important;transition:transform .1s ease;}',
    /* Emoji */
    '#zitlas-navbar .nav-emoji{font-size:19px;line-height:1;display:block;transition:transform .28s,filter .2s;}',
    '#zitlas-navbar .nav-item.active .nav-emoji{filter:drop-shadow(0 0 6px rgba(var(--primary-rgb),.55));transform:translateY(-1px);}',
    '#zitlas-navbar .nav-item:hover:not(.active) .nav-emoji{transform:translateY(-2px) scale(1.1);}',
    '#zitlas-navbar .nav-item:active .nav-emoji{transform:scale(.9);}',
    /* Label */
    '#zitlas-navbar .nav-label{font-size:9px;font-weight:700;letter-spacing:.2px;line-height:1;white-space:nowrap;}',
    /* Active dot */
    '#zitlas-navbar .nav-active-dot{',
      'position:absolute;bottom:5px;left:50%;transform:translateX(-50%);',
      'width:4px;height:4px;border-radius:50%;',
      'background:var(--primary);box-shadow:0 0 7px var(--primary);',
      'animation:zn-dot-pop .3s cubic-bezier(.34,1.56,.64,1) both;',
    '}',
    '@keyframes zn-dot-pop{',
      'from{transform:translateX(-50%) scale(0);opacity:0;}',
      'to{transform:translateX(-50%) scale(1);opacity:1;}',
    '}',
    /* Responsive max-widths */
    '@media(min-width:480px){#zitlas-navbar{max-width:500px;}}',
    '@media(min-width:640px){#zitlas-navbar{max-width:560px;}}',
    '@media(min-width:768px){#zitlas-navbar{max-width:620px;}}',
  ].join('');

  /* ── Build nav HTML ───────────────────────────────────────────────────── */
  function buildNav(base, activeId) {
    var items = TABS.map(function (tab) {
      var active = tab.id === activeId;
      var cls    = 'nav-item' + (active ? ' active' : '');
      var dot    = active ? '<span class="nav-active-dot"></span>' : '';
      return (
        '<a href="' + base + tab.file + '" class="' + cls + '"' +
        (active ? ' aria-current="page"' : '') + '>' +
          '<span class="nav-emoji" aria-hidden="true">' + tab.emoji + '</span>' +
          '<span class="nav-label" data-i18n="' + tab.i18n + '">' + tab.label + '</span>' +
          dot +
        '</a>'
      );
    });
    return (
      '<nav id="zitlas-navbar" role="navigation" aria-label="Main navigation">' +
        items.join('') +
      '</nav>'
    );
  }

  /* ── Inject ───────────────────────────────────────────────────────────── */
  function inject() {
    /* Remove any hardcoded bottom-nav leftover in the page HTML */
    var old = document.querySelector('.bottom-nav');
    if (old) old.remove();
    /* Also remove ourselves if re-injected (e.g. hot-reload) */
    var existing = document.getElementById('zitlas-navbar');
    if (existing) existing.remove();

    /* Inject scoped CSS once */
    if (!document.getElementById('zitlas-navbar-css')) {
      var style = document.createElement('style');
      style.id  = 'zitlas-navbar-css';
      style.textContent = NAV_CSS;
      document.head.appendChild(style);
    }

    /* Inject HTML */
    var base     = getBase();
    var activeId = getActiveId();
    document.body.insertAdjacentHTML('beforeend', buildNav(base, activeId));

    /* Trigger i18n if available */
    if (window.ZitlasLang) window.ZitlasLang.applyTranslations();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
