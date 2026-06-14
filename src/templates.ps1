$script:HtmlTemplates = @{
    # Shared HTML header + CSS + polling script.
    # Format args: {0}=Title, {1}=BgColor (BgColor accepted for compatibility; theme is unified via CSS variables).
    HtmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <title>{0}</title>
    <style>
        :root {{
            --bg:#0b0d10; --bg-2:#121519; --panel:#171b20; --panel-2:#1d2229;
            --line:#262c34; --line-soft:#1f242b;
            --txt:#e9edf2; --txt-dim:#9aa4b0; --txt-faint:#5d6772;
            --go:#34d27b; --go-glow:rgba(52,210,123,.35);
            --standby:#f5a623; --live:#ff4d4f; --accent:#5aa9ff;
            --radius:16px; --radius-sm:11px;
            --ease:cubic-bezier(.16,.84,.44,1);
            --sans:ui-sans-serif,-apple-system,"Segoe UI Variable","Segoe UI","Yu Gothic UI","Meiryo",system-ui,sans-serif;
            --mono:ui-monospace,"Cascadia Code","SF Mono","Consolas","Roboto Mono",monospace;
        }}
        *, *::before, *::after {{ box-sizing:border-box; }}
        html, body {{ height:100%; }}
        body {{
            font-family:var(--sans); color:var(--txt); margin:0;
            background:
                radial-gradient(120% 55% at 50% -10%, #1a2733 0%, transparent 55%),
                radial-gradient(90% 45% at 50% 112%, #14110a 0%, transparent 50%),
                var(--bg);
            height:100vh; height:100dvh; overflow:hidden;
            display:flex; flex-direction:column;
        }}
        body::after {{
            content:""; position:fixed; inset:0; pointer-events:none; z-index:1;
            background:radial-gradient(135% 95% at 50% 50%, transparent 56%, rgba(0,0,0,.55) 100%);
            mix-blend-mode:multiply;
        }}
        /* top bar */
        .topbar {{
            flex:0 0 auto; display:flex; align-items:center; gap:10px;
            padding:13px 18px; border-bottom:1px solid var(--line-soft);
            background:linear-gradient(180deg,rgba(18,21,25,.85),rgba(18,21,25,.25));
            position:relative; z-index:20;
        }}
        .brand {{ display:flex; align-items:center; gap:9px; font-weight:600; font-size:14px; letter-spacing:.2px; }}
        .brand .dot {{
            width:9px; height:9px; border-radius:50%; background:var(--go);
            box-shadow:0 0 0 3px var(--go-glow); animation:breathe 2.6s var(--ease) infinite;
        }}
        .topbar .status {{
            margin-left:auto; font-family:var(--mono); font-size:11px; letter-spacing:1px;
            color:var(--txt-dim); border:1px solid var(--line); background:var(--panel);
            padding:4px 10px; border-radius:999px;
        }}
        /* layout */
        .container {{
            width:100%; max-width:600px; margin:0 auto;
            flex:1; min-height:0; display:flex; flex-direction:column;
            overflow:hidden; position:relative; z-index:10;
        }}
        .stage {{ flex:1; min-height:0; display:flex; flex-direction:column; align-items:center; justify-content:center; text-align:center; padding:26px; }}
        h1 {{ font-size:1.5rem; font-weight:650; margin:0; letter-spacing:.2px; }}
        h2 {{ font-size:1.2rem; font-weight:600; margin:0; }}
        p {{ color:var(--txt-dim); font-size:.92rem; margin:6px 0; line-height:1.55; }}
        .card {{ background:linear-gradient(180deg,var(--panel-2),var(--panel)); border:1px solid var(--line); border-radius:var(--radius); padding:18px; }}
        /* lobby */
        .lobby-head {{ flex:0 0 auto; padding:16px 18px 8px; }}
        .sec-label {{ font-size:1.05rem; font-weight:650; letter-spacing:.2px; }}
        .lobby-hint {{ color:var(--txt-faint); font-size:.82rem; margin:5px 0 0; }}
        .list-scroll {{ flex:1; min-height:0; overflow-y:auto; overflow-x:hidden; padding:8px 18px 4px; text-align:left; }}
        .list-scroll::-webkit-scrollbar {{ width:8px; }}
        .list-scroll::-webkit-scrollbar-thumb {{ background:#2c343d; border-radius:8px; }}
        .sec {{
            display:flex; align-items:center; gap:8px; margin:14px 2px 10px;
            font-family:var(--mono); font-size:10.5px; letter-spacing:1.4px; text-transform:uppercase; color:var(--txt-faint);
        }}
        .sec:first-child {{ margin-top:2px; }}
        .tag {{ padding:2px 7px; border-radius:5px; font-size:10px; font-weight:700; }}
        .tag-standby {{ color:var(--standby); background:rgba(245,166,35,.12); }}
        .tag-done {{ color:var(--go); background:rgba(52,210,123,.12); }}
        .deck-form {{ margin:0; }}
        .deck {{
            width:100%; display:flex; align-items:center; gap:13px; text-align:left;
            padding:13px 14px; margin:0 0 10px; cursor:pointer; color:var(--txt);
            background:linear-gradient(180deg,var(--panel-2),var(--panel));
            border:1px solid var(--line); border-radius:var(--radius);
            transition:.16s var(--ease); position:relative; overflow:hidden; font-family:var(--sans);
        }}
        .deck::before {{ content:""; position:absolute; left:0; top:0; bottom:0; width:3px; background:var(--standby); opacity:0; transition:.16s; }}
        .deck:hover {{ border-color:#34404d; transform:translateY(-1px); }}
        .deck:hover::before {{ opacity:1; }}
        .deck:active {{ transform:scale(.99); }}
        .deck-badge {{
            flex:0 0 auto; width:32px; height:32px; border-radius:9px; display:grid; place-items:center;
            font-family:var(--mono); font-size:13px; background:var(--bg-2); border:1px solid var(--line); color:var(--standby);
        }}
        .deck-name {{ flex:1; min-width:0; font-size:14px; font-weight:550; overflow-wrap:anywhere; }}
        .deck-cue {{ flex:0 0 auto; color:var(--standby); font-size:12px; opacity:.7; }}
        .deck.finished {{ opacity:.6; }}
        .deck.finished:hover {{ transform:none; border-color:var(--line); }}
        .deck.finished:hover::before {{ opacity:0; }}
        .deck.finished .deck-badge {{ color:var(--go); border-color:rgba(52,210,123,.4); }}
        .deck.finished .deck-name {{ text-decoration:line-through; text-decoration-color:var(--txt-faint); }}
        .empty {{ color:var(--txt-faint); font-family:var(--mono); font-size:12.5px; padding:14px 2px; }}
        /* footer + GO */
        .footer {{
            flex:0 0 auto; display:flex; gap:10px; align-items:stretch;
            padding:14px 18px calc(14px + env(safe-area-inset-bottom));
            border-top:1px solid var(--line-soft);
            background:linear-gradient(180deg,rgba(11,13,16,.35),var(--bg));
        }}
        .footer .grow {{ flex:1; margin:0; }}
        .go-btn {{
            width:100%; border:none; border-radius:14px; cursor:pointer; color:#06210f;
            padding:16px; font-family:var(--sans); display:flex; align-items:center; justify-content:center; gap:11px;
            background:linear-gradient(180deg,var(--go),#22b566);
            box-shadow:0 8px 22px var(--go-glow), inset 0 1px 0 rgba(255,255,255,.35);
            transition:.14s var(--ease); position:relative; overflow:hidden;
        }}
        .go-btn:active {{ transform:scale(.985); }}
        .go-btn:disabled {{ filter:grayscale(.6); cursor:not-allowed; box-shadow:none; }}
        .go-kicker {{ font-size:11px; font-weight:800; letter-spacing:2px; background:rgba(0,0,0,.18); padding:4px 9px; border-radius:7px; }}
        .go-main {{ font-size:15px; font-weight:700; letter-spacing:.3px; }}
        .go-btn::after {{ content:""; position:absolute; inset:0; border-radius:inherit; box-shadow:0 0 0 0 var(--go-glow); animation:goPulse 2.6s var(--ease) infinite; }}
        .exit-wrap {{ margin:0; display:flex; }}
        .exit-btn {{
            border:1px solid var(--line); background:var(--panel); color:var(--txt-dim);
            border-radius:14px; padding:0 18px; font-family:var(--sans); font-size:13px; font-weight:600; cursor:pointer;
            transition:.14s var(--ease);
        }}
        .exit-btn:hover {{ color:var(--txt); border-color:#3a4651; }}
        /* now playing */
        .onair {{
            display:inline-flex; align-items:center; gap:9px; font-family:var(--mono);
            font-size:12px; letter-spacing:2.5px; font-weight:600; color:var(--live);
            padding:7px 15px; border-radius:999px; border:1px solid rgba(255,77,79,.4); background:rgba(255,77,79,.08);
        }}
        .onair i {{ width:9px; height:9px; border-radius:50%; background:var(--live); box-shadow:0 0 12px var(--live); }}
        .now-name {{ font-size:1.45rem; font-weight:650; margin:24px 0 6px; line-height:1.35; max-width:92%; overflow-wrap:anywhere; }}
        .now-sub {{ font-family:var(--mono); font-size:12px; color:var(--txt-faint); }}
        .now-timer {{ font-family:var(--mono); font-size:52px; font-weight:300; letter-spacing:2px; margin:26px 0 4px; font-variant-numeric:tabular-nums; color:#cfd6dd; }}
        .now-actions {{ margin:34px 0 0; width:100%; max-width:340px; }}
        .ctl-btn {{
            width:100%; padding:16px; border-radius:14px; cursor:pointer; font-family:var(--sans);
            font-size:15px; font-weight:650; border:1px solid var(--line); background:var(--panel-2); color:var(--txt);
            transition:.14s var(--ease);
        }}
        .ctl-btn:active {{ transform:scale(.98); }}
        .ctl-btn.danger {{ border-color:rgba(255,77,79,.4); color:#ff8d8e; background:rgba(255,77,79,.08); }}
        .ctl-btn.danger:hover {{ background:rgba(255,77,79,.14); }}
        /* dialog (post-presentation) */
        .done-mark {{
            width:64px; height:64px; border-radius:50%; display:grid; place-items:center; margin-bottom:16px;
            color:var(--go); background:rgba(52,210,123,.1); border:1px solid rgba(52,210,123,.4); animation:pop .5s var(--ease);
        }}
        .done-mark svg {{ width:30px; height:30px; }}
        .dlg-title {{ font-size:1.25rem; font-weight:650; }}
        .dlg-name {{ font-family:var(--mono); font-size:12.5px; color:var(--txt-dim); margin-top:8px; overflow-wrap:anywhere; max-width:90%; }}
        .post-stack {{ display:flex; flex-direction:column; gap:11px; width:100%; max-width:340px; margin-top:28px; }}
        .post-stack form {{ margin:0; }}
        .pp-btn {{
            width:100%; padding:15px; border-radius:14px; cursor:pointer; font-family:var(--sans);
            font-size:15px; font-weight:650; border:1px solid var(--line); transition:.14s var(--ease);
        }}
        .pp-btn:active {{ transform:scale(.98); }}
        .pp-next {{ border:none; color:#06210f; background:linear-gradient(180deg,var(--go),#22b566); box-shadow:0 8px 20px var(--go-glow); }}
        .pp-next:disabled {{ filter:grayscale(.6); cursor:not-allowed; box-shadow:none; }}
        .pp-retry {{ background:var(--panel-2); color:var(--standby); border-color:rgba(245,166,35,.3); }}
        .pp-lobby {{ background:var(--panel-2); color:var(--txt); }}
        .pp-exit {{ background:transparent; color:var(--txt-faint); border-color:transparent; }}
        .pp-exit:hover {{ color:var(--txt-dim); }}
        /* processing + exit */
        .loader {{ width:46px; height:46px; border-radius:50%; border:3px solid var(--line); border-top-color:var(--standby); animation:spin 1s linear infinite; margin-bottom:20px; }}
        .end-icon {{ width:64px; height:64px; border-radius:50%; display:grid; place-items:center; margin-bottom:16px; color:var(--go); background:rgba(52,210,123,.1); border:1px solid rgba(52,210,123,.4); }}
        .end-icon svg {{ width:30px; height:30px; }}
        /* offline overlay */
        #offline-overlay {{
            display:none; position:fixed; inset:0; z-index:9999; flex-direction:column;
            justify-content:center; align-items:center; gap:16px; text-align:center; padding:30px;
            background:rgba(8,10,12,.82); backdrop-filter:blur(10px) saturate(.6); color:#fff;
        }}
        #offline-overlay.active {{ display:flex; }}
        .offline-icon {{ width:54px; height:54px; color:var(--standby); animation:pulse 2s infinite; }}
        .offline-icon svg {{ width:54px; height:54px; }}
        /* animations */
        @keyframes spin {{ to {{ transform:rotate(360deg); }} }}
        @keyframes pulse {{ 0%,100% {{ transform:scale(1); opacity:1; }} 50% {{ transform:scale(1.08); opacity:.8; }} }}
        @keyframes breathe {{ 0%,100% {{ opacity:1; }} 50% {{ opacity:.45; }} }}
        @keyframes goPulse {{ 0% {{ box-shadow:0 0 0 0 var(--go-glow); }} 70%,100% {{ box-shadow:0 0 0 13px transparent; }} }}
        @keyframes pop {{ 0% {{ transform:scale(.4); opacity:0; }} 60% {{ transform:scale(1.1); }} 100% {{ transform:scale(1); }} }}
        /* ===== desktop: use the width, deck grid, panel framing ===== */
        @media (min-width: 760px) {{
            .container {{
                max-width: 960px; width: 100%;
                flex: 0 1 auto; margin: auto; height: auto; min-height: 0;
                max-height: min(820px, calc(100dvh - 80px));
                border: 1px solid var(--line); border-radius: 22px;
                background: linear-gradient(180deg, rgba(23,27,32,.55), rgba(18,21,25,.30));
                box-shadow: 0 30px 90px rgba(0,0,0,.5);
            }}
            .lobby-head {{ padding: 22px 26px 4px; }}
            .sec-label {{ font-size: 1.25rem; }}
            .list-scroll {{
                display: grid; grid-template-columns: repeat(2, minmax(0,1fr));
                gap: 12px 14px; align-content: start; padding: 14px 26px 10px;
            }}
            .list-scroll .sec, .list-scroll .empty {{ grid-column: 1 / -1; }}
            .list-scroll .deck {{ margin: 0; height: 100%; }}
            .footer {{ padding: 16px 26px; }}
            .stage {{ min-height: min(460px, calc(100dvh - 120px)); }}
        }}
        @media (min-width: 1200px) {{
            .container {{ max-width: 1180px; max-height: min(860px, calc(100dvh - 80px)); }}
            .list-scroll {{ grid-template-columns: repeat(3, minmax(0,1fr)); }}
        }}
    </style>
    <script>
        window.startPolling = function(expectedStatusArray, redirectUrl, opts) {{
            opts = opts || {{}};
            var overlay = document.getElementById('offline-overlay');
            var defaultDelay = opts.defaultDelay || 1000;
            var maxDelay = opts.maxDelay || 5000;
            var backoffMultiplier = opts.backoffMultiplier || 1.5;
            var maxRetries = opts.maxRetries || 0;
            var maxErrors = opts.maxErrors || 0;
            var statusRedirects = opts.statusRedirects || {{}};
            var currentDelay = defaultDelay;
            var checkCount = 0;
            var errorCount = 0;
            var isPolling = true;

            function pollStatus() {{
                if (!isPolling) return;
                var showOverlayTimer = setTimeout(function() {{
                    if (overlay) overlay.classList.add('active');
                }}, 3000);

                fetch('/status?t=' + Date.now())
                .then(function(r) {{
                    clearTimeout(showOverlayTimer);
                    if (overlay) overlay.classList.remove('active');
                    return r.text();
                }})
                .then(function(status) {{
                    currentDelay = defaultDelay;
                    checkCount++;
                    if (statusRedirects[status]) {{
                        isPolling = false;
                        window.location.href = statusRedirects[status];
                        return;
                    }}
                    if (expectedStatusArray.indexOf(status) === -1) {{
                        isPolling = false;
                        window.location.href = redirectUrl;
                    }} else if (maxRetries > 0 && checkCount > maxRetries) {{
                        window.location.href = redirectUrl;
                    }} else {{
                        setTimeout(pollStatus, currentDelay);
                    }}
                }})
                .catch(function(e) {{
                    clearTimeout(showOverlayTimer);
                    if (overlay) overlay.classList.add('active');
                    currentDelay = Math.min(currentDelay * backoffMultiplier, maxDelay);
                    checkCount++;
                    errorCount++;
                    if ((maxRetries > 0 && checkCount > maxRetries) || (maxErrors > 0 && errorCount > maxErrors)) {{
                        window.location.href = redirectUrl;
                    }} else {{
                        setTimeout(pollStatus, currentDelay);
                    }}
                }});
            }}

            var forms = document.querySelectorAll('form');
            forms.forEach(function(form) {{
                form.addEventListener('submit', function(e) {{
                    if (overlay && overlay.classList.contains('active')) {{
                        e.preventDefault();
                        return;
                    }}
                    isPolling = false;
                }});
            }});

            pollStatus();
        }};
    </script>
</head>
<body>
    <div class="topbar">
        <span class="brand"><span class="dot"></span>ppt-orchestrator</span>
        <span class="status">LIVE</span>
    </div>
    <div id="offline-overlay">
        <div class="offline-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg></div>
        <h2>Connection Lost</h2>
        <p>The connection looks unstable. Reconnecting&hellip;<br>The presentation will not be interrupted.</p>
    </div>
    <div class="container">
"@

    # Now Presenting view (remote control). Injected via .Replace on %%DECK%% (single braces; NOT -f).
    NowPlayingView = @"
    <div class="stage np">
        <div class="onair"><i></i> ON AIR</div>
        <div class="now-name">%%DECK%%</div>
        <div class="now-sub">Remote slide control</div>
        <div class="now-timer" id="elapsed">00:00</div>
        <div class="pos" id="pos">&mdash; / &mdash;</div>

        <div class="lockbar" id="lockbar">
            <div class="lbl" id="lockLbl">REMOTE CONTROL LOCK</div>
            <div class="switch" id="lockSwitch" role="switch" aria-checked="false" tabindex="0"><i></i></div>
        </div>
        <div class="lock-other" id="lockOther" hidden>
            <span>This presentation is being controlled by another device.</span>
            <button class="steal-btn hold" id="stealBtn" type="button" data-hold="1500">
                <svg class="hold-ring" viewBox="0 0 100 100" preserveAspectRatio="none"><rect x="1.5" y="1.5" width="97" height="97" rx="11" pathLength="100"/></svg>
                <span>Hold to take control</span>
            </button>
        </div>

        <div class="slidepad" id="pad">
            <button class="slide-btn nav" data-cmd="prev"  disabled aria-label="Previous">&#9664;</button>
            <button class="slide-btn nav" data-cmd="next"  disabled aria-label="Next">&#9654;</button>
            <button class="slide-btn"     data-cmd="first" disabled>&#9198; First</button>
            <button class="slide-btn"     data-cmd="last"  disabled>Last &#9197;</button>
            <button class="slide-btn blk" data-cmd="blackout" disabled>&#9632; Black</button>
            <button class="slide-btn blk" data-cmd="whiteout" disabled>&#9633; White</button>
        </div>

        <form method="post" action="/stop" class="now-actions" id="stopForm">
            <button class="ctl-btn danger hold" type="button" id="stopBtn" data-hold="1500">
                <svg class="hold-ring" viewBox="0 0 100 100" preserveAspectRatio="none"><rect x="1.5" y="1.5" width="97" height="97" rx="13" pathLength="100"/></svg>
                <span>&#9632; Hold to Stop</span>
            </button>
        </form>
    </div>
    <style>
        .np .pos { font:600 13px var(--mono); color:var(--txt-dim); letter-spacing:2px; margin-top:4px; }
        .lockbar { display:flex; align-items:center; justify-content:space-between; gap:12px; width:100%; max-width:360px; margin:26px 0 0; padding:11px 14px 11px 16px; border:1px solid var(--line); border-radius:13px; background:var(--panel); }
        .lockbar .lbl { font:700 11px/1 var(--mono); letter-spacing:1.6px; color:var(--txt-dim); transition:color .16s; }
        .switch { width:54px; height:30px; border-radius:999px; background:var(--bg-2); border:1px solid var(--line); position:relative; cursor:pointer; transition:.16s var(--ease); flex:0 0 auto; }
        .switch i { position:absolute; top:3px; left:3px; width:22px; height:22px; border-radius:50%; background:var(--txt-faint); transition:.16s var(--ease); }
        .switch.on { background:rgba(90,169,255,.25); border-color:var(--accent); }
        .switch.on i { left:26px; background:var(--accent); box-shadow:0 0 10px var(--accent); }
        .lock-other { display:flex; flex-direction:column; align-items:center; gap:10px; width:100%; max-width:360px; margin:12px 0 0; font:600 12.5px var(--sans); color:var(--standby); line-height:1.4; }
        .steal-btn { position:relative; overflow:hidden; padding:11px 18px; border-radius:11px; border:1px solid rgba(245,166,35,.4); background:rgba(245,166,35,.08); color:var(--standby); font:650 13px var(--sans); cursor:pointer; }
        .slidepad { display:grid; grid-template-columns:1fr 1fr; gap:10px; width:100%; max-width:360px; margin:22px 0 0; }
        .slide-btn { padding:15px; border-radius:12px; border:1px solid var(--line); background:var(--panel-2); color:var(--txt); font:650 14px var(--sans); cursor:pointer; transition:.12s var(--ease); display:flex; align-items:center; justify-content:center; gap:8px; -webkit-user-select:none; user-select:none; -webkit-tap-highlight-color:transparent; }
        .slide-btn.nav { font-size:22px; padding:20px; }
        .slide-btn.blk { color:var(--txt-dim); }
        .slide-btn:active:not(:disabled) { transform:scale(.96); }
        .slide-btn:disabled { opacity:.35; cursor:not-allowed; }
        .slide-btn.act { border-color:var(--accent); color:var(--accent); background:rgba(90,169,255,.10); }
        .container.armed { animation:armPulse 1.7s ease-in-out infinite; }
        @keyframes armPulse { 0%,100% { box-shadow:0 0 0 1.5px rgba(90,169,255,.55), 0 0 26px -2px var(--accent); } 50% { box-shadow:0 0 0 1.5px rgba(90,169,255,.9), 0 0 50px 2px var(--accent); } }
        .hold { position:relative; overflow:hidden; }
        .hold .hold-ring { position:absolute; inset:0; width:100%; height:100%; pointer-events:none; opacity:0; transition:opacity .12s; }
        .hold.charging .hold-ring { opacity:1; }
        .hold .hold-ring rect { fill:none; stroke:#ff6b6d; stroke-width:3; stroke-dasharray:100; stroke-dashoffset:100; }
        .steal-btn .hold-ring rect { stroke:var(--standby); }
    </style>
    <script>
    (function() {
        var cid = sessionStorage.getItem('ppt_cid');
        if (!cid) {
            cid = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : (Date.now() + '' + Math.random()).replace(/\D/g,'').slice(0,18);
            sessionStorage.setItem('ppt_cid', cid);
        }

        var el        = document.getElementById('elapsed');
        var posEl     = document.getElementById('pos');
        var dot       = document.querySelector('.onair i');
        var pad       = document.getElementById('pad');
        var btns      = pad.querySelectorAll('.slide-btn');
        var lockSw    = document.getElementById('lockSwitch');
        var lockLbl   = document.getElementById('lockLbl');
        var lockOther = document.getElementById('lockOther');
        var stealBtn  = document.getElementById('stealBtn');
        var stopBtn   = document.getElementById('stopBtn');
        var stopForm  = document.getElementById('stopForm');
        var container = document.querySelector('.container');
        var blkBtn    = pad.querySelector('[data-cmd="blackout"]');
        var whtBtn    = pad.querySelector('[data-cmd="whiteout"]');

        var baseMs = 0, baseAt = performance.now(), seeded = false, lastT = '';
        var armed = false, lockOn = false;

        function post(url) {
            return fetch(url, { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:'cid=' + encodeURIComponent(cid) })
                   .then(function(r){ return r.json(); });
        }
        function buzz(p) { if (navigator.vibrate) { try { navigator.vibrate(p); } catch(e){} } }

        function paint() {
            var total = baseMs + (performance.now() - baseAt);
            if (total < 0) total = 0;
            var s = Math.floor(total / 1000);
            var m = String(Math.floor(s / 60)).padStart(2, '0');
            var x = String(s % 60).padStart(2, '0');
            var t = m + ':' + x;
            if (el && t !== lastT) { el.textContent = t; lastT = t; }
            if (dot) { dot.style.opacity = (total % 1000) < 500 ? '1' : '0.25'; }
            requestAnimationFrame(paint);
        }

        function setArmed(on) {
            armed = on;
            for (var i = 0; i < btns.length; i++) { btns[i].disabled = !on; }
            if (container) container.classList.toggle('armed', on);
        }
        function setProj(black, white) {
            if (blkBtn) blkBtn.classList.toggle('act', !!black);
            if (whtBtn) whtBtn.classList.toggle('act', !!white);
        }
        function renderLock(st) {
            lockOn = !!st.lock;
            var mine = !!st.mine;
            lockSw.classList.toggle('on', mine);
            lockSw.setAttribute('aria-checked', mine ? 'true' : 'false');
            if (mine) {
                lockLbl.textContent = 'YOU HAVE CONTROL';
                lockLbl.style.color = 'var(--accent)';
                lockOther.hidden = true;
                setArmed(true);
            } else if (lockOn) {
                lockLbl.textContent = 'LOCKED BY ANOTHER';
                lockLbl.style.color = 'var(--standby)';
                lockOther.hidden = false;
                setArmed(false);
            } else {
                lockLbl.textContent = 'REMOTE CONTROL LOCK';
                lockLbl.style.color = '';
                lockOther.hidden = true;
                setArmed(false);
            }
            setProj(st.black, st.white);
        }

        function pollState() {
            fetch('/slide/state?cid=' + encodeURIComponent(cid) + '&t=' + Date.now())
            .then(function(r){ return r.json(); })
            .then(function(st){
                var predicted = baseMs + (performance.now() - baseAt);
                if (!seeded || Math.abs(st.ms - predicted) > 1000) { baseMs = st.ms; baseAt = performance.now(); seeded = true; }
                if (st.total > 0 && posEl) { posEl.textContent = st.pos + ' / ' + st.total; }
                renderLock(st);
            })
            .catch(function(){});
        }

        function sendSlide(cmd) {
            if (!armed) return;
            buzz(12);
            post('/slide/' + cmd).then(function(res){
                if (!res) return;
                if (res.locked) { setArmed(false); pollState(); return; }
                if (res.total > 0 && posEl) { posEl.textContent = res.pos + ' / ' + res.total; }
                setProj(res.black, res.white);
            });
        }
        for (var i = 0; i < btns.length; i++) {
            (function(b){ b.addEventListener('click', function(){ sendSlide(b.getAttribute('data-cmd')); }); })(btns[i]);
        }

        document.addEventListener('keydown', function(e){
            if (!armed) return;
            var k = e.key;
            if (k === 'ArrowRight' || k === 'PageDown' || k === ' ' || k === 'Spacebar') { e.preventDefault(); sendSlide('next'); }
            else if (k === 'ArrowLeft' || k === 'PageUp') { e.preventDefault(); sendSlide('prev'); }
            else if (k === 'Home') { e.preventDefault(); sendSlide('first'); }
            else if (k === 'End')  { e.preventDefault(); sendSlide('last'); }
            else if (k === 'b' || k === 'B') { sendSlide('blackout'); }
            else if (k === 'w' || k === 'W') { sendSlide('whiteout'); }
        });

        function toggleLock() {
            if (armed) { post('/lock/off').then(pollState); }
            else if (!lockOn) { post('/lock/on').then(function(){ pollState(); }); }
            else { pollState(); }
        }
        lockSw.addEventListener('click', toggleLock);
        lockSw.addEventListener('keydown', function(e){ if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggleLock(); } });

        function bindHold(btn, onComplete) {
            var dur = parseInt(btn.getAttribute('data-hold'), 10) || 1500;
            var ring = btn.querySelector('.hold-ring rect');
            var raf = null, t0 = 0;
            function frame(now) {
                var p = Math.min((now - t0) / dur, 1);
                if (ring) ring.style.strokeDashoffset = String(100 - p * 100);
                if (p >= 1) { stop(true); onComplete(); return; }
                raf = requestAnimationFrame(frame);
            }
            function start(e) { if (btn.disabled) return; e.preventDefault(); btn.classList.add('charging'); t0 = performance.now(); raf = requestAnimationFrame(frame); buzz(10); }
            function stop(done) { if (raf) { cancelAnimationFrame(raf); raf = null; } btn.classList.remove('charging'); if (ring) ring.style.strokeDashoffset = '100'; if (done) buzz([20,40,20]); }
            btn.addEventListener('pointerdown', start);
            btn.addEventListener('pointerup', function(){ stop(false); });
            btn.addEventListener('pointerleave', function(){ stop(false); });
            btn.addEventListener('pointercancel', function(){ stop(false); });
        }
        bindHold(stopBtn, function(){ if (stopForm.requestSubmit) stopForm.requestSubmit(); else stopForm.submit(); });
        if (stealBtn) bindHold(stealBtn, function(){ post('/lock/steal').then(pollState); });

        var wl = null;
        function reqWake() {
            if (document.visibilityState === 'visible' && 'wakeLock' in navigator) {
                navigator.wakeLock.request('screen').then(function(s){ wl = s; }).catch(function(){});
            }
        }
        reqWake();
        document.addEventListener('visibilitychange', function(){ if (document.visibilityState === 'visible') { reqWake(); pollState(); } });

        requestAnimationFrame(paint);
        pollState();
        setInterval(pollState, 1200);
        window.startPolling(['running'], '/');
    })();
    </script>
</div></body></html>
"@

    # Lobby view (deck queue). Format args: {0}=startBtnAttrs, {1}=nextFileName, {2}=listHtml
    LobbyView = @"
        <div class="lobby-head">
            <div class="sec-label">Select a deck</div>
            <p class="lobby-hint">Tap a deck to queue it, or hit GO to start the next one.</p>
        </div>
        {2}
        <div class="footer">
            <form method="post" action="/start" class="grow" id="goForm">
                <button class="go-btn hold" type="button" {0} data-hold="1500" data-submit="goForm">
                    <svg class="hold-ring" viewBox="0 0 100 100" preserveAspectRatio="none"><rect x="1.5" y="1.5" width="97" height="97" rx="13" pathLength="100"/></svg>
                    <span class="go-kicker">GO</span><span class="go-main">Hold &middot; {1}</span>
                </button>
            </form>
            <form method="post" action="/exit" class="exit-wrap" onsubmit="return confirm('Shut down the system?\nThe presentation running on the PC will also be closed.');">
                <button class="exit-btn" type="submit" title="Exit System">Exit</button>
            </form>
        </div>
"@

    # Post-presentation dialog. Format args: {0}=CurrentFileName, {1}=nextBtnAttrs, {2}=nextBtnLabel
    DialogView = @"
        <div class="stage">
            <div class="done-mark"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg></div>
            <h2 class="dlg-title">Presentation ended</h2>
            <div class="dlg-name">{0}</div>
            <div class="post-stack">
                <form method="post" action="/next"><button class="pp-btn pp-next" {1} type="submit">{2}</button></form>
                <form method="post" action="/retry"><button class="pp-btn pp-retry" type="submit">&#8635; Play Again</button></form>
                <form method="post" action="/lobby"><button class="pp-btn pp-lobby" type="submit">Back to List</button></form>
                <form method="post" action="/exit" onsubmit="return confirm('Shut down the system?\nThe presentation running on the PC will also be closed.');"><button class="pp-btn pp-exit" type="submit">Exit System</button></form>
            </div>
        </div>
"@

    # Polling script for Lobby / Dialog (concatenated directly: single braces).
    # Generic hold-to-charge binder for [data-hold] buttons (concatenated: single braces).
    # data-hold = ms to charge; data-submit = form id to requestSubmit on completion (else closest form).
    HoldToConfirmScript = @"
    <style>
        .hold { position:relative; overflow:hidden; }
        .hold .hold-ring { position:absolute; inset:0; width:100%; height:100%; pointer-events:none; opacity:0; transition:opacity .12s; }
        .hold.charging .hold-ring { opacity:1; }
        .hold .hold-ring rect { fill:none; stroke:rgba(255,255,255,.9); stroke-width:3; stroke-dasharray:100; stroke-dashoffset:100; }
    </style>
    <script>
    (function(){
        function buzz(p){ if (navigator.vibrate) { try { navigator.vibrate(p); } catch(e){} } }
        function bind(btn){
            var dur = parseInt(btn.getAttribute('data-hold'), 10) || 1500;
            var formId = btn.getAttribute('data-submit');
            var ring = btn.querySelector('.hold-ring rect');
            var raf = null, t0 = 0;
            function frame(now){
                var p = Math.min((now - t0) / dur, 1);
                if (ring) ring.style.strokeDashoffset = String(100 - p * 100);
                if (p >= 1) { stop(true); fire(); return; }
                raf = requestAnimationFrame(frame);
            }
            function start(e){ if (btn.disabled) return; e.preventDefault(); btn.classList.add('charging'); t0 = performance.now(); raf = requestAnimationFrame(frame); buzz(10); }
            function stop(done){ if (raf) { cancelAnimationFrame(raf); raf = null; } btn.classList.remove('charging'); if (ring) ring.style.strokeDashoffset = '100'; if (done) buzz([20,40,20]); }
            function fire(){ var f = formId ? document.getElementById(formId) : btn.closest('form'); if (f) { if (f.requestSubmit) f.requestSubmit(); else f.submit(); } }
            btn.addEventListener('pointerdown', start);
            btn.addEventListener('pointerup', function(){ stop(false); });
            btn.addEventListener('pointerleave', function(){ stop(false); });
            btn.addEventListener('pointercancel', function(){ stop(false); });
        }
        var list = document.querySelectorAll('[data-hold]');
        for (var i = 0; i < list.length; i++) { bind(list[i]); }
    })();
    </script>
"@

    PollingScript = @"
    <script>
        window.startPolling(['waiting'], '/', { defaultDelay: 300, statusRedirects: { 'stopping': '/exit' } });
    </script>
"@

    # Processing view (concatenated directly: single braces).
    ProcessingView = @"
    <div class="stage">
        <div class="loader"></div>
        <h2 class="dlg-title">Processing&hellip;</h2>
        <p class="lobby-hint">The screen will refresh automatically.</p>
    </div>
    <script>
        window.startPolling(['changing', 'starting'], '/', { defaultDelay: 500, maxRetries: 60, maxErrors: 40 });
    </script>
</div></body></html>
"@

    # Exit view (concatenated directly: single braces).
    ExitView = @"
    <div class="stage">
        <div class="end-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg></div>
        <h1 class="dlg-title">System Shutdown</h1>
        <p class="now-sub">You can safely close this tab or window.</p>
        <p class="lobby-hint" style="margin-top:12px;">Shutting down safely&hellip;</p>
    </div>
</div></body></html>
"@

    # PIN authentication view. Format args: {0}=BgColor (compat), {1}=ErrorFlag ("error" or "")
    AuthView = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <title>Authentication Required</title>
    <style>
        :root {{
            --bg:#0b0d10; --panel:#171b20; --panel-2:#1d2229; --line:#262c34;
            --txt:#e9edf2; --txt-dim:#9aa4b0; --txt-faint:#5d6772;
            --standby:#f5a623; --live:#ff4d4f;
            --ease:cubic-bezier(.16,.84,.44,1);
            --sans:ui-sans-serif,-apple-system,"Segoe UI Variable","Segoe UI","Yu Gothic UI","Meiryo",system-ui,sans-serif;
            --mono:ui-monospace,"Cascadia Code","SF Mono","Consolas","Roboto Mono",monospace;
        }}
        * {{ margin:0; padding:0; box-sizing:border-box; }}
        body {{
            font-family:var(--sans); color:var(--txt);
            background:
                radial-gradient(120% 55% at 50% -10%, #1a2733 0%, transparent 55%),
                radial-gradient(90% 45% at 50% 112%, #1d160a 0%, transparent 50%),
                var(--bg);
            min-height:100vh; min-height:100dvh;
            display:flex; align-items:center; justify-content:center; padding:24px;
            position:relative; overflow:hidden;
        }}
        body::after {{
            content:""; position:fixed; inset:0; pointer-events:none;
            background:radial-gradient(135% 95% at 50% 50%, transparent 56%, rgba(0,0,0,.55) 100%);
            mix-blend-mode:multiply;
        }}
        .auth-container {{
            position:relative; z-index:10; width:100%; max-width:380px; text-align:center;
            background:linear-gradient(180deg,var(--panel-2),var(--panel));
            border:1px solid var(--line); border-radius:22px; padding:42px 30px 34px;
            box-shadow:0 24px 60px rgba(0,0,0,.5);
        }}
        .lock-shield {{
            width:62px; height:62px; border-radius:18px; display:grid; place-items:center; margin:0 auto 20px;
            color:var(--standby); background:linear-gradient(160deg,#23282f,#171b20);
            border:1px solid var(--line); box-shadow:0 10px 26px rgba(0,0,0,.4);
        }}
        .lock-shield svg {{ width:28px; height:28px; }}
        h1 {{ font-size:1.35rem; font-weight:650; margin-bottom:8px; }}
        .subtitle {{ color:var(--txt-dim); font-size:.88rem; margin-bottom:24px; line-height:1.5; }}
        .pin-dots {{ display:flex; justify-content:center; gap:12px; margin-bottom:12px; }}
        .pin-dots.shake {{ animation:shake .5s; }}
        .pin-dots i {{
            display:block; width:16px; height:16px; border-radius:50%;
            border:2px solid var(--line); background:transparent;
            transition:.18s var(--ease);
        }}
        .pin-dots i.full {{
            background:var(--standby); border-color:var(--standby);
            box-shadow:0 0 8px rgba(245,166,35,.55);
        }}
        @keyframes shake {{
            0%,100% {{ transform:translateX(0); }}
            10%,30%,50%,70%,90% {{ transform:translateX(-7px); }}
            20%,40%,60%,80% {{ transform:translateX(7px); }}
        }}
        .error-msg {{ color:var(--live); font-size:.85rem; margin:0 0 16px; opacity:0; transition:opacity .3s; }}
        .error-msg.show {{ opacity:1; }}
        .keypad {{ display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin-bottom:18px; }}
        .key {{
            padding:16px 0; font-family:var(--mono); font-size:1.3rem; font-weight:600;
            border:1px solid var(--line); border-radius:13px;
            background:linear-gradient(180deg,var(--panel-2),var(--panel));
            color:var(--txt); cursor:pointer; transition:.12s var(--ease);
        }}
        .key:active {{ transform:scale(.93); background:var(--panel-2); }}
        .key:focus-visible {{ outline:2px solid var(--standby); outline-offset:2px; }}
        .key.ghost {{ color:var(--txt-dim); border-color:transparent; background:transparent; font-size:1.1rem; }}
        .key.ghost:active {{ background:var(--panel-2); border-color:var(--line); }}
        .btn-submit {{
            width:100%; padding:16px; font-family:var(--sans); font-size:1rem; font-weight:700; letter-spacing:.4px;
            border:none; border-radius:14px; cursor:pointer; color:#1c1304;
            background:linear-gradient(180deg,var(--standby),#e0921a);
            box-shadow:0 8px 22px rgba(245,166,35,.28), inset 0 1px 0 rgba(255,255,255,.3);
            transition:.16s var(--ease);
        }}
        .btn-submit:hover {{ filter:brightness(1.05); }}
        .btn-submit:active {{ transform:scale(.985); }}
        .btn-submit:disabled {{ filter:grayscale(.5); opacity:.5; cursor:not-allowed; box-shadow:none; }}
    </style>
</head>
<body>
    <div class="auth-container">
        <div class="lock-shield">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>
        </div>
        <h1>Enter PIN Code</h1>
        <p class="subtitle">Check the host PC console for the 6-digit PIN.</p>

        <form method="post" action="/auth" id="authForm">
            <div class="pin-dots {1}" id="pinDots">
                <i></i><i></i><i></i><i></i><i></i><i></i>
            </div>
            <div class="error-msg {1}" id="errorMsg">Invalid PIN. Please try again.</div>
            <input type="hidden" name="pin" id="pinValue">
            <div class="keypad">
                <button type="button" class="key" aria-label="1" onclick="pressKey('1')">1</button>
                <button type="button" class="key" aria-label="2" onclick="pressKey('2')">2</button>
                <button type="button" class="key" aria-label="3" onclick="pressKey('3')">3</button>
                <button type="button" class="key" aria-label="4" onclick="pressKey('4')">4</button>
                <button type="button" class="key" aria-label="5" onclick="pressKey('5')">5</button>
                <button type="button" class="key" aria-label="6" onclick="pressKey('6')">6</button>
                <button type="button" class="key" aria-label="7" onclick="pressKey('7')">7</button>
                <button type="button" class="key" aria-label="8" onclick="pressKey('8')">8</button>
                <button type="button" class="key" aria-label="9" onclick="pressKey('9')">9</button>
                <div class="key ghost" aria-hidden="true"></div>
                <button type="button" class="key" aria-label="0" onclick="pressKey('0')">0</button>
                <button type="button" class="key ghost" aria-label="Delete" onclick="deleteKey()">&#9003;</button>
            </div>
            <button type="submit" class="btn-submit" id="submitBtn" disabled>Unlock</button>
        </form>
    </div>

    <script>
        var pin = '';
        var pinDots = document.getElementById('pinDots');
        var submitBtn = document.getElementById('submitBtn');
        var pinValue = document.getElementById('pinValue');
        var form = document.getElementById('authForm');
        var errorMsg = document.getElementById('errorMsg');
        var dots = pinDots.querySelectorAll('i');

        var hasError = '{1}' === 'error';
        if (hasError) {{
            errorMsg.classList.add('show');
            pinDots.classList.add('shake');
            setTimeout(function() {{ pinDots.classList.remove('shake'); }}, 500);
        }}

        function updateDots() {{
            for (var i = 0; i < dots.length; i++) {{
                if (i < pin.length) {{
                    dots[i].classList.add('full');
                }} else {{
                    dots[i].classList.remove('full');
                }}
            }}
            submitBtn.disabled = pin.length < 6;
        }}

        function pressKey(digit) {{
            if (pin.length >= 6) return;
            pin += digit;
            updateDots();
            if (pin.length === 6) {{
                pinValue.value = pin;
                form.submit();
            }}
        }}

        function deleteKey() {{
            if (pin.length === 0) return;
            pin = pin.slice(0, -1);
            updateDots();
        }}

        document.addEventListener('keydown', function(e) {{
            if (e.key >= '0' && e.key <= '9') {{
                pressKey(e.key);
            }} else if (e.key === 'Backspace') {{
                deleteKey();
            }} else if (e.key === 'Enter' && pin.length === 6) {{
                pinValue.value = pin;
                form.submit();
            }}
        }});

        document.addEventListener('paste', function(e) {{
            e.preventDefault();
            var pasted = (e.clipboardData || window.clipboardData).getData('text').replace(/[^0-9]/g, '').substring(0, 6);
            pin = pasted;
            updateDots();
            if (pin.length === 6) {{
                pinValue.value = pin;
                form.submit();
            }}
        }});

        form.addEventListener('submit', function() {{
            pinValue.value = pin;
        }});
    </script>
</body>
</html>
"@
}
