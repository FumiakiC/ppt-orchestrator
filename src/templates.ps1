$script:HtmlTemplates = @{
    # 共通HTMLヘッダー + CSS (パラメータ: {0}=Title, {1}=BgColor)
    HtmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <title>{0}</title>
    <style>
        *, *::before, *::after {{ box-sizing: border-box; }}
        body {{
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: #000000;
            color: #ffffff;
            text-align: center;
            padding: 20px;
            margin: 0;
            position: relative;
            overflow-x: hidden;
            height: 100vh;
            height: 100dvh;
            overflow: hidden;
            display: flex;
            flex-direction: column;
        }}
        .container {{
            max-width: 600px;
            width: 100%;
            min-width: 0;
            margin: 0 auto;
            position: relative;
            z-index: 10;
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
            height: 100%;
        }}
        .card {{
            background: #1e1e1e;
            border: 1px solid #333333;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
        }}
        h2 {{ color: #ffffff; margin: 0 0 5px 0; font-size: 1.3rem; }}
        p {{ color: #dcdcdc; font-size: 0.9rem; margin: 5px 0; }}
        .btn {{
            display: block;
            width: 100%;
            padding: 16px;
            margin: 10px 0;
            font-size: 1.1rem;
            border: none;
            border-radius: 12px;
            cursor: pointer;
            color: #ffffff;
            font-weight: bold;
            transition: filter 0.2s ease;
        }}
        .btn:hover {{ filter: brightness(1.15); }}
        .btn-start {{ background: #0d6efd; color: #ffffff; font-size: 1.2rem; padding: 20px; }}
        .btn-stop  {{ background: #dc3545; color: #ffffff; font-size: 1.2rem; padding: 20px; }}
        .btn-next  {{ background: #198754; color: #ffffff; padding: 20px; font-size: 1.2rem; }}
        .btn-retry {{ background: #ffc107; color: #000000; }}
        .btn-list  {{ background: #0dcaf0; color: #000000; }}
        .btn-exit  {{ background: #495057; color: #ffffff; opacity: 0.95; margin-top: 20px; margin-bottom: 50px; }}
        .btn-file {{ background: #2b2b2b; text-align: left; padding: 12px 15px; font-size: 1rem; margin: 5px 0; border-left: 5px solid #0d6efd; color: #ffffff; }}
        .btn-finished {{ background: #121212; border-left: 5px solid #495057; color: #6c757d; }}
        .list-container {{
            text-align: left;
            margin-top: 20px;
            flex-grow: 1;
            overflow-y: auto;
            overflow-x: hidden;
            word-wrap: break-word;
            overflow-wrap: break-word;
            white-space: normal;
        }}
        .list-container::-webkit-scrollbar {{ width: 10px; }}
        .list-container::-webkit-scrollbar-track {{ background: #111111; border-radius: 8px; }}
        .list-container::-webkit-scrollbar-thumb {{ background: #343a40; border-radius: 8px; }}
        .list-container::-webkit-scrollbar-thumb:hover {{ background: #495057; }}
        .loader {{ border: 5px solid #333; border-top: 5px solid #00d2ff; border-radius: 50%; width: 40px; height: 40px; animation: spin 1s linear infinite; margin: 20px auto; }}
        .playing-icon {{
            font-size: 3rem;
            margin: 10px;
            animation: pulse 2s infinite;
            color: #198754;
        }}
        .end-icon {{
            font-size: 4rem;
            margin: 20px 0;
            color: #dc3545;
        }}
        #offline-overlay {{ display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.85); z-index: 9999; flex-direction: column; justify-content: center; align-items: center; color: #fff; backdrop-filter: blur(5px); }}
        #offline-overlay.active {{ display: flex; }}
        .offline-icon {{ font-size: 4rem; margin-bottom: 10px; color: #dc3545; animation: pulse 2s infinite; }}
        @keyframes spin {{ 0% {{ transform: rotate(0deg); }} 100% {{ transform: rotate(360deg); }} }}
        @keyframes pulse {{ 0% {{ transform: scale(1); opacity: 1; }} 50% {{ transform: scale(1.1); opacity: 0.8; }} 100% {{ transform: scale(1); opacity: 1; }} }}
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
    <div id="offline-overlay">
        <div class="offline-icon">⚠️</div>
        <h2>Connection Lost</h2>
        <p>Connection unstable.<br>Attempting to reconnect...</p>
    </div>
    <div class="container">
"@

    # プレゼンテーション実行中画面 (パラメータ: {0}=FileName)
    NowPlayingView = @"
    <div class="card" style="border: 1px solid #28a745;">
        <div class="playing-icon">▶</div>
        <h2>Now Presenting</h2>
        <p style="font-weight:bold; color:#fff;">{0}</p>
        <p>Controlling slides on PC...</p>
    </div>
    <form method="post" action="/stop">
        <button class="btn btn-stop">■ Stop Presentation</button>
    </form>

    <script>
        window.startPolling(['running'], '/', {{ defaultDelay: 1500 }});
    </script>
</div></body></html>
"@

    # Lobby画面（スライド一覧） (パラメータ: {0}=stBtn, {1}=nextTxt, {2}=listHtml)
    LobbyView = @"
        <div class="card"><h2>Select Slide</h2><p>Select from list or press Start</p></div>
        <form method="post" action="/start"><button class="btn btn-start" {0}>Start: {1}</button></form>
        {2}
        <form method="post" action="/exit" onsubmit="return confirm('本当にシステムを終了しますか？\n（PC上のプレゼンテーションも強制終了されます）');"><button class="btn btn-exit">Exit System</button></form>
"@

    # プレゼンテーション終了後のダイアログ画面 (パラメータ: {0}=CurrentFileName, {1}=nxtSt, {2}=nxtLbl)
    DialogView = @"
        <div class="card"><h2>Presentation Ended</h2><p>{0}</p></div>
        <form method="post" action="/next"><button class="btn btn-next" {1}>{2}</button></form>
        <form method="post" action="/retry"><button class="btn btn-retry">Play Again</button></form>
        <form method="post" action="/lobby"><button class="btn btn-list">Back to List</button></form>
        <form method="post" action="/exit" onsubmit="return confirm('本当にシステムを終了しますか？\n（PC上のプレゼンテーションも強制終了されます）');"><button class="btn btn-exit">Exit System</button></form>
"@

    # ポーリングスクリプト（Lobby/Dialog用）
    PollingScript = @"
    <script>
        window.startPolling(['waiting'], '/', { defaultDelay: 300, statusRedirects: { 'stopping': '/exit' } });
    </script>
"@

    # 処理中画面
    ProcessingView = @"
    <div style="margin-top:50px;"><div class="loader"></div><h2>Processing...</h2><p>Screen will refresh</p></div>
    <script>
        window.startPolling(['changing', 'starting'], '/', { defaultDelay: 500, maxRetries: 60, maxErrors: 40 });
    </script>
</body></html>
"@

    # 終了画面
    ExitView = @"
    <div style="margin-top:50px;">
        <div class="end-icon">✔</div>
        <h1>System Shutdown</h1>
        <p style="font-size:1.2rem; color:#fff;">Please close this tab<br>or window.</p>
        <p style="color:#666; margin-top:20px;">System is shutting down safely...</p>
    </div>
</body></html>
"@

    # PIN認証画面 (パラメータ: {0}=BgColor, {1}=ErrorFlag "error" or "")
    AuthView = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <title>Authentication Required</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #000000;
            min-height: 100vh;
            min-height: 100dvh;
            display: flex;
            align-items: center;
            justify-content: center;
            position: relative;
            overflow: hidden;
        }}
        .auth-container {{
            position: relative;
            z-index: 10;
            background: #1e1e1e;
            border: 1px solid #333333;
            border-radius: 12px;
            padding: 50px 40px;
            max-width: 450px;
            width: 90%;
            text-align: center;
        }}
        .lock-icon {{
            font-size: 4rem;
            margin-bottom: 20px;
            color: #0d6efd;
        }}
        h1 {{
            color: #fff;
            font-size: 1.8rem;
            margin-bottom: 10px;
            font-weight: 600;
        }}
        .subtitle {{
            color: #aaa;
            font-size: 0.95rem;
            margin-bottom: 40px;
        }}
        .pin-inputs {{
            display: flex;
            justify-content: center;
            gap: 10px;
            margin-bottom: 30px;
            width: 100%;
        }}
        .pin-inputs.shake {{
            animation: shake 0.5s;
        }}
        @keyframes shake {{
            0%, 100% {{ transform: translateX(0); }}
            10%, 30%, 50%, 70%, 90% {{ transform: translateX(-8px); }}
            20%, 40%, 60%, 80% {{ transform: translateX(8px); }}
        }}
        .pin-box {{
            flex: 1 1 0;
            min-width: 0;
            max-width: 55px;
            height: 65px;
            font-size: 2rem;
            text-align: center;
            border: 2px solid #444;
            border-radius: 12px;
            background: #2b2b2b;
            color: #fff;
            outline: none;
            transition: all 0.3s;
            caret-color: #0d6efd;
        }}
        .pin-box:focus {{
            border-color: #0d6efd;
            background: #2b2b2b;
        }}
        .pin-box.error {{
            border-color: #dc3545;
            background: rgba(220, 53, 69, 0.1);
        }}
        .error-msg {{
            color: #dc3545;
            font-size: 0.9rem;
            margin-top: -20px;
            margin-bottom: 20px;
            opacity: 0;
            transition: opacity 0.3s;
        }}
        .error-msg.show {{
            opacity: 1;
        }}
        .btn-submit {{
            width: 100%;
            padding: 18px;
            font-size: 1.1rem;
            font-weight: 600;
            border: none;
            border-radius: 12px;
            background: #0d6efd;
            color: #ffffff;
            cursor: pointer;
            transition: filter 0.2s ease;
        }}
        .btn-submit:hover {{
            filter: brightness(1.15);
        }}
        .btn-submit:active {{
            filter: brightness(1.0);
        }}
        .btn-submit:disabled {{
            opacity: 0.5;
            cursor: not-allowed;
        }}
    </style>
</head>
<body>
    <div class="auth-container">
        <div class="lock-icon">🔒</div>
        <h1>Enter PIN Code</h1>
        <p class="subtitle">Please check your PC console for 6-digit PIN</p>

        <form method="post" action="/auth" id="authForm">
            <div class="pin-inputs {1}" id="pinInputs">
                <input type="text" class="pin-box {1}" maxlength="1" inputmode="numeric" pattern="[0-9]" autocomplete="off" id="pin1">
                <input type="text" class="pin-box {1}" maxlength="1" inputmode="numeric" pattern="[0-9]" autocomplete="off" id="pin2">
                <input type="text" class="pin-box {1}" maxlength="1" inputmode="numeric" pattern="[0-9]" autocomplete="off" id="pin3">
                <input type="text" class="pin-box {1}" maxlength="1" inputmode="numeric" pattern="[0-9]" autocomplete="off" id="pin4">
                <input type="text" class="pin-box {1}" maxlength="1" inputmode="numeric" pattern="[0-9]" autocomplete="off" id="pin5">
                <input type="text" class="pin-box {1}" maxlength="1" inputmode="numeric" pattern="[0-9]" autocomplete="off" id="pin6">
            </div>
            <div class="error-msg {1}" id="errorMsg">❌ Invalid PIN. Please try again.</div>
            <input type="hidden" name="pin" id="pinValue">
            <button type="submit" class="btn-submit" id="submitBtn" disabled>Unlock</button>
        </form>
    </div>

    <script>
        var boxes = [document.getElementById('pin1'), document.getElementById('pin2'), document.getElementById('pin3'),
                     document.getElementById('pin4'), document.getElementById('pin5'), document.getElementById('pin6')];
        var submitBtn = document.getElementById('submitBtn');
        var pinValue = document.getElementById('pinValue');
        var form = document.getElementById('authForm');
        var errorMsg = document.getElementById('errorMsg');
        var pinInputsDiv = document.getElementById('pinInputs');

        // エラー状態の場合は表示
        var hasError = '{1}' === 'error';
        if (hasError) {{
            errorMsg.classList.add('show');
        }}

        boxes.forEach(function(box, index) {{
            // 数字のみ入力可能
            box.addEventListener('input', function(e) {{
                var val = e.target.value;
                if (!/^[0-9]$/.test(val)) {{
                    e.target.value = '';
                    return;
                }}

                // エラー状態をクリア
                box.classList.remove('error');
                errorMsg.classList.remove('show');
                pinInputsDiv.classList.remove('shake');

                // 次のボックスにフォーカス
                if (val && index < 5) {{
                    boxes[index + 1].focus();
                }}

                // すべて入力されたら送信ボタンを有効化
                checkComplete();
            }});

            // Backspaceで前のボックスに戻る
            box.addEventListener('keydown', function(e) {{
                if (e.key === 'Backspace' && !e.target.value && index > 0) {{
                    boxes[index - 1].focus();
                }}
            }});

            // ペースト対応
            box.addEventListener('paste', function(e) {{
                e.preventDefault();
                var pasteData = e.clipboardData.getData('text').replace(/[^0-9]/g, '').substring(0, 6);
                for (var j = 0; j < boxes.length; j++) {{
                    boxes[j].value = '';
                }}
                for (var i = 0; i < pasteData.length && i < 6; i++) {{
                    boxes[i].value = pasteData[i];
                }}
                if (pasteData.length < 6) {{
                    boxes[pasteData.length].focus();
                }} else {{
                    boxes[5].focus();
                }}
                checkComplete();
            }});
        }});

        function checkComplete() {{
            var complete = boxes.every(function(b) {{ return b.value.length === 1; }});
            submitBtn.disabled = !complete;
        }}

        // フォーム送信時に6桁を結合
        form.addEventListener('submit', function() {{
            pinValue.value = boxes.map(function(b) {{ return b.value; }}).join('');
        }});

        // 最初のボックスにフォーカス
        boxes[0].focus();
    </script>
</body>
</html>
"@
}
