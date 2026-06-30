/* ══════════════════════════════════════════════
   ZITLAS — Login Page
   login.js
   ══════════════════════════════════════════════ */

'use strict';

/* Phase 8 fast-redirect REMOVED.
   It trusted localStorage without verifying Firebase Auth, which caused
   User A's stale session to redirect User B to User A's dashboard.
   onAuthStateChanged below is the single source of truth for redirects. */

/* ══════════════════════════════════════════════
   STAT COUNT-UP
   Same algorithm as dashboard.js countUp()
   ══════════════════════════════════════════════ */

function formatStatNum(val, target) {
  if (target >= 1000) {
    const k = val / 1000;
    return (k % 1 === 0 ? k.toFixed(0) : k.toFixed(1)) + 'K+';
  }
  return val + '+';
}

function countUp(el, target, duration) {
  const start = performance.now();
  function tick(now) {
    const p = Math.min((now - start) / duration, 1);
    const e = 1 - Math.pow(1 - p, 3); /* ease-out cubic */
    const v = Math.round(e * target);
    el.textContent = formatStatNum(v, target);
    if (p < 1) requestAnimationFrame(tick);
    else el.textContent = formatStatNum(target, target);
  }
  requestAnimationFrame(tick);
}

const statsEl = document.getElementById('loginStats');
if (statsEl) {
  const targets = [
    { id: 'lstat0', val: 10000 },
    { id: 'lstat1', val: 1200  },
    { id: 'lstat2', val: 500   },
    { id: 'lstat3', val: 100   },
  ];

  const io = new IntersectionObserver((entries) => {
    if (!entries[0].isIntersecting) return;
    targets.forEach(({ id, val }, i) => {
      const el = document.getElementById(id);
      if (el) setTimeout(() => countUp(el, val, 1600), i * 100);
    });
    io.disconnect();
  }, { threshold: 0.3 });

  io.observe(statsEl);
}

/* ══════════════════════════════════════════════
   PASSWORD TOGGLE
   ══════════════════════════════════════════════ */

const pwToggle = document.getElementById('pwToggle');
const pwInput  = document.getElementById('passwordInput');
const eyeIcon  = document.getElementById('eyeIcon');

const EYE_OPEN   = `<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>`;
const EYE_CLOSED = `<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>`;

if (pwToggle && pwInput && eyeIcon) {
  pwToggle.addEventListener('click', () => {
    const hidden = pwInput.type === 'password';
    pwInput.type       = hidden ? 'text' : 'password';
    eyeIcon.innerHTML  = hidden ? EYE_CLOSED : EYE_OPEN;
    pwToggle.setAttribute('aria-label', hidden ? 'Hide password' : 'Show password');
  });
}

/* ══════════════════════════════════════════════
   ROLE SELECTOR
   ══════════════════════════════════════════════ */

let selectedRole = 'athlete';
let isSignupMode = false;

const roleTabAthlete = document.getElementById('roleTabAthlete');
const roleTabExpert  = document.getElementById('roleTabExpert');
const expertHintBtn  = document.getElementById('expertHintBtn');
const expertHint     = document.getElementById('expertHint');
const loginCardTitle = document.getElementById('loginCardTitle');
const loginCardSub   = document.getElementById('loginCardSub');
const skipBtn        = document.getElementById('skipBtn');

function setRole(role) {
  selectedRole = role;
  if (roleTabAthlete) roleTabAthlete.classList.toggle('active', role === 'athlete');
  if (roleTabExpert)  roleTabExpert.classList.toggle('active',  role === 'expert');
  if (expertHint)     expertHint.style.display = (role === 'expert' || isSignupMode) ? 'none' : '';
  if (skipBtn)        skipBtn.style.display    = (role === 'expert' || isSignupMode) ? 'none' : '';
  if (loginCardTitle) loginCardTitle.textContent = isSignupMode
    ? (role === 'expert' ? 'Create Expert Account 👨‍⚕️' : 'Create Account 🚀')
    : (role === 'expert' ? 'Expert Login 👨‍⚕️' : 'Welcome Back 👋');
  if (loginCardSub)   loginCardSub.textContent = isSignupMode
    ? 'Join ZITLAS — start your journey'
    : (role === 'expert' ? 'Sign in to your ZITLAS Expert Portal' : 'Sign in to continue your weight-loss journey');
  if (emailInput)    emailInput.placeholder = role === 'expert' ? 'Expert Email' : 'Email or Mobile Number';
  if (loginBtnText)  loginBtnText.textContent = isSignupMode
    ? (role === 'expert' ? 'Create Expert Account' : 'Create Account')
    : (role === 'expert' ? 'Expert Login →' : 'Sign In');
}

if (roleTabAthlete) roleTabAthlete.addEventListener('click', () => setRole('athlete'));
if (roleTabExpert)  roleTabExpert.addEventListener('click',  () => setRole('expert'));
if (expertHintBtn)  expertHintBtn.addEventListener('click',  () => {
  setRole('expert');
  document.getElementById('emailInput')?.focus();
});

/* ══════════════════════════════════════════════
   SIGNUP MODE TOGGLE
   ══════════════════════════════════════════════ */

function setSignupMode(on) {
  isSignupMode = on;
  const nameGroup      = document.getElementById('nameGroup');
  const confirmPwGroup = document.getElementById('confirmPwGroup');
  const forgotRow      = document.querySelector('.lf-row-between');

  if (nameGroup)      nameGroup.style.display     = on ? '' : 'none';
  if (confirmPwGroup) confirmPwGroup.style.display = on ? '' : 'none';
  if (forgotRow)      forgotRow.style.display      = on ? 'none' : '';

  if (loginCardTitle) loginCardTitle.textContent = on
    ? (selectedRole === 'expert' ? 'Create Expert Account 👨‍⚕️' : 'Create Account 🚀')
    : (selectedRole === 'expert' ? 'Expert Login 👨‍⚕️' : 'Welcome Back 👋');
  if (loginCardSub) loginCardSub.textContent = on
    ? 'Join ZITLAS — start your journey'
    : (selectedRole === 'expert' ? 'Sign in to your ZITLAS Expert Portal' : 'Sign in to continue your weight-loss journey');
  if (loginBtnText) loginBtnText.textContent = on
    ? (selectedRole === 'expert' ? 'Create Expert Account' : 'Create Account')
    : (selectedRole === 'expert' ? 'Expert Login →' : 'Sign In');
  if (createLink) createLink.textContent = on ? 'Already have an account? Sign In' : 'Create Account';
  if (expertHint) expertHint.style.display = (on || selectedRole === 'expert') ? 'none' : '';
  if (skipBtn)    skipBtn.style.display    = on ? 'none' : (selectedRole === 'expert' ? 'none' : '');
}

/* ══════════════════════════════════════════════
   AUTH ERROR MESSAGES
   ══════════════════════════════════════════════ */

function getAuthErrorMsg(code) {
  var msgs = {
    'auth/user-not-found':         'No account found with this email.',
    'auth/wrong-password':         'Incorrect password. Please try again.',
    'auth/invalid-credential':     'Invalid email or password.',
    'auth/email-already-in-use':   'An account with this email already exists.',
    'auth/weak-password':          'Password must be at least 6 characters.',
    'auth/invalid-email':          'Please enter a valid email address.',
    'auth/too-many-requests':      'Too many attempts. Please try again later.',
    'auth/network-request-failed': 'Network error. Check your connection.',
  };
  return msgs[code] || 'Authentication failed. Please try again.';
}

/* ══════════════════════════════════════════════
   FIREBASE — AUTO-REDIRECT IF ALREADY SIGNED IN
   ══════════════════════════════════════════════ */

if (typeof ZitlasAuth !== 'undefined') {
  ZitlasAuth.onAuthStateChanged(async function (user) {
    if (!user) return; /* not signed in — stay on login */
    console.log('[AUTH] onAuthStateChanged uid=' + user.uid + ' email=' + user.email);
    try {
      const docSnap = await ZitlasDB.collection('users').doc(user.uid).get();
      if (!docSnap.exists) return; /* new user awaiting role selection */
      const data = docSnap.data();
      console.log('[USER FOUND] uid=' + user.uid + ' email=' + user.email);

      /* Resolve role from new schema (roles[]/expert_status) or legacy (role field) */
      const roles        = Array.isArray(data.roles) ? data.roles : [];
      const expertStatus = data.expert_status || '';
      const legacyRole   = data.role          || '';
      const isExpert     =
        roles.includes('expert')         ||
        roles.includes('expert_pending') ||
        expertStatus === 'approved'      ||
        expertStatus === 'pending'       ||
        legacyRole   === 'expert';
      const resolvedRole = isExpert ? 'expert' : 'athlete';

      if (isExpert) console.log('[EXPERT FOUND] uid=' + user.uid + ' email=' + user.email);

      /* Update name/photo/last_login without touching roles or expert_status */
      try {
        await ZitlasDB.collection('users').doc(user.uid).update({
          name:       user.displayName || data.name  || '',
          photo:      user.photoURL    || data.photo || data.photo_url || null,
          last_login: firebase.firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      syncFirebaseUser(user, resolvedRole);

      const dest = resolvedRole === 'expert'
        ? '../experts/expert-dashboard.html'
        : (function () {
            const p = new URLSearchParams(window.location.search);
            const r = p.get('redirect');
            const q = sessionStorage.getItem('zitlas_pending_action');
            return (r === 'set-goal' || q === 'set-goal')
              ? '../dashboard/dashboard.html?action=set-goal'
              : '../dashboard/dashboard.html';
          }());
      console.log('[REDIRECT]', dest);
      window.location.replace(dest);
    } catch (e) {
      console.warn('[AUTH] onAuthStateChanged error:', e);
    }
  });
}

/* ══════════════════════════════════════════════
   REDIRECT DESTINATION
   Reads ?redirect= param + sessionStorage pending action
   ══════════════════════════════════════════════ */

function getRedirectDestination() {
  if (selectedRole === 'expert') {
    return '../experts/expert-dashboard.html';
  }
  const params   = new URLSearchParams(window.location.search);
  const redirect = params.get('redirect');
  const pending  = sessionStorage.getItem('zitlas_pending_action');

  if (redirect === 'set-goal' || pending === 'set-goal') {
    return '../dashboard/dashboard.html?action=set-goal';
  }
  return '../dashboard/dashboard.html';
}

/* ══════════════════════════════════════════════
   POST-LOGIN OVERLAY
   ══════════════════════════════════════════════ */

const loginOverlay = document.getElementById('loginOverlay');

function showLoginOverlay() {
  if (!loginOverlay) return;
  const msgEl = loginOverlay.querySelector('.overlay-msg');
  if (msgEl) {
    msgEl.textContent = selectedRole === 'expert'
      ? 'Expert Portal Loading 👨‍⚕️'
      : 'Welcome back 👋';
  }
  loginOverlay.removeAttribute('aria-hidden');
  loginOverlay.classList.add('active');
  const dest = getRedirectDestination();
  setTimeout(() => {
    sessionStorage.removeItem('zitlas_pending_action');
    window.location.href = dest;
  }, 1900);
}

/* ══════════════════════════════════════════════
   INPUT ERROR HELPER
   ══════════════════════════════════════════════ */

function setInputError(groupId) {
  const el = document.getElementById(groupId);
  if (!el) return;
  el.classList.add('input-error');
  el.addEventListener('animationend', () => el.classList.remove('input-error'), { once: true });
  el.querySelector('input')?.focus();
}

function clearInputError(groupId) {
  document.getElementById(groupId)?.classList.remove('input-error');
}

/* ══════════════════════════════════════════════
   LOGIN FORM
   ══════════════════════════════════════════════ */

const loginForm      = document.getElementById('loginForm');
const loginBtn       = document.getElementById('loginBtn');
const loginBtnText   = document.getElementById('loginBtnText');
const loginBtnSpinner = document.getElementById('loginBtnSpinner');
const emailInput     = document.getElementById('emailInput');
const passwordInput  = document.getElementById('passwordInput');
const nameInput      = document.getElementById('nameInput');
const confirmPwInput = document.getElementById('confirmPwInput');
const rememberInput  = document.getElementById('rememberInput');

function setLoading(on) {
  if (!loginBtn) return;
  loginBtn.disabled = on;
  if (loginBtnText)   loginBtnText.style.opacity = on ? '0' : '1';
  if (loginBtnSpinner) loginBtnSpinner.classList.toggle('active', on);
}

if (emailInput)    emailInput.addEventListener('input',    () => clearInputError('emailGroup'));
if (passwordInput) passwordInput.addEventListener('input', () => clearInputError('passwordGroup'));

if (loginForm) {
  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const email     = emailInput?.value.trim()  || '';
    const password  = passwordInput?.value      || '';
    const name      = nameInput?.value.trim()   || '';
    const confirmPw = confirmPwInput?.value     || '';

    if (!email)    { setInputError('emailGroup');    return; }
    if (!password) { setInputError('passwordGroup'); return; }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      setInputError('emailGroup');
      showToast('Please enter a valid email address.');
      return;
    }

    if (typeof ZitlasAuth === 'undefined') {
      showToast('Firebase not configured. Please set up firebase-config.js.');
      return;
    }

    if (isSignupMode) {
      if (!name)                 { setInputError('nameGroup');      showToast('Please enter your full name.');           return; }
      if (password.length < 6)   { setInputError('passwordGroup'); showToast('Password must be at least 6 characters.'); return; }
      if (password !== confirmPw) { setInputError('confirmPwGroup'); showToast('Passwords do not match.');               return; }
    }

    setLoading(true);

    try {
      if (isSignupMode) {
        /* ── STEP 1: Pre-auth checks — no Firebase Auth account exists yet ── */

        /* Abort if email already has ANY sign-in method */
        const existingMethods = await ZitlasAuth.fetchSignInMethodsForEmail(email);
        if (existingMethods.length > 0) {
          showToast('Account already exists. Please sign in.');
          setLoading(false);
          return;
        }

        /* For experts: check Firestore BEFORE creating the Auth account */
        if (selectedRole === 'expert') {
          const existingExpert = await ZitlasDB.collection('experts')
            .where('email', '==', email).limit(1).get();
          if (!existingExpert.empty) {
            console.log('[EXPERT FOUND] by email before signup — aborting account creation');
            showToast('Expert account already exists. Please sign in.');
            setLoading(false);
            return;
          }
        }

        /* ── STEP 2: Create Firebase Auth account ── */
        const cred = await ZitlasAuth.createUserWithEmailAndPassword(email, password);
        const user = cred.user;

        /* ── STEP 3: Firestore setup — rollback Auth account on any failure ── */
        try {
          await user.updateProfile({ displayName: name });
          const ts = firebase.firestore.FieldValue.serverTimestamp();

          if (selectedRole === 'expert') {
            console.log('[PROFILE CREATED] new expert uid=' + user.uid + ' email=' + user.email);
            await ZitlasDB.collection('users').doc(user.uid).set({
              uid: user.uid, email: user.email, name,
              role: 'expert', photo: '', createdAt: ts,
            });
            await ZitlasDB.collection('experts').doc(user.uid).set({
              uid: user.uid, email: user.email, name,
              role: 'expert', speciality: '', photo: '',
              verified: false, approved: false, rating: 0, reviews: 0, createdAt: ts,
            });
            syncEmailUser(user, name, 'expert');
            setLoading(false);
            showToast('Expert account created! Your application is under review.');
            setTimeout(() => window.location.replace('../experts/expert-dashboard.html'), 2200);
          } else {
            await ZitlasDB.collection('users').doc(user.uid).set({
              uid: user.uid, email: user.email, name,
              role: 'athlete', photo: '', createdAt: ts,
            });
            syncEmailUser(user, name, 'athlete');
            selectedRole = 'athlete';
            showLoginOverlay();
          }
        } catch (firestoreErr) {
          /* Rollback: delete the just-created Auth account so the email stays free */
          console.warn('[AUTH] Firestore setup failed — deleting orphan Auth account', firestoreErr);
          try { await user.delete(); } catch (_) {}
          throw firestoreErr; /* re-throw so outer catch shows the error */
        }
      } else {
        /* ── Sign In ── */
        await ZitlasAuth.signInWithEmailAndPassword(email, password);
        if (rememberInput?.checked) localStorage.setItem('zitlas_remember', 'true');
        /* onAuthStateChanged handles localStorage sync + redirect — keep loading state */
      }
    } catch (err) {
      setLoading(false);
      showToast(getAuthErrorMsg(err.code));
      if (['auth/user-not-found', 'auth/wrong-password', 'auth/invalid-credential'].includes(err.code)) {
        setInputError('emailGroup');
        setInputError('passwordGroup');
      } else if (err.code === 'auth/email-already-in-use') {
        setInputError('emailGroup');
      } else if (err.code === 'auth/weak-password') {
        setInputError('passwordGroup');
      }
    }
  });
}

/* ══════════════════════════════════════════════
   GOOGLE SIGN-IN — Firebase Authentication
   ══════════════════════════════════════════════ */

const googleBtn = document.getElementById('googleBtn');

function setGoogleLoading(on) {
  if (!googleBtn) return;
  googleBtn.disabled       = on;
  googleBtn.style.opacity  = on ? '0.6' : '';
  googleBtn.style.cursor   = on ? 'wait' : '';
  const span = googleBtn.querySelector('span:last-of-type');
  if (span) span.textContent = on ? 'Signing in…' : 'Continue with Google';
}

if (googleBtn) {
  googleBtn.addEventListener('click', async () => {

    /* Graceful fallback if Firebase config is missing */
    if (typeof ZitlasAuth === 'undefined') {
      showToast('Firebase not configured — fill in firebase-config.js first');
      return;
    }

    try {
      setGoogleLoading(true);

      const provider = new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });

      const result = await ZitlasAuth.signInWithPopup(provider);
      const user   = result.user;
      console.log('[GOOGLE LOGIN] uid=' + user.uid + ' email=' + user.email);

      /* Check Firestore for existing role */
      const doc = await ZitlasDB.collection('users').doc(user.uid).get();

      if (doc.exists) {
        /* Returning user — resolve role from new schema OR legacy schema */
        const data        = doc.data();
        const roles       = Array.isArray(data.roles) ? data.roles : [];
        const expertStatus = data.expert_status || '';
        const legacyRole  = data.role           || '';
        const isExpert    =
          roles.includes('expert')         ||
          roles.includes('expert_pending') ||
          expertStatus === 'approved'      ||
          expertStatus === 'pending'       ||
          legacyRole   === 'expert';
        const resolvedRole = isExpert ? 'expert' : 'athlete';

        console.log('[USER FOUND] uid=' + user.uid + ' resolvedRole=' + resolvedRole);
        if (isExpert) console.log('[EXPERT FOUND] uid=' + user.uid + ' email=' + user.email);

        /* Update name/photo/last_login without overwriting roles/expert_status */
        try {
          await ZitlasDB.collection('users').doc(user.uid).update({
            name:       user.displayName || '',
            photo:      user.photoURL    || null,
            last_login: firebase.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}

        syncFirebaseUser(user, resolvedRole);
        selectedRole = resolvedRole;
        showLoginOverlay();
      } else {
        /* New Google user — check experts collection by email before showing role modal */
        console.log('[GOOGLE LOGIN] No users doc for uid=' + user.uid + ' — checking experts by email');
        const expertByEmail = await ZitlasDB.collection('experts')
          .where('email', '==', user.email).limit(1).get();
        if (!expertByEmail.empty) {
          console.log('[EXPERT FOUND] by email', user.email);
          await ZitlasDB.collection('users').doc(user.uid).set({
            uid: user.uid, name: user.displayName || '', email: user.email || '',
            photo: user.photoURL || null, role: 'expert',
            created_at: firebase.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          syncFirebaseUser(user, 'expert');
          selectedRole = 'expert';
          showLoginOverlay();
        } else {
          setGoogleLoading(false);
          showRoleModal(user);
        }
      }

    } catch (err) {
      setGoogleLoading(false);
      /* Ignore user-cancelled popup */
      if (err.code === 'auth/popup-closed-by-user' ||
          err.code === 'auth/cancelled-popup-request') return;
      console.error('[ZITLAS] Google sign-in error:', err);
      showToast(err.message || 'Sign-in failed. Please try again.');
    }
  });
}

/* ══════════════════════════════════════════════
   SKIP FOR NOW
   ══════════════════════════════════════════════ */

if (skipBtn) {
  skipBtn.addEventListener('click', () => {
    sessionStorage.setItem('zitlas_guest', '1');
    sessionStorage.removeItem('zitlas_pending_action');
    window.location.href = getRedirectDestination();
  });
}

/* ══════════════════════════════════════════════
   FIREBASE HELPERS
   ══════════════════════════════════════════════ */

function _clearAuthLocalStorage() {
  ['zitlas_user','zitlas_user_role','zitlas_expert_profile','zitlas_expert_id',
   'zitlas_firebase_user','zitlas_token','loggedIn','currentUser','user'
  ].forEach(function(k) { localStorage.removeItem(k); });
  console.log('[LOCAL STORAGE CLEARED]');
}

function _addToExpertsStorage(uid, email, name) {
  var list = [];
  try {
    var _parsed = JSON.parse(localStorage.getItem('zitlas_experts'));
    if (Array.isArray(_parsed)) list = _parsed;
  } catch(_) {}
  var expertProfile = { id: uid, name: name, email: email, role: 'expert', approved: true, rating: 0, specialization: 'General Fitness' };
  console.log('[EXPERT SIGNUP]', expertProfile);
  if (!list.some(function(e) { return e.id === uid; })) {
    list.push(expertProfile);
  }
  localStorage.setItem('zitlas_experts', JSON.stringify(list));
  console.log('[EXPERTS]', list);
}

function syncFirebaseUser(user, role) {
  _clearAuthLocalStorage();
  console.log('[AUTH] syncFirebaseUser uid=' + user.uid + ' role=' + role);

  const provider = (user.providerData && user.providerData[0])
    ? user.providerData[0].providerId : 'password';

  localStorage.setItem('zitlas_user', JSON.stringify({
    uid:      user.uid,
    name:     user.displayName || '',
    email:    user.email       || '',
    photo:    user.photoURL    || null,
    provider: provider,
  }));
  localStorage.setItem('loggedIn', 'true');
  localStorage.setItem('zitlas_token',     'firebase_' + user.uid);
  localStorage.setItem('zitlas_user_role', role);

  if (role === 'expert') {
    localStorage.setItem('zitlas_expert_id', user.uid);
    localStorage.setItem('zitlas_expert_profile', JSON.stringify({
      uid:   user.uid,
      email: user.email          || '',
      name:  user.displayName    || '',
      role:  'expert',
    }));
    _addToExpertsStorage(user.uid, user.email || '', user.displayName || '');
  }

  localStorage.setItem('zitlas_firebase_user', JSON.stringify({
    uid:   user.uid,
    name:  user.displayName  || '',
    email: user.email        || '',
    photo: user.photoURL     || null,
    role:  role,
  }));
}

/* Sync for email/password sign-ups (name may not be set on user.displayName yet) */
function syncEmailUser(user, name, role) {
  _clearAuthLocalStorage();
  console.log('[AUTH] syncEmailUser uid=' + user.uid + ' role=' + role);

  const userName = name || user.displayName || '';
  localStorage.setItem('zitlas_user', JSON.stringify({
    uid:      user.uid,
    name:     userName,
    email:    user.email || '',
    photo:    null,
    provider: 'password',
  }));
  localStorage.setItem('loggedIn',         'true');
  localStorage.setItem('zitlas_token',     'firebase_' + user.uid);
  localStorage.setItem('zitlas_user_role', role);

  if (role === 'expert') {
    localStorage.setItem('zitlas_expert_id', user.uid);
    localStorage.setItem('zitlas_expert_profile', JSON.stringify({
      uid:   user.uid,
      email: user.email || '',
      name:  userName,
      role:  'expert',
    }));
    _addToExpertsStorage(user.uid, user.email || '', userName);
  }

  localStorage.setItem('zitlas_firebase_user', JSON.stringify({
    uid:   user.uid,
    name:  userName,
    email: user.email || '',
    photo: null,
    role:  role,
  }));

  if (rememberInput?.checked) localStorage.setItem('zitlas_remember', 'true');
}

/* ══════════════════════════════════════════════
   GOOGLE ROLE-SELECTION MODAL (new users only)
   ══════════════════════════════════════════════ */

let _pendingGoogleUser = null;

function showRoleModal(user) {
  _pendingGoogleUser = user;
  const backdrop = document.getElementById('grmBackdrop');
  if (!backdrop) return;

  const photoEl = document.getElementById('grmPhoto');
  const nameEl  = document.getElementById('grmUserName');
  const emailEl = document.getElementById('grmUserEmail');

  if (photoEl) {
    if (user.photoURL) { photoEl.src = user.photoURL; photoEl.style.display = ''; }
    else               { photoEl.style.display = 'none'; }
  }
  if (nameEl)  nameEl.textContent  = user.displayName || 'User';
  if (emailEl) emailEl.textContent = user.email       || '';

  backdrop.removeAttribute('aria-hidden');
  backdrop.classList.add('active');
  document.body.style.overflow = 'hidden';
}

function hideRoleModal() {
  const backdrop = document.getElementById('grmBackdrop');
  if (backdrop) {
    backdrop.setAttribute('aria-hidden', 'true');
    backdrop.classList.remove('active');
  }
  document.body.style.overflow = '';
}

(function initRoleModal() {
  const options     = document.querySelectorAll('.grm-option');
  const confirmBtn  = document.getElementById('grmConfirm');
  const confirmTxt  = document.getElementById('grmConfirmText');
  const confirmSpin = document.getElementById('grmConfirmSpinner');
  let   chosenRole  = null;

  options.forEach(function (opt) {
    opt.addEventListener('click', function () {
      options.forEach(function (o) { o.classList.remove('active'); });
      opt.classList.add('active');
      chosenRole = opt.dataset.role;
      if (confirmBtn) confirmBtn.disabled = false;
    });
  });

  if (!confirmBtn) return;

  confirmBtn.addEventListener('click', async function () {
    if (!chosenRole || !_pendingGoogleUser) return;
    const user = _pendingGoogleUser;

    confirmBtn.disabled = true;
    if (confirmTxt)  confirmTxt.textContent   = 'Setting up…';
    if (confirmSpin) confirmSpin.style.display = 'flex';

    try {
      /* Phase 5 — Firestore schema: roles[] + expert_status (never overwrites on update) */
      const newRoles = ['athlete'];
      if (chosenRole === 'expert') newRoles.push('expert_pending');

      await ZitlasDB.collection('users').doc(user.uid).set({
        uid:           user.uid,
        name:          user.displayName || '',
        email:         user.email       || '',
        photo:         user.photoURL    || null,
        roles:         newRoles,
        expert_status: chosenRole === 'expert' ? 'pending' : 'none',
        created_at:    firebase.firestore.FieldValue.serverTimestamp(),
      });

      if (chosenRole === 'expert') {
        /* Mark application pending in localStorage so profile.html can show the banner */
        localStorage.setItem('zitlas_expert_applied', user.email || 'true');
        /* Show "Application Under Review" panel — do NOT redirect to expert-dashboard */
        showExpertApplicationReview(user.email);
      } else {
        syncFirebaseUser(user, chosenRole);
        selectedRole = chosenRole;
        hideRoleModal();
        showLoginOverlay();
      }

    } catch (err) {
      console.error('[ZITLAS] saveUserRole error:', err);
      confirmBtn.disabled = false;
      if (confirmTxt)  confirmTxt.textContent   = 'Continue →';
      if (confirmSpin) confirmSpin.style.display = 'none';
      showToast('Failed to save account. Please try again.');
    }
  });

  /* Wire "Continue as Athlete" button on the under-review panel */
  const reviewHomeBtn = document.getElementById('grmReviewHomeBtn');
  if (reviewHomeBtn) {
    reviewHomeBtn.addEventListener('click', function () {
      console.log('[ZITLAS] Under-review → continuing as athlete guest');
      sessionStorage.setItem('zitlas_guest', '1');
      /* replace() so the back button does NOT return to the application form */
      window.location.replace('../dashboard/dashboard.html');
    });
  }
}());

function showExpertApplicationReview(email) {
  /* Hide the role-selection form elements */
  ['grmUserStrip', 'grmTitle'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.style.display = 'none';
  });
  document.querySelectorAll('.grm-sub, .grm-options, .grm-confirm-btn').forEach(function (el) {
    el.style.display = 'none';
  });

  /* Update email line and show the under-review panel */
  var emailEl = document.getElementById('grmReviewEmail');
  if (emailEl && email) {
    emailEl.textContent = 'Application submitted for ' + email;
  }
  var panel = document.getElementById('grmUnderReview');
  if (panel) panel.style.display = 'flex';
}

/* ══════════════════════════════════════════════
   CREATE ACCOUNT / FORGOT PASSWORD
   ══════════════════════════════════════════════ */

const createLink = document.getElementById('createLink');
if (createLink) {
  createLink.addEventListener('click', (e) => {
    e.preventDefault();
    setSignupMode(!isSignupMode);
  });
}

const forgotLink = document.getElementById('forgotLink');
if (forgotLink) {
  forgotLink.addEventListener('click', async (e) => {
    e.preventDefault();
    const email = emailInput?.value.trim() || '';
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      showToast('Enter your email address above, then click Forgot Password.');
      setInputError('emailGroup');
      return;
    }
    if (typeof ZitlasAuth === 'undefined') return;
    try {
      await ZitlasAuth.sendPasswordResetEmail(email);
      showToast('Password reset email sent! Check your inbox.');
    } catch (err) {
      showToast(getAuthErrorMsg(err.code));
    }
  });
}

/* ══════════════════════════════════════════════
   MINI TOAST
   ══════════════════════════════════════════════ */

let _toastEl, _toastTimer;

function showToast(msg) {
  if (!_toastEl) {
    _toastEl = document.createElement('div');
    _toastEl.style.cssText = [
      'position:fixed',
      'bottom:28px',
      'left:50%',
      'transform:translateX(-50%)',
      'background:var(--bg-card)',
      'border:1px solid var(--border)',
      'color:var(--text-primary)',
      'font-size:13px',
      'font-weight:600',
      'padding:11px 22px',
      'border-radius:40px',
      'box-shadow:0 4px 24px rgba(var(--black-rgb),0.5)',
      'z-index:10000',
      'opacity:0',
      'transition:opacity 0.22s ease',
      'pointer-events:none',
      'font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif',
      'white-space:nowrap',
    ].join(';');
    document.body.appendChild(_toastEl);
  }
  clearTimeout(_toastTimer);
  _toastEl.textContent = msg;
  _toastEl.style.opacity = '1';
  _toastTimer = setTimeout(() => { _toastEl.style.opacity = '0'; }, 2600);
}
