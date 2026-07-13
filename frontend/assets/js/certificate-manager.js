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
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && bd.classList.contains('open')) closeModal();
    });
    return bd;
  }
  function closeModal() {
    var bd = document.getElementById('certModalBackdrop');
    if (!bd) return;
    bd.classList.remove('open', 'cert-modal-backdrop--fullscreen');
    var modal = document.getElementById('certModal');
    if (modal) modal.classList.remove('cert-modal--viewer', 'cert-modal--fullscreen');
    if (_zoomPanCleanup) { _zoomPanCleanup(); _zoomPanCleanup = null; }
    setTimeout(function () { bd.style.display = 'none'; }, 200);
  }
  function openModalHtml(html) {
    var bd = ensureModal();
    var modal = document.getElementById('certModal');
    modal.classList.remove('cert-modal--viewer', 'cert-modal--fullscreen');
    modal.innerHTML = html;
    bd.style.display = 'flex';
    requestAnimationFrame(function () { requestAnimationFrame(function () { bd.classList.add('open'); }); });
    return modal;
  }

  /* Every openViewCertificate() call attaches fresh window-level drag
     listeners (below) for the new image — without tearing down the
     previous pair first, each certificate viewed in one session would
     leak another permanent 'mousemove'/'mouseup' listener on `window`
     (the stage/img-scoped listeners die naturally with their DOM nodes,
     but window itself never goes away). One module-level cleanup slot,
     invoked at the top of every new attach, keeps it to at most one. */
  var _zoomPanCleanup = null;

  /* ── Pan/zoom controller for the certificate image — pinch (touch),
     mouse-wheel (desktop), double-tap/double-click toggle, and drag-to-pan
     once zoomed in. No external library — this app has no bundler. ── */
  function _attachZoomPan(img, stage) {
    if (_zoomPanCleanup) { _zoomPanCleanup(); _zoomPanCleanup = null; }
    var scale = 1, tx = 0, ty = 0;
    var MIN = 1, MAX = 4;

    function clampPan() {
      if (!stage || !img.naturalWidth) return;
      var stageRect = stage.getBoundingClientRect();
      var w = img.clientWidth * scale, h = img.clientHeight * scale;
      var maxX = Math.max(0, (w - stageRect.width) / 2);
      var maxY = Math.max(0, (h - stageRect.height) / 2);
      tx = Math.max(-maxX, Math.min(maxX, tx));
      ty = Math.max(-maxY, Math.min(maxY, ty));
    }
    function render(withTransition) {
      img.style.transition = withTransition ? 'transform 0.22s ease' : 'none';
      img.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + scale + ')';
      img.classList.toggle('cert-modal-img--zoomed', scale > 1.01);
    }
    function setScale(next, withTransition) {
      scale = Math.max(MIN, Math.min(MAX, next));
      if (scale === MIN) { tx = 0; ty = 0; }
      clampPan();
      render(withTransition);
    }

    /* Desktop: mouse-wheel zoom */
    stage.addEventListener('wheel', function (e) {
      e.preventDefault();
      setScale(scale - e.deltaY * 0.0016, false);
    }, { passive: false });

    /* Double-click (desktop) / double-tap (mobile) toggle */
    var lastTap = 0;
    function toggleZoom() {
      setScale(scale > 1.01 ? 1 : 2.5, true);
    }
    img.addEventListener('dblclick', function (e) { e.preventDefault(); toggleZoom(); });
    img.addEventListener('touchend', function () {
      var now = Date.now();
      if (now - lastTap < 320) toggleZoom();
      lastTap = now;
    });

    /* Pinch-to-zoom + single-finger pan (touch) */
    var pinchStartDist = 0, pinchStartScale = 1;
    var panStartX = 0, panStartY = 0, panOriginX = 0, panOriginY = 0, isPanning = false;
    function touchDist(t) {
      var dx = t[0].clientX - t[1].clientX, dy = t[0].clientY - t[1].clientY;
      return Math.sqrt(dx * dx + dy * dy);
    }
    stage.addEventListener('touchstart', function (e) {
      if (e.touches.length === 2) {
        pinchStartDist = touchDist(e.touches);
        pinchStartScale = scale;
        isPanning = false;
      } else if (e.touches.length === 1 && scale > 1.01) {
        isPanning = true;
        panStartX = e.touches[0].clientX; panStartY = e.touches[0].clientY;
        panOriginX = tx; panOriginY = ty;
      }
    }, { passive: true });
    stage.addEventListener('touchmove', function (e) {
      if (e.touches.length === 2 && pinchStartDist) {
        e.preventDefault();
        setScale(pinchStartScale * (touchDist(e.touches) / pinchStartDist), false);
      } else if (isPanning && e.touches.length === 1) {
        e.preventDefault();
        tx = panOriginX + (e.touches[0].clientX - panStartX);
        ty = panOriginY + (e.touches[0].clientY - panStartY);
        clampPan();
        render(false);
      }
    }, { passive: false });
    stage.addEventListener('touchend', function (e) {
      if (e.touches.length === 0) { pinchStartDist = 0; isPanning = false; }
    });

    /* Desktop: drag-to-pan once zoomed in */
    var mouseDown = false;
    img.addEventListener('mousedown', function (e) {
      if (scale <= 1.01) return;
      e.preventDefault();
      mouseDown = true;
      panStartX = e.clientX; panStartY = e.clientY;
      panOriginX = tx; panOriginY = ty;
      img.style.cursor = 'grabbing';
    });
    function onMouseMove(e) {
      if (!mouseDown) return;
      tx = panOriginX + (e.clientX - panStartX);
      ty = panOriginY + (e.clientY - panStartY);
      clampPan();
      render(false);
    }
    function onMouseUp() {
      mouseDown = false;
      img.style.cursor = scale > 1.01 ? 'grab' : 'zoom-in';
    }
    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
    _zoomPanCleanup = function () {
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
    };

    render(false);
  }

  /* ── Download: fetch as a blob so the browser saves the file instead of
     navigating to it (works for cross-origin Firebase Storage URLs too);
     falls back to opening the URL in a new tab if the fetch itself fails
     (e.g. no CORS on an older upload) rather than doing nothing. ── */
  function _downloadFile(url, suggestedName) {
    fetch(url).then(function (r) {
      if (!r.ok) throw new Error('fetch failed');
      return r.blob();
    }).then(function (blob) {
      var objectUrl = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = objectUrl; a.download = suggestedName || 'certificate';
      document.body.appendChild(a); a.click();
      document.body.removeChild(a);
      setTimeout(function () { URL.revokeObjectURL(objectUrl); }, 4000);
    }).catch(function () {
      window.open(url, '_blank', 'noopener');
    });
  }

  function _fileExtFromUrl(url, fileType) {
    if ((fileType || '').indexOf('pdf') !== -1) return 'pdf';
    var m = /\.(jpe?g|png|webp|gif)($|\?)/i.exec(url || '');
    return m ? m[1].toLowerCase() : 'jpg';
  }

  /* "View Certificate" — a professional, Drive/WhatsApp-style viewer:
     always-visible close button, loading spinner, error state with retry,
     pinch/wheel/double-tap zoom, drag-to-pan, download, and full-screen. */
  function openViewCertificate(cert) {
    var isPdf = (cert.fileType || '').indexOf('pdf') !== -1 || /\.pdf($|\?)/i.test(cert.certificateUrl || '');
    var downloadName = (cert.certificateName || 'certificate').replace(/[^a-z0-9\- ]/gi, '').trim() || 'certificate';
    downloadName += '.' + _fileExtFromUrl(cert.certificateUrl, cert.fileType);

    var modal = openModalHtml(
      '<div class="cert-viewer">' +
        '<div class="cert-viewer-header">' +
          '<div class="cert-viewer-titles">' +
            '<p class="cert-modal-title">📄 ' + esc(cert.certificateName || 'Certificate') + '</p>' +
            '<p class="cert-modal-sub">' + esc(cert.issuingOrganization || '') + '</p>' +
          '</div>' +
          '<button class="cert-viewer-close" id="certViewerCloseBtn" aria-label="Close">' +
            '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
          '</button>' +
        '</div>' +
        '<div class="cert-viewer-stage" id="certViewerStage">' +
          (isPdf
            ? '<div class="cert-viewer-pdf">' +
                '<span class="cert-viewer-pdf-icon">📄</span>' +
                '<p class="cert-modal-sub">This certificate was uploaded as a PDF and can\'t be previewed inline.</p>' +
                '<a class="cert-viewer-action cert-viewer-action--primary" href="' + esc(cert.certificateUrl) + '" target="_blank" rel="noopener">Open PDF in New Tab</a>' +
              '</div>'
            : '<div class="cert-viewer-loading" id="certViewerLoading"><span class="cert-spinner cert-spinner--lg"></span><span>Loading certificate…</span></div>' +
              '<div class="cert-viewer-error" id="certViewerError" style="display:none">' +
                '<span class="cert-viewer-error-icon">⚠️</span>' +
                '<p>Couldn\'t load this certificate.</p>' +
                '<button class="cert-viewer-action" id="certViewerRetryBtn">Try Again</button>' +
              '</div>' +
              '<img class="cert-modal-img" id="certViewerImg" alt="Certificate" draggable="false" style="opacity:0">'
          ) +
        '</div>' +
        '<div class="cert-viewer-footer">' +
          '<button class="cert-viewer-action" id="certDownloadBtn">⬇ Download Certificate</button>' +
          (isPdf ? '' : '<button class="cert-viewer-action" id="certFullscreenBtn">⤢ Full Screen</button>') +
        '</div>' +
      '</div>'
    );
    modal.classList.add('cert-modal--viewer');

    document.getElementById('certViewerCloseBtn').addEventListener('click', closeModal);
    var downloadBtn = document.getElementById('certDownloadBtn');
    if (downloadBtn) downloadBtn.addEventListener('click', function () {
      _downloadFile(cert.certificateUrl, downloadName);
    });
    var fsBtn = document.getElementById('certFullscreenBtn');
    if (fsBtn) fsBtn.addEventListener('click', function () {
      var isFs = modal.classList.toggle('cert-modal--fullscreen');
      var bd = document.getElementById('certModalBackdrop');
      if (bd) bd.classList.toggle('cert-modal-backdrop--fullscreen', isFs);
      fsBtn.innerHTML = isFs ? '⤡ Exit Full Screen' : '⤢ Full Screen';
    });

    if (isPdf) return; // no image stage to wire up

    var imgEl     = document.getElementById('certViewerImg');
    var loadingEl = document.getElementById('certViewerLoading');
    var errorEl   = document.getElementById('certViewerError');
    var stageEl   = document.getElementById('certViewerStage');

    function loadImage(bust) {
      loadingEl.style.display = 'flex';
      errorEl.style.display = 'none';
      imgEl.style.opacity = '0';
      imgEl.onload = function () {
        loadingEl.style.display = 'none';
        imgEl.style.opacity = '1';
        imgEl.style.cursor = 'zoom-in';
        _attachZoomPan(imgEl, stageEl);
      };
      imgEl.onerror = function () {
        loadingEl.style.display = 'none';
        errorEl.style.display = 'flex';
      };
      /* Cache-bust only on retry, so a transient network blip doesn't keep
         resolving to the browser's already-failed cache entry — the
         normal path still benefits from the browser cache. */
      imgEl.src = bust
        ? cert.certificateUrl + (cert.certificateUrl.indexOf('?') === -1 ? '?' : '&') + '_r=' + Date.now()
        : cert.certificateUrl;
    }
    var retryBtn = document.getElementById('certViewerRetryBtn');
    if (retryBtn) retryBtn.addEventListener('click', function () { loadImage(true); });
    loadImage(false);
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
