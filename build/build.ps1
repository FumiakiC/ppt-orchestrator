# ==============================================================================
#  ビルドスクリプト: src/ の各ファイルを単一の .ps1 に統合し、
#  src/frontend/ のアセットをビルド時トークンへ注入する。
#  出力先: dist/presentation-controller.ps1
# ==============================================================================
param(
    [string]$Version = 'dev'
)

if ($Version -notmatch '^[\w.\-]+$') {
    Write-Error "Invalid -Version value: '$Version'. Only word characters, dots, and hyphens are allowed."
    exit 1
}

$srcDir      = Join-Path (Split-Path $PSScriptRoot -Parent) "src"
$frontendDir = Join-Path $srcDir "frontend"
$distDir     = Join-Path (Split-Path $PSScriptRoot -Parent) "dist"
$outFile     = Join-Path $distDir "presentation-controller.ps1"

if (-not (Test-Path $distDir)) {
    New-Item -Path $distDir -ItemType Directory | Out-Null
}

# config.ps1 を先頭に置き、残りを順序どおり結合する
$files = @(
    "config.ps1",
    "templates.ps1",
    "utils.ps1",
    "auth.ps1",
    "server.ps1",
    "ui-console.ps1",
    "com-handler.ps1",
    "main.ps1"
)

$header = @"
# ==============================================================================
#  対話型プレゼンテーション実行スクリプト (Built by build/build.ps1)
# ==============================================================================

"@

$parts = @($header)

foreach ($file in $files) {
    $path = Join-Path $srcDir $file
    if (-not (Test-Path $path)) {
        Write-Error "Source file not found: $path"
        exit 1
    }

    $content = Get-Content -Path $path -Raw -Encoding UTF8

    # main.ps1 のドットソース行を除去する（ビルド後は不要）
    if ($file -eq "main.ps1") {
        $content = $content -replace '(?m)^\.\s+["'']\$PSScriptRoot[\\/].*\.ps1["'']\r?\n', ''
    }

    $parts += "# --- $file ---`n" + $content.TrimEnd() + "`n"
}

$combined = $parts -join "`n"

# ビルド時トークン注入: src/frontend/ のアセットを .Replace() で埋め込む。
# HtmlHeader.html が内部に %%BUILD_ASSET_MAIN_CSS%% / %%BUILD_SCRIPT_POLLING%% /
# %%BUILD_JS_HOLD%% を含むため、%%BUILD_VIEW_HTMLHEADER%% 解決後にもう一周必要。
# 最大 $maxIter 回反復し、変化が無くなった時点で終了する。

function Read-Frontend([string]$RelPath) {
    $full = Join-Path $frontendDir $RelPath
    if (-not (Test-Path $full)) { Write-Error "Frontend asset not found: $full"; exit 1 }
    return Get-Content -Path $full -Raw -Encoding UTF8
}

$tokenMap = [ordered]@{
    '%%BUILD_ASSET_MAIN_CSS%%'      = Read-Frontend 'css/main.css'
    '%%BUILD_SCRIPT_POLLING%%'      = Read-Frontend 'js/polling.js'
    '%%BUILD_JS_HOLD%%'             = Read-Frontend 'js/hold.js'
    '%%BUILD_JS_REMOTE%%'           = Read-Frontend 'js/remote.js'
    '%%BUILD_VIEW_HTMLHEADER%%'     = Read-Frontend 'views/HtmlHeader.html'
    '%%BUILD_VIEW_NOWPLAYING%%'     = Read-Frontend 'views/NowPlaying.html'
    '%%BUILD_VIEW_LOBBY%%'          = Read-Frontend 'views/Lobby.html'
    '%%BUILD_VIEW_DIALOG%%'         = Read-Frontend 'views/Dialog.html'
    '%%BUILD_VIEW_PROCESSING%%'     = Read-Frontend 'views/Processing.html'
    '%%BUILD_VIEW_EXIT%%'           = Read-Frontend 'views/Exit.html'
    '%%BUILD_VIEW_AUTH%%'           = Read-Frontend 'views/Auth.html'
    '%%BUILD_VERSION%%'             = $Version
}

$maxIter = 10
for ($i = 0; $i -lt $maxIter; $i++) {
    $before = $combined
    foreach ($kv in $tokenMap.GetEnumerator()) {
        $combined = $combined.Replace($kv.Key, [string]$kv.Value)
    }
    if ($combined -eq $before) { break }
    if ($i -eq ($maxIter - 1)) {
        Write-Error "Build token loop did not converge after $maxIter iterations — possible circular token reference"
        exit 1
    }
}

$utf8BOM = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($outFile, $combined, $utf8BOM)

Write-Host "Build complete: $outFile" -ForegroundColor Green
Write-Host "  Version    : $Version" -ForegroundColor Gray
Write-Host "  Total size : $([Math]::Round((Get-Item $outFile).Length / 1KB, 1)) KB" -ForegroundColor Gray
