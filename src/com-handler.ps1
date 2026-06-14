function Watch-RunningPresentation {
    param (
        [object]$PptApp,
        [object]$TargetFileItem,
        [System.Net.HttpListener]$Listener
    )

    $head     = Get-HtmlHeader -Title "Now Playing" -BgColor "#000000"
    $bodyHtml = $script:HtmlTemplates.NowPlayingView.Replace(
        '%%DECK%%', [System.Web.HttpUtility]::HtmlEncode($TargetFileItem.Name))
    $fullHtml = $head + $bodyHtml

    $status = "NormalEnd"

    $projBlack   = $false
    $projWhite   = $false
    $totalSlides = 0

    try {
        $isFileOpen = $true
        $startTime = [DateTime]::UtcNow
        while ($isFileOpen) {

            # 1. Webリクエスト確認
            if ($script:ContextTask -and $script:ContextTask.Wait(100)) {
                try {
                    $context = $script:ContextTask.Result
                } catch {
                    Write-Host " [Warning] Context read failed in Watch: $($_.Exception.Message)" -ForegroundColor Yellow
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    continue
                }
                $req  = $context.Request
                $res  = $context.Response
                $path = $req.Url.LocalPath.ToLower()

                $isAuthenticated = Test-IsAuthenticated -Request $req

                if (-not $isAuthenticated -and $path -ne "/status" -and $path -ne "/auth") {
                    $authHtml = $script:HtmlTemplates.AuthView -f "#0f2027", ""
                    Send-HttpResponse -Response $res -Content $authHtml
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    continue
                }

                if ($path -eq "/auth" -and $req.HttpMethod -eq "POST") {
                    $authBody = $null
                    if ($req.HasEntityBody) {
                        $encoding = if ($req.ContentEncoding) { $req.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
                        $sr = New-Object System.IO.StreamReader($req.InputStream, $encoding)
                        try {
                            $authBody = $sr.ReadToEnd()
                        } finally {
                            $sr.Dispose()
                        }
                    }
                    Invoke-AuthHandler -Request $req -Response $res -Body $authBody | Out-Null
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    continue
                }

                if ($path -eq "/status") {
                    Send-HttpResponse -Response $res -Content "running" -ContentType "text/plain"
                } elseif ($path -eq "/elapsed") {
                    $ms = [long][Math]::Floor(([DateTime]::UtcNow - $startTime).TotalMilliseconds)
                    Send-HttpResponse -Response $res -Content "$ms" -ContentType "text/plain"
                } elseif ($path -eq "/slide/state") {
                    $pos = 0
                    try {
                        if ($PptApp.SlideShowWindows.Count -ge 1) {
                            $view = $PptApp.SlideShowWindows.Item(1).View
                            $pos  = [int]$view.CurrentShowPosition
                            if ($totalSlides -le 0) {
                                $totalSlides = [int]$PptApp.SlideShowWindows.Item(1).Presentation.Slides.Count
                            }
                        }
                    } catch {}
                    $ms = [long][Math]::Floor(([DateTime]::UtcNow - $startTime).TotalMilliseconds)
                    $payload = @{
                        ms    = $ms
                        pos   = $pos
                        total = $totalSlides
                        black = [bool]$projBlack
                        white = [bool]$projWhite
                    } | ConvertTo-Json -Compress
                    Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                } elseif (($path -like '/slide/*') -and $req.HttpMethod -eq "POST") {
                    $cmd   = $path.Substring(7)   # '/slide/'.Length = 7
                    $valid = @('next','prev','first','last','blackout','whiteout')
                    if ($valid -notcontains $cmd) {
                        $payload = @{ ok = $false; error = 'unknown' } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    } else {
                        $ok = $false
                        try {
                            if ($PptApp.SlideShowWindows.Count -ge 1) {
                                $view = $PptApp.SlideShowWindows.Item(1).View
                                switch ($cmd) {
                                    'next'     { $view.Next();     $projBlack = $false; $projWhite = $false }
                                    'prev'     { $view.Previous(); $projBlack = $false; $projWhite = $false }
                                    'first'    { $view.First();    $projBlack = $false; $projWhite = $false }
                                    'last'     { $view.Last();     $projBlack = $false; $projWhite = $false }
                                    'blackout' {
                                        if ($projBlack) { $view.State = 1; $projBlack = $false }
                                        else            { $view.State = 3; $projBlack = $true; $projWhite = $false }
                                    }
                                    'whiteout' {
                                        if ($projWhite) { $view.State = 1; $projWhite = $false }
                                        else            { $view.State = 4; $projWhite = $true; $projBlack = $false }
                                    }
                                }
                                $ok = $true
                            }
                        } catch {
                            Write-Host " [Warning] Slide control '$cmd' failed: $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                        $pos = 0
                        try {
                            if ($PptApp.SlideShowWindows.Count -ge 1) {
                                $pos = [int]$PptApp.SlideShowWindows.Item(1).View.CurrentShowPosition
                                if ($totalSlides -le 0) {
                                    $totalSlides = [int]$PptApp.SlideShowWindows.Item(1).Presentation.Slides.Count
                                }
                            }
                        } catch {}
                        $payload = @{
                            ok    = [bool]$ok
                            pos   = $pos
                            total = $totalSlides
                            black = [bool]$projBlack
                            white = [bool]$projWhite
                        } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                } elseif ($path -eq "/stop" -and $req.HttpMethod -eq "POST") {
                    $status = "ManualStop"
                    try {
                        $res.StatusCode = 302
                        $res.KeepAlive  = $false
                        $res.AddHeader("Location", "/")
                        $res.Close()
                    } catch {}
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    break
                } else {
                    Send-HttpResponse -Response $res -Content $fullHtml
                }

                $script:ContextTask = Get-SafeContextAsync -Listener $Listener
            }

            # 2. PowerPointの状態確認
            $stillOpen = $false
            try {
                $null = $PptApp.Presentations.Count
                foreach ($p in $PptApp.Presentations) {
                    if ($p.FullName -eq $TargetFileItem.FullName) {
                        $stillOpen = $true
                        break
                    }
                }
            } catch {
                # HResult ベースの判定で OS 言語に依存しない堅牢なエラー分類
                $hr = $_.Exception.HResult
                if (-not $hr -and $_.Exception.InnerException) {
                    $hr = $_.Exception.InnerException.HResult
                }
                # 0x80010001 (RPC_E_CALL_REJECTED) / 0x800A175D (PPT busy/enum error)
                $transientHResults = @(
                    [int]0x80010001,  # RPC_E_CALL_REJECTED
                    [int]0x800A175D   # PowerPoint enumeration error
                )
                if ($hr -and ($transientHResults -contains $hr)) {
                    $stillOpen = $true
                    Write-Host " [Warning] COM transient error (HResult: 0x$($hr.ToString('X8')), presentation assumed still open)" -ForegroundColor Yellow
                } else {
                    $stillOpen = $false
                    Write-Host " [Warning] COM fatal error (HResult: $(if($hr){'0x'+$hr.ToString('X8')}else{'N/A'}), presentation assumed closed): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }

            if (-not $stillOpen) {
                $status = "NormalEnd"
                break
            }
        }
    } finally {
        # HttpListener はメインフロー内で一元管理するため、ここでは Stop/Close しない
    }

    return $status
}

function Set-PptKillOnClose {
    param(
        [object]$PptApp,
        [int[]]$PreExistingPids = @()
    )
    # Bind only an instance WE spawned to a kill-on-close job (never the operator's own).
    try {
        $pptPid = 0
        try { $pptPid = [JobGuard]::GetProcessIdFromHwnd([IntPtr]$PptApp.HWND) } catch {}
        if ($pptPid -le 0) {
            $candidatePids = @(Get-Process -Name POWERPNT -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) |
                             Where-Object { $PreExistingPids -notcontains $_ }
            if (@($candidatePids).Count -eq 1) { $pptPid = $candidatePids[0] }
        }
        if ($pptPid -gt 0 -and ($PreExistingPids -notcontains $pptPid)) {
            [void][JobGuard]::Guard($pptPid)
        } else {
            Write-Host " [Info] Skipping kill-on-close binding (existing instance or PID unresolved)." -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "Could not bind PowerPoint to kill-on-close job: $($_.Exception.Message)"
    }
}
