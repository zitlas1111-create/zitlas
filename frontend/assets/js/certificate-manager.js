/*!
 * ZITLAS — Expert Certificate Verification (assets/js/certificate-manager.js)
 *
 * Shared logic used by expert-dashboard.js (upload + own certs), cprofile.js
 * (Verified Certificates + ZITLAS Verification modal), and the admin review
 * dashboard. Firestore-first architecture like the rest of this app — this
 * backend has no Firebase Admin SDK anywhere, so all Firestore writes happen
 * from the authenticated client, same as every other feature in ZITLAS.
 *
 * Firestore: expert_certificates/{certId}
 *   { certId, expertId, expertName, certificateUrl, fileType,
 *     coachName, certificateName, issuingOrganization, certificateNumber,
 *     issuedDate, expiryDate, verificationScore, verificationStatus
 *       ('verified' | 'pending_review' | 'rejected'),
 *     flags: {...}, analysisNotes,
 *     uploadedAt, reviewedBy, reviewedAt, rejectionReason }
 *
 * SECURITY NOTE: verificationStatus is only ever set by (a) the AI's own
 * computed result at upload time (backend-computed, client just persists —
 * never a user-editable field in any UI), or (b) the admin Approve/Reject
 * actions below. No UI anywhere lets an expert edit their own status. Real
 * enforcement ultimately needs Firestore security rules — flagged
 * repeatedly elsewhere in this project as a standing gap (currently
 * world-readable/writable) that should be closed before this ships wide.
 */
(function (win) {
  'use strict';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function db() { return (typeof ZitlasDB !== 'undefined') ? ZitlasDB : null; }
  function newId() { return 'CERT_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8); }

  var _toastEl = null, _toastTimer = null;
  function toast(msg) {
    if (!_toastEl) {
      _toastEl = document.createElement('div');
      _toastEl.className = 'cert-toast';
      document.body.appendChild(_toastEl);
    }
    _toastEl.textContent = msg;
    _toastEl.classList.add('show');
    clearTimeout(_toastTimer);
    _toastTimer = setTimeout(function () { _toastEl.classList.remove('show'); }, 3600);
  }

  /* ── Upload + AI verification (backend) ── */
  function uploadAndVerify(expertId, file) {
    var fd = new FormData();
    fd.append('expertId', expertId);
    fd.append('file', file);
    return fetch('/api/certificates/verify', { method: 'POST', body: fd })
      .then(function (r) {
        if (!r.ok) return r.json().catch(function () { return null; }).then(function (e) {
          throw new Error((e && e.detail) || ('Verification failed (' + r.status + ')'));
        });
        return r.json();
      });
  }

  /* ── Persist an accepted result as a new certificate doc ── */
  function saveCertificate(expertId, expertName, result) {
    var d = db();
    if (!d) return Promise.reject(new Error('Database unavailable'));
    var id = newId();
    var doc = {
      certId: id, expertId: expertId, expertName: expertName || 'Expert',
      certificateUrl: result.certificateUrl, fileType: result.fileType,
      coachName: result.coachName, certificateName: result.certificateName,
      issuingOrganization: result.issuingOrganization,
      certificateNumber: result.certificateNumber,
      issuedDate: result.issuedDate, expiryDate: result.expiryDate,
      verificationScore: result.verificationScore,
      verificationStatus: result.verificationStatus,
      flags: result.flags || {}, analysisNotes: result.analysisNotes || '',
      uploadedAt: new Date().toISOString(),
      reviewedBy: null, reviewedAt: null, rejectionReason: null,
    };
    console.log('[CERT] saving', doc);
    return d.collection('expert_certificates').doc(id).set(doc)
      .then(function () { return recomputeVerifiedFlag(expertId); })
      .then(function () { return doc; });
  }

  /* ── Keeps experts/{uid}.verified in sync with "at least one verified cert" ── */
  function recomputeVerifiedFlag(expertId) {
    var d = db();
    if (!d) return Promise.resolve();
    return d.collection('expert_certificates').where('expertId', '==', expertId).get()
      .then(function (snap) {
        var anyVerified = snap.docs.some(function (x) { return x.data().verificationStatus === 'verified'; });
        return d.collection('experts').doc(expertId).set({ verified: anyVerified }, { merge: true });
      })
      .catch(function (e) { console.warn('[CERT] recomputeVerifiedFlag failed', e); });
  }

  /* ── Realtime listener: all certs for one expert ── */
  function listenForExpertCertificates(expertId, cb) {
    var d = db();
    if (!d || !expertId) return function () {};
    return d.collection('expert_certificates').where('expertId', '==', expertId)
      .onSnapshot(function (snap) {
        var certs = snap.docs.map(function (x) { return x.data(); })
          .sort(function (a, b) { return (b.uploadedAt || '') < (a.uploadedAt || '') ? -1 : 1; });
        cb(certs);
      }, function (e) { console.warn('[CERT] listener error', e); });
  }

  /* ── Admin: all pending_review certs across every expert ── */
  function listenForPendingCertificates(cb) {
    var d = db();
    if (!d) return function () {};
    return d.collection('expert_certificates').where('verificationStatus', '==', 'pending_review')
      .onSnapshot(function (snap) {
        var certs = snap.docs.map(function (x) { return x.data(); })
          .sort(function (a, b) { return (a.uploadedAt || '') < (b.uploadedAt || '') ? -1 : 1; });
        cb(certs);
      }, function (e) { console.warn('[CERT] pending listener error', e); });
  }

  /* ── Admin actions — the ONLY place verificationStatus changes post-upload ── */
  function approveCertificate(cert, adminUid) {
    var d = db();
    if (!d) return Promise.reject(new Error('Database unavailable'));
    return d.collection('expert_certificates').doc(cert.certId).update({
      verificationStatus: 'verified',
      reviewedBy: adminUid, reviewedAt: new Date().toISOString(), rejectionReason: null,
    }).then(function () { return recomputeVerifiedFlag(cert.expertId); });
  }
  function rejectCertificate(cert, adminUid, reason) {
    var d = db();
    if (!d) return Promise.reject(new Error('Database unavailable'));
    return d.collection('expert_certificates').doc(cert.certId).update({
      verificationStatus: 'rejected',
      reviewedBy: adminUid, reviewedAt: new Date().toISOString(), rejectionReason: reason,
    }).then(function () { return recomputeVerifiedFlag(cert.expertId); });
  }

  var REJECT_REASONS = [
    'Fake Certificate', 'Image Too Blurry', 'Document Not Readable',
    'Wrong Document Uploaded', 'Expired Certificate', 'Edited Certificate', 'Other',
  ];

  /* ══════════════════════════════════════════════
     SHARED MODALS
  ══════════════════════════════════════════════ */
  function ensureModal() {
    var bd = document.getElementById('certModalBackdrop');
    if (bd) return bd;
    bd = document.createElement('div');
    bd.id = 'certModalBackdrop'; bd.className = 'cert-modal-backdrop';
    bd.innerHTML = '<div class="cert-modal" id="certModal"></div>';
    document.body.appendChild(bd);
    bd.addEventListener('click', function (e) { if (e.target === bd) closeModal(); });
    return bd;
  }
  function closeModal() {
    var bd = document.getElementById('certModalBackdrop');
    if (!bd) return;
    bd.classList.remove('open');
    setTimeout(function () { bd.style.display = 'none'; }, 200);
  }
  function openModalHtml(html) {
    var bd = ensureModal();
    document.getElementById('certModal').innerHTML = html;
    bd.style.display = 'flex';
    requestAnimationFrame(function () { requestAnimationFrame(function () { bd.classList.add('open'); }); });
  }

  /* "View Certificate" — shows the uploaded image/PDF full size */
  function openViewCertificate(cert) {
    var isPdf = (cert.fileType || '').indexOf('pdf') !== -1 || /\.pdf($|\?)/i.test(cert.certificateUrl || '');
    openModalHtml(
      '<p class="cert-modal-title">📄 ' + esc(cert.certificateName || 'Certificate') + '</p>' +
      '<p class="cert-modal-sub">' + esc(cert.issuingOrganization || '') + '</p>' +
      (isPdf
        ? '<p class="cert-modal-sub">This certificate was uploaded as a PDF.</p>' +
          '<a class="cert-view-btn" style="display:block;text-decoration:none" href="' + esc(cert.certificateUrl) + '" target="_blank" rel="noopener">Open PDF in new tab</a>'
        : '<img class="cert-modal-img" src="' + esc(cert.certificateUrl) + '" alt="Certificate">') +
      '<button class="cert-modal-close" id="certModalCloseBtn">Close</button>'
    );
    document.getElementById('certModalCloseBtn').addEventListener('click', closeModal);
  }

  /* "ZITLAS Verification" — tapped from the Verified Expert badge */
  function openVerificationInfo(expertName, cert) {
    if (!cert) {
      openModalHtml(
        '<p class="cert-modal-title">🛡️ ZITLAS Verification</p>' +
        '<p class="cert-modal-sub">' + esc(expertName || 'This expert') + ' has not been verified yet.</p>' +
        '<button class="cert-modal-close" id="certModalCloseBtn">Close</button>'
      );
      document.getElementById('certModalCloseBtn').addEventListener('click', closeModal);
      return;
    }
    function fmtDate(iso) {
      try { return new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }); }
      catch (_) { return iso || '—'; }
    }
    openModalHtml(
      '<p class="cert-modal-title">🛡️ ZITLAS Verification</p>' +
      '<p class="cert-modal-sub">' + esc(expertName || 'Expert') + '</p>' +
      '<div class="cert-verify-row"><span class="cert-verify-check">✓</span><span class="cert-verify-label">Identity Verified</span></div>' +
      '<div class="cert-verify-row"><span class="cert-verify-check">✓</span><span class="cert-verify-label">Certificate Verified</span></div>' +
      '<div class="cert-detail-row"><span>AI Verification Score</span><b><span class="cert-score-badge">' + esc(String(cert.verificationScore)) + '%</span></b></div>' +
      '<div class="cert-detail-row"><span>Issuing Organization</span><b>' + esc(cert.issuingOrganization || '—') + '</b></div>' +
      '<div class="cert-detail-row"><span>Verification Date</span><b>' + esc(fmtDate(cert.uploadedAt)) + '</b></div>' +
      '<div class="cert-detail-row"><span>Certificate Number</span><b>' + esc(cert.certificateNumber || '—') + '</b></div>' +
      '<div class="cert-detail-row"><span>Status</span><b style="color:#578A2C">✓ Verified</b></div>' +
      '<button class="cert-modal-close" id="certModalCloseBtn">Close</button>'
    );
    document.getElementById('certModalCloseBtn').addEventListener('click', closeModal);
  }

  win.ZitlasCertificates = {
    uploadAndVerify: uploadAndVerify,
    saveCertificate: saveCertificate,
    recomputeVerifiedFlag: recomputeVerifiedFlag,
    listenForExpertCertificates: listenForExpertCertificates,
    listenForPendingCertificates: listenForPendingCertificates,
    approveCertificate: approveCertificate,
    rejectCertificate: rejectCertificate,
    REJECT_REASONS: REJECT_REASONS,
    openViewCertificate: openViewCertificate,
    openVerificationInfo: openVerificationInfo,
    closeModal: closeModal,
    toast: toast,
  };
})(window);
