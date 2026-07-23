/* ============================================================================
 * demo-shim.js — GitHub Pages 静的モックアップ専用の疑似バックエンド
 * build/build-mockup.ps1 が生成物の head 終端直前へインライン注入する。
 * 製品コード（src/）には一切含まれない。CI / Pages 限定。
 *
 * 方針: 製品 JS（polling.js / hold.js / remote.js / Auth.html 内 JS）は
 * 無改変のまま実走させ、window.fetch と form 送信だけを横取りして
 * server.ps1 / com-handler.ps1 相当の応答を返す。これにより
 * LIVE/SLOW/OFFLINE 表示・offline overlay・backoff・lock UI・スライド操作は
 * すべて製品コードの実経路で動く。
 *
 * 依存する製品側 API 契約（変更時はここも追従すること）:
 *   GET  /status            -> text: waiting|changing|starting|running|stopping
 *   GET  /slide/state?cid=  -> json: {ms,pos,total,atEnd,lock,mine,black,white}
 *   POST /slide/<cmd>  body cid= -> json: {locked:true} | {pos,total,atEnd,black,white}
 *   POST /lock/(on|off|steal) body cid= -> json: {}
 *   form POST: /auth /select /start /next /retry /lobby /exit /stop
 * ========================================================================== */
(function () {
    'use strict';

    /* PAGE / DEMO_PIN / DECKS はビルド時に build/build-mockup.ps1 が注入する。
       shim 側では値を持たない（PIN とサンプルデッキ名の二重管理を避けるため）。 */
    var PAGE = window.__MOCK_PAGE || 'index';
    var DEMO_PIN = window.__MOCK_PIN || '';
    var DECKS = window.__MOCK_DECKS || { queue: [], done: [] };
    var TOTAL_SLIDES = 24;
    var PROCESSING_MS = 1600;

    /* ---------------- 状態（sessionStorage でページ間永続） ---------------- */
    var DEFAULT_STATE = {
        queue: (DECKS.queue || []).slice(),
        done: (DECKS.done || []).slice(),
        current: null,          /* 再生中デッキ名 */
        lastPlayed: null,       /* Dialog 表示・retry 用 */
        pos: 1, total: TOTAL_SLIDES, atEnd: false,
        black: false, white: false,
        lockCid: '',            /* '' = ロックなし。'mock-other' = 他端末 */
        startedAt: 0,
        nextPage: ''            /* Processing 通過後の遷移先 */
    };
    function loadState() {
        try {
            var raw = sessionStorage.getItem('mock_state');
            if (raw) { return JSON.parse(raw); }
        } catch (e) { /* fallthrough */ }
        return JSON.parse(JSON.stringify(DEFAULT_STATE));
    }
    function saveState() { try { sessionStorage.setItem('mock_state', JSON.stringify(S)); } catch (e) {} }
    var S = loadState();

    /* ---------------- ネットワークシミュレータ ---------------- */
    /* live: 40-120ms / slow: 900-1500ms (>600ms で製品側が SLOW 判定) / offline: 失敗 */
    function getNet() { return sessionStorage.getItem('mock_net') || 'live'; }
    function setNet(v) { try { sessionStorage.setItem('mock_net', v); } catch (e) {} renderPanel(); }
    function latencyMs() {
        return getNet() === 'slow' ? 900 + Math.random() * 600 : 40 + Math.random() * 80;
    }

    /* ---------------- 疑似バックエンド（fetch 横取り） ---------------- */
    function bodyCid(init) {
        var b = (init && typeof init.body === 'string') ? init.body : '';
        var m = /(?:^|&)cid=([^&]*)/.exec(b);
        return m ? decodeURIComponent(m[1]) : '';
    }
    function stateJson(cid) {
        return {
            ms: S.startedAt ? (Date.now() - S.startedAt) : 0,
            pos: S.pos, total: S.total, atEnd: S.atEnd,
            lock: S.lockCid !== '',
            mine: S.lockCid !== '' && S.lockCid === cid,
            black: S.black, white: S.white
        };
    }
    function applySlideCmd(cmd) {
        if (cmd === 'next')      { if (S.pos < S.total) { S.pos++; } }
        else if (cmd === 'prev') { if (S.pos > 1) { S.pos--; } }
        else if (cmd === 'first'){ S.pos = 1; }
        else if (cmd === 'last') { S.pos = S.total; }
        else if (cmd === 'blackout') { S.black = !S.black; if (S.black) { S.white = false; } }
        else if (cmd === 'whiteout') { S.white = !S.white; if (S.white) { S.black = false; } }
        S.atEnd = (S.pos >= S.total);
        saveState();
    }
    /* ページごとに polling.js の期待ステータスを返し、root への redirect を発生させない。
       画面遷移は shim 側（form 横取り / Processing タイマー）が担う。 */
    var PAGE_STATUS = { lobby: 'waiting', dialog: 'waiting', processing: 'changing', nowplaying: 'running' };

    function routeRequest(path, query, init) {
        var method = (init && init.method ? init.method : 'GET').toUpperCase();
        if (path === '/status') {
            return { body: PAGE_STATUS[PAGE] || 'waiting', type: 'text/plain' };
        }
        if (path === '/slide/state') {
            var qm = /(?:^|&)cid=([^&]*)/.exec(query || '');
            return { body: JSON.stringify(stateJson(qm ? decodeURIComponent(qm[1]) : '')), type: 'application/json' };
        }
        if (method === 'POST' && path.indexOf('/slide/') === 0) {
            var cid = bodyCid(init);
            if (S.lockCid === '' || S.lockCid !== cid) {
                return { body: JSON.stringify({ locked: true }), type: 'application/json' };
            }
            applySlideCmd(path.substring('/slide/'.length));
            return { body: JSON.stringify({ pos: S.pos, total: S.total, atEnd: S.atEnd, black: S.black, white: S.white }), type: 'application/json' };
        }
        if (method === 'POST' && path.indexOf('/lock/') === 0) {
            var c = bodyCid(init), op = path.substring('/lock/'.length);
            if (op === 'on')    { if (S.lockCid === '') { S.lockCid = c; } }
            else if (op === 'off')   { if (S.lockCid === c) { S.lockCid = ''; } }
            else if (op === 'steal') { S.lockCid = c; }
            saveState();
            return { body: JSON.stringify({}), type: 'application/json' };
        }
        return { body: '', type: 'text/plain', status: 404 };
    }

    window.fetch = function (input, init) {
        var href = (typeof input === 'string') ? input : (input && input.url) || '';
        var u;
        try { u = new URL(href, window.location.href); } catch (e) { u = null; }
        var path = u ? u.pathname : '';
        var query = u ? u.search.replace(/^\?/, '') : '';
        return new Promise(function (resolve, reject) {
            if (getNet() === 'offline') {
                setTimeout(function () { reject(new TypeError('mockup: network offline')); }, 1200);
                return;
            }
            setTimeout(function () {
                var r = routeRequest(path, query, init);
                resolve(new Response(r.body, { status: r.status || 200, headers: { 'Content-Type': r.type } }));
            }, latencyMs());
        });
    };

    /* ---------------- 画面遷移（form 横取り） ---------------- */
    function go(page) { window.location.href = './' + page; }
    function overlayActive() {
        var o = document.getElementById('offline-overlay');
        return !!(o && o.classList.contains('active'));
    }
    function startDeck(name) {
        if (!name) { return; }
        S.current = name; S.lastPlayed = name;
        S.pos = 1; S.atEnd = false; S.black = false; S.white = false;
        S.lockCid = '';                       /* 再生ごとにロック破棄（製品の安全リセットと同義） */
        S.startedAt = Date.now();
        S.nextPage = 'nowplaying.html';
        saveState();
        go('processing.html');
    }
    function pendingAfterCurrent() {
        /* Dialog の Start Next: 未再生キューの先頭（lastPlayed を除く） */
        for (var i = 0; i < S.queue.length; i++) {
            if (S.queue[i] !== S.lastPlayed && S.done.indexOf(S.queue[i]) === -1) { return S.queue[i]; }
        }
        return null;
    }
    function endShow() {
        if (S.current) {
            if (S.done.indexOf(S.current) === -1) { S.done.push(S.current); }
            var i = S.queue.indexOf(S.current);
            if (i !== -1) { S.queue.splice(i, 1); }
            S.current = null;
            saveState();
        }
        go('dialog.html');
    }
    function handleAction(actionPath, form) {
        if (actionPath === '/auth') {
            var pinEl = form.querySelector('#pinValue');
            var pin = pinEl ? pinEl.value : '';
            if (pin === DEMO_PIN) { go('lobby.html'); } else { go('auth-error.html'); }
        }
        else if (actionPath === '/select') {
            var f = form.querySelector('input[name="filename"]');
            startDeck(f ? f.value : null);
        }
        else if (actionPath === '/start') {
            var first = null;
            for (var i = 0; i < S.queue.length; i++) {
                if (S.done.indexOf(S.queue[i]) === -1) { first = S.queue[i]; break; }
            }
            if (first) { startDeck(first); }
        }
        else if (actionPath === '/next')  { var n = pendingAfterCurrent(); if (n) { startDeck(n); } }
        else if (actionPath === '/retry') { startDeck(S.lastPlayed); }
        else if (actionPath === '/lobby') { go('lobby.html'); }
        else if (actionPath === '/exit' || actionPath === '/stop') { go('exit.html'); }
    }
    document.addEventListener('submit', function (e) {
        e.preventDefault();                   /* 実送信は常に抑止（静的ホスティング） */
        if (overlayActive()) { return; }      /* 製品同様、オフライン中は操作を弾く */
        var form = e.target;
        var a = form.getAttribute('action') || '';
        var path;
        try { path = new URL(a, window.location.href).pathname; } catch (er) { path = a; }
        /* Pages はサブパス配信のため、root 相対 action は pathname 末尾で判定する */
        var m = /\/(auth|select|start|next|retry|lobby|exit|stop)$/.exec(path);
        handleAction(m ? '/' + m[1] : path, form);
    }, true);
    /* Auth.html は form.submit() を直接呼ぶ（submit イベント非発火）ため、
       prototype 経由で cancelable な submit イベントに変換して上の経路へ流す */
    HTMLFormElement.prototype.submit = function () {
        var ev = new Event('submit', { bubbles: true, cancelable: true });
        this.dispatchEvent(ev);
    };

    /* Processing: 実製品ではサーバの status 変化で自動遷移する箇所を、shim のタイマーで再現 */
    if (PAGE === 'processing') {
        setTimeout(function () { go(S.nextPage || 'lobby.html'); }, PROCESSING_MS);
    }

    /* ---------------- 静的 HTML への状態反映（DOM パッチ） ---------------- */
    function patchNowPlaying() {
        var segs = document.querySelectorAll('.nn-seg');
        for (var i = 0; i < segs.length; i++) { segs[i].textContent = S.current || S.lastPlayed || 'Sample_Deck.pptx'; }
    }
    function patchDialog() {
        var nameEl = document.querySelector('.dlg-name');
        if (nameEl) { nameEl.textContent = S.lastPlayed || ''; }
        var nextBtn = document.querySelector('.pp-next');
        var n = pendingAfterCurrent();
        if (nextBtn) {
            if (n) {
                var d = nextBtn.querySelector('.pp-main-d');
                if (d) { d.textContent = n; }
            } else {
                nextBtn.classList.remove('hold');
                nextBtn.disabled = true;
                nextBtn.removeAttribute('data-hold');
                nextBtn.textContent = 'No slides in queue';
            }
        }
    }
    function patchLobby() {
        var scroll = document.querySelector('.list-scroll');
        if (!scroll) { return; }
        var secs = scroll.querySelectorAll('.sec');
        if (secs.length < 2) { return; }
        var doneSec = secs[1];
        var forms = scroll.querySelectorAll('form.deck-form');
        var idx = 0;
        for (var i = 0; i < forms.length; i++) {
            var form = forms[i];
            var nameEl = form.querySelector('.deck-name');
            var name = nameEl ? nameEl.textContent : '';
            var btn = form.querySelector('button');
            var badge = form.querySelector('.deck-badge');
            if (S.done.indexOf(name) !== -1) {
                if (btn && !btn.classList.contains('finished')) {
                    btn.classList.add('finished');
                    btn.style.setProperty('--chg-edge', '#5af0a0');
                    btn.style.setProperty('--chg-track', 'rgba(52,210,123,.18)');
                    btn.style.setProperty('--chg-glow', 'rgba(52,210,123,.5)');
                    var cue = form.querySelector('.deck-cue');
                    if (cue) { cue.parentNode.removeChild(cue); }
                }
                if (badge) { badge.innerHTML = '&#10003;'; }
                scroll.appendChild(form);          /* DONE セクションの後ろへ移動 */
            } else {
                idx++;
                if (badge) { badge.textContent = String(idx); }
                scroll.insertBefore(form, doneSec); /* STANDBY 側に整列 */
            }
        }
        /* GO ボタンの次デッキ表示 / キュー空なら無効化（ui-console.ps1 と同じ見え方） */
        var pending = [];
        for (var j = 0; j < S.queue.length; j++) {
            if (S.done.indexOf(S.queue[j]) === -1) { pending.push(S.queue[j]); }
        }
        var goMain = document.querySelector('.go-main');
        var goBtn = document.querySelector('.go-btn');
        if (goMain) { goMain.innerHTML = 'Start &middot; ' + (pending.length ? '' : 'None'); }
        if (goMain && pending.length) { goMain.appendChild(document.createTextNode(pending[0])); }
        if (goBtn && !pending.length) { goBtn.disabled = true; goBtn.style.opacity = '0.5'; }
    }

    /* ---------------- デモ操作パネル ---------------- */
    var panel = null;
    function renderPanel() {
        if (!panel) { return; }
        var net = getNet();
        var html = '<div style="font:700 10px/1 system-ui,sans-serif;letter-spacing:.08em;color:#f5a623;margin-bottom:6px;">DEMO CONTROLS</div>';
        html += '<div style="display:flex;gap:4px;margin-bottom:6px;">';
        [['live', 'LIVE'], ['slow', 'SLOW'], ['offline', 'OFFLINE']].forEach(function (p) {
            var on = (net === p[0]);
            html += '<button data-net="' + p[0] + '" style="flex:1;padding:5px 6px;border-radius:5px;border:1px solid ' + (on ? '#f5a623' : '#3a4552') + ';background:' + (on ? '#f5a623' : 'transparent') + ';color:' + (on ? '#1a1a1a' : '#c7d1dc') + ';font:700 10px system-ui,sans-serif;cursor:pointer;">' + p[1] + '</button>';
        });
        html += '</div>';
        if (PAGE === 'auth' || PAGE === 'auth-error') {
            html += '<div style="font:11px system-ui,sans-serif;color:#c7d1dc;margin-bottom:6px;">Demo PIN: <b style="color:#e8edf3;letter-spacing:.15em;">' + DEMO_PIN + '</b><br><span style="color:#8a97a5;">(on stage you read it off the host PC)</span></div>';
        }
        if (PAGE === 'nowplaying') {
            html += '<button data-act="endshow" style="width:100%;margin-bottom:4px;padding:5px;border-radius:5px;border:1px solid #3a4552;background:transparent;color:#c7d1dc;font:11px system-ui,sans-serif;cursor:pointer;">&#127916; End show &rarr; Dialog</button>';
            html += '<button data-act="otherlock" style="width:100%;margin-bottom:4px;padding:5px;border-radius:5px;border:1px solid #3a4552;background:transparent;color:#c7d1dc;font:11px system-ui,sans-serif;cursor:pointer;">&#128274; Other device takes lock</button>';
        }
        html += '<a href="./index.html" style="display:block;text-align:center;font:11px system-ui,sans-serif;color:#8fa3b8;">&#8962; All screens</a>';
        panel.innerHTML = html;
    }
    function buildPanel() {
        var chip = document.createElement('button');
        chip.textContent = 'DEMO';
        chip.title = 'Static mockup — demo controls';
        chip.style.cssText = 'position:fixed;right:10px;bottom:10px;background:#f5a623;color:#1a1a1a;font:700 11px/1 system-ui,sans-serif;padding:6px 9px;border-radius:6px;border:0;z-index:99999;opacity:.9;cursor:pointer;';
        panel = document.createElement('div');
        panel.id = 'mockup-panel';
        panel.style.cssText = 'position:fixed;right:10px;bottom:42px;width:172px;background:rgba(18,22,28,.96);border:1px solid #2a3441;border-radius:10px;padding:10px;z-index:99999;display:none;';
        chip.addEventListener('click', function () {
            panel.style.display = (panel.style.display === 'none') ? 'block' : 'none';
        });
        panel.addEventListener('click', function (e) {
            var t = e.target;
            if (t.dataset && t.dataset.net) { setNet(t.dataset.net); }
            else if (t.dataset && t.dataset.act === 'endshow') { endShow(); }
            else if (t.dataset && t.dataset.act === 'otherlock') { S.lockCid = 'mock-other'; saveState(); }
        });
        document.body.appendChild(chip);
        document.body.appendChild(panel);
        renderPanel();
    }

    document.addEventListener('DOMContentLoaded', function () {
        if (PAGE === 'nowplaying') { patchNowPlaying(); }
        else if (PAGE === 'dialog') { patchDialog(); }
        else if (PAGE === 'lobby') { patchLobby(); }
        buildPanel();
    });
})();
