function Get-UserAction {
    param (
        [string]$Mode,
        [string]$CurrentFileName = "",
        [array]$ActiveFiles = @(),
        [array]$FinishedFiles = @(),
        [string]$NextFileName = "",
        [System.Net.HttpListener]$Listener
    )

    $currentPage  = 0
    $itemsPerPage = 9
    $cachedAdapters = Get-LocalActiveIPs

    function Show-ConsolePage {
        Clear-Host
        $adapters = $cachedAdapters
        $line = "━" * 70
        Write-Host $line -ForegroundColor DarkCyan
        Write-Host "  [ ppt-orchestrator ] " -ForegroundColor Cyan -NoNewline
        Write-Host "v1.0 - Presentation Controller" -ForegroundColor DarkGray
        Write-Host $line -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "   🔐 PIN CODE: " -NoNewline -ForegroundColor Yellow
        Write-Host $script:AuthPin -ForegroundColor White -BackgroundColor DarkRed
        Write-Host ""
        foreach ($adapter in $adapters) {
            Write-Host " [Web URL - $($adapter.InterfaceAlias)] http://$($adapter.IPAddress):$($WebPort)/" -ForegroundColor Yellow
        }
        Write-Host " [Status]   $Mode" -ForegroundColor White
        Write-Host ""
        Write-Host " --- PC Control Menu ---" -ForegroundColor Gray
        if ($Mode -eq "Lobby") {
            Write-Host " [Enter] Start" -ForegroundColor Green
            Write-Host " [1-9]   Select Slide by Number" -ForegroundColor Cyan

            $totalActiveFiles   = @($ActiveFiles).Count
            $totalFinishedFiles = @($FinishedFiles).Count
            $totalFiles = $totalActiveFiles + $totalFinishedFiles
            $totalPages = [Math]::Ceiling($totalFiles / $itemsPerPage)

            if ($totalPages -gt 1) {
                Write-Host " [N]     Next Page  [P] Previous Page" -ForegroundColor Magenta
            }
            Write-Host " [U]     Update Network Info" -ForegroundColor DarkYellow
            Write-Host " [Q]     Exit System" -ForegroundColor Red
            Write-Host "   * Note: To close a presentation, please click the 'X' button on the PowerPoint window." -ForegroundColor DarkGray
            Write-Host ""

            if ($totalPages -gt 1) {
                Write-Host " --- Available Slides (Page $($currentPage + 1)/$totalPages) ---" -ForegroundColor Gray
            } else {
                Write-Host " --- Available Slides ---" -ForegroundColor Gray
            }

            $startIdx = $currentPage * $itemsPerPage
            $endIdx   = $startIdx + $itemsPerPage - 1

            $displayIndex        = 1
            $currentFileIndex    = 0
            $activeSectionShown  = $false

            if (@($ActiveFiles).Count -gt 0) {
                foreach ($f in $ActiveFiles) {
                    if ($currentFileIndex -ge $startIdx -and $currentFileIndex -le $endIdx) {
                        if (-not $activeSectionShown) {
                            Write-Host " [Pending]" -ForegroundColor Green
                            $activeSectionShown = $true
                        }
                        Write-Host "  [$displayIndex] $($f.Name)" -ForegroundColor White
                        $displayIndex++
                    }
                    $currentFileIndex++
                }
            }

            $finishedSectionShown = $false
            if (@($FinishedFiles).Count -gt 0) {
                foreach ($f in $FinishedFiles) {
                    if ($currentFileIndex -ge $startIdx -and $currentFileIndex -le $endIdx) {
                        if (-not $finishedSectionShown) {
                            Write-Host " [Completed]" -ForegroundColor DarkGray
                            $finishedSectionShown = $true
                        }
                        Write-Host "  [$displayIndex] $($f.Name)" -ForegroundColor DarkGray
                        $displayIndex++
                    }
                    $currentFileIndex++
                }
            }
        } else {
            Write-Host " [Enter] Next" -ForegroundColor Green
            Write-Host " [R]     Retry" -ForegroundColor Yellow
            Write-Host " [L]     Back to Lobby" -ForegroundColor Cyan
            Write-Host " [U]     Update Network Info" -ForegroundColor DarkYellow
            Write-Host " [Q]     Exit System" -ForegroundColor Red
            Write-Host "   * Note: To close a presentation, please click the 'X' button on the PowerPoint window." -ForegroundColor DarkGray
            Write-Host ""
            Write-Host " --- Next Slide ---" -ForegroundColor Gray
            if ($NextFileName) {
                Write-Host "  $($NextFileName)" -ForegroundColor White
            } else {
                Write-Host "  (No more slides available)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
        Write-Host $line -ForegroundColor DarkCyan
        Write-Host "  Copyright (c) 2026 FumiakiC" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host " ▶ Waiting for command... (Press a key to execute immediately)" -ForegroundColor Green
        Write-Host "" -NoNewline
    }

    Show-ConsolePage
    $head = Get-HtmlHeader -Title "Controller" -BgColor $(if ($Mode -eq 'Lobby') { "#1a1a1a" } else { "#000000" })

    $bodyContent = ""
    if ($Mode -eq 'Lobby') {
        $nextTxt = if ($ActiveFiles) { [System.Web.HttpUtility]::HtmlEncode($ActiveFiles[0].Name) } else { "None" }
        $stBtn   = if ($ActiveFiles) { "" } else { "disabled style='opacity:0.5;'" }

        $listHtml = "<div class='list-scroll'>"
        $listHtml += "<div class='sec'><span class='tag tag-standby'>STANDBY</span> Pending</div>"
        if (!$ActiveFiles) { $listHtml += "<div class='empty'>No decks queued.</div>" }
        $idx = 0
        foreach ($f in $ActiveFiles) {
            $idx++
            $fname = [System.Web.HttpUtility]::HtmlEncode($f.Name)
            $listHtml += "<form method='post' action='/select' class='deck-form'><input type='hidden' name='filename' value='$fname'><button type='submit' class='deck'><span class='deck-badge'>$idx</span><span class='deck-name'>$fname</span><span class='deck-cue'>&#9654;</span></button></form>"
        }
        $listHtml += "<div class='sec'><span class='tag tag-done'>DONE</span> Completed</div>"
        if (!$FinishedFiles) { $listHtml += "<div class='empty'>None yet.</div>" }
        foreach ($f in $FinishedFiles) {
            $fname = [System.Web.HttpUtility]::HtmlEncode($f.Name)
            $listHtml += "<form method='post' action='/select' class='deck-form'><input type='hidden' name='filename' value='$fname'><button type='submit' class='deck finished'><span class='deck-badge'>&#10003;</span><span class='deck-name'>$fname</span></button></form>"
        }
        $listHtml += "</div>"

        $bodyContent = $script:HtmlTemplates.LobbyView -f $stBtn, $nextTxt, $listHtml
    } else {
        $nxtLbl = if ($NextFileName) { "Start Next Slide<br><span style='font-size:0.8rem;font-weight:normal'>$([System.Web.HttpUtility]::HtmlEncode($NextFileName))</span>" } else { "No slides in queue" }
        $nxtSt  = if ($NextFileName) { "" } else { "disabled style='opacity:0.5;'" }

        $bodyContent = $script:HtmlTemplates.DialogView -f ([System.Web.HttpUtility]::HtmlEncode($CurrentFileName)), $nxtSt, $nxtLbl
    }

    $mainHtml       = $head + $bodyContent + $script:HtmlTemplates.PollingScript + "</div></body></html>"
    $processingHtml = $head + $script:HtmlTemplates.ProcessingView
    $exitHtml       = $head + $script:HtmlTemplates.ExitView

    $resultAction    = $null
    $resultFile      = $null
    $actionSetTime   = $null
    $shuttingDown    = $false
    $shutdownDeadline = $null
    $waitingExitConfirm = $false

    # プレゼン中の誤操作防止：溜まっているキー入力バッファをクリア
    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

    while ($true) {

        # --- Web確認 ---
        if ($script:ContextTask -and $script:ContextTask.Wait(100)) {
            try {
                $context = $script:ContextTask.Result
            } catch {
                Write-Host " [Warning] Context read failed in UserAction: $($_.Exception.Message)" -ForegroundColor Yellow
                $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                continue
            }

            $webResult = Invoke-WebRequestProcessor `
                -Context         $context `
                -MainHtml        $mainHtml `
                -ProcessingHtml  $processingHtml `
                -ExitHtml        $exitHtml `
                -Listener        $Listener `
                -ShuttingDown    $shuttingDown `
                -ResultAction    $resultAction `
                -ShutdownDeadline $shutdownDeadline

            if ($webResult.ShouldContinue) { continue }

            $resultAction    = $webResult.ResultAction
            if ($webResult.ResultFile    -ne $null) { $resultFile      = $webResult.ResultFile }
            if ($webResult.ActionSetTime -ne $null) { $actionSetTime   = $webResult.ActionSetTime }
            $shuttingDown    = $webResult.ShuttingDown
            $shutdownDeadline = $webResult.ShutdownDeadline
        }

        # --- コンソール確認 ---
        if ((!$shuttingDown) -and ($resultAction -eq $null) -and [Console]::KeyAvailable) {
            $keyInfo = [Console]::ReadKey($true)
            $k = $keyInfo.Key.ToString().ToUpper()

            if ($waitingExitConfirm) {
                if ($k -eq "Y") {
                    $shuttingDown     = $true
                    $shutdownDeadline = (Get-Date).AddSeconds(5)
                    Write-Host ""
                    Write-Host " [System] Shutting down... (Notifying web clients / Will exit in 5 seconds)" -ForegroundColor Magenta
                } else {
                    $waitingExitConfirm = $false
                    Show-ConsolePage
                }
            } else {
                if ($k -eq "Q" -or $k -eq "ESCAPE" -or ($k -eq "C" -and $keyInfo.Modifiers -band [ConsoleModifiers]::Control)) {
                    $waitingExitConfirm = $true
                    Write-Host ""
                    Write-Host " Are you sure you want to exit? [Y] Confirm / [N] Cancel : " -ForegroundColor Yellow -NoNewline
                }

                if ($k -eq "U") {
                    Write-Host ""
                    Write-Host " [System] Updating network info..." -ForegroundColor DarkYellow
                    $cachedAdapters = Get-LocalActiveIPs
                    Start-Sleep -Milliseconds 300
                    Show-ConsolePage
                }

                if ($Mode -eq "Lobby") {
                    if ($k -eq "ENTER" -or $k -eq "S") {
                        if ($ActiveFiles -and @($ActiveFiles).Count -gt 0) {
                            $resultAction = "Start"; $actionSetTime = Get-Date
                        } else {
                            Write-Host ""
                            Write-Host " [System] No slides in queue. Press [1-9] to select a completed slide." -ForegroundColor DarkYellow
                            Start-Sleep -Milliseconds 3000
                            Show-ConsolePage
                        }
                    }

                    $totalActiveFiles   = @($ActiveFiles).Count
                    $totalFinishedFiles = @($FinishedFiles).Count
                    $totalFiles = $totalActiveFiles + $totalFinishedFiles
                    $totalPages = [Math]::Ceiling($totalFiles / $itemsPerPage)

                    if ($k -eq "N") {
                        if ($currentPage -lt ($totalPages - 1)) {
                            $currentPage++
                            Show-ConsolePage
                        }
                    } elseif ($k -eq "P") {
                        if ($currentPage -gt 0) {
                            $currentPage--
                            Show-ConsolePage
                        }
                    }

                    if ($k -match "^D([0-9])$" -or $k -match "^NUMPAD([0-9])$") {
                        $num = [int]$matches[1]
                        if ($num -ge 1 -and $num -le 9) {
                            $absoluteIndex = $currentPage * $itemsPerPage + ($num - 1)

                            $allFiles = @()
                            if ($ActiveFiles)  { $allFiles += $ActiveFiles }
                            if ($FinishedFiles) { $allFiles += $FinishedFiles }

                            if ($absoluteIndex -lt $allFiles.Count) {
                                $resultAction  = "Select"
                                $resultFile    = $allFiles[$absoluteIndex].Name
                                $actionSetTime = Get-Date
                            }
                        }
                    }
                } else {
                    if ($k -eq "ENTER" -or $k -eq "N") {
                        if ($NextFileName) {
                            $resultAction = "Next"; $actionSetTime = Get-Date
                        } else {
                            Write-Host ""
                            Write-Host " [System] No slides in queue. Please press [L] to go Back to Lobby, or [R] to Retry." -ForegroundColor DarkYellow
                            Start-Sleep -Milliseconds 3000
                            Show-ConsolePage
                        }
                    }
                    if ($k -eq "R") { $resultAction = "Retry"; $actionSetTime = Get-Date }
                    if ($k -eq "L" -or $k -eq "BACKSPACE") { $resultAction = "Lobby"; $actionSetTime = Get-Date }
                }
            }
        }

        # --- 終了判定 ---
        if ($resultAction -ne $null -and $resultAction -ne "Exit") {
            if ($actionSetTime -and ((Get-Date) - $actionSetTime).TotalMilliseconds -gt 800) {
                break
            }
        }
        if ($shuttingDown -and $shutdownDeadline) {
            if ((Get-Date) -gt $shutdownDeadline) {
                $resultAction = "Exit"
                break
            }
        }
    }

    return @{ Action = $resultAction; FileName = $resultFile }
}
