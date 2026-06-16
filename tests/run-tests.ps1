# =============================================================================
#  tests/run-tests.ps1  —  テストエントリポイント
#  使い方: pwsh -NoProfile -File ./tests/run-tests.ps1
# =============================================================================

$here = $PSScriptRoot

. "$here/_harness.ps1"

Get-ChildItem "$here" -Filter '*.tests.ps1' | Sort-Object Name | ForEach-Object {
    Write-Host "`n--- $($_.Name) ---"
    . $_.FullName
}

Invoke-TestSummary
