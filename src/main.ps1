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
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrator privileges required. Please run PowerShell as Administrator."
    Start-Sleep 3
    exit
}

[ConsoleWindow]::DisableCloseButton()
try { [ConsoleWindow]::DisableQuickEdit() } catch {}
[console]::TreatControlCAsInput = $true

if (-not (Test-Path $TargetFolderPath)) { Write-Error "Target Folder Not Found"; exit }
$finishFolderPath = Join-Path $TargetFolderPath $FinishFolderName
if (-not (Test-Path $finishFolderPath)) { New-Item -Path $finishFolderPath -ItemType Directory | Out-Null }

Write-Host "Starting PowerPoint..." -ForegroundColor Cyan

# Snapshot pre-existing PowerPoint PIDs so we never bind/kill an operator's own instance.
$preExistingPptPids = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

$pptApp  = $null
$lastErr = $null
for ($i = 1; $i -le 3; $i++) {
    try { $pptApp = New-Object -ComObject PowerPoint.Application; break }
    catch { $lastErr = $_; if ($i -lt 3) { Start-Sleep -Milliseconds 1500 } }
}

# If still not up, optionally clear stale instances (opt-in) and retry once.
if (-not $pptApp) {
    $stale = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue)
    if ($stale.Count -gt 0 -and $KillStalePowerPoint) {
        Write-Warning "PowerPoint not responding. Clearing stale POWERPNT process(es) and retrying..."
        $stale | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 1000
        try { $pptApp = New-Object -ComObject PowerPoint.Application } catch { $lastErr = $_ }
    }
}

if (-not $pptApp) {
    $msg = if ($lastErr) { $lastErr.Exception.Message } else { "unknown error" }
    $hr  = if ($lastErr) { ("0x{0:X8}" -f $lastErr.Exception.HResult) } else { "n/a" }
    if ((Get-Process -Name POWERPNT -ErrorAction SilentlyContinue) -and -not $KillStalePowerPoint) {
        Write-Error "Failed to start PowerPoint: $msg (HRESULT $hr). A PowerPoint process is already running; re-run with -KillStalePowerPoint to clear it, or close it manually."
    } else {
        Write-Error "Failed to start PowerPoint: $msg (HRESULT $hr)"
    }
    exit
}

$pptApp.Visible = [Microsoft.Office.Core.MsoTriState]::msoTrue

# Bind only an instance WE spawned to a kill-on-close job (never the operator's own).
try {
    $pptPid = 0
    try { $pptPid = [JobGuard]::GetProcessIdFromHwnd([IntPtr]$pptApp.HWND) } catch {}
    if ($pptPid -le 0) {
        $newPids = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) |
                   Where-Object { $preExistingPptPids -notcontains $_ }
        if (@($newPids).Count -eq 1) { $pptPid = $newPids[0] }
    }
    if ($pptPid -gt 0 -and ($preExistingPptPids -notcontains $pptPid)) {
        [void][JobGuard]::Guard($pptPid)
    } else {
        Write-Host " [Info] Skipping kill-on-close binding (existing instance or PID unresolved)." -ForegroundColor DarkGray
    }
} catch {
    Write-Warning "Could not bind PowerPoint to kill-on-close job: $($_.Exception.Message)"
}

try {
    $exitLoop      = $false
    $autoPlayTarget = $null

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$WebPort/")
    try {
        $listener.Start()
        $script:ContextTask = Get-SafeContextAsync -Listener $listener
    } catch {
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
                }
            }
        }

        if (-not $targetFileItem) { continue }
        if ($exitLoop) { break }

        # --- B. プレゼン実行 ---
        $presentation = $null
        $status       = "NormalEnd"

        # PowerPointプロセスの生存確認と自動復旧
        try {
            $null = $pptApp.Name
            $null = $pptApp.Version
        } catch {
            Write-Host " [Warning] PowerPoint COM object is dead. Attempting recovery..." -ForegroundColor Yellow
            Release-ComObject -obj $pptApp
            $pptApp = $null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            try {
                $pptApp = New-Object -ComObject PowerPoint.Application
                $pptApp.Visible = [Microsoft.Office.Core.MsoTriState]::msoTrue
                Write-Host " [System] PowerPoint COM object recovered successfully." -ForegroundColor Green
            } catch {
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
            }

            # --- C. 移動判定 ---
            if ($targetFileItem.DirectoryName -ne $finishFolderPath) {
                try {
                    Write-Host " >> Moving to finished folder..." -ForegroundColor Gray
                    $targetFileItem = Move-Item -LiteralPath $targetFileItem.FullName -Destination $finishFolderPath -Force -PassThru
                } catch { Write-Warning "Move failed: $_" }
            }

            # --- D. 終了後の画面遷移 ---
            if ($status -eq "ManualStop") {
                $autoPlayTarget = $null
                continue
            }

            $activeFiles = Get-PptFiles -Path $TargetFolderPath
            $nextName    = if ($activeFiles) { $activeFiles[0].Name } else { "" }

            $postResult = Get-UserAction -Mode "Dialog" -CurrentFileName $targetFileItem.Name -NextFileName $nextName -Listener $listener

            switch ($postResult.Action) {
                "Next"  { if ($activeFiles) { $autoPlayTarget = $activeFiles[0] } }
                "Retry" { $autoPlayTarget = $targetFileItem }
                "Lobby" { $autoPlayTarget = $null }
                "Exit"  { $exitLoop = $true }
            }

        } catch {
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

    [Environment]::Exit(0)
}
