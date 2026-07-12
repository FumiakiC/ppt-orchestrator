# =============================================================================
#  tests/run-tests.ps1  —  テストエントリポイント
#  使い方: pwsh -NoProfile -File ./tests/run-tests.ps1
# =============================================================================

$here = $PSScriptRoot

. "$here/_harness.ps1"

Get-ChildItem "$here" -Filter '*.tests.ps1' | Sort-Object Name | ForEach-Object {
    $file = $_
    Write-Host "`n--- $($file.Name) ---"
    try {
        . $file.FullName
    } catch {
        Assert-True $false ("Unhandled exception in {0}: {1}" -f $file.Name, $_.Exception.Message)
    }
}

Invoke-TestSummary
