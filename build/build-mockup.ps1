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
$demoPin       = '123456'

# デモ用の初期値はこのブロックが唯一の定義元。shim（build/mockup/demo-shim.js）と
# index の案内文は下記から注入・展開され、二重管理によるドリフトを防ぐ。
$mockDecksJson = (@{ queue = @($activeDecks); done = @($finishedDecks) } | ConvertTo-Json -Compress -Depth 3)
if ($mockDecksJson -match '</') {
    Write-Error "Sample deck names must not contain '</' (would break the injected <script> block)"
    exit 1
}

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

# --- 4) demo shim（</head> 直前へ注入。生成物のみ。src は不変） ---
# build/mockup/demo-shim.js が疑似バックエンド（fetch 横取り・状態機械・
# ネットワークシミュレータ・デモパネル）を提供する。
# ページ識別子とデモ用初期値（window.__MOCK_PAGE / __MOCK_PIN / __MOCK_DECKS）を
# 先に注入し、shim 本体をインライン展開する。shim 側は値を持たずこれらを参照する。
$demoShimJs = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mockup/demo-shim.js') -Raw -Encoding UTF8

function Add-DemoShim([string]$Html, [string]$PageId) {
    # </head> が見つからない / 複数ある場合は fail fast。テンプレート側で閉じタグの
    # 削除・改名・大文字化が起きたとき、注入が黙って失敗して生成物が実 submit /
    # 実 polling を行う状態で公開されるのを防ぐ。
    $count = ([regex]::Matches($Html, '</head>')).Count
    if ($count -ne 1) {
        Write-Error "Cannot inject demo shim into '$PageId': expected exactly one '</head>', found $count. Frontend template may have changed."
        exit 1
    }
    $bootstrap = "window.__MOCK_PAGE='$PageId';window.__MOCK_PIN='$demoPin';window.__MOCK_DECKS=$mockDecksJson;"
    $inject = "    <script>$bootstrap</script>`n    <script>`n$demoShimJs`n    </script>`n</head>"
    return $Html.Replace('</head>', $inject)
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
# Auth エラー変種（auth.ps1 の PIN 失敗時と同じ 'error' 注入。demo で誤 PIN 時に遷移）
$authErrorHtml = $viewAuth.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', 'error')

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
<p class="note">This is an <b>interactive mockup</b>: there is no PowerPoint or server behind these pages &mdash; a demo shim fakes the backend. Start at <b>Auth</b> (demo PIN: <b>$demoPin</b>), pick a deck in the Lobby, and control the &quot;presentation&quot; from Now Playing. Use the <b>DEMO</b> button (bottom right) to simulate LIVE / SLOW / OFFLINE network conditions and other stage events.</p>
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
    'auth.html'       = (Add-DemoShim $authHtml 'auth')
    'auth-error.html' = (Add-DemoShim $authErrorHtml 'auth-error')
    'lobby.html'      = (Add-DemoShim $lobbyHtml 'lobby')
    'nowplaying.html' = (Add-DemoShim $nowPlayingHtml 'nowplaying')
    'dialog.html'     = (Add-DemoShim $dialogHtml 'dialog')
    'processing.html' = (Add-DemoShim $processingHtml 'processing')
    'exit.html'       = (Add-DemoShim $exitHtml 'exit')
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