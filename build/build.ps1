# ==============================================================================
#  ビルドスクリプト: src/ の各ファイルを単一の .ps1 に統合する
#  出力先: dist/Invoke-PPTController.ps1
# ==============================================================================

$srcDir  = Join-Path $PSScriptRoot "..\src"
$distDir = Join-Path $PSScriptRoot "..\dist"
$outFile = Join-Path $distDir "Invoke-PPTController.ps1"

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
        $content = $content -replace '(?m)^\. "\$PSScriptRoot\\.*\.ps1"\r?\n', ''
    }

    $parts += "# --- $file ---`n" + $content.TrimEnd() + "`n"
}

$combined = $parts -join "`n"
[System.IO.File]::WriteAllText($outFile, $combined, [System.Text.Encoding]::UTF8)

Write-Host "Build complete: $outFile" -ForegroundColor Green
Write-Host "  Total size: $([Math]::Round((Get-Item $outFile).Length / 1KB, 1)) KB" -ForegroundColor Gray
