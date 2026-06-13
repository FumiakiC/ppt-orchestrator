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
try {
    $pptApp = New-Object -ComObject PowerPoint.Application
    $pptApp.Visible = [Microsoft.Office.Core.MsoTriState]::msoTrue
} catch {
    Write-Error "Failed to start PowerPoint"
    exit
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
