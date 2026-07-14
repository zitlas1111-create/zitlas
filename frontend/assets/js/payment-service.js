/*!
 * ZITLAS — Shared Payment Engine (assets/js/payment-service.js)
 *
 * The ONE place money moves for Review Verification, Expert Chat, and
 * Personal Coaching. Money is never deducted when a request is sent —
 * only attemptCharge() below moves money, and it only ever runs when an
 * expert has just pressed Accept.
 *
 * SECURITY: the whole read-check-write sequence runs inside a single
 * Firestore transaction (db.runTransaction). That gives three guarantees
 * for free, which is why nothing here uses a plain get()+then()+update():
 *   - Duplicate deduction is impossible: the transaction re-reads the
 *     request doc fresh, and if paymentStatus is already 'paid' (from an
 *     earlier successful run — a double-click, two tabs, a retried
 *     network call) it short-circuits to a no-op success instead of
 *     charging again.
 *   - Race conditions are impossible: if two attemptCharge() calls run
 *     concurrently (e.g. the athlete's retry-after-recharge fires at the
 *     same moment as the expert's auto-attempt), Firestore serializes them
 *     — the second transaction automatically retries against the first
 *     one's committed result and hits the same 'already paid' short-circuit.
 *   - "Multiple accepts" is covered by callers additionally gating on the
 *     request's own `status` field before calling this at all (see
 *     expert-dashboard.js) — this module only owns the money part.
 */
(function (win) {
  'use strict';

  // Single configurable point — ZITLAS's cut of every payment.
  var PLATFORM_FEE_PERCENT = 0.20;

  function _defaultWallet() {
    return { balance: 0, total_added: 0, total_spent: 0, transactions: [] };
  }

  function _newTxnId() {
    return 'txn_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
  }

  /**
   * attemptCharge({
   *   userId, expertId, amount, serviceType, serviceLabel, expertName,
   *   requestCollection, requestId,
   *   onSuccessUpdate,       // fields merged onto the request ONLY when payment succeeds
   *                          // (e.g. {status:'in_progress', chatUnlocked:true}) — never
   *                          // applied on the insufficient-balance path, so a request can
   *                          // never advance to an active/serving state without payment.
   *   notifyUser: {title, message}, notifyExpert: {title, message},
   * }) -> Promise<{success, alreadyPaid?, error?, balance?, shortfall?, required?,
   *                transactionId?, walletBefore?, walletAfter?, platformFee?, expertAmount?}>
   */
  function attemptCharge(opts) {
    var db = win.ZitlasDB;
    if (!db) return Promise.resolve({ success: false, error: 'no_db' });

    var userId    = opts.userId;
    var requestId = opts.requestId;
    var reqColl   = opts.requestCollection;
    if (!userId || !requestId || !reqColl) {
      return Promise.resolve({ success: false, error: 'missing_params' });
    }

    var amount = Math.max(0, Number(opts.amount) || 0);
    var onSuccessUpdate = opts.onSuccessUpdate || {};

    var userRef    = db.collection('users').doc(userId);
    var requestRef = db.collection(reqColl).doc(requestId);
    var txnId      = _newTxnId();
    var txnRef     = db.collection('wallet_transactions').doc(txnId);

    var outcome = { success: false };

    return db.runTransaction(function (tx) {
      return Promise.all([tx.get(userRef), tx.get(requestRef)]).then(function (results) {
        var userSnap    = results[0];
        var requestSnap = results[1];

        if (!requestSnap.exists) { outcome = { success: false, error: 'request_missing' }; return; }

        var reqData = requestSnap.data();
        if (reqData.paymentStatus === 'paid') {
          // Already charged by an earlier run of this exact transaction —
          // treat as success so the caller's UI doesn't show a false error.
          outcome = { success: true, alreadyPaid: true, walletTransactionId: reqData.walletTransactionId };
          return;
        }

        /* Audit requirement: never silently default to 0 without saying so.
           userSnap.exists=false or .wallet undefined are DIFFERENT diagnoses
           from "balance genuinely is 0" — walletDocStatus carries that
           distinction through to the caller so the UI can say "your wallet
           hasn't synced yet" instead of implying the athlete has no money. */
        var walletDocStatus = !userSnap.exists ? 'user_doc_missing'
                             : !userSnap.data().wallet ? 'wallet_field_missing'
                             : 'ok';
        var wallet  = (userSnap.exists && userSnap.data().wallet) ? userSnap.data().wallet : _defaultWallet();
        var balance = Number(wallet.balance || 0);

        console.log('[WALLET]');
        console.log('[WALLET] uid=' + userId);
        console.log('[WALLET] walletPath=users/' + userId + '.wallet');
        console.log('[WALLET] documentExists=' + userSnap.exists);
        console.log('[WALLET] walletFieldStatus=' + walletDocStatus);
        console.log('[WALLET] rawData=', userSnap.exists ? userSnap.data() : null);
        console.log('[WALLET] balance=' + balance + ' (typeof stored value=' +
                    (userSnap.exists && userSnap.data().wallet ? typeof userSnap.data().wallet.balance : 'n/a') + ')');
        console.log('[WALLET] required=' + amount);
        console.log('[WALLET] comparison=' + (balance >= amount ? 'SUFFICIENT' : 'INSUFFICIENT') +
                    ' (balance ' + balance + (balance >= amount ? ' >= ' : ' < ') + amount + ')');

        if (amount > 0 && balance < amount) {
          outcome = {
            success: false, error: 'insufficient_balance',
            balance: balance, required: amount, shortfall: amount - balance,
            walletDocStatus: walletDocStatus,
          };
          // Deliberately does NOT apply onSuccessUpdate — payment failed, so
          // the request must not advance to an active/serving state. `status`
          // is fixed at 'accepted' here (not caller-controlled) so the
          // expert's decision is recorded in the SAME transaction as the
          // failed charge — no separate out-of-transaction write is needed,
          // which would otherwise race against this one and risk landing
          // out of order.
          tx.update(requestRef, {
            status: 'accepted',
            paymentStatus: 'awaiting_payment',
            paymentAttemptedAt: new Date().toISOString(),
          });
          return;
        }

        var walletBefore = balance;
        var walletAfter  = balance - amount;
        var platformFee  = Math.round(amount * PLATFORM_FEE_PERCENT);
        var expertAmount = amount - platformFee;

        var newWallet = {
          balance:      walletAfter,
          total_added:  Number(wallet.total_added || 0),
          total_spent:  Number(wallet.total_spent || 0) + amount,
          transactions: Array.isArray(wallet.transactions) ? wallet.transactions.slice() : [],
        };
        if (amount > 0) {
          newWallet.transactions.push({
            id: txnId, type: 'debit', amount: amount,
            description: (opts.serviceLabel || 'ZITLAS service') + (opts.expertName ? ' — ' + opts.expertName : ''),
            date: new Date().toISOString(),
          });
        }

        tx.set(userRef, { wallet: newWallet, walletUpdatedAt: new Date().toISOString() }, { merge: true });
        tx.set(txnRef, {
          transactionId: txnId,
          serviceType:   opts.serviceType || 'unknown',
          expertId:      opts.expertId || null,
          userId:        userId,
          amount:        amount,
          walletBefore:  walletBefore,
          walletAfter:   walletAfter,
          grossAmount:   amount,
          platformFee:   platformFee,
          expertAmount:  expertAmount,
          status:        'success',
          createdAt:     new Date().toISOString(),
        });
        tx.update(requestRef, Object.assign({}, onSuccessUpdate, {
          paymentStatus: 'paid',
          walletTransactionId: txnId,
          paidAt: new Date().toISOString(),
        }));

        outcome = {
          success: true, transactionId: txnId,
          walletBefore: walletBefore, walletAfter: walletAfter,
          platformFee: platformFee, expertAmount: expertAmount,
        };
      });
    }).then(function () {
      if (outcome.success && !outcome.alreadyPaid && typeof win.ZitlasNotify !== 'undefined') {
        if (opts.notifyUser) {
          win.ZitlasNotify.send(userId, Object.assign({ category: 'payment', type: 'service_payment' }, opts.notifyUser));
        }
        if (opts.notifyExpert && opts.expertId) {
          win.ZitlasNotify.send(opts.expertId, Object.assign({ category: 'payment', type: 'service_payment' }, opts.notifyExpert));
        }
      }
      return outcome;
    }).catch(function (err) {
      console.error('[PAYMENT] attemptCharge failed', err);
      return { success: false, error: (err && err.message) || 'transaction_failed' };
    });
  }

  /**
   * creditWallet({ userId, amount, method, description }) -> Promise<{success, balance, transactionId, error?}>
   *
   * THE single place money is ADDED to a wallet — the credit-side sibling of
   * attemptCharge() above. Runs inside the same db.runTransaction() pattern
   * (atomic read-then-write against the live Firestore balance, never a
   * blind "local cache + amount" increment), so it is correct regardless of
   * which page calls it and never depends on cloud-sync.js being loaded.
   *
   * ROOT CAUSE THIS REPLACES: wallet.js's old creditFunds() computed
   * getWallet().balance + amount from localStorage and wrote the result via
   * ZitlasCloudSync.saveCloudOnly(), which (a) silently no-ops when
   * cloud-sync.js isn't loaded on the page — true for coaches.html,
   * cprofile.html, dietitian.html, help-support.html, and membership.html,
   * confirmed by grepping every page that loads wallet.js — and (b) even
   * when it IS loaded, swallows any write failure into a console.warn with
   * no user-facing signal. The result: the Add Funds button could show
   * "✅ Added to wallet!" while the money never reached the users/{uid}
   * document that attemptCharge() actually reads at charge time — exactly
   * the "Wallet page shows a balance, payment popup shows ₹0" symptom this
   * fixes. Audited live: 0 of 13 real user documents in production had a
   * wallet field at all before this fix.
   */
  function creditWallet(opts) {
    var db = win.ZitlasDB;
    if (!db) return Promise.resolve({ success: false, error: 'no_db' });
    var userId = opts.userId;
    if (!userId) return Promise.resolve({ success: false, error: 'missing_user' });
    var amount = Math.max(0, Number(opts.amount) || 0);
    if (amount <= 0) return Promise.resolve({ success: false, error: 'invalid_amount' });

    var userRef = db.collection('users').doc(userId);
    var txnId   = _newTxnId();
    var txnRef  = db.collection('wallet_transactions').doc(txnId);
    var result  = null;

    return db.runTransaction(function (tx) {
      return tx.get(userRef).then(function (userSnap) {
        var wallet       = (userSnap.exists && userSnap.data().wallet) ? userSnap.data().wallet : _defaultWallet();
        var walletBefore = Number(wallet.balance || 0);
        var walletAfter  = walletBefore + amount;

        console.log('[WALLET]');
        console.log('[WALLET] operation=credit (recharge)');
        console.log('[WALLET] uid=' + userId);
        console.log('[WALLET] walletPath=users/' + userId + '.wallet');
        console.log('[WALLET] documentExists=' + userSnap.exists);
        console.log('[WALLET] rawData(before)=', userSnap.exists ? userSnap.data() : null);
        console.log('[WALLET] balance(before)=' + walletBefore);
        console.log('[WALLET] amount=' + amount);
        console.log('[WALLET] balance(after)=' + walletAfter);

        var newWallet = {
          balance:      walletAfter,
          total_added:  Number(wallet.total_added || 0) + amount,
          total_spent:  Number(wallet.total_spent || 0),
          transactions: Array.isArray(wallet.transactions) ? wallet.transactions.slice() : [],
        };
        newWallet.transactions.push({
          id: txnId, type: 'credit', amount: amount,
          description: opts.description || ('Added Funds via ' + (opts.method || 'wallet')),
          date: new Date().toISOString(),
        });

        tx.set(userRef, { wallet: newWallet, walletUpdatedAt: new Date().toISOString() }, { merge: true });
        tx.set(txnRef, {
          transactionId: txnId, serviceType: 'wallet_recharge', userId: userId,
          amount: amount, walletBefore: walletBefore, walletAfter: walletAfter,
          method: opts.method || null, status: 'success', createdAt: new Date().toISOString(),
        });

        result = { walletBefore: walletBefore, walletAfter: walletAfter };
      });
    }).then(function () {
      return { success: true, transactionId: txnId, balance: result.walletAfter, walletBefore: result.walletBefore };
    }).catch(function (err) {
      console.error('[WALLET] creditWallet FAILED — uid=' + userId + ' amount=' + amount +
                    ' code=' + (err && err.code) + ' message=' + (err && err.message));
      return { success: false, error: (err && err.message) || 'transaction_failed' };
    });
  }

  /* ══════════════════════════════════════════
     LOW BALANCE POPUP — shared, self-injecting
  ══════════════════════════════════════════ */

  var _cssInjected = false;
  function _injectCss() {
    if (_cssInjected) return;
    _cssInjected = true;
    var style = document.createElement('style');
    style.textContent =
      '.zpay-overlay{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;align-items:center;' +
        'justify-content:center;z-index:99999;opacity:0;transition:opacity .2s;padding:20px;box-sizing:border-box;}' +
      '.zpay-overlay.open{opacity:1;}' +
      '.zpay-card{background:var(--bg-card,#fff);border-radius:20px;padding:24px 22px;max-width:340px;width:100%;' +
        'text-align:center;transform:translateY(12px) scale(.97);transition:transform .2s;box-shadow:0 20px 60px rgba(0,0,0,.3);}' +
      '.zpay-overlay.open .zpay-card{transform:translateY(0) scale(1);}' +
      '.zpay-icon{font-size:40px;margin-bottom:8px;}' +
      '.zpay-title{font-size:17px;font-weight:800;color:var(--text-primary,#1E293B);margin-bottom:6px;}' +
      '.zpay-sub{font-size:13.5px;color:var(--text-secondary,#64748B);line-height:1.5;margin-bottom:16px;}' +
      '.zpay-row{display:flex;justify-content:space-between;font-size:13.5px;padding:8px 0;' +
        'border-top:1px solid var(--border,rgba(0,0,0,.08));color:var(--text-primary,#1E293B);}' +
      '.zpay-row span:last-child{font-weight:700;}' +
      '.zpay-btn{width:100%;padding:12px;border-radius:12px;font-size:14px;font-weight:700;margin-top:10px;' +
        'border:none;cursor:pointer;}' +
      '.zpay-btn--primary{background:linear-gradient(90deg,#FF8C00,#FFA726);color:#000;}' +
      '.zpay-btn--secondary{background:var(--bg-card-light,#F1F5F9);color:var(--text-secondary,#64748B);}';
    document.head.appendChild(style);
  }

  function showLowBalancePopup(opts) {
    _injectCss();
    var balance   = Number(opts.balance || 0);
    var required  = Number(opts.required || 0);
    var shortfall = Math.max(0, required - balance);
    /* Audit requirement: never let a ₹0 balance look like "your wallet is
       empty" when it actually means "your wallet has never synced to the
       server" — those are different problems with different fixes (the
       first needs money, the second needs a page reload / re-login). */
    var syncNote = (opts.walletDocStatus === 'user_doc_missing' || opts.walletDocStatus === 'wallet_field_missing')
      ? '<p class="zpay-sub" style="color:#B35900;font-weight:700;">⚠️ Your wallet hasn\'t synced to the server yet. If you\'ve added funds before, try reloading this page — your balance shown elsewhere may be a stale local copy.</p>'
      : '';

    var existing = document.getElementById('zpayLowBalanceOverlay');
    if (existing) existing.remove();

    var overlay = document.createElement('div');
    overlay.id = 'zpayLowBalanceOverlay';
    overlay.className = 'zpay-overlay';
    overlay.innerHTML =
      '<div class="zpay-card">' +
        '<div class="zpay-icon">💰</div>' +
        '<h3 class="zpay-title">Insufficient Wallet Balance</h3>' +
        '<p class="zpay-sub">You need &#8377;' + shortfall.toLocaleString('en-IN') + ' more to start this service.</p>' +
        syncNote +
        '<div class="zpay-row"><span>Current Balance</span><span>&#8377;' + balance.toLocaleString('en-IN') + '</span></div>' +
        '<div class="zpay-row"><span>Required</span><span>&#8377;' + required.toLocaleString('en-IN') + '</span></div>' +
        '<button class="zpay-btn zpay-btn--primary" id="zpayRechargeBtn" type="button">Recharge Wallet</button>' +
        '<button class="zpay-btn zpay-btn--secondary" id="zpayCancelBtn" type="button">Cancel</button>' +
      '</div>';
    document.body.appendChild(overlay);
    requestAnimationFrame(function () { overlay.classList.add('open'); });

    function close() {
      overlay.classList.remove('open');
      setTimeout(function () { overlay.remove(); }, 200);
    }
    overlay.querySelector('#zpayCancelBtn').addEventListener('click', function () {
      close();
      if (opts.onCancel) opts.onCancel();
    });
    overlay.querySelector('#zpayRechargeBtn').addEventListener('click', function () {
      close();
      if (opts.onRecharge) { opts.onRecharge(); return; }
      if (win.ZitlasWallet && typeof win.ZitlasWallet.openAddFunds === 'function') {
        win.ZitlasWallet.openAddFunds();
      } else if (win.ZitlasWallet && typeof win.ZitlasWallet.openPanel === 'function') {
        win.ZitlasWallet.openPanel();
      }
    });
    overlay.addEventListener('click', function (e) { if (e.target === overlay) { close(); if (opts.onCancel) opts.onCancel(); } });
  }

  win.ZitlasPayment = {
    PLATFORM_FEE_PERCENT: PLATFORM_FEE_PERCENT,
    attemptCharge: attemptCharge,
    creditWallet: creditWallet,
    showLowBalancePopup: showLowBalancePopup,
  };
})(window);
