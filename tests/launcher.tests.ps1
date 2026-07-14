# =============================================================================
#  launcher.tests.ps1  —  Start-Presenter.bat regression guards
#  This test performs content inspection only and does NOT execute the .bat file.
#  Reason: CI (ubuntu) cannot run cmd.exe / netsh / UAC flows.
#  Runtime behavior is covered by Windows smoke checks in docs/05.
# =============================================================================

$raw = Get-Content -LiteralPath "$PSScriptRoot/../Start-Presenter.bat" -Raw

Assert-True ($raw.EndsWith("exit /b 0`r`n")) 'Start-Presenter.bat は exit /b 0 + CRLF で終端する（末尾バッククォート禁止）'
Assert-True ($raw -notmatch 'whoami\s+/upn[^\r\n]*\bfind\b') 'whoami /upn の出力を find でフィルタしない'
Assert-True ($raw -match 'whoami /upn') 'whoami /upn による UPN 取得が存在する'
Assert-True ($raw -match '%USERDOMAIN%\\%USERNAME%') 'DOMAIN\USERNAME への fallback が存在する'
