/*!
 * ZITLAS — Expert Profile: Single Source of Truth
 * frontend/assets/js/expert-profile.js
 *
 * Provides getExpertProfile(), saveExpertProfile(), initializeDefaultExpertProfile().
 * All pages that display expert data load this file and read/write from
 * localStorage['zitlas_expert_profile'] via ZitlasExpertProfile.
 *
 * Dispatches window event 'expertProfileUpdated' on every save so all open
 * pages can re-render without a full reload.
 */
(function (win) {
  'use strict';

  var STORAGE_KEY  = 'zitlas_expert_profile';
  var EXPERT_ID_KEY = 'zitlas_expert_id';

  /* ── Blank template seeded for new experts (completed via profile editor) ── */
  var EXPERT_BLANK = {
    id: '', name: '', initials: 'EX',
    specialization: '',
    title: '',
    bio: '',
    quote: '',
    sessions: '0', clients: '0', successRate: '0%', experience: '0+',
    reviewFee: 0, sessionDuration: 20, status: 'online', profilePhoto: null,
    colorAccent: 'var(--primary)', rating: '5.0', reviewCount: 0,
  };

  /* ── Helpers ────────────────────────────────────────────────────────────── */

  function _getExpertId() {
    return (localStorage.getItem(EXPERT_ID_KEY) || '').trim();
  }

  function _computeInitials(name) {
    return (name || '').split(/\s+/).map(function (p) { return p[0] || ''; }).slice(0, 2).join('').toUpperCase() || 'EX';
  }

  function _extractNum(str) {
    var m = String(str || '').match(/(\d+)/);
    return m ? parseInt(m[1], 10) : 0;
  }

  /* Migrate profile saved in the OLD schema (pre-canonical) to new schema */
  function _migrateOldSchema(old, expertId) {
    var base = getDefault(expertId);
    return {
      id:              expertId,
      name:            old.name            || base.name,
      initials:        old.initials        || _computeInitials(old.name || base.name),
      specialization:  old.role            || base.specialization,
      title:           old.title           || base.title,
      bio:             old.about           || base.bio,
      quote:           old.quote           || base.quote,
      sessions:        old.sessions        || base.sessions,
      clients:         old.clients         || base.clients,
      successRate:     old.successRate     || base.successRate,
      experience:      old.years           || base.experience,
      reviewFee:       (old.fee !== undefined ? old.fee : base.reviewFee),
      sessionDuration: _extractNum(old.duration) || base.sessionDuration,
      status:          (old.isOnline !== undefined ? (old.isOnline ? 'online' : 'offline') : base.status),
      profilePhoto:    (old.photo !== undefined ? old.photo : null),
      colorAccent:     old.colorAccent     || base.colorAccent,
      rating:          old.rating          || base.rating,
      reviewCount:     old.reviewCount     || base.reviewCount,
    };
  }

  /* ── Public API ─────────────────────────────────────────────────────────── */

  function getExpertId() {
    return _getExpertId();
  }

  function getDefault(id) {
    var blank = Object.assign({}, EXPERT_BLANK);
    blank.id = id || '';
    return blank;
  }

  function initializeDefaultExpertProfile() {
    var id = _getExpertId();
    var existing = null;
    try { existing = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null'); } catch (_) {}

    if (existing) {
      /* Detect old schema: has 'role'/'about'/'isOnline' but not 'specialization'/'bio'/'status' */
      var needsMigration = (existing.role !== undefined && existing.specialization === undefined)
                        || (existing.about !== undefined && existing.bio === undefined)
                        || (existing.isOnline !== undefined && existing.status === undefined);
      if (needsMigration) {
        existing = _migrateOldSchema(existing, id);
        try { localStorage.setItem(STORAGE_KEY, JSON.stringify(existing)); } catch (_) {}
      }
      return existing;
    }

    /* First-ever load: seed from defaults */
    var def = getDefault(id);
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(def)); } catch (_) {}
    return def;
  }

  function getExpertProfile() {
    var id     = _getExpertId();
    var saved  = null;
    try { saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null'); } catch (_) {}

    if (!saved) return initializeDefaultExpertProfile();

    /* Migrate old schema if needed */
    var needsMigration = (saved.role !== undefined && saved.specialization === undefined)
                      || (saved.about !== undefined && saved.bio === undefined)
                      || (saved.isOnline !== undefined && saved.status === undefined);
    if (needsMigration) {
      saved = _migrateOldSchema(saved, id);
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify(saved)); } catch (_) {}
    }

    if (!saved.id) saved.id = id;
    return saved;
  }

  function saveExpertProfile(updates) {
    var current = getExpertProfile();
    var merged  = Object.assign({}, current, updates);

    /* Always recompute initials when name changes */
    if (updates.name && updates.name.trim()) {
      merged.initials = _computeInitials(updates.name.trim());
    }

    /* Ensure id is always present */
    if (!merged.id) merged.id = _getExpertId();

    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(merged));
    } catch (e) {
      console.warn('[ZitlasExpertProfile] localStorage save failed:', e);
    }

    /* Notify all listeners (same tab and via storage event for other tabs) */
    try {
      win.dispatchEvent(new CustomEvent('expertProfileUpdated', { detail: merged }));
    } catch (_) {}

    return merged;
  }

  /* ── Utility: translate canonical → expert-dashboard.js internal format ── */
  function toInternalFormat(profile, base) {
    base = base || {};
    var baseStats = base.stats || [];
    var m = Object.assign({}, base);

    if (!profile) return m;

    /* Always carry the id through so downstream Firestore queries use the real uid */
    if (profile.id) m.id = profile.id;

    if (profile.name) {
      m.name      = profile.name;
      m.firstName = profile.name.split(/\s+/)[0] || profile.name;
      m.initials  = profile.initials || _computeInitials(profile.name);
    }
    if (profile.specialization)         m.role        = profile.specialization;
    if (profile.title)                  m.achievement = profile.title;
    if (profile.bio)                    m.about       = profile.bio;
    if (profile.quote)                  m.quote       = profile.quote;
    if (profile.reviewFee !== undefined) m.fee        = profile.reviewFee;
    if (profile.sessionDuration)        m.duration    = profile.sessionDuration + ' Min';
    if (profile.profilePhoto !== undefined) m.photo   = profile.profilePhoto || null;
    if (profile.colorAccent)            m.colorAccent = profile.colorAccent;
    if (profile.rating)                 m.rating      = profile.rating;
    if (profile.reviewCount !== undefined) m.reviewCount = profile.reviewCount;

    m.isOnline = (profile.status !== 'offline');

    var expRaw     = String(profile.experience || '').replace(/[^0-9.]/g, '');
    var expDisplay = profile.experience
      ? (String(profile.experience).includes('+') ? profile.experience : profile.experience + '+')
      : (baseStats[3] ? baseStats[3].value : '-');

    if (expRaw) m.experience = expRaw + '+ Years Experience';

    m.stats = [
      { value: profile.sessions    || (baseStats[0] ? baseStats[0].value : '-'), label: 'Sessions'     },
      { value: profile.clients     || (baseStats[1] ? baseStats[1].value : '-'), label: 'Clients'      },
      { value: profile.successRate || (baseStats[2] ? baseStats[2].value : '-'), label: 'Success Rate' },
      { value: expDisplay,                                                         label: 'Years'       },
    ];

    return m;
  }

  /* ── Utility: apply canonical profile to a marketplace card object ──────── */
  function applyToCard(card) {
    var p = getExpertProfile();
    if (!p) return card;

    var expYears = String(p.experience || '').replace(/[^0-9]/g, '');
    var expDisplay = p.experience
      ? (String(p.experience).includes('+') ? p.experience : p.experience + '+')
      : card.exp || card.experience || '';

    return Object.assign({}, card, {
      name:     p.name          || card.name,
      initials: p.initials      || card.initials,
      /* coaches.js uses 'role', dietitian.js uses 'specialization' */
      role:          p.specialization || card.role,
      specialization: p.specialization || card.specialization,
      fee:           p.reviewFee !== undefined ? p.reviewFee : card.fee,
      /* coaches.js uses 'duration', dietitian.js doesn't */
      duration:      p.sessionDuration ? (p.sessionDuration + ' Min') : card.duration,
      /* coaches.js uses 'exp' (string), dietitian.js uses 'experience' (number) */
      exp:           expDisplay,
      experience:    p.experience ? (parseInt(expYears) || card.experience) : card.experience,
      /* online status */
      available:     p.status !== 'offline',
      mode:          p.status === 'offline' ? ['offline'] : ['online'],
      /* photo */
      image:         p.profilePhoto || card.image,
      color:         p.colorAccent  || card.color,
    });
  }

  /* ── Utility: apply canonical profile onto a cprofile.js COACH_DB entry ── */
  function applyToCoach(coach) {
    var p = getExpertProfile();
    if (!p) return coach;

    var expRaw = String(p.experience || '').replace(/[^0-9.]/g, '');
    var expDisplay = p.experience
      ? (String(p.experience).includes('+') ? p.experience : p.experience + '+')
      : (coach.stats && coach.stats[3] ? coach.stats[3].value : coach.experience);

    var updated = Object.assign({}, coach);
    if (p.name)             { updated.name = p.name; updated.firstName = p.name.split(/\s+/)[0]; }
    if (p.initials)           updated.initials    = p.initials;
    if (p.specialization)     updated.role        = p.specialization;
    if (p.title)              updated.achievement = p.title;
    if (p.bio)                updated.about       = p.bio;
    if (p.quote)              updated.quote       = p.quote;
    if (p.reviewFee !== undefined) updated.fee    = p.reviewFee;
    if (p.sessionDuration)    updated.duration    = p.sessionDuration + ' Min';
    if (p.profilePhoto !== undefined) updated.image = p.profilePhoto || coach.image;
    if (p.colorAccent)        updated.colorAccent = p.colorAccent;
    if (expRaw)               updated.experience  = expRaw + '+ Years Experience';

    updated.availability = {
      isAvailableToday: p.status !== 'offline',
      slots: (coach.availability && coach.availability.slots) || ['9:00 AM', '11:00 AM', '2:00 PM', '5:00 PM'],
    };

    if (p.sessions || p.clients || p.successRate || p.experience) {
      var bs = coach.stats || [];
      updated.stats = [
        { value: p.sessions    || (bs[0] ? bs[0].value : '-'), label: 'Sessions'     },
        { value: p.clients     || (bs[1] ? bs[1].value : '-'), label: 'Clients'      },
        { value: p.successRate || (bs[2] ? bs[2].value : '-'), label: 'Success Rate' },
        { value: expDisplay,                                     label: 'Years'       },
      ];
    }

    return updated;
  }

  /* ── Export ─────────────────────────────────────────────────────────────── */
  win.ZitlasExpertProfile = {
    /* Core */
    getExpertId:  getExpertId,
    getDefault:   getDefault,
    init:         initializeDefaultExpertProfile,
    getProfile:   getExpertProfile,
    save:         saveExpertProfile,
    /* Rendering utilities */
    toInternal:   toInternalFormat,
    applyToCard:  applyToCard,
    applyToCoach: applyToCoach,
    /* Blank template reference */
    DEFAULTS: {},
  };

  /* Seed on first load */
  initializeDefaultExpertProfile();

})(window);
