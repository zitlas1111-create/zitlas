/*!
 * ZITLAS — Premium Call UI (frontend/assets/js/call-ui.js)
 *
 * Pure UI layer over the existing WebRTC engine (assets/js/webrtc-call.js).
 * Owns the fullscreen call overlay: outgoing, incoming, and active states,
 * the duration timer, mute, speaker, and the remote <audio> element.
 * It never touches Firestore or RTCPeerConnection — integration code wires
 * its callbacks to ZitlasCall.startCall / answerCall / declineCall.
 *
 * API (window.ZitlasCallUI):
 *   showOutgoing({name, role, photo, onHangup})
 *   showIncoming({name, role, photo, onAccept, onReject})
 *   setActive(statusText)   — switch incoming → active controls (after accept)
 *   setStatus(text)         — "Ringing…", "Connecting…", …
 *   setConnected()          — stop ring animation, start the duration timer
 *   setLocalStream(stream)  — enables the Mute button
 *   setRemoteStream(stream) — plays remote audio, enables Speaker button
 *   close({message})        — optional farewell text, then animate out + cleanup
 *   isOpen()
 */
(function (win) {
  'use strict';

  var ICONS = {
    mic:    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>',
    micOff: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>',
    speaker: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>',
    phoneDown: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="transform:rotate(135deg)"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 12 19.79 19.79 0 0 1 1.63 3.37 2 2 0 0 1 3.6 1h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L7.91 8.56a16 16 0 0 0 6 6l.94-.94a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>',
    phone:  '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 12 19.79 19.79 0 0 1 1.63 3.37 2 2 0 0 1 3.6 1h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L7.91 8.56a16 16 0 0 0 6 6l.94-.94a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/></svg>',
  };

  var el    = null;   /* overlay root, created lazily on first show */
  var refs  = {};
  var state = {
    mode:        null,   /* 'outgoing' | 'incoming' | 'active' | null */
    timerId:     null,
    startedAt:   0,
    vibrateId:   null,
    closing:     false,
    muted:       false,
    speakerOn:   true,
    localStream: null,
    cbs:         {},
  };

  function ensure() {
    if (el) return;
    el = document.createElement('div');
    el.id = 'callModal';
    el.className = 'zcall-overlay';
    el.innerHTML =
      '<div class="zcall-glow"></div>' +
      '<div class="zcall-top">' +
        '<span class="zcall-brand">ZITLAS</span>' +
        '<span class="zcall-secure">🔒 Peer-to-peer voice call</span>' +
      '</div>' +
      '<div class="zcall-body">' +
        '<div class="zcall-ring"><div class="zcall-avatar"></div></div>' +
        '<h2 class="zcall-name"></h2>' +
        '<p class="zcall-role"></p>' +
        '<p class="zcall-status"></p>' +
      '</div>' +
      '<div class="zcall-actions zcall-actions--active">' +
        '<div class="zcall-action"><button type="button" class="zcall-btn" data-act="mute" aria-label="Mute">' + ICONS.mic + '</button><span data-lbl="mute">Mute</span></div>' +
        '<div class="zcall-action"><button type="button" class="zcall-btn zcall-btn--end" data-act="end" aria-label="End call">' + ICONS.phoneDown + '</button><span>End</span></div>' +
        '<div class="zcall-action"><button type="button" class="zcall-btn zcall-on" data-act="speaker" aria-label="Speaker">' + ICONS.speaker + '</button><span>Speaker</span></div>' +
      '</div>' +
      '<div class="zcall-actions zcall-actions--incoming">' +
        '<div class="zcall-action"><button type="button" class="zcall-btn zcall-btn--decline" data-act="decline" aria-label="Decline call">' + ICONS.phoneDown + '</button><span>Decline</span></div>' +
        '<div class="zcall-action"><button type="button" class="zcall-btn zcall-btn--accept" data-act="accept" aria-label="Accept call">' + ICONS.phone + '</button><span>Accept</span></div>' +
      '</div>' +
      '<audio class="zcall-audio" autoplay playsinline></audio>';
    document.body.appendChild(el);

    refs = {
      avatar:   el.querySelector('.zcall-avatar'),
      name:     el.querySelector('.zcall-name'),
      role:     el.querySelector('.zcall-role'),
      status:   el.querySelector('.zcall-status'),
      audio:    el.querySelector('.zcall-audio'),
      muteBtn:  el.querySelector('[data-act="mute"]'),
      muteLbl:  el.querySelector('[data-lbl="mute"]'),
      spkBtn:   el.querySelector('[data-act="speaker"]'),
    };

    el.addEventListener('click', function (e) {
      var btn = e.target.closest('[data-act]');
      if (!btn) return;
      var act = btn.dataset.act;
      if (act === 'mute')    toggleMute();
      if (act === 'speaker') toggleSpeaker();
      if (act === 'end')     { if (state.cbs.onHangup) state.cbs.onHangup(); }
      if (act === 'accept')  { stopVibrate(); if (state.cbs.onAccept) state.cbs.onAccept(); }
      if (act === 'decline') { stopVibrate(); if (state.cbs.onReject) state.cbs.onReject(); }
    });
  }

  function setIdentity(opts) {
    refs.name.textContent = opts.name || 'Unknown';
    refs.role.textContent = opts.role || '';
    refs.avatar.innerHTML = '';
    var photo = opts.photo || null;
    if (photo) {
      var img = document.createElement('img');
      img.alt = opts.name || '';
      img.src = photo; /* property assignment — never string-concatenated into HTML */
      refs.avatar.appendChild(img);
    } else {
      var initials = (opts.name || '?').trim().split(/\s+/)
        .map(function (w) { return w[0] || ''; }).slice(0, 2).join('').toUpperCase() || '?';
      refs.avatar.textContent = initials;
    }
  }

  function open(mode) {
    console.log('[CALL] opening modal —', mode);
    state.mode    = mode;
    state.closing = false;
    el.classList.toggle('zcall-mode-incoming', mode === 'incoming');
    el.classList.add('zcall-ringing');
    el.classList.add('zcall-show');
    /* double rAF so the display change commits before the transition starts */
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { el.classList.add('zcall-in'); });
    });
  }

  function resetControls() {
    state.muted     = false;
    state.speakerOn = true;
    if (refs.muteBtn) {
      refs.muteBtn.classList.remove('zcall-on');
      refs.muteBtn.innerHTML = ICONS.mic;
    }
    if (refs.muteLbl) refs.muteLbl.textContent = 'Mute';
    if (refs.spkBtn)  refs.spkBtn.classList.add('zcall-on');
    if (refs.audio)   refs.audio.volume = 1;
  }

  function startTimer() {
    stopTimer();
    state.startedAt = Date.now();
    state.timerId = setInterval(function () {
      var s  = Math.floor((Date.now() - state.startedAt) / 1000);
      var hh = Math.floor(s / 3600);
      var mm = Math.floor((s % 3600) / 60);
      var ss = s % 60;
      var pad = function (n) { return (n < 10 ? '0' : '') + n; };
      refs.status.textContent = (hh ? pad(hh) + ':' : '') + pad(mm) + ':' + pad(ss);
    }, 1000);
    refs.status.textContent = '00:00';
  }

  function stopTimer() {
    if (state.timerId) { clearInterval(state.timerId); state.timerId = null; }
  }

  function startVibrate() {
    stopVibrate();
    if (!navigator.vibrate) return;
    navigator.vibrate([350, 180, 350]);
    state.vibrateId = setInterval(function () { navigator.vibrate([350, 180, 350]); }, 2000);
  }

  function stopVibrate() {
    if (state.vibrateId) { clearInterval(state.vibrateId); state.vibrateId = null; }
    if (navigator.vibrate) navigator.vibrate(0);
  }

  function toggleMute() {
    state.muted = !state.muted;
    if (state.localStream) {
      state.localStream.getAudioTracks().forEach(function (t) { t.enabled = !state.muted; });
    }
    refs.muteBtn.classList.toggle('zcall-on', state.muted);
    refs.muteBtn.innerHTML = state.muted ? ICONS.micOff : ICONS.mic;
    refs.muteLbl.textContent = state.muted ? 'Unmute' : 'Mute';
    console.log('[CALL UI] mute', state.muted);
  }

  /* Web platform note: browsers can't route to an earpiece the way native
     apps can, so "speaker off" lowers the remote volume instead of
     re-routing. Visual behaviour matches native call UIs. */
  function toggleSpeaker() {
    state.speakerOn = !state.speakerOn;
    if (refs.audio) refs.audio.volume = state.speakerOn ? 1 : 0.25;
    refs.spkBtn.classList.toggle('zcall-on', state.speakerOn);
    console.log('[CALL UI] speaker', state.speakerOn);
  }

  function hide() {
    stopTimer();
    stopVibrate();
    if (refs.audio) refs.audio.srcObject = null;
    state.localStream = null;
    state.cbs  = {};
    state.mode = null;
    el.classList.remove('zcall-in');
    setTimeout(function () {
      el.classList.remove('zcall-show', 'zcall-ringing', 'zcall-mode-incoming');
    }, 340);
  }

  win.ZitlasCallUI = {
    showOutgoing: function (opts) {
      ensure();
      resetControls();
      setIdentity(opts);
      state.cbs = { onHangup: opts.onHangup };
      refs.status.textContent = 'Calling…';
      open('outgoing');
    },

    showIncoming: function (opts) {
      ensure();
      resetControls();
      setIdentity(opts);
      state.cbs = { onAccept: opts.onAccept, onReject: opts.onReject, onHangup: opts.onHangup };
      refs.status.textContent = 'Incoming Call';
      open('incoming');
      startVibrate();
    },

    /* After the callee accepts: swap incoming buttons for the active set */
    setActive: function (statusText) {
      if (!el) return;
      state.mode = 'active';
      el.classList.remove('zcall-mode-incoming');
      if (statusText) refs.status.textContent = statusText;
    },

    /* Wire (or replace) the End-button handler — needed on the callee side,
       where the call session only exists after Accept is pressed */
    setHangup: function (fn) {
      state.cbs.onHangup = fn;
    },

    setStatus: function (text) {
      if (!el || state.timerId) return; /* never overwrite a running timer */
      refs.status.textContent = text;
    },

    setConnected: function () {
      if (!el) return;
      el.classList.remove('zcall-ringing');
      startTimer();
    },

    setLocalStream: function (stream) {
      state.localStream = stream;
      if (state.muted && stream) {
        stream.getAudioTracks().forEach(function (t) { t.enabled = false; });
      }
    },

    setRemoteStream: function (stream) {
      ensure();
      refs.audio.srcObject = stream;
      refs.audio.volume = state.speakerOn ? 1 : 0.25;
    },

    close: function (opts) {
      if (!el || state.closing || !state.mode) return;
      state.closing = true;
      stopTimer();
      stopVibrate();
      el.classList.remove('zcall-ringing');
      var message = opts && opts.message;
      if (message) {
        refs.status.textContent = message;
        setTimeout(hide, 900);
      } else {
        hide();
      }
    },

    isOpen: function () {
      return !!(el && state.mode);
    },

    /* Manual self-test: shows a demo outgoing screen for 4 seconds.
       Run `ZitlasCallUI.test()` in the console to verify the overlay
       renders on this page without placing a real call. */
    test: function () {
      var self = this;
      this.showOutgoing({
        name: 'UI Self-Test', role: 'No call is being placed',
        onHangup: function () { self.close({ message: 'Test finished' }); },
      });
      setTimeout(function () { self.close({ message: 'Test finished' }); }, 4000);
    },
  };

  /* Debug aliases so `typeof showCallModal` / `hideCallModal` work in the
     console, and eager injection so `document.getElementById('callModal')`
     returns the overlay element on page load (hidden until a call). */
  win.showCallModal = function () { win.ZitlasCallUI.test(); };
  win.hideCallModal = function () { win.ZitlasCallUI.close(); };

  function _init() {
    ensure();
    console.log('[CALL UI] ready — overlay injected (#callModal), ZitlasCallUI available');
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', _init);
  } else {
    _init();
  }
})(window);
