function Watch-RunningPresentation {
    param (
        [object]$PptApp,
        [object]$TargetFileItem,
        [System.Net.HttpListener]$Listener
    )

    $head     = Get-HtmlHeader -Title "Now Playing" -BgColor "#000000"
    $bodyHtml = $script:HtmlTemplates.NowPlayingView -f ([System.Web.HttpUtility]::HtmlEncode($TargetFileItem.Name))
    $fullHtml = $head + $bodyHtml

    $status = "NormalEnd"

    try {
        $isFileOpen = $true
        $startTime = Get-Date
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
                    $sec = [int]([Math]::Floor(((Get-Date) - $startTime).TotalSeconds))
                    Send-HttpResponse -Response $res -Content "$sec" -ContentType "text/plain"
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
