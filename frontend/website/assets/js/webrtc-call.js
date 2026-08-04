/*!
 * ZITLAS — WebRTC voice calling, signaled over Firestore.
 * frontend/assets/js/webrtc-call.js
 *
 * Firestore schema:
 *   chat_rooms/{chatId}/calls/{callId}
 *     { callId, chatId, callerId, calleeId, status, offer, answer, createdAt }
 *   chat_rooms/{chatId}/calls/{callId}/callerCandidates/{autoId}
 *   chat_rooms/{chatId}/calls/{callId}/calleeCandidates/{autoId}
 *
 * status: 'ringing' -> 'accepted' -> 'ended'  (or 'rejected' instead of accepted)
 *
 * IMPORTANT — STUN only, no TURN configured. Public STUN servers let two
 * peers discover each other's public IP/port, but cannot relay media when
 * a direct peer-to-peer path is blocked (symmetric NAT, many corporate
 * firewalls, some mobile carriers). Those calls will connect the signaling
 * (both sides see "ringing"/"accepted") but audio will never flow, and
 * onconnectionstatechange will report 'failed'. Before relying on this
 * across arbitrary real-world networks, add a TURN server (e.g. Twilio
 * Network Traversal Service, Cloudflare Calls, or a self-hosted coturn
 * instance) to ICE_SERVERS below.
 */
(function (win) {
  'use strict';

  var ICE_SERVERS = {
    iceServers: [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
    ],
  };

  function _callsCollection(db, chatId) {
    return db.collection('chat_rooms').doc(chatId).collection('calls');
  }

  function _callDocRef(db, chatId, callId) {
    return _callsCollection(db, chatId).doc(callId);
  }

  function _makeSession(pc, callRef) {
    var localStream = null;
    var unsubCallDoc = null;
    var unsubCandidates = null;
    var ended = false;

    function cleanup() {
      if (ended) return;
      ended = true;
      if (unsubCallDoc) { unsubCallDoc(); unsubCallDoc = null; }
      if (unsubCandidates) { unsubCandidates(); unsubCandidates = null; }
      try { pc.close(); } catch (_) {}
      if (localStream) localStream.getTracks().forEach(function (t) { t.stop(); });
    }

    return {
      pc: pc,
      setLocalStream: function (s) { localStream = s; },
      setUnsubCallDoc: function (fn) { unsubCallDoc = fn; },
      setUnsubCandidates: function (fn) { unsubCandidates = fn; },
      isEnded: function () { return ended; },
      cleanup: cleanup,
      hangup: function () {
        console.log('[CALL] call ended');
        callRef.update({ status: 'ended' }).catch(function (err) {
          console.error('[CALL] failed to write ended status', err);
        });
        cleanup();
      },
    };
  }

  /* ── Caller side ── */
  function startCall(opts) {
    var db = opts.db, chatId = opts.chatId, myUid = opts.myUid, otherUid = opts.otherUid;
    var callId = 'call_' + Date.now();
    var callRef = _callDocRef(db, chatId, callId);
    var pc = new RTCPeerConnection(ICE_SERVERS);
    var session = _makeSession(pc, callRef);

    pc.onicecandidate = function (e) {
      if (e.candidate) {
        callRef.collection('callerCandidates').add(e.candidate.toJSON())
          .catch(function (err) { console.error('[CALL] failed to write caller ICE candidate', err); });
      }
    };
    pc.ontrack = function (e) {
      console.log('[CALL] remote stream received');
      if (opts.onRemoteStream) opts.onRemoteStream(e.streams[0]);
    };
    pc.onconnectionstatechange = function () {
      console.log('[CALL] connection state (caller)', pc.connectionState);
      if (pc.connectionState === 'connected') console.log('[CALL] call connected');
      if (opts.onStateChange) opts.onStateChange(pc.connectionState);
      if (pc.connectionState === 'failed' || pc.connectionState === 'closed') session.cleanup();
    };

    navigator.mediaDevices.getUserMedia({ audio: true, video: false })
      .then(function (stream) {
        session.setLocalStream(stream);
        if (opts.onLocalStream) opts.onLocalStream(stream);
        stream.getTracks().forEach(function (t) { pc.addTrack(t, stream); });
        console.log('[CALL] creating offer');
        return pc.createOffer();
      })
      .then(function (offer) { return pc.setLocalDescription(offer).then(function () { return offer; }); })
      .then(function (offer) {
        console.log('[CALL] writing offer', { chatId: chatId, callId: callId, callerId: myUid, calleeId: otherUid });
        return callRef.set({
          callId:    callId,
          chatId:    chatId,
          callerId:  myUid,
          calleeId:  otherUid,
          status:    'ringing',
          offer:     { type: offer.type, sdp: offer.sdp },
          answer:    null,
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
      })
      .then(function () {
        /* Offer is in Firestore — the other side can now ring */
        if (opts.onStateChange) opts.onStateChange('ringing');
        session.setUnsubCallDoc(callRef.onSnapshot(function (doc) {
          var data = doc.data();
          if (!data) return;
          if (data.status === 'rejected') {
            console.log('[CALL] callee rejected', callId);
            if (opts.onStateChange) opts.onStateChange('rejected');
            session.cleanup();
            return;
          }
          if (data.status === 'ended') {
            console.log('[CALL] ended remotely', callId);
            if (opts.onStateChange) opts.onStateChange('ended');
            session.cleanup();
            return;
          }
          if (data.answer && !pc.currentRemoteDescription) {
            console.log('[CALL] received answer', callId);
            pc.setRemoteDescription(new RTCSessionDescription(data.answer))
              .then(function () { if (opts.onStateChange) opts.onStateChange('accepted'); })
              .catch(function (err) { console.error('[CALL] setRemoteDescription(answer) failed', err); });
          }
        }, function (err) { console.error('[CALL] call-doc listener error (caller)', err); }));

        session.setUnsubCandidates(callRef.collection('calleeCandidates').onSnapshot(function (snap) {
          snap.docChanges().forEach(function (change) {
            if (change.type === 'added') {
              pc.addIceCandidate(new RTCIceCandidate(change.doc.data()))
                .catch(function (err) { console.error('[CALL] addIceCandidate (callee->caller) failed', err); });
            }
          });
        }, function (err) { console.error('[CALL] candidate listener error (caller)', err); }));
      })
      .catch(function (err) {
        console.error('[CALL] startCall failed', err);
        if (opts.onStateChange) opts.onStateChange('failed');
        session.cleanup();
      });

    return session;
  }

  /* ── Callee side: listen for a ringing call addressed to me in this chat room ── */
  function listenForIncomingCalls(opts) {
    var db = opts.db, chatId = opts.chatId, myUid = opts.myUid;
    return _callsCollection(db, chatId)
      .where('calleeId', '==', myUid)
      .where('status', '==', 'ringing')
      .onSnapshot(function (snap) {
        snap.docChanges().forEach(function (change) {
          if (change.type === 'added') {
            var data = change.doc.data();
            /* Ignore stale ringing docs (caller closed the browser without
               hanging up) — only ring for offers created in the last 60s. */
            var createdMs = (data.createdAt && data.createdAt.toMillis) ? data.createdAt.toMillis() : null;
            if (createdMs && (Date.now() - createdMs) > 60000) {
              console.log('[CALL] ignoring stale ringing call', change.doc.id);
              return;
            }
            console.log('[CALL] incoming call detected', data);
            if (opts.onIncomingCall) {
              opts.onIncomingCall({
                callId:   data.callId || change.doc.id,
                chatId:   chatId,
                callerId: data.callerId,
                offer:    data.offer,
              });
            }
          }
          /* A doc leaving the status=='ringing' query means the caller hung
             up (or the call was answered elsewhere) — let the UI dismiss a
             still-ringing incoming popup instead of ringing forever. */
          if (change.type === 'removed') {
            console.log('[CALL] ringing call withdrawn', change.doc.id);
            if (opts.onCallCancelled) opts.onCallCancelled(change.doc.id);
          }
        });
      }, function (err) { console.error('[CALL] incoming-call listener error', err); });
  }

  /* ── Callee side: accept an incoming call ── */
  function answerCall(opts) {
    var db = opts.db, chatId = opts.chatId, callId = opts.callId, offer = opts.offer;
    console.log('[CALL] received offer', callId);
    var callRef = _callDocRef(db, chatId, callId);
    var pc = new RTCPeerConnection(ICE_SERVERS);
    var session = _makeSession(pc, callRef);

    pc.onicecandidate = function (e) {
      if (e.candidate) {
        callRef.collection('calleeCandidates').add(e.candidate.toJSON())
          .catch(function (err) { console.error('[CALL] failed to write callee ICE candidate', err); });
      }
    };
    pc.ontrack = function (e) {
      console.log('[CALL] remote stream received');
      if (opts.onRemoteStream) opts.onRemoteStream(e.streams[0]);
    };
    pc.onconnectionstatechange = function () {
      console.log('[CALL] connection state (callee)', pc.connectionState);
      if (pc.connectionState === 'connected') console.log('[CALL] call connected');
      if (opts.onStateChange) opts.onStateChange(pc.connectionState);
      if (pc.connectionState === 'failed' || pc.connectionState === 'closed') session.cleanup();
    };

    navigator.mediaDevices.getUserMedia({ audio: true, video: false })
      .then(function (stream) {
        session.setLocalStream(stream);
        if (opts.onLocalStream) opts.onLocalStream(stream);
        stream.getTracks().forEach(function (t) { pc.addTrack(t, stream); });
        return pc.setRemoteDescription(new RTCSessionDescription(offer));
      })
      .then(function () { console.log('[CALL] creating answer'); return pc.createAnswer(); })
      .then(function (answer) { return pc.setLocalDescription(answer).then(function () { return answer; }); })
      .then(function (answer) {
        console.log('[CALL] writing answer', { chatId: chatId, callId: callId });
        return callRef.update({
          status: 'accepted',
          answer: { type: answer.type, sdp: answer.sdp },
        });
      })
      .then(function () {
        session.setUnsubCallDoc(callRef.onSnapshot(function (doc) {
          var data = doc.data();
          if (!data) return;
          if (data.status === 'ended') {
            console.log('[CALL] ended remotely', callId);
            if (opts.onStateChange) opts.onStateChange('ended');
            session.cleanup();
          }
        }, function (err) { console.error('[CALL] call-doc listener error (callee)', err); }));

        session.setUnsubCandidates(callRef.collection('callerCandidates').onSnapshot(function (snap) {
          snap.docChanges().forEach(function (change) {
            if (change.type === 'added') {
              pc.addIceCandidate(new RTCIceCandidate(change.doc.data()))
                .catch(function (err) { console.error('[CALL] addIceCandidate (caller->callee) failed', err); });
            }
          });
        }, function (err) { console.error('[CALL] candidate listener error (callee)', err); }));
      })
      .catch(function (err) {
        console.error('[CALL] answerCall failed', err);
        if (opts.onStateChange) opts.onStateChange('failed');
        session.cleanup();
      });

    return session;
  }

  /* ── Callee side: decline without ever creating a peer connection ── */
  function declineCall(opts) {
    return _callDocRef(opts.db, opts.chatId, opts.callId)
      .update({ status: 'rejected' })
      .catch(function (err) { console.error('[CALL] declineCall failed', err); });
  }

  win.ZitlasCall = {
    startCall:              startCall,
    listenForIncomingCalls: listenForIncomingCalls,
    answerCall:             answerCall,
    declineCall:            declineCall,
  };
})(window);
