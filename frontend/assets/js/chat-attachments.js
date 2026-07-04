/*!
 * ZITLAS — Shared chat image attachments (frontend/assets/js/chat-attachments.js)
 *
 * One implementation for both chat surfaces (athlete cprofile.js and
 * expert expert-dashboard.js):
 *   validate()       jpg/jpeg/png/webp only, 10 MB cap, friendly reasons
 *   upload()         canvas compression (max 1280px, JPEG q0.8) then
 *                    POST /api/chat/upload (the project's FastAPI storage;
 *                    routes/chat.py re-validates type + size server-side)
 *   confirmPreview() WhatsApp-style "Cancel / Send" preview, resolves bool
 *   openViewer()     fullscreen viewer: wheel + double-tap zoom, drag pan,
 *                    pinch zoom (two-pointer), close button / Esc / backdrop
 *
 * The preview modal and viewer are injected once, lazily, and use the
 * "-backdrop" naming convention so the global navbar modal-watcher
 * (components/navbar.js) hides the bottom nav automatically while open.
 * Styles live in assets/css/chat-cards.css.
 */
(function (win) {
  'use strict';

  var ALLOWED   = ['image/jpeg', 'image/png', 'image/webp'];
  var MAX_BYTES = 10 * 1024 * 1024;

  /* ── Validation ── */
  function validate(file) {
    if (!file) return { ok: false, reason: 'No file selected.' };
    if (ALLOWED.indexOf(file.type) === -1) {
      return { ok: false, reason: 'That file type isn’t supported — please choose a JPG, PNG, or WEBP image.' };
    }
    if (file.size > MAX_BYTES) {
      return { ok: false, reason: 'That image is larger than 10 MB — please choose a smaller one.' };
    }
    return { ok: true };
  }

  /* ── Compression (canvas downscale, keeps aspect ratio) ── */
  function compress(file) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onerror = reject;
      reader.onload = function (e) {
        var img = new Image();
        img.onerror = reject;
        img.onload = function () {
          var MAX = 1280;
          var w = img.naturalWidth, h = img.naturalHeight;
          if (w > MAX || h > MAX) {
            var scale = Math.min(MAX / w, MAX / h);
            w = Math.round(w * scale);
            h = Math.round(h * scale);
          }
          var canvas = document.createElement('canvas');
          canvas.width = w; canvas.height = h;
          canvas.getContext('2d').drawImage(img, 0, 0, w, h);
          canvas.toBlob(function (blob) {
            if (blob) resolve(blob); else reject(new Error('Canvas compression failed'));
          }, 'image/jpeg', 0.8);
        };
        img.src = e.target.result;
      };
      reader.readAsDataURL(file);
    });
  }

  /* ── Upload: validate -> compress -> POST. Resolves the public URL. ── */
  function upload(file) {
    var v = validate(file);
    if (!v.ok) return Promise.reject(new Error(v.reason));
    console.log('[CHAT IMAGE] compressing', file.name, file.type, file.size + 'B');
    return compress(file).then(function (blob) {
      console.log('[CHAT IMAGE] compressed to', blob.size + 'B — uploading');
      var fd = new FormData();
      fd.append('file', blob, 'photo.jpg');
      return fetch('/api/chat/upload', { method: 'POST', body: fd });
    }).then(function (resp) {
      if (!resp.ok) throw new Error('Upload failed (' + resp.status + ')');
      return resp.json();
    }).then(function (data) {
      if (!data.success || !data.url) throw new Error('Server rejected the image');
      console.log('[CHAT IMAGE] uploaded →', data.url);
      return data.url;
    });
  }

  /* ── Preview modal (Cancel / Send) ─────────────────────────────────── */
  var _previewEl = null;

  function _ensurePreview() {
    if (_previewEl) return _previewEl;
    _previewEl = document.createElement('div');
    _previewEl.className = 'zca-preview-backdrop';
    _previewEl.innerHTML =
      '<div class="zca-preview-card">' +
        '<img class="zca-preview-img" alt="Image preview" />' +
        '<div class="zca-preview-actions">' +
          '<button type="button" class="zca-btn zca-btn--cancel">Cancel</button>' +
          '<button type="button" class="zca-btn zca-btn--send">Send</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(_previewEl);
    return _previewEl;
  }

  /* Shows the selected image; resolves true (Send) or false (Cancel). */
  function confirmPreview(file) {
    return new Promise(function (resolve) {
      var el  = _ensurePreview();
      var img = el.querySelector('.zca-preview-img');
      var url = URL.createObjectURL(file);
      img.src = url;

      function done(send) {
        el.classList.remove('open');
        URL.revokeObjectURL(url);
        el.querySelector('.zca-btn--send').onclick   = null;
        el.querySelector('.zca-btn--cancel').onclick = null;
        el.onclick = null;
        resolve(send);
      }
      el.querySelector('.zca-btn--send').onclick   = function () { done(true); };
      el.querySelector('.zca-btn--cancel').onclick = function () { done(false); };
      el.onclick = function (e) { if (e.target === el) done(false); };
      el.classList.add('open');
    });
  }

  /* ── Fullscreen viewer: zoom (wheel / double-tap / pinch), pan, close ── */
  var _viewerEl = null;

  function _ensureViewer() {
    if (_viewerEl) return _viewerEl;
    _viewerEl = document.createElement('div');
    _viewerEl.className = 'zca-viewer-backdrop';
    _viewerEl.innerHTML =
      '<button type="button" class="zca-viewer-close" aria-label="Close image">' +
        '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>' +
      '</button>' +
      '<img class="zca-viewer-img" alt="Image" draggable="false" />';
    document.body.appendChild(_viewerEl);

    var img = _viewerEl.querySelector('.zca-viewer-img');
    var scale = 1, tx = 0, ty = 0;
    var pointers = {};           /* active pointers for pan/pinch */
    var pinchStartDist = 0, pinchStartScale = 1;
    var lastTap = 0;

    function apply() {
      img.style.transform = 'translate(' + tx + 'px,' + ty + 'px) scale(' + scale + ')';
    }
    function reset() { scale = 1; tx = 0; ty = 0; apply(); }
    function clampScale(s) { return Math.min(5, Math.max(1, s)); }

    function close() {
      _viewerEl.classList.remove('open');
      document.removeEventListener('keydown', onKey);
      reset();
    }
    function onKey(e) { if (e.key === 'Escape') close(); }

    _viewerEl.querySelector('.zca-viewer-close').addEventListener('click', close);
    _viewerEl.addEventListener('click', function (e) {
      if (e.target === _viewerEl) close();
    });

    /* Wheel zoom (desktop) */
    _viewerEl.addEventListener('wheel', function (e) {
      e.preventDefault();
      scale = clampScale(scale * (e.deltaY < 0 ? 1.15 : 0.87));
      if (scale === 1) { tx = 0; ty = 0; }
      apply();
    }, { passive: false });

    /* Pointer events: 1 pointer = pan (when zoomed) / double-tap zoom,
       2 pointers = pinch zoom. Covers mouse + touch uniformly. */
    img.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      img.setPointerCapture(e.pointerId);
      pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
      var ids = Object.keys(pointers);
      if (ids.length === 2) {
        var a = pointers[ids[0]], b = pointers[ids[1]];
        pinchStartDist  = Math.hypot(a.x - b.x, a.y - b.y);
        pinchStartScale = scale;
      } else if (ids.length === 1) {
        var now = Date.now();
        if (now - lastTap < 320) { /* double tap toggles 1x / 2.5x */
          scale = scale > 1 ? 1 : 2.5;
          if (scale === 1) { tx = 0; ty = 0; }
          apply();
        }
        lastTap = now;
      }
    });
    img.addEventListener('pointermove', function (e) {
      if (!pointers[e.pointerId]) return;
      var ids = Object.keys(pointers);
      if (ids.length === 2) {
        var prev = pointers[e.pointerId];
        pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
        var a = pointers[ids[0]], b = pointers[ids[1]];
        var dist = Math.hypot(a.x - b.x, a.y - b.y);
        if (pinchStartDist > 0) {
          scale = clampScale(pinchStartScale * (dist / pinchStartDist));
          apply();
        }
        void prev;
      } else if (ids.length === 1 && scale > 1) {
        var p = pointers[e.pointerId];
        tx += e.clientX - p.x;
        ty += e.clientY - p.y;
        pointers[e.pointerId] = { x: e.clientX, y: e.clientY };
        apply();
      }
    });
    function endPointer(e) {
      delete pointers[e.pointerId];
      if (Object.keys(pointers).length < 2) pinchStartDist = 0;
    }
    img.addEventListener('pointerup', endPointer);
    img.addEventListener('pointercancel', endPointer);

    _viewerEl._open = function (src) {
      reset();
      img.src = src;
      _viewerEl.classList.add('open');
      document.addEventListener('keydown', onKey);
    };
    return _viewerEl;
  }

  function openViewer(src) {
    if (!src) return;
    _ensureViewer()._open(src);
  }

  win.ZitlasChatAttach = {
    validate:       validate,
    compress:       compress,
    upload:         upload,
    confirmPreview: confirmPreview,
    openViewer:     openViewer,
  };
})(window);
