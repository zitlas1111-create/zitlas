/* ── ZITLAS Nutritionist Marketplace ── */
'use strict';

// ─── DATA ──────────────────────────────────────────────────────────────────

const NUTRITIONISTS = [
  {
    id: 'rahul',
    name: 'Rahul Sharma',
    role: 'Weight Loss Nutritionist',
    image: '../../assets/coach1.png',
    initials: 'RS',
    color: '#FF8A00',
    rating: 4.9,
    reviews: 128,
    exp: '8+',
    fee: 149,
    duration: '15 Min',
    available: true,
    specialties: ['weight_loss', 'general'],
    lang: ['EN', 'HI'],
  },
  {
    id: 'vikas',
    name: 'Vikas Saxena',
    role: 'Strength & Fitness Specialist',
    image: '../../assets/coach2.png',
    initials: 'VS',
    color: '#EAB308',
    rating: 4.7,
    reviews: 80,
    exp: '6+',
    fee: 129,
    duration: '15 Min',
    available: true,
    specialties: ['general', 'muscle_gain'],
    lang: ['HI', 'MR'],
  },
  {
    id: 'rohit',
    name: 'Rohit Deshmukh',
    role: 'Fat Loss Nutritionist',
    image: '../../assets/coach3.png',
    initials: 'RD',
    color: '#EF4444',
    rating: 4.8,
    reviews: 72,
    exp: '7+',
    fee: 199,
    duration: '20 Min',
    available: false,
    specialties: ['weight_loss'],
    lang: ['EN', 'HI'],
  },
  {
    id: 'aman',
    name: 'Aman Verma',
    role: 'Habit & Wellness Expert',
    image: '../../assets/coach4.png',
    initials: 'AV',
    color: '#22C55E',
    rating: 4.6,
    reviews: 54,
    exp: '5+',
    fee: 99,
    duration: '10 Min',
    available: true,
    specialties: ['general', 'diabetes'],
    lang: ['HI'],
  },
  {
    id: 'prakash',
    name: 'Prakash Sir',
    role: 'Head Nutritionist',
    image: '../../assets/ac1.png',
    initials: 'PS',
    color: '#FF8A00',
    rating: 4.9,
    reviews: 210,
    exp: '12+',
    fee: 299,
    duration: '30 Min',
    available: true,
    specialties: ['weight_loss', 'pcos', 'diabetes'],
    lang: ['EN', 'HI', 'MR'],
  },
  {
    id: 'ramesh',
    name: 'Ramesh Patil',
    role: 'Weight Loss Nutritionist',
    image: '../../assets/ac2.png',
    initials: 'RP',
    color: '#22C55E',
    rating: 4.8,
    reviews: 145,
    exp: '9+',
    fee: 249,
    duration: '25 Min',
    available: false,
    specialties: ['weight_loss', 'general'],
    lang: ['HI', 'MR'],
  },
  {
    id: 'vivek',
    name: 'Vivek Sharma',
    role: 'Fitness Specialist',
    image: '../../assets/ac3.png',
    initials: 'VS',
    color: '#3B82F6',
    rating: 4.8,
    reviews: 118,
    exp: '8+',
    fee: 179,
    duration: '20 Min',
    available: true,
    specialties: ['muscle_gain', 'general'],
    lang: ['EN', 'HI'],
  },
  {
    id: 'sanjay',
    name: 'Sanjay Kulkarni',
    role: 'Habit & Wellness Expert',
    image: '../../assets/ac4.png',
    initials: 'SK',
    color: '#8B5CF6',
    rating: 4.7,
    reviews: 98,
    exp: '7+',
    fee: 149,
    duration: '15 Min',
    available: true,
    specialties: ['general', 'diabetes'],
    lang: ['HI', 'MR'],
  },
  {
    id: 'abhishek',
    name: 'Abhishek More',
    role: 'Sports Nutrition Specialist',
    image: '../../assets/ac5.png',
    initials: 'AM',
    color: '#EAB308',
    rating: 4.8,
    reviews: 132,
    exp: '6+',
    fee: 199,
    duration: '20 Min',
    available: false,
    specialties: ['muscle_gain', 'pcos'],
    lang: ['EN', 'MR'],
  },
];

// ─── STATE ─────────────────────────────────────────────────────────────────

let currentSort      = 'rated';
let currentSpecialty = 'all';
let searchQuery      = '';

// drawer pending selections (applied on "Apply")
let pendingSort      = 'rated';
let pendingSpecialty = 'all';

// ─── DOM REFS ──────────────────────────────────────────────────────────────

const coachesList        = document.getElementById('coachesList');
const resultsCount       = document.getElementById('resultsCount');
const searchInput        = document.getElementById('searchInput');
const searchClearBtn     = document.getElementById('searchClearBtn');
const filterPills        = document.getElementById('filterPills');
const menuBtn            = document.getElementById('menuBtn');
const sortToggleBtn      = document.getElementById('sortToggleBtn');
const sideDrawer         = document.getElementById('sideDrawer');
const drawerOverlay      = document.getElementById('drawerOverlay');
const drawerCloseBtn     = document.getElementById('drawerCloseBtn');
const drawerApplyBtn     = document.getElementById('drawerApplyBtn');
const drawerSortGroup    = document.getElementById('drawerSortGroup');
const drawerSpecialtyGroup = document.getElementById('drawerSpecialtyGroup');
const toast              = document.getElementById('toast');

// ─── RENDER ────────────────────────────────────────────────────────────────

function avatarBg(n) {
  return `background:${n.color}22;color:${n.color};`;
}

function renderNutritionistCard(n) {
  const availClass = n.available ? 'avail-tag--now' : 'avail-tag--later';
  const availText  = n.available ? '🟢 Available Today' : '⏰ Available Tomorrow';
  const langStr    = n.lang.join(', ');

  return `<article class="nutri-card" role="button" tabindex="0" data-id="${n.id}" aria-label="${n.name}, ${n.role}">
  <div class="nutri-left">
    <div class="nutri-avatar-wrap">
      <div class="nutri-avatar" style="${avatarBg(n)}">
        <img src="${n.image}" alt="${n.name}" class="nutri-avatar-img" onerror="this.style.display='none'" />
        <span class="nutri-initials" aria-hidden="true">${n.initials}</span>
      </div>
      ${n.available ? '<span class="avail-dot" title="Available today"></span>' : ''}
    </div>
  </div>
  <div class="nutri-body">
    <div class="nutri-name-row">
      <span class="nutri-name">${n.name}</span>
      <svg class="verified-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#22C55E" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-label="Verified expert">
        <polyline points="20 6 9 17 4 12"/>
      </svg>
    </div>
    <span class="nutri-role">${n.role}</span>
    <div class="nutri-rating-row">
      <span class="n-star">★</span>
      <span class="n-score">${n.rating}</span>
      <span class="n-reviews">(${n.reviews})</span>
      <span class="n-sep">·</span>
      <span class="n-exp">${n.exp} yrs</span>
      <span class="n-sep">·</span>
      <span class="n-lang">${langStr}</span>
    </div>
    <div class="nutri-avail-row">
      <span class="avail-tag ${availClass}">${availText}</span>
    </div>
    <div class="nutri-fee-row">
      <div class="fee-info">
        <span class="fee-amount">₹${n.fee}</span>
        <span class="fee-duration">/ ${n.duration}</span>
      </div>
      <button class="ask-btn" data-id="${n.id}" aria-label="Ask ${n.name}">
        Ask Expert
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/>
        </svg>
      </button>
    </div>
  </div>
</article>`;
}

function renderEmptyState() {
  return `<div class="empty-state">
  <div class="empty-icon">🧑‍⚕️</div>
  <h3 class="empty-heading">No experts found</h3>
  <p class="empty-desc">${searchQuery ? `No results for "${searchQuery}". Try a different search.` : 'Try changing your filter or specialty.'}</p>
</div>`;
}

// ─── FILTER + SORT ─────────────────────────────────────────────────────────

function getFiltered() {
  let list = NUTRITIONISTS.slice();

  if (currentSpecialty !== 'all') {
    list = list.filter(n => n.specialties.includes(currentSpecialty));
  }

  if (searchQuery) {
    const q = searchQuery.toLowerCase();
    list = list.filter(n =>
      n.name.toLowerCase().includes(q) ||
      n.role.toLowerCase().includes(q) ||
      n.specialties.some(s => s.replace(/_/g, ' ').includes(q))
    );
  }

  if (currentSort === 'price') {
    list.sort((a, b) => a.fee - b.fee);
  } else if (currentSort === 'available') {
    list.sort((a, b) => {
      if (a.available !== b.available) return a.available ? -1 : 1;
      return b.rating - a.rating;
    });
  } else {
    list.sort((a, b) => b.rating - a.rating || b.reviews - a.reviews);
  }

  return list;
}

function updateList() {
  const list = getFiltered();
  if (list.length === 0) {
    coachesList.innerHTML = renderEmptyState();
    resultsCount.textContent = '0 Experts';
    return;
  }
  coachesList.innerHTML = list.map(renderNutritionistCard).join('');
  const n = list.length;
  resultsCount.textContent = `${n} Expert${n === 1 ? '' : 's'}`;
}

// ─── PILL SYNC ─────────────────────────────────────────────────────────────

function syncPills() {
  filterPills.querySelectorAll('.cat-pill').forEach(btn => {
    const sameSort      = btn.dataset.sort === currentSort;
    const sameSpecialty = btn.dataset.specialty === currentSpecialty;
    btn.classList.toggle('active', sameSort && sameSpecialty);
  });
}

function syncDrawerPills() {
  drawerSortGroup.querySelectorAll('.drawer-pill').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.sort === pendingSort);
  });
  drawerSpecialtyGroup.querySelectorAll('.drawer-pill').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.specialty === pendingSpecialty);
  });
}

// ─── DRAWER ────────────────────────────────────────────────────────────────

function openDrawer() {
  pendingSort      = currentSort;
  pendingSpecialty = currentSpecialty;
  syncDrawerPills();
  sideDrawer.classList.add('open');
  drawerOverlay.classList.add('active');
  sideDrawer.setAttribute('aria-hidden', 'false');
}

function closeDrawer() {
  sideDrawer.classList.remove('open');
  drawerOverlay.classList.remove('active');
  sideDrawer.setAttribute('aria-hidden', 'true');
}

function applyDrawer() {
  currentSort      = pendingSort;
  currentSpecialty = pendingSpecialty;
  syncPills();
  updateList();
  closeDrawer();
}

// ─── EVENTS ────────────────────────────────────────────────────────────────

menuBtn.addEventListener('click', openDrawer);
sortToggleBtn.addEventListener('click', openDrawer);
drawerCloseBtn.addEventListener('click', closeDrawer);
drawerOverlay.addEventListener('click', closeDrawer);
drawerApplyBtn.addEventListener('click', applyDrawer);

drawerSortGroup.addEventListener('click', e => {
  const btn = e.target.closest('[data-sort]');
  if (!btn) return;
  pendingSort = btn.dataset.sort;
  syncDrawerPills();
});

drawerSpecialtyGroup.addEventListener('click', e => {
  const btn = e.target.closest('[data-specialty]');
  if (!btn) return;
  pendingSpecialty = btn.dataset.specialty;
  syncDrawerPills();
});

filterPills.addEventListener('click', e => {
  const btn = e.target.closest('.cat-pill');
  if (!btn) return;
  currentSort      = btn.dataset.sort;
  currentSpecialty = btn.dataset.specialty;
  pendingSort      = currentSort;
  pendingSpecialty = currentSpecialty;
  syncPills();
  updateList();
});

searchInput.addEventListener('input', () => {
  searchQuery = searchInput.value.trim();
  searchClearBtn.style.display = searchQuery ? '' : 'none';
  updateList();
});

searchClearBtn.addEventListener('click', () => {
  searchInput.value = '';
  searchQuery = '';
  searchClearBtn.style.display = 'none';
  searchInput.focus();
  updateList();
});

coachesList.addEventListener('click', e => {
  const askBtn = e.target.closest('.ask-btn');
  if (askBtn) {
    window.location.href = `cprofile.html?id=${askBtn.dataset.id}`;
    return;
  }
  const card = e.target.closest('.nutri-card');
  if (card) window.location.href = `cprofile.html?id=${card.dataset.id}`;
});

coachesList.addEventListener('keydown', e => {
  if (e.key !== 'Enter' && e.key !== ' ') return;
  const card = e.target.closest('.nutri-card');
  if (card) {
    e.preventDefault();
    window.location.href = `cprofile.html?id=${card.dataset.id}`;
  }
});

document.getElementById('notifBtn').addEventListener('click', () => {
  showToast('🔔 No new notifications');
});

// ─── TOAST ─────────────────────────────────────────────────────────────────

let _toastTimer;
function showToast(msg) {
  clearTimeout(_toastTimer);
  toast.textContent = msg;
  toast.classList.add('show');
  _toastTimer = setTimeout(() => toast.classList.remove('show'), 2800);
}

// ─── INIT ──────────────────────────────────────────────────────────────────

(function init() {
  const t = localStorage.getItem('zitlas_theme') || 'dark';
  document.documentElement.setAttribute('data-theme', t);

  searchClearBtn.style.display = 'none';
  updateList();

  if (window.ZitlasLang) window.ZitlasLang.applyTranslations();
})();
