. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\templates.ps1"
. "$PSScriptRoot\utils.ps1"
. "$PSScriptRoot\auth.ps1"
. "$PSScriptRoot\server.ps1"
. "$PSScriptRoot\ui-console.ps1"
. "$PSScriptRoot\com-handler.ps1"

# ==============================================================================
# メインフロー
# ==============================================================================
# 管理者チェックより前にログを開く。非管理者で即 exit するケースこそ
# 「起動したのに何も起きない」の切り分けに必要なため。Initialize-Log は失敗しても
# throw しない設計なので、ProgramData に書けなくても起動は止まらない。
# 変数名を $logDir にしないこと: PowerShell の変数名は大文字小文字を区別しないため
# config.ps1 の $script:LogDir と同一変数になる。現状は同じ値を書き戻すだけで無害だが、
# access ログ用のディレクトリ状態が増えた時点で衝突が実害になる。
$eventsLogDir = Join-Path (Split-Path -Parent $StatePath) 'logs'
Initialize-Log -Directory $eventsLogDir -Meta ([ordered]@{
    schema       = $script:LogSchema
    host         = $env:COMPUTERNAME
    version      = '%%BUILD_VERSION%%'
    port         = $WebPort
    slideLogMode = $script:SlideLogMode
})

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Log -EventName 'app.start' -Data ([ordered]@{ admin = [bool]$isAdmin; targetFolder = $TargetFolderPath })
if (-not $isAdmin) {
    Write-Warning "Administrator privileges required. Please run PowerShell as Administrator."
    Write-Log -EventName 'app.stop' -Data ([ordered]@{ reason = 'not-admin' })
    Close-Log
    Start-Sleep 3
    exit
}

[ConsoleWindow]::DisableCloseButton()
try { [ConsoleWindow]::DisableQuickEdit() } catch {}
[console]::TreatControlCAsInput = $true

# Stabilize console dimensions so header info (PIN / URL) is not pushed off-screen.
# Buffer height is kept large so content never overflows the buffer (with quick-edit off, scrolling is unavailable).
try {
    $rawUI = $Host.UI.RawUI
    $desiredWidth  = [Math]::Max($rawUI.BufferSize.Width, 100)
    $desiredWinH   = 40
    $maxWinH       = $rawUI.MaxPhysicalWindowSize.Height
    if ($maxWinH -gt 0 -and $desiredWinH -gt $maxWinH) { $desiredWinH = $maxWinH }

    # Buffer must be >= window. Set buffer first (width+height), then window.
    $rawUI.BufferSize = New-Object System.Management.Automation.Host.Size($desiredWidth, 1000)
    $newWin = New-Object System.Management.Automation.Host.Size($desiredWidth, $desiredWinH)
    $rawUI.WindowSize = $newWin
} catch {
    # Non-fatal: some hosts (e.g. redirected output) don't support resizing.
}

if (-not (Test-Path -LiteralPath $TargetFolderPath)) {
    # $ErrorActionPreference='Stop' のため Write-Error はここで terminating になる。
    # ログと Close-Log は必ず Write-Error より前に置く（後置だと到達しない）。
    # これが無いと app.start だけ残って「app.stop 無し＝異常終了」に誤読される。
    Write-Log -EventName 'app.stop' -Data ([ordered]@{ reason = 'no-target-folder' })
    Close-Log
    Write-Error "Target Folder Not Found"; exit
}
$finishFolderPath = Join-Path $TargetFolderPath $FinishFolderName
New-DirectoryIfMissing -Path $finishFolderPath

Write-Host "Starting PowerPoint..." -ForegroundColor Cyan

# Snapshot pre-existing PowerPoint PIDs so we never bind/kill an operator's own instance.
$preExistingPptPids = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

$pptApp  = $null
$lastErr = $null
for ($i = 1; $i -le 3; $i++) {
    try { $pptApp = New-Object -ComObject PowerPoint.Application; break }
    catch { $lastErr = $_; if ($i -lt 3) { Start-Sleep -Milliseconds 1500 } }
}
if ($pptApp) { Write-Log -EventName 'ppt.launch' -Data ([ordered]@{ attempts = $i }) }

# If still not up, optionally clear stale instances (opt-in) and retry once.
if (-not $pptApp) {
    $stale = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue)
    if ($stale.Count -gt 0 -and $KillStalePowerPoint) {
        Write-Warning "PowerPoint not responding. Clearing stale POWERPNT process(es) and retrying..."
        $stale | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
        try { $pptApp = New-Object -ComObject PowerPoint.Application } catch { $lastErr = $_ }
        # この経路の成功は上の ppt.launch を通らないため、ここで別途記録する。
        # 記録しないと PowerPoint は起動しているのにログ上は「一度も起動していない」ように見える。
        if ($pptApp) { Write-Log -EventName 'ppt.recover' -Level 'warn' -Data ([ordered]@{ killedStale = $stale.Count }) }
    }
}

if (-not $pptApp) {
    $msg = if ($lastErr) { $lastErr.Exception.Message } else { "unknown error" }
    $hr  = if ($lastErr) { ("0x{0:X8}" -f $lastErr.Exception.HResult) } else { "n/a" }
    # 計算済みの $hr / $msg を使い回す（COM 呼び出しは増やさない）。
    # Write-Error は EAP=Stop で terminating になるため、ログと Close-Log を先に出す。
    Write-Log -EventName 'ppt.launch.fail' -Level 'error' -Data ([ordered]@{ hr = $hr; msg = $msg })
    Write-Log -EventName 'app.stop' -Data ([ordered]@{ reason = 'ppt-launch-failed' })
    Close-Log
    if ((Get-Process -Name POWERPNT -ErrorAction SilentlyContinue) -and -not $KillStalePowerPoint) {
        Write-Error "Failed to start PowerPoint: $msg (HRESULT $hr). A PowerPoint process is already running; re-run with -KillStalePowerPoint to clear it, or close it manually."
    } else {
        Write-Error "Failed to start PowerPoint: $msg (HRESULT $hr)"
    }
    exit
}

$pptApp.Visible = [Microsoft.Office.Core.MsoTriState]::msoTrue
try { $pptApp.DisplayAlerts = 1 } catch {}   # 1 = ppAlertsNone（PIA非依存のため数値リテラル）

# Bind only an instance WE spawned to a kill-on-close job (never the operator's own).
Set-PptKillOnClose -PptApp $pptApp -PreExistingPids $preExistingPptPids

try {
    $exitLoop      = $false
    $autoPlayTarget = $null

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$WebPort/")
    try {
        $listener.Start()
        $script:ContextTask = Get-SafeContextAsync -Listener $listener
        Write-Log -EventName 'net.listener.start' -Data ([ordered]@{ port = $WebPort })
        # Get-LocalActiveIPs は @{ InterfaceAlias; IPAddress } のハッシュテーブル配列を返す。
        # "$_" で文字列化すると System.Collections.Hashtable になるため、alias / ip を明示展開する。
        Write-Log -EventName 'net.binding' -Data ([ordered]@{
            url      = "http://+:$WebPort/"
            port     = $WebPort
            adapters = @(Get-LocalActiveIPs | ForEach-Object { [ordered]@{ alias = $_.InterfaceAlias; ip = $_.IPAddress } })
        })
    } catch {
        Write-Log -EventName 'net.listener.error' -Level 'error' -Data ([ordered]@{ port = $WebPort; msg = $_.Exception.Message })
        Write-Warning "Web control is unavailable due to port conflict. Only keyboard operations are available."
    }

    while (-not $exitLoop) {

        $activeFiles   = Get-PptFiles -Path $TargetFolderPath
        $finishedFiles = Get-PptFiles -Path $finishFolderPath

        $targetFileItem = $null

        # --- A. 選択 ---
        if ($autoPlayTarget) {
            $targetFileItem  = $autoPlayTarget
            $autoPlayTarget  = $null
        } else {
            $result = Get-UserAction -Mode "Lobby" -ActiveFiles $activeFiles -FinishedFiles $finishedFiles -Listener $listener

            switch ($result.Action) {
                "Exit"   { $exitLoop = $true; break }
                "Start"  { if ($activeFiles) { $targetFileItem = $activeFiles[0] } }
                "Select" {
                    $name = $result.FileName
                    $targetFileItem = $activeFiles   | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                    if (!$targetFileItem) {
                        $targetFileItem = $finishedFiles | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                    }
                    if (!$targetFileItem) {
                        # 選択されたファイルが表示後に手動移動/削除された等。無音だと
                        # 「押したのに始まらない」が事後に再構成できない。記録位置をここ（Select アーム内）に
                        # 限定するのは、下の continue 直前に置くと Exit 経路でも誤発火するため。
                        Write-Log -EventName 'ui.select.miss' -Level 'warn' -Data ([ordered]@{ name = $name })
                    }
                }
            }
        }

        if (-not $targetFileItem) { continue }
        if ($exitLoop) { break }

        # --- B. プレゼン実行 ---
        $presentation = $null
        $status       = "SlideshowExited"

        # PowerPointプロセスの生存確認と自動復旧
        try {
            $null = $pptApp.Name
            $null = $pptApp.Version
        } catch {
            # HResult は例外オブジェクトからの読み出し（COM 呼び出しではない）。書式は com-handler の
            # com.fatal と同じ '0x' + X8 に揃える。
            $hrDead = $_.Exception.HResult
            Write-Log -EventName 'ppt.dead' -Level 'warn' -Data ([ordered]@{
                hr  = $(if ($hrDead) { '0x' + $hrDead.ToString('X8') } else { $null })
                msg = $_.Exception.Message
            })
            Write-Host " [Warning] PowerPoint COM object is dead. Attempting recovery..." -ForegroundColor Yellow
            Release-ComObject -obj $pptApp
            $pptApp = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $recoveryPreexisting = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
            try {
                $pptApp = New-Object -ComObject PowerPoint.Application
                $pptApp.Visible = [Microsoft.Office.Core.MsoTriState]::msoTrue
                try { $pptApp.DisplayAlerts = 1 } catch {}   # 1 = ppAlertsNone（PIA非依存のため数値リテラル）
                # ppt.dead と対になる復旧成功。直後の Set-PptKillOnClose が ppt.guard で紐付け結果を残す。
                Write-Log -EventName 'ppt.relaunch'
                Write-Host " [System] PowerPoint COM object recovered successfully." -ForegroundColor Green
                Set-PptKillOnClose -PptApp $pptApp -PreExistingPids $recoveryPreexisting
            } catch {
                # これが無いと「選んだのに再生されず Lobby に戻る」理由がログから消える。
                $hrRelaunch = $_.Exception.HResult
                Write-Log -EventName 'ppt.relaunch.fail' -Level 'error' -Data ([ordered]@{
                    hr  = $(if ($hrRelaunch) { '0x' + $hrRelaunch.ToString('X8') } else { $null })
                    msg = $_.Exception.Message
                })
                Write-Host " [Error] Failed to recover PowerPoint: $($_.Exception.Message)" -ForegroundColor Red
                Start-Sleep 3
                continue
            }
        }

        try {
            Write-Host " >> Opening: $($targetFileItem.Name)" -ForegroundColor Cyan
            $presentation = $pptApp.Presentations.Open($targetFileItem.FullName, $false, $false, $true)

            Start-Sleep -Milliseconds 100
            $presentation.SlideShowSettings.Run() | Out-Null

            $status = Watch-RunningPresentation -PptApp $pptApp -TargetFileItem $targetFileItem -Listener $listener

            if ($status -eq "ManualStop") {
                Write-Host " >> Manually stopped." -ForegroundColor Yellow
                try { $presentation.Close() } catch {}
                $targetFileItem = Move-ToFinishIfPending -TargetFileItem $targetFileItem -FinishFolderPath $finishFolderPath -Presentation $presentation

                $autoPlayTarget = $null
                continue
            }

            if ($status -eq "ClosedByUser") {
                $targetFileItem = Move-ToFinishIfPending -TargetFileItem $targetFileItem -FinishFolderPath $finishFolderPath -Presentation $presentation
                $autoPlayTarget = $null
                continue
            }

            # SlideshowExited path: defer move until explicit completion action.
            $activeFiles   = Get-PptFiles -Path $TargetFolderPath
            $nextCandidate = $activeFiles | Where-Object { $_.FullName -ne $targetFileItem.FullName } | Select-Object -First 1
            $nextName      = if ($nextCandidate) { $nextCandidate.Name } else { "" }

            $postResult = Get-UserAction -Mode "Dialog" -CurrentFileName $targetFileItem.Name -NextFileName $nextName -Listener $listener

            switch ($postResult.Action) {
                "Next"  {
                    $targetFileItem = Move-ToFinishIfPending -TargetFileItem $targetFileItem -FinishFolderPath $finishFolderPath -Presentation $presentation
                    $activeFiles = Get-PptFiles -Path $TargetFolderPath
                    $autoPlayTarget = if ($activeFiles) {
                        $next = $activeFiles | Where-Object { $_.FullName -ne $targetFileItem.FullName } | Select-Object -First 1
                        if ($next) { $next } else { $activeFiles[0] }
                    } else { $null }
                }
                "Retry" {
                    $autoPlayTarget = $targetFileItem
                }
                "Lobby" {
                    $targetFileItem = Move-ToFinishIfPending -TargetFileItem $targetFileItem -FinishFolderPath $finishFolderPath -Presentation $presentation
                    $autoPlayTarget = $null
                }
                "Exit"  {
                    $targetFileItem = Move-ToFinishIfPending -TargetFileItem $targetFileItem -FinishFolderPath $finishFolderPath -Presentation $presentation
                    $exitLoop = $true
                }
            }

        } catch {
            # Presentations.Open / SlideShowSettings.Run の失敗は Watch-RunningPresentation に
            # 到達せず show.start すら出ない。この catch が壊れた pptx ・開けないファイルの
            # 唯一の痕跡になる（deck / hr は計算済み値の使い回し）。
            $hrShow = $_.Exception.HResult
            Write-Log -EventName 'show.error' -Level 'error' -Data ([ordered]@{
                deck = $targetFileItem.Name
                hr   = $(if ($hrShow) { '0x' + $hrShow.ToString('X8') } else { $null })
                msg  = $_.Exception.Message
            })
            Write-Host " [Error] $($_.Exception.Message)" -ForegroundColor Red
            if ($presentation) { try { $presentation.Close() } catch {} }
            Start-Sleep 2
        } finally {
            if ($presentation) {
                try { $presentation.Close() } catch {}
                Release-ComObject -obj $presentation
                $presentation = $null
            }
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }
    }

} finally {
    if ($listener) {
        try {
            if ($listener.IsListening) { $listener.Stop() }
            $listener.Close()
            Start-Sleep -Milliseconds 200
            Write-Log -EventName 'net.listener.stop'
        } catch {}
    }

    Clear-Host
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  [System] Shutting down..." -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""

    if ($pptApp) {
        try { $pptApp.Quit() } catch {}
        Release-ComObject -obj $pptApp
        $pptApp = $null
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    Write-Host "System terminated." -ForegroundColor Green
    Write-Host ""

    # この finally は未処理例外でメインループを抜けた場合にも実行される。常に 'normal' を
    # 書くと異常終了が正常終了に偽装され、「app.stop が無い＝異常終了」（docs/06 §7）の
    # 切り分けもすり抜ける。Exit 要求でループを抜けたか（$exitLoop）から導出する。
    # $exitLoop は try 先頭で $false に初期化済みのため、ここでは常に定義されている。
    $stopReason = if ($exitLoop) { 'normal' } else { 'error' }
    Write-Log -EventName 'app.stop' -Data ([ordered]@{ reason = $stopReason })
    Close-Log

    [Environment]::Exit(0)
}
