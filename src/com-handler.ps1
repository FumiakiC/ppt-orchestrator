function Test-SlideShowAtEnd {
    # 最終スライドかつ未消化のビルド（アニメーション）が無いときだけ $true。
    # GetClickIndex/GetClickCount が使えない環境では位置のみで判定（フォールバック）。
    param([object]$View, [int]$Pos, [int]$Total)
    if ($Total -le 0 -or $Pos -lt $Total) { return $false }
    try {
        $ci = [int]$View.GetClickIndex()
        $cc = [int]$View.GetClickCount()
        return ($ci -ge $cc)
    } catch {
        return $true
    }
}

function Watch-RunningPresentation {
    param (
        [object]$PptApp,
        [object]$TargetFileItem,
        [System.Net.HttpListener]$Listener
    )

    $head     = Get-HtmlHeader -Title "Now Playing" -BgColor "#000000"
    # NowPlayingView は単一ブレースのテンプレート。デッキ名はトークン置換で注入する（-f を使わない）。
    $bodyHtml = $script:HtmlTemplates.NowPlayingView.Replace(
        '%%DECK%%', [System.Web.HttpUtility]::HtmlEncode($TargetFileItem.Name))
    $fullHtml = $head + $bodyHtml

    $status = "NormalEnd"

    # ---- リモート操作のサーバ権威ステート（この再生セッションのローカル＝全端末で共有） ----
    # 再生が終わるとスコープごと破棄され、次の再生ではロック解除済みの状態から始まる（安全側）。
    $lockActive  = $false        # ロック（操作可能モード）が有効か
    $ownerCid    = ''            # 現在の操作権を持つ端末ID（1台のみ）
    $ownerSeen   = [DateTime]::UtcNow
    $ownerTtlSec = 15            # 操作端末が無反応のとき自動解放するまでの秒数
    $projBlack   = $false        # 暗転中か
    $projWhite   = $false        # ホワイトアウト中か
    $totalSlides = 0             # スライド総数（初回のみCOM取得してキャッシュ）
    $showSeen    = $false       # スライドショー投影ウィンドウを一度でも観測したか（編集復帰検知用）
    $startupGraceSec = 20        # 起動直後にウィンドウ未検出でも終了扱いしない猶予秒

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

                # ---- クライアントID(cid) の抽出（POSTボディ or GETクエリ） ----
                $cid = ''
                if ($req.HttpMethod -eq "POST") {
                    $reqBody = $null
                    if ($req.HasEntityBody) {
                        $encoding = if ($req.ContentEncoding) { $req.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
                        $sr = New-Object System.IO.StreamReader($req.InputStream, $encoding)
                        try { $reqBody = $sr.ReadToEnd() } finally { $sr.Dispose() }
                    }
                    if ($reqBody -and ([System.Web.HttpUtility]::UrlDecode($reqBody) -match 'cid=([A-Za-z0-9_\-]+)')) {
                        $cid = $matches[1]
                    }
                } else {
                    $qcid = $req.QueryString['cid']
                    if ($qcid) { $cid = $qcid }
                }

                # ---- 失効した操作権の自動解放（無反応TTL超過） ----
                if ($lockActive -and (([DateTime]::UtcNow - $ownerSeen).TotalSeconds -gt $ownerTtlSec)) {
                    $lockActive = $false
                    $ownerCid   = ''
                }

                if ($path -eq "/status") {
                    Send-HttpResponse -Response $res -Content "running" -ContentType "text/plain"
                }
                elseif ($path -eq "/elapsed") {
                    $ms = [long][Math]::Floor(([DateTime]::UtcNow - $startTime).TotalMilliseconds)
                    Send-HttpResponse -Response $res -Content "$ms" -ContentType "text/plain"
                }
                elseif ($path -eq "/slide/state") {
                    # 現在位置(N/M)を取得（COMアクセスは最小限：位置1プロパティ＋総数は初回のみ）
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

                    $mine = ($lockActive -and $cid -and ($ownerCid -eq $cid))
                    if ($mine) { $ownerSeen = [DateTime]::UtcNow }   # ハートビート（操作端末の生存更新）

                    $atEnd = $false
                    try {
                        if ($PptApp.SlideShowWindows.Count -ge 1) {
                            $atEnd = [bool](Test-SlideShowAtEnd -View $PptApp.SlideShowWindows.Item(1).View -Pos $pos -Total $totalSlides)
                        }
                    } catch {}

                    $ms = [long][Math]::Floor(([DateTime]::UtcNow - $startTime).TotalMilliseconds)
                    $payload = @{
                        ms    = $ms
                        pos   = $pos
                        total = $totalSlides
                        lock  = [bool]$lockActive
                        mine  = [bool]$mine
                        black = [bool]$projBlack
                        white = [bool]$projWhite
                        atEnd = [bool]$atEnd
                    } | ConvertTo-Json -Compress
                    Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                }
                elseif ($path -eq "/lock/on" -and $req.HttpMethod -eq "POST") {
                    if ((-not $lockActive) -or ($ownerCid -eq $cid)) {
                        $lockActive = $true; $ownerCid = $cid; $ownerSeen = [DateTime]::UtcNow
                        $payload = @{ ok = $true; mine = $true; busy = $false } | ConvertTo-Json -Compress
                    } else {
                        $payload = @{ ok = $false; mine = $false; busy = $true } | ConvertTo-Json -Compress
                    }
                    Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                }
                elseif ($path -eq "/lock/steal" -and $req.HttpMethod -eq "POST") {
                    # 明示的な操作権の奪取（バックアップ端末向け。誤爆防止のためUI側は長押し必須）
                    $lockActive = $true; $ownerCid = $cid; $ownerSeen = [DateTime]::UtcNow
                    $payload = @{ ok = $true; mine = $true } | ConvertTo-Json -Compress
                    Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                }
                elseif ($path -eq "/lock/off" -and $req.HttpMethod -eq "POST") {
                    if ($ownerCid -eq $cid) { $lockActive = $false; $ownerCid = '' }
                    $payload = @{ ok = $true } | ConvertTo-Json -Compress
                    Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                }
                elseif (($path -like '/slide/*') -and $req.HttpMethod -eq "POST") {
                    $cmd = $path.Substring(7)   # '/slide/'.Length = 7
                    $valid = @('next','prev','first','last','blackout','whiteout')
                    if ($valid -notcontains $cmd) {
                        $payload = @{ ok = $false; error = 'unknown' } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                    elseif (-not ($lockActive -and $cid -and ($ownerCid -eq $cid))) {
                        # ロックOFF or 操作権が他端末 → サーバ側で拒否（多層防御）
                        $payload = @{ ok = $false; locked = $true } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                    else {
                        $ownerSeen = [DateTime]::UtcNow   # 操作＝ハートビート
                        $ok = $false
                        try {
                            if ($PptApp.SlideShowWindows.Count -ge 1) {
                                $view = $PptApp.SlideShowWindows.Item(1).View
                                switch ($cmd) {
                                    'next'  {
                                        $cp = 0; try { $cp = [int]$view.CurrentShowPosition } catch {}
                                        if (-not (Test-SlideShowAtEnd -View $view -Pos $cp -Total $totalSlides)) {
                                            $view.Next(); $projBlack = $false; $projWhite = $false
                                        }
                                    }
                                    'prev'  { $view.Previous(); $projBlack = $false; $projWhite = $false }
                                    'first' { $view.First();    $projBlack = $false; $projWhite = $false }
                                    'last'  { $view.Last();     $projBlack = $false; $projWhite = $false }
                                    'blackout' {
                                        if ($projBlack) { $view.State = 1; $projBlack = $false }   # 1=running(復帰)
                                        else            { $view.State = 3; $projBlack = $true; $projWhite = $false }  # 3=black
                                    }
                                    'whiteout' {
                                        if ($projWhite) { $view.State = 1; $projWhite = $false }
                                        else            { $view.State = 4; $projWhite = $true; $projBlack = $false }  # 4=white
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

                        $atEnd = $false
                        try {
                            if ($PptApp.SlideShowWindows.Count -ge 1) {
                                $atEnd = [bool](Test-SlideShowAtEnd -View $PptApp.SlideShowWindows.Item(1).View -Pos $pos -Total $totalSlides)
                            }
                        } catch {}

                        $payload = @{
                            ok    = [bool]$ok; locked = $false
                            pos   = $pos; total = $totalSlides
                            black = [bool]$projBlack; white = [bool]$projWhite
                            atEnd = [bool]$atEnd
                        } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                }
                elseif ($path -eq "/stop" -and $req.HttpMethod -eq "POST") {
                    $status = "ManualStop"
                    try {
                        $res.StatusCode = 302
                        $res.KeepAlive  = $false
                        $res.AddHeader("Location", "/")
                        $res.Close()
                    } catch {}
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    break
                }
                else {
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

            # ---- スライドショー終了（編集画面復帰）検知 ----
            # ファイルは開いたままでも、投影ウィンドウが消えたら「終了」とみなして Dialog を出す。
            $showCount = -1
            try { $showCount = [int]$PptApp.SlideShowWindows.Count } catch { $showCount = -1 }
            if ($showCount -ge 1) {
                $showSeen = $true
            }
            elseif ($showCount -eq 0) {
                $sinceStart = ([DateTime]::UtcNow - $startTime).TotalSeconds
                if ($showSeen -or ($sinceStart -gt $startupGraceSec)) {
                    $status = "NormalEnd"
                    break
                }
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
