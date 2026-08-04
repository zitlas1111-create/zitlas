/*!
 * ZITLAS — Admin Certificate Review (pages/admin/admin-review.js)
 *
 * Gated by users/{uid}.roles including 'admin' (or legacy role === 'admin'),
 * mirroring the exact expert role-check pattern used in login.js /
 * expert-dashboard.js. There is no admin-invite UI in this project yet —
 * grant access by adding role:'admin' (or roles:['admin']) to a user's
 * Firestore doc directly.
 */
(function () {
  'use strict';

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function timeAgo(iso) {
    if (!iso) return '';
    var min = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
    if (min < 1) return 'just now';
    if (min < 60) return min + ' min ago';
    var hr = Math.floor(min / 60);
    if (hr < 24) return hr + 'h ago';
    return Math.floor(hr / 24) + 'd ago';
  }

  var _adminUid = null;
  var _certs = [];

  function showAccessDenied() {
    $('admMain').innerHTML =
      '<div class="adm-access-denied">' +
        '<span class="adm-access-icon">🔒</span>' +
        '<p class="adm-access-title">Admin Access Required</p>' +
        '<p class="adm-access-sub">This page is restricted to ZITLAS admins. If you believe this is a mistake, ask an existing admin to grant your account the "admin" role.</p>' +
      '</div>';
  }

  function isAdmin(userData) {
    var roles = Array.isArray(userData.roles) ? userData.roles : [];
    return roles.indexOf('admin') !== -1 || userData.role === 'admin';
  }

  function boot() {
    if (typeof ZitlasAuth === 'undefined') { showAccessDenied(); return; }
    ZitlasAuth.onAuthStateChanged(function (user) {
      if (!user) { showAccessDenied(); return; }
      /* AUTHORITATIVE admin signal is the `admin` CUSTOM CLAIM baked into the
         ID token (backend-set, not client-writable) — the ONLY thing trusted
         here. It matches what the pending-certificates Security Rule requires
         and what the backend approval endpoints enforce. The old
         users/{uid}.role=='admin' fallback was removed: that field is
         client-writable, and a spoofed role would render the shell but the
         Firestore cert listing (rule needs the claim) and every backend
         approval (require_admin) would reject anyway — so the fallback was a
         useless spoof surface. Bootstrap the first admin via ZITLAS_ADMIN_UIDS
         + POST /api/admin/grant-admin, then re-login. */
      user.getIdTokenResult().then(function (res) {
        var claimAdmin = !!(res && res.claims && res.claims.admin);
        if (!claimAdmin) { showAccessDenied(); return; }
        _adminUid = user.uid;
        renderShell();
        ZitlasCertificates.listenForPendingCertificates(onCertsUpdate);
      }).catch(function (e) {
        console.error('[ADMIN] admin claim check failed', e);
        showAccessDenied();
      });
    });
  }

  function renderShell() {
    $('admMain').innerHTML =
      '<p class="adm-section-title">Pending Certificate Reviews</p>' +
      '<div id="admCertList"></div>';
  }

  function onCertsUpdate(certs) {
    _certs = certs;
    var badge = $('admPendingBadge');
    if (badge) {
      badge.textContent = certs.length + ' pending';
      badge.style.display = certs.length ? '' : 'none';
    }
    renderList();
  }

  function renderList() {
    var wrap = $('admCertList');
    if (!wrap) return;
    if (!_certs.length) {
      wrap.innerHTML = '<div class="adm-empty"><span class="adm-empty-icon">✅</span>All caught up — no certificates awaiting review.</div>';
      return;
    }
    wrap.innerHTML = _certs.map(function (cert) { return buildCard(cert); }).join('');
    _certs.forEach(function (cert) {
      var card = document.getElementById('admCard_' + cert.certId);
      if (!card) return;
      var thumb = card.querySelector('[data-adm-thumb]');
      if (thumb) thumb.addEventListener('click', function () { ZitlasCertificates.openViewCertificate(cert); });

      card.querySelector('[data-adm-approve]').addEventListener('click', function (e) {
        var btn = e.currentTarget;
        btn.disabled = true; btn.textContent = 'Approving…';
        ZitlasCertificates.approveCertificate(cert, _adminUid)
          .then(function () { ZitlasCertificates.toast('✅ Certificate approved — Verified Expert badge is now live.'); })
          .catch(function (err) { console.error('[ADMIN] approve failed', err); ZitlasCertificates.toast('Could not approve — try again.'); btn.disabled = false; btn.textContent = 'Approve'; });
      });

      var rejectBtn = card.querySelector('[data-adm-reject]');
      var panel = card.querySelector('[data-adm-reject-panel]');
      rejectBtn.addEventListener('click', function () { panel.classList.toggle('show'); });

      var selectedReason = null;
      card.querySelectorAll('[data-adm-reason]').forEach(function (chip) {
        chip.addEventListener('click', function () {
          selectedReason = chip.dataset.admReason;
          card.querySelectorAll('[data-adm-reason]').forEach(function (c) { c.classList.remove('selected'); });
          chip.classList.add('selected');
          card.querySelector('[data-adm-reject-confirm]').disabled = false;
        });
      });
      card.querySelector('[data-adm-reject-confirm]').addEventListener('click', function (e) {
        if (!selectedReason) return;
        var btn = e.currentTarget;
        btn.disabled = true; btn.textContent = 'Rejecting…';
        ZitlasCertificates.rejectCertificate(cert, _adminUid, selectedReason)
          .then(function () { ZitlasCertificates.toast('Certificate rejected: ' + selectedReason); })
          .catch(function (err) { console.error('[ADMIN] reject failed', err); ZitlasCertificates.toast('Could not reject — try again.'); btn.disabled = false; btn.textContent = 'Confirm Rejection'; });
      });
    });
  }

  function buildCard(cert) {
    var isPdf = (cert.fileType || '').indexOf('pdf') !== -1;
    var flags = [
      { key: 'hasOfficialLogo',  label: 'Logo',      good: true },
      { key: 'hasSignature',     label: 'Signature',  good: true },
      { key: 'hasQrCode',        label: 'QR Code',    good: true },
      { key: 'hasStampOrSeal',   label: 'Stamp',      good: true },
      { key: 'signsOfTampering', label: 'Tampering',  good: false },
      { key: 'isBlurry',         label: 'Blurry',     good: false },
      { key: 'hasCroppedText',   label: 'Cropped Text', good: false },
      { key: 'missingIssuer',    label: 'Missing Issuer', good: false },
    ];
    var f = cert.flags || {};
    var flagsHtml = flags.map(function (fl) {
      var present = !!f[fl.key];
      if (fl.good && !present) return '';
      if (!fl.good && !present) return '';
      var warn = (fl.good && !present) || (!fl.good && present);
      return '<span class="adm-flag' + (warn ? ' adm-flag--warn' : '') + '">' +
        (fl.good ? '✓ ' : '⚠ ') + esc(fl.label) + '</span>';
    }).join('');

    return '<div class="adm-cert-card" id="admCard_' + esc(cert.certId) + '">' +
      '<div class="adm-cert-head">' +
        '<span class="adm-cert-expert">' + esc(cert.expertName || 'Expert') + '</span>' +
        '<span class="adm-cert-time">' + esc(timeAgo(cert.uploadedAt)) + '</span>' +
      '</div>' +
      '<div class="adm-cert-body">' +
        (isPdf
          ? '<div class="adm-cert-thumb-pdf" data-adm-thumb>📄</div>'
          : '<img class="adm-cert-thumb" src="' + esc(cert.certificateUrl) + '" alt="Certificate" data-adm-thumb>') +
        '<div>' +
          '<div class="adm-field-row"><span>Certificate</span><b>' + esc(cert.certificateName || '—') + '</b></div>' +
          '<div class="adm-field-row"><span>Organization</span><b>' + esc(cert.issuingOrganization || '—') + '</b></div>' +
          '<div class="adm-field-row"><span>Coach Name (OCR)</span><b>' + esc(cert.coachName || '—') + '</b></div>' +
          '<div class="adm-field-row"><span>Cert Number</span><b>' + esc(cert.certificateNumber || '—') + '</b></div>' +
          '<div class="adm-field-row"><span>Issued / Expires</span><b>' + esc(cert.issuedDate || '—') + ' / ' + esc(cert.expiryDate || '—') + '</b></div>' +
        '</div>' +
      '</div>' +
      '<div class="adm-score-line">' +
        '<div class="adm-score-bar"><div class="adm-score-fill" style="width:' + esc(String(cert.verificationScore || 0)) + '%"></div></div>' +
        '<span class="adm-score-val">' + esc(String(cert.verificationScore || 0)) + '%</span>' +
      '</div>' +
      '<div class="adm-flags">' + flagsHtml + '</div>' +
      (cert.analysisNotes ? '<p class="adm-notes">"' + esc(cert.analysisNotes) + '"</p>' : '') +
      '<div class="adm-actions">' +
        '<button class="adm-btn adm-btn--approve" data-adm-approve>Approve</button>' +
        '<button class="adm-btn adm-btn--reject" data-adm-reject>Reject</button>' +
      '</div>' +
      '<div class="adm-reject-panel" data-adm-reject-panel>' +
        '<div class="adm-reason-grid">' +
          ZitlasCertificates.REJECT_REASONS.map(function (r) {
            return '<button class="adm-reason-chip" data-adm-reason="' + esc(r) + '">' + esc(r) + '</button>';
          }).join('') +
        '</div>' +
        '<button class="adm-reject-confirm" data-adm-reject-confirm disabled>Confirm Rejection</button>' +
      '</div>' +
    '</div>';
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
