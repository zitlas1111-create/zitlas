/*!
 * ZITLAS — Global Wallet Component  v1.0
 * Self-injecting wallet button + slide panel.
 *
 * Usage:  <script src="../../components/wallet.js"></script>
 * Public: window.ZitlasWallet.deduct(amount, desc) / .canAfford(n) / .getBalance()
 */
(function () {
  'use strict';

  /* ══════════════════════════════════════════
     STORAGE & DATA
  ══════════════════════════════════════════ */

  var KEY = 'zitlas_wallet';

  function getWallet() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) {
        var p = JSON.parse(raw);
        return {
          balance:      Number(p.balance      || 0),
          total_added:  Number(p.total_added  || 0),
          total_spent:  Number(p.total_spent  || 0),
          transactions: Array.isArray(p.transactions) ? p.transactions : [],
        };
      }
    } catch (_) {}
    return { balance: 0, total_added: 0, total_spent: 0, transactions: [] };
  }

  function saveWallet(w) {
    try { localStorage.setItem(KEY, JSON.stringify(w)); } catch (_) {}
  }

  /* ══════════════════════════════════════════
     COUPONS
  ══════════════════════════════════════════ */

  var COUPONS = [
    { code: 'WELCOME100', discount: '₹100 off', desc: 'Welcome bonus — first purchase',    valid: 'Dec 31, 2026' },
    { code: 'FIT50',      discount: '₹50 off',  desc: 'Nutritionist review discount',      valid: 'Dec 30, 2026' },
    { code: 'ZITLASPRO',  discount: '20% off',  desc: 'Premium features bundle',           valid: 'Dec 31, 2026' },
    { code: 'HEALTHIFY',  discount: '₹75 off',  desc: 'Diet plan verification discount',   valid: 'Dec 15, 2026' },
  ];

  /* ══════════════════════════════════════════
     STATE
  ══════════════════════════════════════════ */

  var _open         = false;
  var _view         = 'main';    // 'main' | 'transactions' | 'offers' | 'addFunds'
  var _addStep      = 1;         // 1 = choose amount, 2 = choose payment
  var _amt          = 0;
  var _payMethod    = null;

  /* ══════════════════════════════════════════
     CSS
  ══════════════════════════════════════════ */

  var CSS = (
    /* ── Wallet Button ─────────────────────────── */
    '.zw-btn{display:flex;flex-direction:column;align-items:center;justify-content:center;' +
      'gap:1px;min-width:40px;min-height:40px;padding:4px 6px;border-radius:12px;' +
      'background:transparent;border:none;cursor:pointer;color:rgba(var(--white-rgb),.65);' +
      'position:relative;-webkit-tap-highlight-color:transparent;' +
      'transition:background .18s,color .18s,transform .18s;}' +
    '.zw-btn:hover{background:rgba(var(--white-rgb),.07);color:var(--text-primary);transform:scale(1.06);}' +
    '.zw-btn:active{transform:scale(.92);}' +
    '[data-theme="light"] .zw-btn{color:rgba(var(--black-rgb),.55);}' +
    '[data-theme="light"] .zw-btn:hover{background:rgba(var(--black-rgb),.05);color:var(--bg-primary);}' +
    '.zw-btn-icon{display:flex;align-items:center;justify-content:center;position:relative;}' +
    '.zw-btn-lbl{font-size:9.5px;font-weight:800;color:var(--primary);line-height:1;' +
      'letter-spacing:.01em;font-variant-numeric:tabular-nums;}' +
    '.zw-dot{position:absolute;top:-2px;right:-3px;width:7px;height:7px;' +
      'background:var(--primary);border-radius:50%;border:2px solid var(--bg,var(--bg-primary));' +
      'opacity:0;transition:opacity .3s;}' +
    '.zw-dot.on{opacity:1;}' +

    /* ── Overlay ─────────────────────────────── */
    '#zwOverlay{position:fixed;inset:0;background:rgba(var(--black-rgb),.65);backdrop-filter:blur(4px);' +
      '-webkit-backdrop-filter:blur(4px);z-index:8500;opacity:0;pointer-events:none;' +
      'transition:opacity .25s ease;}' +
    '#zwOverlay.zw-open{opacity:1;pointer-events:all;}' +

    /* ── Panel ───────────────────────────────── */
    '#zwPanel{position:fixed;top:0;right:0;bottom:0;width:340px;max-width:100vw;' +
      'background:var(--bg-card);border-left:1px solid var(--border);z-index:8501;' +
      'display:flex;flex-direction:column;' +
      'transform:translateX(100%);transition:transform .3s cubic-bezier(.4,0,.2,1);' +
      'overflow:hidden;}' +
    '#zwPanel.zw-open{transform:translateX(0);}' +
    '@media(max-width:360px){#zwPanel{width:100vw;border-left:none;}}' +

    /* Panel header */
    '.zw-ph{display:flex;align-items:center;justify-content:space-between;' +
      'padding:18px 20px 14px;border-bottom:1px solid var(--border);flex-shrink:0;}' +
    '.zw-ph-left{display:flex;align-items:center;gap:10px;}' +
    '.zw-ph-ico{width:36px;height:36px;border-radius:10px;' +
      'background:rgba(var(--primary-rgb),.13);border:1px solid rgba(var(--primary-rgb),.25);' +
      'display:flex;align-items:center;justify-content:center;}' +
    '.zw-ph-title{font-size:17px;font-weight:800;color:var(--text-primary);letter-spacing:-.3px;}' +
    '.zw-ph-right{display:flex;align-items:center;gap:8px;}' +
    '.zw-icon-circle-btn{width:32px;height:32px;border-radius:50%;' +
      'background:rgba(var(--white-rgb),.07);border:none;cursor:pointer;' +
      'color:rgba(var(--white-rgb),.6);font-size:17px;' +
      'display:flex;align-items:center;justify-content:center;transition:background .15s;}' +
    '.zw-icon-circle-btn:hover{background:rgba(var(--white-rgb),.13);color:var(--text-primary);}' +

    /* Body */
    '.zw-body{flex:1;overflow-y:auto;scrollbar-width:thin;scrollbar-color:var(--border) transparent;' +
      '-webkit-overflow-scrolling:touch;}' +
    '.zw-body::-webkit-scrollbar{width:4px;}' +
    '.zw-body::-webkit-scrollbar-thumb{background:var(--border);border-radius:2px;}' +

    /* Balance Card */
    '.zw-bal-card{margin:16px;background:linear-gradient(135deg,var(--bg-card-light),var(--bg-card));' +
      'border:1px solid var(--border);border-radius:18px;padding:22px;position:relative;overflow:hidden;}' +
    '.zw-bal-card::before{content:"";position:absolute;top:-40px;right:-40px;' +
      'width:140px;height:140px;' +
      'background:radial-gradient(circle,rgba(var(--primary-rgb),.11) 0%,transparent 70%);pointer-events:none;}' +
    '.zw-bal-lbl{font-size:10px;font-weight:600;letter-spacing:.09em;' +
      'color:rgba(var(--white-rgb),.35);text-transform:uppercase;margin-bottom:6px;}' +
    '.zw-bal-amt{font-size:40px;font-weight:900;color:var(--text-primary);letter-spacing:-1.5px;' +
      'font-variant-numeric:tabular-nums;line-height:1.05;}' +
    '.zw-bal-cur{font-size:24px;font-weight:800;color:var(--primary);' +
      'vertical-align:super;margin-right:1px;}' +
    '.zw-bal-sub{font-size:11px;color:rgba(var(--white-rgb),.28);margin-top:5px;}' +

    /* Section title */
    '.zw-stitle{font-size:10px;font-weight:700;letter-spacing:.08em;' +
      'color:rgba(var(--white-rgb),.28);text-transform:uppercase;' +
      'padding:0 16px;margin:16px 0 8px;}' +

    /* Quick Actions */
    '.zw-qa-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;padding:0 16px;}' +
    '.zw-qa-btn{display:flex;flex-direction:column;align-items:center;gap:7px;' +
      'padding:14px 8px;background:var(--bg-card-light);border:1px solid var(--border);border-radius:14px;' +
      'cursor:pointer;transition:border-color .18s,background .18s,transform .12s;' +
      'color:rgba(var(--white-rgb),.75);}' +
    '.zw-qa-btn:hover{border-color:rgba(var(--primary-rgb),.35);background:rgba(var(--primary-rgb),.06);' +
      'color:var(--text-primary);transform:translateY(-1px);}' +
    '.zw-qa-btn:active{transform:scale(.94);}' +
    '.zw-qa-ico{width:36px;height:36px;border-radius:10px;font-size:17px;' +
      'background:rgba(var(--primary-rgb),.1);border:1px solid rgba(var(--primary-rgb),.18);' +
      'display:flex;align-items:center;justify-content:center;}' +
    '.zw-qa-lbl{font-size:10px;font-weight:700;text-align:center;line-height:1.3;}' +

    /* Stats Grid */
    '.zw-stats{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin:0 16px 16px;}' +
    '.zw-sc{background:var(--bg-card-light);border:1px solid var(--border);border-radius:14px;' +
      'padding:12px 8px;text-align:center;}' +
    '.zw-sc-lbl{font-size:9px;font-weight:600;color:rgba(var(--white-rgb),.3);' +
      'text-transform:uppercase;letter-spacing:.05em;display:block;margin-bottom:4px;}' +
    '.zw-sc-val{font-size:14px;font-weight:900;color:var(--text-primary);font-variant-numeric:tabular-nums;}' +
    '.zw-sc-val.g{color:var(--success);}.zw-sc-val.r{color:var(--primary-dark);}.zw-sc-val.o{color:var(--primary);}' +

    /* Transactions preview */
    '.zw-txp{margin:0 16px 16px;background:var(--bg-card-light);border:1px solid var(--border);' +
      'border-radius:14px;overflow:hidden;}' +
    '.zw-txp-hdr{display:flex;align-items:center;justify-content:space-between;' +
      'padding:12px 14px 10px;border-bottom:1px solid var(--border);}' +
    '.zw-txp-ttl{font-size:12px;font-weight:700;color:var(--text-primary);}' +
    '.zw-see-all{font-size:11px;color:var(--primary);background:none;border:none;' +
      'cursor:pointer;font-weight:700;padding:0;}' +
    '.zw-txp-empty{padding:18px 14px;font-size:12px;' +
      'color:rgba(var(--white-rgb),.3);text-align:center;}' +
    '.zw-tr{display:flex;align-items:center;gap:10px;padding:10px 14px;' +
      'border-bottom:1px solid var(--bg-card-light);transition:background .12s;}' +
    '.zw-tr:last-child{border-bottom:none;}' +
    '.zw-tr:hover{background:rgba(var(--white-rgb),.03);}' +
    '.zw-tr-ico{width:32px;height:32px;border-radius:8px;' +
      'display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;}' +
    '.zw-tr-ico.c{background:rgba(74,222,128,.1);}' +
    '.zw-tr-ico.d{background:rgba(248,113,113,.1);}' +
    '.zw-tr-inf{flex:1;min-width:0;}' +
    '.zw-tr-desc{font-size:12px;font-weight:600;color:var(--text-primary);' +
      'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' +
    '.zw-tr-date{font-size:10px;color:rgba(var(--white-rgb),.3);margin-top:1px;}' +
    '.zw-tr-amt{font-size:13px;font-weight:800;font-variant-numeric:tabular-nums;flex-shrink:0;}' +
    '.zw-tr-amt.c{color:var(--success);}.zw-tr-amt.d{color:var(--primary-dark);}' +

    /* Full Transactions / Offers */
    '.zw-txn-list{padding:10px 16px;}' +
    '.zw-txn-empty{padding:40px 20px;text-align:center;' +
      'color:rgba(var(--white-rgb),.3);font-size:13px;}' +
    '.zw-txn-empty-icon{font-size:38px;display:block;margin-bottom:10px;}' +
    '.zw-offers-list{padding:12px 16px;display:flex;flex-direction:column;gap:10px;}' +
    '.zw-cpn{background:linear-gradient(135deg,var(--bg-card-light),var(--bg-card-light));' +
      'border:1px solid rgba(var(--primary-rgb),.18);border-radius:14px;' +
      'padding:14px 16px;display:flex;align-items:center;gap:12px;' +
      'position:relative;overflow:hidden;}' +
    '.zw-cpn::before{content:"";position:absolute;inset-y:0;left:0;' +
      'width:3px;background:var(--primary);}' +
    '.zw-cpn-l{flex:1;min-width:0;}' +
    '.zw-cpn-code{font-size:14px;font-weight:900;color:var(--primary);' +
      'letter-spacing:.06em;margin-bottom:2px;}' +
    '.zw-cpn-desc{font-size:11px;color:rgba(var(--white-rgb),.5);}' +
    '.zw-cpn-valid{font-size:10px;color:rgba(var(--white-rgb),.28);margin-top:3px;}' +
    '.zw-cpn-r{flex-shrink:0;text-align:right;}' +
    '.zw-cpn-disc{font-size:13px;font-weight:800;color:var(--text-primary);display:block;margin-bottom:6px;}' +
    '.zw-copy-btn{font-size:10px;font-weight:700;color:var(--primary);' +
      'background:rgba(var(--primary-rgb),.1);border:1px solid rgba(var(--primary-rgb),.25);' +
      'border-radius:20px;padding:3px 10px;cursor:pointer;transition:background .15s;' +
      'white-space:nowrap;}' +
    '.zw-copy-btn:hover{background:rgba(var(--primary-rgb),.2);}' +
    '.zw-copy-btn.copied{color:var(--success);background:rgba(74,222,128,.1);' +
      'border-color:rgba(74,222,128,.25);}' +

    /* Add Funds */
    '.zw-af-body{padding:16px;}' +
    '.zw-af-sub{font-size:12px;color:rgba(var(--white-rgb),.4);margin-bottom:16px;}' +
    '.zw-amt-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:14px;}' +
    '.zw-amt-btn{padding:14px;background:var(--bg-card-light);border:1px solid var(--border);' +
      'border-radius:12px;font-size:17px;font-weight:800;color:var(--text-primary);cursor:pointer;' +
      'text-align:center;font-variant-numeric:tabular-nums;' +
      'transition:border-color .15s,background .15s,transform .1s;}' +
    '.zw-amt-btn:hover{border-color:rgba(var(--primary-rgb),.4);background:rgba(var(--primary-rgb),.06);}' +
    '.zw-amt-btn:active{transform:scale(.96);}' +
    '.zw-amt-btn.sel{border-color:var(--primary);background:rgba(var(--primary-rgb),.1);color:var(--primary);}' +
    '.zw-custom-wrap{position:relative;margin-bottom:20px;}' +
    '.zw-custom-pfx{position:absolute;left:14px;top:50%;transform:translateY(-50%);' +
      'font-size:16px;font-weight:700;color:rgba(var(--white-rgb),.35);}' +
    '.zw-custom-inp{width:100%;box-sizing:border-box;background:var(--bg-card-light);' +
      'border:1px solid var(--border);border-radius:12px;padding:14px 14px 14px 30px;' +
      'font-size:15px;font-weight:700;color:var(--text-primary);outline:none;font-family:inherit;' +
      'transition:border-color .15s;}' +
    '.zw-custom-inp:focus{border-color:rgba(var(--primary-rgb),.5);}' +
    '.zw-custom-inp::placeholder{color:rgba(var(--white-rgb),.22);font-weight:400;}' +

    /* Payment methods */
    '.zw-pay-amt-row{display:flex;align-items:center;justify-content:space-between;' +
      'margin:0 16px 16px;background:rgba(var(--primary-rgb),.07);' +
      'border:1px solid rgba(var(--primary-rgb),.2);border-radius:12px;padding:12px 14px;}' +
    '.zw-pay-lbl{font-size:12px;color:rgba(var(--white-rgb),.45);}' +
    '.zw-pay-val{font-size:19px;font-weight:900;color:var(--primary);' +
      'font-variant-numeric:tabular-nums;}' +
    '.zw-pay-methods{padding:0 16px;display:flex;flex-direction:column;gap:10px;}' +
    '.zw-pay-opt{display:flex;align-items:center;gap:12px;padding:14px 16px;' +
      'background:var(--bg-card-light);border:2px solid var(--border);border-radius:14px;cursor:pointer;' +
      'transition:border-color .15s,background .15s;}' +
    '.zw-pay-opt:hover{border-color:rgba(var(--primary-rgb),.35);background:rgba(var(--primary-rgb),.04);}' +
    '.zw-pay-opt.sel{border-color:var(--primary);background:rgba(var(--primary-rgb),.07);}' +
    '.zw-pay-ico{width:40px;height:40px;border-radius:10px;font-size:20px;' +
      'display:flex;align-items:center;justify-content:center;' +
      'background:rgba(var(--white-rgb),.06);flex-shrink:0;}' +
    '.zw-pay-inf{flex:1;}' +
    '.zw-pay-name{font-size:13px;font-weight:700;color:var(--text-primary);}' +
    '.zw-pay-sub{font-size:11px;color:rgba(var(--white-rgb),.38);margin-top:1px;}' +
    '.zw-pay-chk{width:20px;height:20px;border-radius:50%;border:2px solid var(--border);' +
      'flex-shrink:0;transition:border-color .15s,background .15s;}' +
    '.zw-pay-opt.sel .zw-pay-chk{border-color:var(--primary);background:var(--primary);}' +
    '.zw-pay-footer{padding:16px 16px 24px;}' +

    /* Primary CTA button */
    '.zw-cta{width:100%;padding:15px;background:linear-gradient(135deg,var(--primary),var(--primary-dark));' +
      'border:none;border-radius:14px;font-size:15px;font-weight:800;color:var(--text-primary);' +
      'cursor:pointer;transition:opacity .18s,transform .14s;' +
      'box-shadow:0 4px 18px rgba(var(--primary-rgb),.35);}' +
    '.zw-cta:hover{opacity:.9;}.zw-cta:active{transform:scale(.97);}' +
    '.zw-cta:disabled{opacity:.3;cursor:default;box-shadow:none;}' +

    /* Toast */
    '#zwToast{position:fixed;bottom:110px;left:50%;transform:translateX(-50%);' +
      'background:var(--border);border:1px solid rgba(var(--primary-rgb),.25);border-radius:40px;' +
      'padding:10px 22px;font-size:13px;font-weight:700;color:var(--text-primary);' +
      'z-index:9999;pointer-events:none;opacity:0;transition:opacity .22s;' +
      'white-space:nowrap;box-shadow:0 4px 20px rgba(var(--black-rgb),.55);}' +
    '#zwToast.on{opacity:1;}'
  );

  /* ══════════════════════════════════════════
     HELPERS
  ══════════════════════════════════════════ */

  function esc(s) {
    return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }
  function fmtAmt(n) { return '₹' + Number(n || 0).toLocaleString('en-IN'); }
  function fmtDate(iso) {
    if (!iso) return '—';
    try { return new Date(iso).toLocaleDateString('en-IN', { day:'numeric', month:'short', year:'numeric' }); }
    catch (_) { return ''; }
  }

  /* ══════════════════════════════════════════
     BUTTON HTML
  ══════════════════════════════════════════ */

  var WALLET_SVG = (
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="1" y="4" width="22" height="16" rx="2" ry="2"/>' +
      '<path d="M1 10h22"/>' +
      '<circle cx="17" cy="15" r="1.5" fill="currentColor" stroke="none"/>' +
    '</svg>'
  );

  function buildButton(balance) {
    return (
      '<button class="zw-btn" id="zwBtn" aria-label="My Wallet">' +
        '<span class="zw-btn-icon">' + WALLET_SVG + '<span class="zw-dot" id="zwDot"></span></span>' +
        '<span class="zw-btn-lbl" id="zwBtnLbl">' + esc(fmtAmt(balance)) + '</span>' +
      '</button>'
    );
  }

  /* ══════════════════════════════════════════
     PANEL SHELL
  ══════════════════════════════════════════ */

  var BACK_SVG = (
    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">' +
      '<line x1="19" y1="12" x2="5" y2="12"/><polyline points="12 19 5 12 12 5"/>' +
    '</svg>'
  );

  function buildPanel() {
    return (
      '<div id="zwPanel">' +
        '<div class="zw-ph">' +
          '<div class="zw-ph-left">' +
            '<div class="zw-ph-ico">' +
              '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" ' +
              'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
                '<rect x="1" y="4" width="22" height="16" rx="2" ry="2"/>' +
                '<path d="M1 10h22"/><circle cx="17" cy="15" r="1.5" fill="var(--primary)" stroke="none"/>' +
              '</svg>' +
            '</div>' +
            '<span class="zw-ph-title" id="zwTitle">My Wallet</span>' +
          '</div>' +
          '<div class="zw-ph-right">' +
            '<button class="zw-icon-circle-btn" id="zwBack" style="display:none" aria-label="Back">' + BACK_SVG + '</button>' +
            '<button class="zw-icon-circle-btn" id="zwClose" aria-label="Close">✕</button>' +
          '</div>' +
        '</div>' +
        '<div class="zw-body" id="zwBody"></div>' +
      '</div>'
    );
  }

  /* ══════════════════════════════════════════
     TRANSACTION ROW HELPER
  ══════════════════════════════════════════ */

  function txnRow(t) {
    var c = t.type === 'credit';
    return (
      '<div class="zw-tr">' +
        '<div class="zw-tr-ico ' + (c ? 'c' : 'd') + '">' + (c ? '⬆️' : '⬇️') + '</div>' +
        '<div class="zw-tr-inf">' +
          '<div class="zw-tr-desc">' + esc(t.description) + '</div>' +
          '<div class="zw-tr-date">' + fmtDate(t.date) + '</div>' +
        '</div>' +
        '<span class="zw-tr-amt ' + (c ? 'c' : 'd') + '">' + (c ? '+' : '−') + esc(fmtAmt(Math.abs(t.amount))) + '</span>' +
      '</div>'
    );
  }

  /* ══════════════════════════════════════════
     VIEWS
  ══════════════════════════════════════════ */

  function renderMain() {
    var w      = getWallet();
    var recent = w.transactions.slice(-3).reverse();
    var txnHTML = recent.length
      ? recent.map(txnRow).join('')
      : '<div class="zw-txp-empty">No transactions yet</div>';

    var lastCount = Math.min(recent.length, 3);

    el('zwBody').innerHTML = (
      /* Balance */
      '<div class="zw-bal-card">' +
        '<div class="zw-bal-lbl">Available Balance</div>' +
        '<div class="zw-bal-amt"><span class="zw-bal-cur">₹</span>' +
          '<span id="zwBalAmt">' + Number(w.balance).toLocaleString('en-IN') + '</span>' +
        '</div>' +
        '<div class="zw-bal-sub">ZITLAS Wallet · Secure &amp; Instant</div>' +
      '</div>' +

      /* Quick Actions */
      '<div class="zw-stitle">Quick Actions</div>' +
      '<div class="zw-qa-grid">' +
        qaBtn('zwQA_add',  '💳', 'Add Funds') +
        qaBtn('zwQA_hist', '📋', 'Transaction History') +
        qaBtn('zwQA_off',  '🎁', 'Offers &amp; Coupons') +
      '</div>' +

      /* Stats */
      '<div class="zw-stitle" style="margin-top:18px">Wallet Usage</div>' +
      '<div class="zw-stats">' +
        statCard('Added',   fmtAmt(w.total_added),  'g') +
        statCard('Spent',   fmtAmt(w.total_spent),  'r') +
        statCard('Balance', fmtAmt(w.balance),       'o') +
      '</div>' +

      /* Recent Transactions */
      '<div class="zw-stitle">Recent Transactions</div>' +
      '<div class="zw-txp">' +
        '<div class="zw-txp-hdr">' +
          '<span class="zw-txp-ttl">Last ' + lastCount + ' transaction' + (lastCount !== 1 ? 's' : '') + '</span>' +
          '<button class="zw-see-all" id="zwSeeAll">See all →</button>' +
        '</div>' +
        txnHTML +
      '</div>'
    );

    on('zwQA_add',  'click', function() { showView('addFunds'); });
    on('zwQA_hist', 'click', function() { showView('transactions'); });
    on('zwQA_off',  'click', function() { showView('offers'); });
    on('zwSeeAll',  'click', function() { showView('transactions'); });
  }

  function qaBtn(id, icon, label) {
    return '<button class="zw-qa-btn" id="' + id + '">' +
      '<div class="zw-qa-ico">' + icon + '</div>' +
      '<span class="zw-qa-lbl">' + label + '</span>' +
    '</button>';
  }
  function statCard(lbl, val, cls) {
    return '<div class="zw-sc"><span class="zw-sc-lbl">' + lbl + '</span>' +
      '<span class="zw-sc-val ' + cls + '">' + esc(val) + '</span></div>';
  }

  function renderTransactions() {
    var txns = getWallet().transactions.slice().reverse();
    el('zwBody').innerHTML = txns.length
      ? '<div class="zw-txn-list">' + txns.map(txnRow).join('') + '</div>'
      : '<div class="zw-txn-empty"><span class="zw-txn-empty-icon">📋</span>' +
          'No transactions yet.<br>Add funds to get started!</div>';
  }

  function renderOffers() {
    el('zwBody').innerHTML = (
      '<div class="zw-offers-list">' +
        COUPONS.map(function(c) {
          return (
            '<div class="zw-cpn">' +
              '<div class="zw-cpn-l">' +
                '<div class="zw-cpn-code">' + esc(c.code) + '</div>' +
                '<div class="zw-cpn-desc">' + esc(c.desc) + '</div>' +
                '<div class="zw-cpn-valid">Valid till ' + esc(c.valid) + '</div>' +
              '</div>' +
              '<div class="zw-cpn-r">' +
                '<span class="zw-cpn-disc">' + esc(c.discount) + '</span>' +
                '<button class="zw-copy-btn" data-code="' + esc(c.code) + '">Copy</button>' +
              '</div>' +
            '</div>'
          );
        }).join('') +
      '</div>'
    );

    el('zwBody').querySelectorAll('.zw-copy-btn').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var code = btn.dataset.code;
        try { navigator.clipboard && navigator.clipboard.writeText(code); } catch (_) {}
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(function() { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000);
        toast('Coupon code copied!');
      });
    });
  }

  function renderAddFundsStep1() {
    _addStep = 1; _amt = 0; _payMethod = null;
    var amounts = [100, 250, 500, 1000, 2000];
    el('zwBody').innerHTML = (
      '<div class="zw-af-body">' +
        '<div class="zw-af-sub">Choose an amount or enter a custom amount to add to your wallet.</div>' +
        '<div class="zw-amt-grid">' +
          amounts.map(function(a) {
            return '<button class="zw-amt-btn" data-a="' + a + '">₹' + a + '</button>';
          }).join('') +
        '</div>' +
        '<div class="zw-custom-wrap">' +
          '<span class="zw-custom-pfx">₹</span>' +
          '<input class="zw-custom-inp" id="zwCustom" type="number" min="1" max="50000" placeholder="Enter custom amount">' +
        '</div>' +
        '<button class="zw-cta" id="zwContinue" disabled>Continue to Payment</button>' +
      '</div>'
    );

    var contBtn   = el('zwContinue');
    var customInp = el('zwCustom');

    function setAmt(a) {
      _amt = a;
      el('zwBody').querySelectorAll('.zw-amt-btn').forEach(function(b) {
        b.classList.toggle('sel', Number(b.dataset.a) === a);
      });
      contBtn.disabled = !(a > 0);
    }

    el('zwBody').querySelectorAll('.zw-amt-btn').forEach(function(btn) {
      btn.addEventListener('click', function() { customInp.value = ''; setAmt(Number(btn.dataset.a)); });
    });

    customInp.addEventListener('input', function() {
      var v = parseInt(customInp.value, 10);
      el('zwBody').querySelectorAll('.zw-amt-btn').forEach(function(b) { b.classList.remove('sel'); });
      _amt = v > 0 ? v : 0;
      contBtn.disabled = !(_amt > 0);
    });

    contBtn.addEventListener('click', function() { if (_amt > 0) renderAddFundsStep2(); });
  }

  function renderAddFundsStep2() {
    _addStep = 2; _payMethod = null;
    var methods = [
      { id: 'upi',     icon: '📱', name: 'UPI',         sub: 'GPay, PhonePe, Paytm, QR code' },
      { id: 'credit',  icon: '💳', name: 'Credit Card',  sub: 'Visa, Mastercard, RuPay, Amex' },
      { id: 'debit',   icon: '🏦', name: 'Debit Card',   sub: 'All Indian bank debit cards'   },
      { id: 'netbank', icon: '🌐', name: 'Net Banking',  sub: 'HDFC, ICICI, SBI, Axis + more' },
    ];

    el('zwBody').innerHTML = (
      '<div class="zw-pay-amt-row">' +
        '<span class="zw-pay-lbl">Adding to wallet</span>' +
        '<span class="zw-pay-val">₹' + Number(_amt).toLocaleString('en-IN') + '</span>' +
      '</div>' +
      '<div class="zw-pay-methods">' +
        methods.map(function(m) {
          return (
            '<div class="zw-pay-opt" data-pid="' + m.id + '">' +
              '<div class="zw-pay-ico">' + m.icon + '</div>' +
              '<div class="zw-pay-inf">' +
                '<div class="zw-pay-name">' + esc(m.name) + '</div>' +
                '<div class="zw-pay-sub">' + esc(m.sub) + '</div>' +
              '</div>' +
              '<div class="zw-pay-chk"></div>' +
            '</div>'
          );
        }).join('') +
      '</div>' +
      '<div class="zw-pay-footer">' +
        '<button class="zw-cta" id="zwPayBtn" disabled>Pay ₹' + Number(_amt).toLocaleString('en-IN') + '</button>' +
      '</div>'
    );

    el('zwBody').querySelectorAll('.zw-pay-opt').forEach(function(opt) {
      opt.addEventListener('click', function() {
        el('zwBody').querySelectorAll('.zw-pay-opt').forEach(function(o) { o.classList.remove('sel'); });
        opt.classList.add('sel');
        _payMethod = opt.dataset.pid;
        el('zwPayBtn').disabled = false;
      });
    });

    on('zwPayBtn', 'click', function() {
      if (_payMethod) creditFunds(_amt, _payMethod);
    });
  }

  /* ══════════════════════════════════════════
     FUND OPERATIONS
  ══════════════════════════════════════════ */

  function creditFunds(amount, method) {
    var w = getWallet();
    w.balance     += amount;
    w.total_added += amount;
    w.transactions.push({
      id:          'txn_' + Date.now(),
      type:        'credit',
      amount:      amount,
      description: 'Added Funds via ' + {upi:'UPI',credit:'Credit Card',debit:'Debit Card',netbank:'Net Banking'}[method] || method,
      date:        new Date().toISOString(),
    });
    saveWallet(w);
    syncBtnLabel(w.balance);
    showDot();
    showView('main');
    toast('✅ ' + fmtAmt(amount) + ' added to your wallet!');
  }

  function deductFunds(amount, description) {
    var w = getWallet();
    if (w.balance < amount) return false;
    w.balance     -= amount;
    w.total_spent += amount;
    w.transactions.push({
      id:          'txn_' + Date.now(),
      type:        'debit',
      amount:      amount,
      description: description || 'Purchase',
      date:        new Date().toISOString(),
    });
    saveWallet(w);
    syncBtnLabel(w.balance);
    showDot();
    return true;
  }

  /* ══════════════════════════════════════════
     VIEW ROUTER
  ══════════════════════════════════════════ */

  var TITLES = { main:'My Wallet', transactions:'Transaction History', offers:'Offers & Coupons', addFunds:'Add Funds' };

  function showView(view) {
    _view = view;
    var isMain = view === 'main';
    var backEl  = el('zwBack');
    var titleEl = el('zwTitle');
    if (backEl)  backEl.style.display  = isMain ? 'none' : 'flex';
    if (titleEl) titleEl.textContent   = TITLES[view] || 'My Wallet';

    if      (view === 'main')         renderMain();
    else if (view === 'transactions') renderTransactions();
    else if (view === 'offers')       renderOffers();
    else if (view === 'addFunds')     renderAddFundsStep1();
  }

  /* ══════════════════════════════════════════
     PANEL OPEN / CLOSE
  ══════════════════════════════════════════ */

  function openPanel() {
    _open = true;
    cl('zwOverlay', 'zw-open', true);
    cl('zwPanel',   'zw-open', true);
    document.body.style.overflow = 'hidden';
    showView('main');
    showDot(false);
  }

  function closePanel() {
    _open = false;
    cl('zwOverlay', 'zw-open', false);
    cl('zwPanel',   'zw-open', false);
    document.body.style.overflow = '';
  }

  /* ══════════════════════════════════════════
     UI HELPERS
  ══════════════════════════════════════════ */

  function el(id) { return document.getElementById(id); }
  function on(id, ev, fn) { var e = el(id); if (e) e.addEventListener(ev, fn); }
  function cl(id, cls, add) {
    var e = el(id);
    if (e) { if (add) e.classList.add(cls); else e.classList.remove(cls); }
  }

  function syncBtnLabel(balance) {
    var lbl = el('zwBtnLbl');
    if (lbl) lbl.textContent = fmtAmt(balance);
  }

  function showDot(show) {
    var dot = el('zwDot');
    if (dot) dot.classList.toggle('on', show !== false);
  }

  var _toastTimer = null;
  function toast(msg) {
    var t = el('zwToast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('on');
    clearTimeout(_toastTimer);
    _toastTimer = setTimeout(function() { t.classList.remove('on'); }, 3200);
  }

  /* ══════════════════════════════════════════
     INJECTION
  ══════════════════════════════════════════ */

  function findTarget() {
    /* Insert BEFORE notification button (creates visual group) */
    var notif = el('notifBtn');
    if (notif) return { parent: notif.parentNode, before: notif };

    /* Insert BEFORE info/menu buttons on other pages */
    var info = el('infoBtn');
    if (info) return { parent: info.parentNode, before: info };

    var menu = el('menuBtn');
    if (menu && menu.closest('header')) return { parent: menu.parentNode, before: menu };

    /* Insert before right-side logo text on plan/training pages */
    var rightLogo = document.querySelector('.wp-header-logo, .tp-header-logo');
    if (rightLogo) return { parent: rightLogo.parentNode, before: rightLogo };

    /* Append to any recognized header */
    var hdr = document.querySelector('header.app-bar, header.dash-header, header.cp-header');
    if (hdr) return { parent: hdr, before: null };

    return null;
  }

  function inject() {
    /* Skip pages where wallet is not relevant */
    var path = window.location.pathname;
    if (/\/(login|expert-dashboard|expert-review)(\.html)?(\?|$|#)/.test(path)) return;

    /* Inject CSS once */
    if (!el('zw-css')) {
      var s = document.createElement('style');
      s.id = 'zw-css';
      s.textContent = CSS;
      document.head.appendChild(s);
    }

    /* Remove stale button from previous inject */
    var old = el('zwBtn');
    if (old) { var grp = el('zwBtnGroup'); if (grp) old.remove(); else old.remove(); }

    /* Inject button next to notification/right-side button */
    var balance = getWallet().balance;
    var target  = findTarget();
    if (target) {
      /* Wrap wallet button + neighbour in a flex group so header layout stays tidy */
      if (target.before && !el('zwBtnGroup')) {
        var group = document.createElement('div');
        group.id = 'zwBtnGroup';
        group.style.cssText = 'display:flex;align-items:center;gap:4px;';
        target.parent.insertBefore(group, target.before);
        group.appendChild(target.before); /* move the neighbour button inside the group */
        var tmp = document.createElement('div');
        tmp.innerHTML = buildButton(balance);
        group.insertBefore(tmp.firstChild, target.before);
      } else {
        var tmp2 = document.createElement('div');
        tmp2.innerHTML = buildButton(balance);
        if (target.before) target.parent.insertBefore(tmp2.firstChild, target.before);
        else target.parent.appendChild(tmp2.firstChild);
      }
    }

    /* Inject overlay */
    if (!el('zwOverlay')) {
      var ov = document.createElement('div');
      ov.id = 'zwOverlay';
      document.body.appendChild(ov);
    }

    /* Inject panel */
    if (!el('zwPanel')) {
      var pd = document.createElement('div');
      pd.innerHTML = buildPanel();
      document.body.appendChild(pd.firstChild);
    }

    /* Inject toast */
    if (!el('zwToast')) {
      var ts = document.createElement('div');
      ts.id = 'zwToast';
      document.body.appendChild(ts);
    }

    /* Wire events */
    on('zwBtn',     'click', openPanel);
    on('zwClose',   'click', closePanel);
    on('zwOverlay', 'click', closePanel);
    on('zwBack', 'click', function() {
      if (_view === 'addFunds' && _addStep === 2) renderAddFundsStep1();
      else showView('main');
    });

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && _open) closePanel();
    });

    /* Show orange dot if balance > 0 to indicate wallet is funded */
    if (getWallet().balance > 0) showDot();
  }

  /* ══════════════════════════════════════════
     PUBLIC API
  ══════════════════════════════════════════ */

  window.ZitlasWallet = {
    getBalance: function()             { return getWallet().balance; },
    canAfford:  function(n)            { return getWallet().balance >= n; },
    deduct:     function(n, desc)      { return deductFunds(n, desc); },
    credit:     function(n, desc)      {
      var w = getWallet();
      w.balance += n; w.total_added += n;
      w.transactions.push({ id:'txn_'+Date.now(), type:'credit', amount:n, description: desc||'Credit', date: new Date().toISOString() });
      saveWallet(w); syncBtnLabel(w.balance); showDot();
    },
    openPanel:  openPanel,
    refresh:    function()             { syncBtnLabel(getWallet().balance); },
  };

  /* ══════════════════════════════════════════
     AUTO-INJECT
  ══════════════════════════════════════════ */

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }

})();
