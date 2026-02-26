@echo off
cd /d %~dp0

:: ===============================================
:: 対話型プレゼン Webリモコン 前処理 + 起動バッチ（完全版）
::  - URLACL 登録（http.sys）
::  - Windows Defender Firewall <WEB_PORT>/TCP 許可（異サブネット含む）
::  - 管理者昇格
::  - 64bit PowerShell で PowerShell スクリプト起動
:: ===============================================

:: 文字コードをUTF-8 (65001) に
chcp 65001 > nul

setlocal

:: -----------------------------------------------
:: 設定
:: -----------------------------------------------
set "SCRIPT_NAME=Invoke-PPTController.ps1"
set "WEB_PORT=8090"
set "FW_RULE_NAME=PresentController TCP %WEB_PORT% In"
:: すべてのNICで待受するURL予約（実IPに固定したい場合は http://<IP>:%WEB_PORT%/ に変更）
set "URLACL_URL=http://+:%WEB_PORT%/"

:: 64bit PowerShell のフルパス（Office 64bit と揃えるために推奨）
set "POWERSHELL_X64=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: -----------------------------------------------
:: PowerShellスクリプトの存在確認
:: -----------------------------------------------
if not exist "%SCRIPT_NAME%" (
    echo [Error] File not found: %SCRIPT_NAME%
    echo Please place the PowerShell script in the same folder as this batch file.
    pause
    exit /b 1
)

:: -----------------------------------------------
:: 管理者権限チェック＆昇格（net session は管理者でのみ成功）
:: -----------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Restarting batch with administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: -----------------------------------------------
:: 64bit PowerShell が見つからない場合のフォールバック
:: -----------------------------------------------
if not exist "%POWERSHELL_X64%" (
    echo [Warning] 64bit PowerShell not found. Using default powershell.exe.
    set "POWERSHELL_X64=powershell.exe"
)

echo.
echo ==== Starting Pre-processing: Configuring URLACL and Firewall ====
echo.

:: -----------------------------------------------
:: URLACL: 既存の URL 予約を削除 → 再登録
::  - 競合や不整合を避けるため、毎回クリーンに作り直します
:: -----------------------------------------------
echo [URLACL] Removing: %URLACL_URL% (OK if it doesn't exist)
netsh http delete urlacl url=%URLACL_URL% >nul 2>&1

echo [URLACL] Adding: %URLACL_URL%
:: URLACL の user は UPN（whoami /upn）を優先、取れない場合は ドメイン\ユーザー を使用
set "CURRENT_UPN="
for /f "tokens=1,* delims=:" %%A in ('whoami /upn 2^>nul ^| find ":"') do set "CURRENT_UPN=%%B"
if defined CURRENT_UPN (
    for /f "tokens=* delims= " %%Z in ("%CURRENT_UPN%") do set "CURRENT_UPN=%%Z"
) else (
    set "CURRENT_UPN=%USERDOMAIN%\%USERNAME%"
)

netsh http add urlacl url=%URLACL_URL% user="%CURRENT_UPN%" listen=yes
if %errorlevel% neq 0 (
    echo [Warning] Failed to add URLACL. Continuing, but please check permissions later.
)

:: -----------------------------------------------
:: Windows Defender Firewall: <WEB_PORT>/TCP 着信許可
::  - RemoteAddress=Any, Profile=Any で「異サブネットからも許可」
::  - 既存の同名ルールは削除してから追加
:: -----------------------------------------------
echo [FW] Removing existing rule (same name): %FW_RULE_NAME%
"%POWERSHELL_X64%" -NoProfile -Command ^
  "Get-NetFirewallRule -DisplayName '%FW_RULE_NAME%' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue" >nul 2>&1

echo [FW] Adding new rule: %FW_RULE_NAME%
"%POWERSHELL_X64%" -NoProfile -Command ^
  "New-NetFirewallRule -DisplayName '%FW_RULE_NAME%' -Direction Inbound -Action Allow -Protocol TCP -LocalPort %WEB_PORT% -RemoteAddress Any -Profile Any" >nul 2>&1

if %errorlevel% neq 0 (
    echo [Warning] Error creating Firewall rule. It may be restricted by GPO or other policies.
)

:: -----------------------------------------------
:: （参考情報）現時点の LISTEN 状況を表示
::  - PowerShell側のWebリスナー起動前なので、空でも正常
:: -----------------------------------------------
echo.
echo [INFO] Current binding status for port %WEB_PORT% (reference before start):
netstat -ano | findstr ":%WEB_PORT%" || echo   (None found)
echo.

:: -----------------------------------------------
:: PowerShell スクリプトを 64bit で起動（実行ポリシー回避）
::  - 既にこのバッチ自体が管理者で動作中のため、改めて RunAs は不要
:: -----------------------------------------------
echo Starting PowerShell script (64bit) with administrator privileges...
echo.

"%POWERSHELL_X64%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0%SCRIPT_NAME%"

:: -----------------------------------------------
:: バッチはここで終了
:: -----------------------------------------------
echo.
echo All processes completed. You can close this window.
exit /b 0
``