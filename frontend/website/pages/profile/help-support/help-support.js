/* =============================================
   ZITLAS Help & Support — help-support.js
   ============================================= */

(function () {
  'use strict';

  /* ---- Theme ---- */
  (function applyTheme() {
    const saved = localStorage.getItem('zitlas_theme') || 'dark';
    const resolved = saved === 'system'
      ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
      : saved;
    document.documentElement.setAttribute('data-theme', resolved);
  })();

  /* ---- DOM refs ---- */
  const form           = document.getElementById('supportForm');
  const nameField      = document.getElementById('nameField');
  const emailField     = document.getElementById('emailField');
  const subjectField   = document.getElementById('subjectField');
  const categoryField  = document.getElementById('categoryField');
  const messageField   = document.getElementById('messageField');
  const screenshotField= document.getElementById('screenshotField');
  const fileUploadArea = document.getElementById('fileUploadArea');
  const fileUploadText = document.getElementById('fileUploadText');
  const fileRemoveBtn  = document.getElementById('fileRemoveBtn');
  const charCountEl    = document.getElementById('charCount');
  const charCounterEl  = document.getElementById('charCounterEl');
  const sendBtn        = document.getElementById('sendBtn');
  const sendBtnText    = document.getElementById('sendBtnText');
  const toastEl        = document.getElementById('toast');
  const formSection    = document.getElementById('formSection');

  /* ---- Toast ---- */
  let toastTimer = null;
  function showToast(msg, type = '', duration = 3000) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.className = 'toast show' + (type ? ' ' + type : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toastEl.classList.remove('show');
    }, duration);
  }

  /* ---- Pre-fill from localStorage ---- */
  function prefillFromStorage() {
    try {
      const user = JSON.parse(localStorage.getItem('zitlas_user') || localStorage.getItem('user') || 'null');
      if (user) {
        if (user.name && nameField) nameField.value = user.name;
        if (user.email && emailField) emailField.value = user.email;
      }
    } catch (_) {}
  }

  /* ---- Char counter ---- */
  function updateCharCounter() {
    const len = messageField.value.length;
    charCountEl.textContent = len;
    charCounterEl.className = 'char-counter' + (len >= 20 ? ' ok' : len > 0 ? ' warn' : '');
  }

  if (messageField) {
    messageField.addEventListener('input', updateCharCounter);
  }

  /* ---- File upload ---- */
  let selectedFile = null;

  function onFileChange() {
    const file = screenshotField.files[0];
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      showToast('File too large — max 5 MB.', 'error');
      screenshotField.value = '';
      return;
    }

    selectedFile = file;
    fileUploadText.textContent = file.name;
    fileUploadArea.classList.add('has-file');
    fileRemoveBtn.classList.add('visible');
  }

  function removeFile() {
    selectedFile = null;
    screenshotField.value = '';
    fileUploadText.textContent = 'Click to attach a screenshot';
    fileUploadArea.classList.remove('has-file');
    fileRemoveBtn.classList.remove('visible');
  }

  if (screenshotField) screenshotField.addEventListener('change', onFileChange);
  if (fileRemoveBtn)  fileRemoveBtn.addEventListener('click', removeFile);

  /* ---- Validation helpers ---- */
  function setError(fieldEl, errEl, msg) {
    if (fieldEl) fieldEl.classList.add('error');
    if (errEl)   errEl.textContent = msg;
  }

  function clearError(fieldEl, errEl) {
    if (fieldEl) fieldEl.classList.remove('error');
    if (errEl)   errEl.textContent = '';
  }

  function isValidEmail(v) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.trim());
  }

  function validateForm() {
    let valid = true;

    const nameErr     = document.getElementById('nameError');
    const emailErr    = document.getElementById('emailError');
    const subjectErr  = document.getElementById('subjectError');
    const categoryErr = document.getElementById('categoryError');
    const messageErr  = document.getElementById('messageError');

    /* Name */
    if (!nameField.value.trim()) {
      setError(nameField, nameErr, 'Full name is required.');
      valid = false;
    } else {
      clearError(nameField, nameErr);
    }

    /* Email */
    if (!emailField.value.trim()) {
      setError(emailField, emailErr, 'Email is required.');
      valid = false;
    } else if (!isValidEmail(emailField.value)) {
      setError(emailField, emailErr, 'Enter a valid email address.');
      valid = false;
    } else {
      clearError(emailField, emailErr);
    }

    /* Subject */
    if (!subjectField.value.trim()) {
      setError(subjectField, subjectErr, 'Subject is required.');
      valid = false;
    } else {
      clearError(subjectField, subjectErr);
    }

    /* Category */
    if (!categoryField.value) {
      setError(categoryField, categoryErr, 'Please select a category.');
      valid = false;
    } else {
      clearError(categoryField, categoryErr);
    }

    /* Message */
    if (!messageField.value.trim()) {
      setError(messageField, messageErr, 'Message is required.');
      valid = false;
    } else if (messageField.value.trim().length < 20) {
      setError(messageField, messageErr, 'Message must be at least 20 characters.');
      valid = false;
    } else {
      clearError(messageField, messageErr);
    }

    return valid;
  }

  /* ---- Clear errors on input ---- */
  function attachClearOnInput(field, errId) {
    if (!field) return;
    field.addEventListener('input', () => clearError(field, document.getElementById(errId)));
    field.addEventListener('change', () => clearError(field, document.getElementById(errId)));
  }

  attachClearOnInput(nameField,     'nameError');
  attachClearOnInput(emailField,    'emailError');
  attachClearOnInput(subjectField,  'subjectError');
  attachClearOnInput(categoryField, 'categoryError');
  attachClearOnInput(messageField,  'messageError');

  /* ---- Submit state helpers ---- */
  function setLoading(on) {
    sendBtn.disabled = on;
    if (on) {
      sendBtnText.textContent = 'Sending…';
      sendBtn.insertAdjacentHTML('afterbegin', '<span class="spinner"></span>');
    } else {
      sendBtnText.textContent = 'Send Message';
      const spinner = sendBtn.querySelector('.spinner');
      if (spinner) spinner.remove();
    }
  }

  /* ---- Clear form ---- */
  function clearForm() {
    form.reset();
    removeFile();
    updateCharCounter();
    document.querySelectorAll('.field-error').forEach(el => (el.textContent = ''));
    document.querySelectorAll('.form-input, .form-select, .form-textarea').forEach(el => el.classList.remove('error'));
  }

  /* ---- Submit ---- */
  async function handleSubmit(e) {
    e.preventDefault();

    if (!validateForm()) {
      const firstErr = form.querySelector('.form-input.error, .form-select.error, .form-textarea.error');
      if (firstErr) firstErr.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }

    setLoading(true);

    const payload = {
      name:     nameField.value.trim(),
      email:    emailField.value.trim(),
      subject:  subjectField.value.trim(),
      category: categoryField.value,
      message:  messageField.value.trim(),
    };

    try {
      const res = await fetch('/api/support/contact', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(payload),
      });

      const data = await res.json().catch(() => ({}));

      if (res.ok) {
        showToast('Your message has been sent to Team ZITLAS.', 'success', 4000);
        clearForm();
      } else {
        const msg = data.detail || 'Something went wrong. Please try again.';
        showToast(msg, 'error', 4000);
      }
    } catch (_) {
      showToast('Network error. Please check your connection.', 'error', 4000);
    } finally {
      setLoading(false);
    }
  }

  if (form) form.addEventListener('submit', handleSubmit);

  /* ---- Init ---- */
  function init() {
    prefillFromStorage();
    updateCharCounter();
    /* Trigger entrance animation */
    requestAnimationFrame(() => {
      if (formSection) formSection.classList.add('visible');
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
