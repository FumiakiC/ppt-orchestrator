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

    $status = "SlideshowExited"

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

    # ---- ログ用の差分キャッシュ（COM を追加で叩かないための保持専用） ----
    # 既に計算済みの位置/投影状態を覚えておき、show.slide の差分判定に使う。
    # ここで COM を読みに行かないこと（1周あたりの COM 呼び出し回数を増やさない）。
    $lastPos     = 0             # 直近に観測したスライド位置（show.slide の from）
    $lastBlack   = $false        # 直近に観測した暗転状態
    $lastWhite   = $false        # 直近に観測したホワイトアウト状態
    $transientStreak = 0         # 連続した COM 過渡エラーの件数（先頭1件だけ記録し、残りは件数で集約）

    Write-Log -EventName 'show.start' -Data ([ordered]@{ deck = $TargetFileItem.Name })

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
                $path  = $req.Url.LocalPath.ToLower()
                $route = Resolve-Route -Path $path -Method $req.HttpMethod

                $isAuthenticated = Test-IsAuthenticated -Request $req

                if (-not $isAuthenticated -and $path -ne "/status" -and $route.Kind -ne 'auth') {
                    if ($path -like '/slide/*' -or $path -like '/lock/*') {
                        # XHRで叩くAPIには401を返し、クライアント側で再認証へ誘導する
                        try { $res.StatusCode = 401 } catch {}
                        Send-HttpResponse -Response $res -Content '{"ok":false,"auth":false}' -ContentType "application/json; charset=utf-8"
                    } else {
                        # 通常のページ遷移には従来どおり認証ページ(200)を返す
                        $authHtml = $script:HtmlTemplates.AuthView.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', '')
                        Send-HttpResponse -Response $res -Content $authHtml
                    }
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    continue
                }

                if ($route.Kind -eq 'auth') {
                    $authBody = Read-RequestBody -Request $req
                    Invoke-AuthHandler -Request $req -Response $res -Body $authBody | Out-Null
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                    continue
                }

                # ---- クライアントID(cid) の抽出（POSTボディ or GETクエリ） ----
                $cid = ''
                if ($req.HttpMethod -eq "POST") {
                    $reqBody = Read-RequestBody -Request $req
                    $cid = Get-CidFromBody $reqBody
                } else {
                    $qcid = $req.QueryString['cid']
                    if ($qcid) { $cid = $qcid }
                }

                # ---- 失効した操作権の自動解放（無反応TTL超過） ----
                if ($lockActive -and (([DateTime]::UtcNow - $ownerSeen).TotalSeconds -gt $ownerTtlSec)) {
                    # cid を付けない＝サーバ起因の解放。端末が明示的に離した lock.release と区別する。
                    Write-Log -EventName 'lock.expire' -Data ([ordered]@{ from = $ownerCid; idleSec = $ownerTtlSec })
                    $lockActive = $false
                    $ownerCid   = ''
                }

                $stopRequested = $false

                switch ($route.Kind) {
                    'status' {
                        Send-HttpResponse -Response $res -Content "running" -ContentType "text/plain"
                    }
                    'elapsed' {
                        $ms = [long][Math]::Floor(([DateTime]::UtcNow - $startTime).TotalMilliseconds)
                        Send-HttpResponse -Response $res -Content "$ms" -ContentType "text/plain"
                    }
                    'slide-state' {
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
                        # PowerPoint 本体側で直接操作された場合もここで位置を拾えるため、
                        # 次の show.slide の from が実態とずれないよう記録なしで同期する。
                        $lastPos = $pos
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
                    'lock-on' {
                        if ((-not $lockActive) -or ($ownerCid -eq $cid)) {
                            # 同一端末による再取得はハートビート相当なので記録しない（新規取得のみ）。
                            if (-not $lockActive) {
                                Write-Log -EventName 'lock.acquire' -Cid $cid -Data ([ordered]@{ from = ''; to = $cid })
                            }
                            $lockActive = $true; $ownerCid = $cid; $ownerSeen = [DateTime]::UtcNow
                            $payload = @{ ok = $true; mine = $true; busy = $false } | ConvertTo-Json -Compress
                        } else {
                            $payload = @{ ok = $false; mine = $false; busy = $true } | ConvertTo-Json -Compress
                        }
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                    'lock-steal' {
                        # 明示的な操作権の奪取（バックアップ端末向け。誤爆防止のためUI側は長押し必須）
                        # 記録は代入より前に行う（$ownerCid が上書きされる前の値が from に必要）。
                        Write-Log -EventName 'lock.steal' -Level 'warn' -Cid $cid -Data ([ordered]@{ from = $ownerCid; to = $cid })
                        $lockActive = $true; $ownerCid = $cid; $ownerSeen = [DateTime]::UtcNow
                        $payload = @{ ok = $true; mine = $true } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                    'lock-off' {
                        if ($ownerCid -eq $cid) {
                            # $ownerCid を空にする前に記録する（解放した端末を from で残すため）。
                            Write-Log -EventName 'lock.release' -Cid $cid -Data ([ordered]@{ from = $ownerCid })
                            $lockActive = $false; $ownerCid = ''
                        }
                        $payload = @{ ok = $true } | ConvertTo-Json -Compress
                        Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                    }
                    'slide' {
                        $cmd = $route.Cmd
                        if (-not $route.Valid) {
                            $payload = @{ ok = $false; error = 'unknown' } | ConvertTo-Json -Compress
                            Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                        }
                        elseif (-not ($lockActive -and $cid -and ($ownerCid -eq $cid))) {
                            # ロックOFF or 操作権が他端末 → サーバ側で拒否（多層防御）
                            # 拒否は正常な多層防御の結果であり通常は記録しない。'all' のときだけ
                            # 「押したのに効かなかった」の追跡用に残す。
                            if ($script:SlideLogMode -eq 'all') {
                                Write-Log -EventName 'show.slide' -Level 'warn' -Cid $cid -Data ([ordered]@{ cmd = $cmd; rejected = 'locked'; owner = $ownerCid })
                            }
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

                            # 変化判定を位置だけで行わないこと。blackout / whiteout は位置を
                            # 変えずに投影状態を変えるため、位置比較だけだと暗転操作が記録から消える。
                            $slideChanged = ($pos -ne $lastPos) -or ($projBlack -ne $lastBlack) -or ($projWhite -ne $lastWhite)
                            if ($script:SlideLogMode -eq 'all' -or $slideChanged) {
                                Write-Log -EventName 'show.slide' -Cid $cid -Data ([ordered]@{
                                    cmd = $cmd; from = $lastPos; to = $pos
                                    black = [bool]$projBlack; white = [bool]$projWhite; ok = [bool]$ok
                                })
                            }
                            $lastPos = $pos; $lastBlack = $projBlack; $lastWhite = $projWhite

                            $payload = @{
                                ok    = [bool]$ok; locked = $false
                                pos   = $pos; total = $totalSlides
                                black = [bool]$projBlack; white = [bool]$projWhite
                                atEnd = [bool]$atEnd
                            } | ConvertTo-Json -Compress
                            Send-HttpResponse -Response $res -Content $payload -ContentType "application/json; charset=utf-8"
                        }
                    }
                    'stop' {
                        # 権限モデル: lock/owner チェックは意図的に省略する。
                        # /stop は「認証済みなら任意の端末が打てる緊急停止」であり、lock（＝後付けの
                        # スライド操作権＝運転席の受け渡し）には依存しない。'slide' がゲート有りなのと
                        # 対照的だが、これは設計判断であって漏れではない。owner 必須にすると操作権の
                        # 奪取を経由できてしまい、緊急停止としての有効性も落ちるため採用しない。
                        # 誤操作は UI の 1500ms hold と停止後の 302 リダイレクトで緩和する。
                        # 事後解析用に show.stop を記録する（誰が押したかは cid / ip で追う）。
                        $status = "ManualStop"
                        Write-Log -EventName 'show.stop' -Cid $cid -Ip $(if ($req.RemoteEndPoint) { $req.RemoteEndPoint.Address.ToString() } else { '' })
                        try {
                            $res.StatusCode = 302
                            $res.KeepAlive  = $false
                            $res.AddHeader("Location", "/")
                            $res.Close()
                        } catch {}
                        $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                        $stopRequested = $true   # switch 内の break は while を抜けないため flag 経由
                    }
                    default {
                        # URL バーを常に / に固定する。認証済み GET /auth が Lobby ループと異なり
                        # 302 しなかった旧非対称もこれで解消。
                        if ($path -eq '/') {
                            Send-HttpResponse -Response $res -Content $fullHtml
                        } else {
                            $code = if ($req.HttpMethod -eq 'POST') { 303 } else { 302 }
                            try {
                                $res.StatusCode = $code
                                $res.KeepAlive  = $false
                                $res.AddHeader("Location", "/")
                                $res.Close()
                            } catch {}
                        }
                    }
                }

                if ($stopRequested) { break }

                $script:ContextTask = Get-SafeContextAsync -Listener $Listener
            }

            # Webリスナー未起動/停止時のフロアスリープ。ContextTaskが$nullのとき
            # .Wait(100)が効かずビジーループ化しCPUを焼くのを防止。生存時は再アーム。
            if (-not $script:ContextTask) {
                Start-Sleep -Milliseconds 100
                if ($Listener -and $Listener.IsListening) {
                    $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                }
            }

            # 2. PowerPointの状態確認
            $stillOpen = $false
            $sawTransient = $false
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
                    # 先頭1件だけ記録する。この catch は再生中ループの毎周（10〜20回/秒）走りうるため、
                    # 毎回記録すると 90 分で最大 5 万行に達し、events が数百行という前提が崩れる。
                    # 抑制した分は復帰時の com.recovery が suppressed 件数としてまとめて残す。
                    $sawTransient = $true
                    if ($transientStreak -eq 0) {
                        Write-Log -EventName 'com.transient' -Level 'warn' -Data ([ordered]@{ hr = ('0x' + $hr.ToString('X8')) })
                    }
                    $transientStreak++
                    Write-Host " [Warning] COM transient error (HResult: 0x$($hr.ToString('X8')), presentation assumed still open)" -ForegroundColor Yellow
                } else {
                    $stillOpen = $false
                    Write-Log -EventName 'com.fatal' -Level 'error' -Data ([ordered]@{
                        hr = $(if ($hr) { '0x' + $hr.ToString('X8') } else { $null })
                        afterTransient = $transientStreak
                        msg = $_.Exception.Message
                    })
                    # 件数は afterTransient に載せたので streak を閉じる。ここで 0 に戻さないと
                    # 直後の復帰判定が成立し、fatal の次の行に偽の com.recovery が出る。
                    $transientStreak = 0
                    Write-Host " [Warning] COM fatal error (HResult: $(if($hr){'0x'+$hr.ToString('X8')}else{'N/A'}), presentation assumed closed): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }

            # 過渡エラーが続いた後、この周で catch に入らなかった＝復帰。抑制した件数をここで残す。
            if ($transientStreak -gt 0 -and -not $sawTransient) {
                Write-Log -EventName 'com.recovery' -Level 'warn' -Data ([ordered]@{ suppressed = $transientStreak })
                $transientStreak = 0
            }

            if (-not $stillOpen) {
                $status = "ClosedByUser"
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
                    $status = "SlideshowExited"
                    break
                }
            }
        }
    } finally {
        # HttpListener はメインフロー内で一元管理するため、ここでは Stop/Close しない
    }

    # 中断か完走かは reason だけでは読めないため、終了時点の位置と総数を併記する
    # （例: 200枚中43枚目で ClosedByUser ＝中断）。
    Write-Log -EventName 'show.end' -Data ([ordered]@{ reason = $status; pos = $lastPos; total = $totalSlides })

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
            Write-Log -EventName 'ppt.guard' -Data ([ordered]@{ pid = $pptPid; bound = $true })
        } else {
            Write-Host " [Info] Skipping kill-on-close binding (existing instance or PID unresolved)." -ForegroundColor DarkGray
            # bound=false は「異常終了時に PowerPoint が残る」ことを意味するため、事後解析で重要。
            Write-Log -EventName 'ppt.guard' -Data ([ordered]@{ pid = $pptPid; bound = $false })
        }
    } catch {
        Write-Warning "Could not bind PowerPoint to kill-on-close job: $($_.Exception.Message)"
        Write-Log -EventName 'ppt.guard' -Level 'warn' -Data ([ordered]@{ bound = $false; msg = $_.Exception.Message })
    }
}
