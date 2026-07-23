# ==============================================================================
#  静的モックアップ生成スクリプト（CI / GitHub Pages 専用。dist 配布物には含めない）
#
#  src/frontend/ のアセットから、実行時のページ組み立て（ui-console.ps1 /
#  com-handler.ps1 / server.ps1 / utils.ps1 Get-HtmlHeader）を模倣した
#  静的 HTML 一式を dist/pages/ に出力する。
#
#  - %%BUILD_*%% トークンはビルド規約どおり .Replace() で解決する
#    （トークン一覧は build/build.ps1 の $tokenMap と同期を保つこと）
#  - 実行時トークン %%NAME%% にはデモ用のサンプル値を注入する
#  - 生成物には demo スタブ（fetch 無効化・form 送信抑止・DEMO バッジ）を
#    </head> 直前に注入する。src/ 側は一切変更しない
#  - 製品コード・製品ビルド（build.ps1 / dist/presentation-controller.ps1）には
#    影響しない。Zero-Dependency 制約上「CI 限定・dist 非同梱」の例外枠で運用する
# ==============================================================================
param(
    [string]$Version = 'dev',
    [string]$OutDir
)

if ($Version -notmatch '^[\w.\-]+$') {
    Write-Error "Invalid -Version value: '$Version'. Only word characters, dots, and hyphens are allowed."
    exit 1
}

$repoRoot    = Split-Path $PSScriptRoot -Parent
$frontendDir = Join-Path (Join-Path $repoRoot 'src') 'frontend'
if (-not $OutDir) { $OutDir = Join-Path (Join-Path $repoRoot 'dist') 'pages' }

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}

function Read-Frontend([string]$RelPath) {
    $full = Join-Path $frontendDir $RelPath
    if (-not (Test-Path -LiteralPath $full)) { Write-Error "Frontend asset not found: $full"; exit 1 }
    return Get-Content -LiteralPath $full -Raw -Encoding UTF8
}

# --- 1) ビルド時トークン解決（build.ps1 と同じ二層規約・反復 .Replace()） ---
$tokenMap = [ordered]@{
    '%%BUILD_ASSET_MAIN_CSS%%'  = Read-Frontend 'css/main.css'
    '%%BUILD_SCRIPT_POLLING%%'  = Read-Frontend 'js/polling.js'
    '%%BUILD_JS_HOLD%%'         = Read-Frontend 'js/hold.js'
    '%%BUILD_JS_REMOTE%%'       = Read-Frontend 'js/remote.js'
    '%%BUILD_VERSION%%'         = $Version
}

function Resolve-BuildTokens([string]$Html) {
    $maxIter = 10
    for ($i = 0; $i -lt $maxIter; $i++) {
        $before = $Html
        foreach ($kv in $tokenMap.GetEnumerator()) {
            $Html = $Html.Replace($kv.Key, [string]$kv.Value)
        }
        if ($Html -eq $before) { return $Html }
    }
    Write-Error "Build token loop did not converge after $maxIter iterations"
    exit 1
}

$viewHeader     = Resolve-BuildTokens (Read-Frontend 'views/HtmlHeader.html')
$viewNowPlaying = Resolve-BuildTokens (Read-Frontend 'views/NowPlaying.html')
$viewLobby      = Resolve-BuildTokens (Read-Frontend 'views/Lobby.html')
$viewDialog     = Resolve-BuildTokens (Read-Frontend 'views/Dialog.html')
$viewProcessing = Resolve-BuildTokens (Read-Frontend 'views/Processing.html')
$viewExit       = Resolve-BuildTokens (Read-Frontend 'views/Exit.html')
$viewAuth       = Resolve-BuildTokens (Read-Frontend 'views/Auth.html')

# --- 2) 実行時の組み立てを模倣する部品（templates.ps1 / utils.ps1 準拠） ---
# PollingScript は src/templates.ps1 の定義と同一内容（Lobby / Dialog ページ用）。
$pollingScript = @'
    <script>
        window.startPolling(['waiting'], '/', { defaultDelay: 300, statusRedirects: { 'stopping': '/exit' } });
    </script>
'@

function Get-MockHtmlHeader([string]$Title, [string]$BgColor) {
    # utils.ps1 Get-HtmlHeader と同じ置換
    return $viewHeader.Replace('%%TITLE%%', [string]$Title).Replace('%%BGCOLOR%%', [string]$BgColor)
}

# --- 3) デモ用サンプルデータ（実行時トークンへ注入する値） ---
$activeDecks   = @('01_Opening_Keynote.pptx', '02_Product_Roadmap_2026.pptx', '03_Engineering_Deep-Dive.pptx')
$finishedDecks = @('00_Venue_Guide.pptx')
$playingDeck   = $activeDecks[1]

# Lobby のリスト HTML は ui-console.ps1 の生成コードと同一マークアップで作る（見た目の忠実度確保）
function New-MockLobbyList {
    $listHtml = "<div class='list-scroll'>"
    $listHtml += "<div class='sec'><span class='tag tag-standby'>STANDBY</span> Pending</div>"
    $idx = 0
    foreach ($fname in $activeDecks) {
        $idx++
        $listHtml += "<form method='post' action='/select' class='deck-form'><input type='hidden' name='filename' value='$fname'><button type='button' class='deck hold' data-hold='1500' data-hint='Press and hold to start this deck' style='--chg-edge:#f5a623;--chg-track:rgba(245,166,35,.18);--chg-glow:rgba(245,166,35,.55)'><span class='deck-badge'>$idx</span><span class='deck-name'>$fname</span><span class='deck-cue'>&#9654;</span></button></form>"
    }
    $listHtml += "<div class='sec'><span class='tag tag-done'>DONE</span> Completed</div>"
    foreach ($fname in $finishedDecks) {
        $listHtml += "<form method='post' action='/select' class='deck-form'><input type='hidden' name='filename' value='$fname'><button type='button' class='deck finished hold' data-hold='1500' data-hint='Press and hold to start this deck' style='--chg-edge:#5af0a0;--chg-track:rgba(52,210,123,.18);--chg-glow:rgba(52,210,123,.5)'><span class='deck-badge'>&#10003;</span><span class='deck-name'>$fname</span></button></form>"
    }
    $listHtml += "</div>"
    return $listHtml
}

# --- 4) demo スタブ（</head> 直前へ注入。生成物のみ。src は不変） ---
# PR-1（静的ギャラリー）: 通信と画面遷移を無効化し、その旨をトーストで示す。
# PR-2 でここを対話デモ shim（fetch/submit intercept の状態機械）に差し替える。
$demoStub = @'
    <script>
    /* == static mockup stub (generated by build/build-mockup.ps1; not part of the product) == */
    (function () {
        'use strict';
        var MSG = 'Static mockup \u2014 no live server behind this page';
        function toast(msg) {
            var el = document.getElementById('mockup-toast');
            if (!el) {
                el = document.createElement('div');
                el.id = 'mockup-toast';
                el.style.cssText = 'position:fixed;left:50%;bottom:64px;transform:translateX(-50%);background:rgba(20,24,30,.92);color:#e8edf3;padding:9px 14px;border-radius:8px;font:12px/1.4 system-ui,sans-serif;z-index:99999;opacity:0;transition:opacity .2s;pointer-events:none;max-width:86vw;text-align:center;';
                (document.body || document.documentElement).appendChild(el);
            }
            el.textContent = msg;
            el.style.opacity = '1';
            clearTimeout(el._t);
            el._t = setTimeout(function () { el.style.opacity = '0'; }, 1800);
        }
        /* GET のポーリング系は軽量な固定応答を返す（失敗ループと offline overlay を避け、
           NowPlaying の経過時間・スライド位置が生きた状態で見えるようにする）。
           状態を持つ対話デモ（lock 取得・スライド送り）は後続 PR-M の shim で実装する。 */
        var MOCK_GET = {
            '/status': { body: 'waiting', type: 'text/plain' },
            '/slide/state': { body: JSON.stringify({ ms: 372000, pos: 12, total: 24, atEnd: false, lock: false, mine: false, black: false, white: false }), type: 'application/json' }
        };
        window.fetch = function (input, init) {
            var method = (init && init.method ? init.method : 'GET').toUpperCase();
            var href = (typeof input === 'string') ? input : (input && input.url) || '';
            var path;
            try { path = new URL(href, window.location.href).pathname; } catch (e) { path = href; }
            var hit = method === 'GET' ? MOCK_GET[path] : null;
            if (hit) {
                return Promise.resolve(new Response(hit.body, { status: 200, headers: { 'Content-Type': hit.type } }));
            }
            if (method !== 'GET') { toast(MSG); }
            return Promise.resolve(new Response('', { status: 503 }));
        };
        window.startPolling = function () {};
        /* hold 完了 (requestSubmit) と Auth の form.submit() 双方を封じる */
        document.addEventListener('submit', function (e) { e.preventDefault(); toast(MSG); }, true);
        HTMLFormElement.prototype.submit = function () { toast(MSG); };
        /* DEMO バッジ（index へ戻る導線） */
        document.addEventListener('DOMContentLoaded', function () {
            var b = document.createElement('a');
            b.href = './index.html';
            b.textContent = 'DEMO';
            b.title = 'Static mockup \u2014 back to screen list';
            b.style.cssText = 'position:fixed;right:10px;bottom:10px;background:#f5a623;color:#1a1a1a;font:700 11px/1 system-ui,sans-serif;padding:6px 9px;border-radius:6px;text-decoration:none;z-index:99999;opacity:.85;';
            document.body.appendChild(b);
        });
    })();
    </script>
'@

function Add-DemoStub([string]$Html, [string]$PageName) {
    # </head> が見つからない / 複数ある場合は fail fast。テンプレート側で閉じタグの
    # 削除・改名・大文字化が起きたとき、注入が黙って失敗して生成物が実 submit /
    # 実 polling を行う状態で公開されるのを防ぐ。
    $count = ([regex]::Matches($Html, '</head>')).Count
    if ($count -ne 1) {
        Write-Error "Cannot inject demo stub into '$PageName': expected exactly one '</head>', found $count. Frontend template may have changed."
        exit 1
    }
    return $Html.Replace('</head>', $demoStub + "`n</head>")
}

# --- 5) 各ページの組み立て（実行時と同じ結合順） ---
$headController = Get-MockHtmlHeader -Title 'Controller' -BgColor '#1a1a1a'
$headDialog     = Get-MockHtmlHeader -Title 'Controller' -BgColor '#000000'
$headNowPlaying = Get-MockHtmlHeader -Title 'Now Playing' -BgColor '#000000'

# Lobby（ui-console.ps1: head + LobbyView + PollingScript + 閉じタグ。HoldToConfirmScript は空文字列）
$lobbyHtml = $viewLobby
$lobbyHtml = $lobbyHtml.Replace('%%LOBBY_NEXT_TEXT%%', [string]$activeDecks[0])
$lobbyHtml = $lobbyHtml.Replace('%%LOBBY_START_BTN%%', '')
$lobbyHtml = $lobbyHtml.Replace('%%LOBBY_LIST%%',      [string](New-MockLobbyList))
$lobbyHtml = $headController + $lobbyHtml + $pollingScript + '</div></body></html>'

# Dialog（次デッキあり変種。ui-console.ps1 の生成値と同一）
$encNext = $activeDecks[2]
$dialogHtml = $viewDialog
$dialogHtml = $dialogHtml.Replace('%%DIALOG_NEXT_CLS%%',   ' hold')
$dialogHtml = $dialogHtml.Replace('%%DIALOG_NEXT_STATE%%', "data-hold='1500' data-hint='Press and hold to start next' style='--chg-edge:#5af0a0;--chg-track:rgba(52,210,123,.22);--chg-glow:rgba(52,210,123,.7)'")
$dialogHtml = $dialogHtml.Replace('%%DIALOG_NEXT_LABEL%%', "<span class='pp-kicker'>&#9711; HOLD</span><span class='pp-main'><span class='pp-main-t'>Start Next</span><span class='pp-main-d'>$encNext</span></span>")
$dialogHtml = $dialogHtml.Replace('%%DIALOG_FILE%%',       [string]$playingDeck)
$dialogHtml = $headDialog + $dialogHtml + $pollingScript + '</div></body></html>'

# NowPlaying（com-handler.ps1: head + NowPlayingView。View 側が閉じタグを持つ）
$nowPlayingHtml = $headNowPlaying + $viewNowPlaying.Replace('%%DECK%%', [string]$playingDeck)

# Processing / Exit（ui-console.ps1: head + View。View 側が閉じタグを持つ）
$processingHtml = $headController + $viewProcessing
$exitHtml       = $headController + $viewExit

# Auth（server.ps1: 単体 View。BGCOLOR は互換トークン・AUTH_ERROR は初期状態 ''）
$authHtml = $viewAuth.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', '')

# --- 6) index（デモの入口。製品 UI ではないため自己完結スタイル） ---
$indexHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ppt-orchestrator &mdash; UI Mockup</title>
<style>
body{margin:0;background:#12161c;color:#e8edf3;font:15px/1.6 system-ui,sans-serif;display:flex;justify-content:center;}
main{max-width:560px;padding:36px 20px 60px;}
h1{font-size:1.35rem;margin:0 0 4px;}
.sub{color:#9aa7b4;font-size:.85rem;margin:0 0 20px;}
.note{background:rgba(245,166,35,.12);border:1px solid rgba(245,166,35,.4);border-radius:8px;padding:10px 14px;font-size:.82rem;margin:0 0 24px;color:#f0d9ad;}
a.card{display:block;background:#1b222b;border:1px solid #2a3441;border-radius:10px;padding:14px 16px;margin:10px 0;color:inherit;text-decoration:none;transition:border-color .15s;}
a.card:hover{border-color:#f5a623;}
a.card b{display:block;font-size:.95rem;}
a.card span{color:#9aa7b4;font-size:.8rem;}
footer{margin-top:28px;color:#5c6773;font-size:.75rem;}
footer a{color:#8fa3b8;}
</style>
</head>
<body>
<main>
<h1>ppt-orchestrator &mdash; UI Mockup</h1>
<p class="sub">Static mockup of the web remote UI, generated from <code>src/frontend/</code> by CI.</p>
<p class="note">This is a <b>static demo</b>: there is no PowerPoint or server behind these pages. Buttons show the real hold-to-confirm interaction, but actions and page transitions are disabled.</p>
<a class="card" href="./auth.html"><b>Auth</b><span>PIN keypad (daily 6-digit PIN on the host PC)</span></a>
<a class="card" href="./lobby.html"><b>Lobby</b><span>Deck queue &mdash; hold a deck or GO to start</span></a>
<a class="card" href="./nowplaying.html"><b>Now Playing</b><span>Live remote: slide control, lock, blackout</span></a>
<a class="card" href="./dialog.html"><b>Post-presentation</b><span>Start next / replay / back to lobby / exit</span></a>
<a class="card" href="./processing.html"><b>Processing</b><span>Transition screen while PowerPoint switches decks</span></a>
<a class="card" href="./exit.html"><b>Exit</b><span>System shutdown screen</span></a>
<footer>Generated from tag <code>$Version</code> &middot; <a href="https://github.com/FumiakiC/ppt-orchestrator">FumiakiC/ppt-orchestrator</a></footer>
</main>
</body>
</html>
"@

# --- 7) 書き出し（HTML は UTF-8 BOM なし・charset meta あり） ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$pages = [ordered]@{
    'index.html'      = $indexHtml
    'auth.html'       = (Add-DemoStub $authHtml 'auth.html')
    'lobby.html'      = (Add-DemoStub $lobbyHtml 'lobby.html')
    'nowplaying.html' = (Add-DemoStub $nowPlayingHtml 'nowplaying.html')
    'dialog.html'     = (Add-DemoStub $dialogHtml 'dialog.html')
    'processing.html' = (Add-DemoStub $processingHtml 'processing.html')
    'exit.html'       = (Add-DemoStub $exitHtml 'exit.html')
}
foreach ($kv in $pages.GetEnumerator()) {
    [System.IO.File]::WriteAllText((Join-Path $OutDir $kv.Key), $kv.Value, $utf8NoBom)
}
# Jekyll 処理を無効化（GitHub Pages 標準対策）
[System.IO.File]::WriteAllText((Join-Path $OutDir '.nojekyll'), '', $utf8NoBom)

# --- 8) 残骸ガード: 未解決トークンが残っていたら失敗させる ---
$bad = @()
foreach ($kv in $pages.GetEnumerator()) {
    if ([regex]::IsMatch($kv.Value, '%%[A-Z0-9_]+%%')) { $bad += $kv.Key }
}
if ($bad.Count -gt 0) {
    Write-Error ("Unresolved %%TOKEN%% left in: " + ($bad -join ', '))
    exit 1
}

Write-Host "Mockup build complete: $OutDir" -ForegroundColor Green
Write-Host "  Pages   : $($pages.Count) + .nojekyll" -ForegroundColor Gray
Write-Host "  Version : $Version" -ForegroundColor Gray