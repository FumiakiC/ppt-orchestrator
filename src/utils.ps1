function Get-LocalActiveIPs {
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq "Up" -and
            -not $_.Virtual -and
            $_.InterfaceAlias -notlike "*Loopback*" -and
            $_.InterfaceAlias -notlike "*vEthernet*" -and
            $_.InterfaceAlias -notlike "*VMware*" -and
            $_.InterfaceAlias -notlike "*VirtualBox*" -and
            $_.InterfaceAlias -notlike "*Tailscale*" -and
            $_.InterfaceAlias -notlike "*ZeroTier*" -and
            $_.InterfaceDescription -notlike "*Loopback*" -and
            $_.InterfaceDescription -notlike "*vEthernet*" -and
            $_.InterfaceDescription -notlike "*VMware*" -and
            $_.InterfaceDescription -notlike "*VirtualBox*" -and
            $_.InterfaceDescription -notlike "*Tailscale*" -and
            $_.InterfaceDescription -notlike "*ZeroTier*"
        }

        $results = @()
        foreach ($adapter in $adapters) {
            $ipAddresses = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
                $_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "0.0.0.0"
            }

            foreach ($ipAddr in $ipAddresses) {
                $results += @{
                    InterfaceAlias = $adapter.InterfaceAlias
                    IPAddress = $ipAddr.IPAddress
                }
            }
        }

        if ($results.Count -eq 0) {
            $results = @(@{ InterfaceAlias = "Local"; IPAddress = "localhost" })
        }

        return $results
    } catch {
        return @(@{ InterfaceAlias = "Local"; IPAddress = "localhost" })
    }
}

function Release-ComObject {
    param([object]$obj)
    if ($obj) { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) | Out-Null } catch {} }
}

function Get-PptFiles {
    param([string]$Path)
    return Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -in @('.ppt', '.pptx') -and $_.Name -notlike '~$*' } | Sort-Object Name
}

function Resolve-FinishDestination {
    param(
        [string]$FileName,
        [object[]]$ExistingNames,
        [datetime]$Timestamp
    )

    $existing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $ExistingNames) {
        if ($null -ne $name) { [void]$existing.Add([string]$name) }
    }

    if (-not $existing.Contains($FileName)) { return $FileName }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)
    $stamp = $Timestamp.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)

    $candidate = "${baseName}_$stamp$extension"
    if (-not $existing.Contains($candidate)) { return $candidate }

    $counter = 2
    while ($true) {
        $candidate = "${baseName}_$stamp-$counter$extension"
        if (-not $existing.Contains($candidate)) { return $candidate }
        $counter++
    }
}

function Move-ToFinishIfPending {
    param(
        [object]$TargetFileItem,
        [string]$FinishFolderPath,
        [object]$Presentation,
        [int[]]$RetryDelaysMs = @(200, 400, 800)
    )

    if (-not $TargetFileItem -or -not $TargetFileItem.FullName) { return $TargetFileItem }

    $sourcePath = [string]$TargetFileItem.FullName
    $sourceFileName = if ($TargetFileItem.Name) { [string]$TargetFileItem.Name } else { [System.IO.Path]::GetFileName($sourcePath) }

    # Idempotent guard: skip when source no longer exists or is already in finish folder.
    if (-not (Test-Path -LiteralPath $sourcePath)) { return $TargetFileItem }
    if ($TargetFileItem.DirectoryName -eq $FinishFolderPath) { return $TargetFileItem }

    # Close an open presentation before move to avoid file lock sharing violations.
    if ($Presentation) {
        try { $Presentation.Close() } catch {}
    }

    $delays = if ($null -eq $RetryDelaysMs) { @() } else { @($RetryDelaysMs) }

    try {
        $existingNames = Get-ChildItem -LiteralPath $FinishFolderPath -File -ErrorAction Stop | ForEach-Object { $_.Name }
        $destinationName = Resolve-FinishDestination -FileName $sourceFileName -ExistingNames $existingNames -Timestamp (Get-Date)
        # Do not WildcardPattern::Escape here: -Destination receives a literal path, and escaping would corrupt file names like deck[1].pptx.
        $destinationPath = Join-Path -Path $FinishFolderPath -ChildPath $destinationName
    } catch {
        # 帰結はリトライ全滅と同じ「元ファイル未移動」なので同じ file.finish.fail を使い、
        # stage で「移動前の移動先解決段階で失敗した」ことを区別する。
        Write-Log -EventName 'file.finish.fail' -Level 'error' -Data ([ordered]@{ msg = $_.Exception.Message; stage = 'resolve' })
        Write-Warning "Resolve finish destination failed: $($_.Exception.Message)"
        return $TargetFileItem
    }

    Write-Host " >> Moving to finished folder..." -ForegroundColor Gray
    for ($attempt = 0; $attempt -le $delays.Count; $attempt++) {
        try {
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                # リトライ発行後にソースが消えた（他所で移動/削除された）場合は終端イベントを残す。
                # file.finish.retry の後に ok / fail のどちらも無いとログ欠落に見えるため。
                # attempt 0 での消失はループ前の冪等ガードと同じ扱い（記録しない）。
                if ($attempt -gt 0) {
                    Write-Log -EventName 'file.finish.fail' -Level 'error' -Data ([ordered]@{ msg = 'source-missing' })
                }
                return $TargetFileItem
            }

            $moved = Move-Item -LiteralPath $sourcePath -Destination $destinationPath -PassThru -ErrorAction Stop
            # renamed = 同名衝突でタイムスタンプ名になったか（Resolve-FinishDestination の結果を使い回す）。
            Write-Log -EventName 'file.finish.ok' -Data ([ordered]@{ dest = $destinationName; renamed = ($destinationName -ne $sourceFileName) })
            return $moved
        } catch {
            if ($attempt -ge $delays.Count) {
                Write-Log -EventName 'file.finish.fail' -Level 'error' -Data ([ordered]@{ msg = $_.Exception.Message })
                Write-Warning "Move failed: $($_.Exception.Message)"
                return $TargetFileItem
            }

            $delay = [int]$delays[$attempt]
            # attempt は 1 始まりで記録する（辞書 §4.6：200/400/800ms の 3 回）。
            Write-Log -EventName 'file.finish.retry' -Level 'warn' -Data ([ordered]@{ attempt = ($attempt + 1); delayMs = $delay })
            if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
        }
    }
}

function Send-HttpResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$Content,
        [string]$ContentType = "text/html; charset=utf-8"
    )

    try {
        if ($Response.OutputStream.CanWrite) {
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)
            $Response.ContentType = $ContentType
            $Response.ContentLength64 = $buffer.Length
            $Response.KeepAlive = $false
            $Response.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
            $Response.AddHeader("Pragma", "no-cache")
            $Response.AddHeader("Expires", "0")
            $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
    } catch {
        # クライアントが切断されているため、エラーを出さずに無視してよい
    } finally {
        try { $Response.Close() } catch {}
    }
}

function Get-SafeContextAsync {
    param([System.Net.HttpListener]$Listener)
    while ($true) {
        try {
            if (-not $Listener.IsListening) {
                return $null
            }
        } catch [System.ObjectDisposedException] {
            return $null
        }
        try {
            return $Listener.GetContextAsync()
        } catch [System.ObjectDisposedException] {
            return $null
        } catch {
            Write-Host " [Warning] GetContextAsync failed, retrying... $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500
        }
    }
}

function Get-HtmlHeader {
    param([string]$Title, [string]$BgColor = "#1a1a1a")
    return $script:HtmlTemplates.HtmlHeader.Replace('%%TITLE%%', [string]$Title).Replace('%%BGCOLOR%%', [string]$BgColor)
}

function Get-CidFromBody {
    param([string]$Body)
    if ($Body -and ([System.Web.HttpUtility]::UrlDecode($Body) -match 'cid=([A-Za-z0-9_\-]+)')) { return $matches[1] }
    return ''
}

function Get-PinFromBody {
    param([string]$Body)
    if ($Body -and ([System.Web.HttpUtility]::UrlDecode($Body) -match 'pin=([0-9]{6})')) { return $matches[1] }
    return ''
}

function Read-RequestBody {
    # $MaxChars: 文字数ベースの上限。DoS閾値として十分（正規利用は数百バイト、最悪のマルチバイトでも
    # 数十KBに収まりメモリ枯渇を防ぐ）。厳密なバイト制限は本PRのスコープ外。
    param([System.Net.HttpListenerRequest]$Request, [int]$MaxChars = 8192)
    if ($null -eq $Request -or -not $Request.HasEntityBody) { return '' }
    $sr = $null
    try {
        $encoding = if ($Request.ContentEncoding) { $Request.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
        $sr = New-Object System.IO.StreamReader($Request.InputStream, $encoding)
        $limit = $MaxChars + 1
        $buf   = New-Object char[] $limit
        $total = 0
        while ($total -lt $limit) {
            $n = $sr.Read($buf, $total, $limit - $total)
            if ($n -le 0) { break }
            $total += $n
        }
        if ($total -gt $MaxChars) { return '' }
        if ($total -le 0) { return '' }
        return (-join $buf[0..($total - 1)])
    } catch {
        return ''
    } finally {
        if ($null -ne $sr) { $sr.Dispose() }
    }
}

function Format-LogEvent {
    # 1本の NDJSON 行（文字列）を組み立てる純粋関数。COM / HttpListener / ファイル IO に触れない。
    # Resolve-Route / Resolve-FinishDestination の [pscustomobject] 返却パターンは踏襲せず、
    # ここでは ConvertTo-Json -Compress で必ず「1行の文字列」を返す（呼び出し側 Write-Log が
    # そのまま WriteLine するため）。
    #   - $Timestamp に既定値は付けない: 付けると引数省略時に内部で時刻を取得することになり
    #     純粋関数でなくなる。呼び出し側（Write-Log）が必ず値を渡す。
    #   - $EventName は $Event（PowerShell 自動変数）と衝突するため使用不可。
    #   - $Data は [ordered]@{} を受けたいので [hashtable] ではなく [System.Collections.IDictionary]。
    #   - cid / ip / d はキーごと条件付きで足す（空/未指定なら“キー自体”を出さない）。
    param(
        [Parameter(Mandatory)][datetime]$Timestamp,
        [Parameter(Mandatory)][long]$ElapsedMs,
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][int]$Seq,
        [ValidateSet('info','warn','error')][string]$Level = 'info',
        [Parameter(Mandatory)][string]$EventName,
        [string]$Cid,
        [string]$Ip,
        [System.Collections.IDictionary]$Data
    )

    # ts は InvariantCulture 固定で 'yyyy-MM-ddTHH:mm:ss.fffzzz'（ロケール依存の桁/区切りを排除）。
    $ts = $Timestamp.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz', [System.Globalization.CultureInfo]::InvariantCulture)

    # フィールド順序を固定（ts, t, sid, seq, lvl, ev）。以降の cid/ip/d は条件付きで末尾に足す。
    $rec = [ordered]@{
        ts  = $ts
        t   = $ElapsedMs
        sid = $Sid
        seq = $Seq
        lvl = $Level
        ev  = $EventName
    }

    # 空文字 / $null のときはキー自体を出さない（存在しないメタは行に含めない）。
    if (-not [string]::IsNullOrEmpty($Cid)) { $rec['cid'] = $Cid }
    if (-not [string]::IsNullOrEmpty($Ip))  { $rec['ip']  = $Ip }
    # 空 Data（未指定 or 0件）のときは 'd' を出さない。
    if ($null -ne $Data -and $Data.Count -gt 0) { $rec['d'] = $Data }

    # -Compress で1行化、-Depth 5 で入れ子（配列/辞書）を潰さず保持する。
    return ($rec | ConvertTo-Json -Compress -Depth 5)
}

function Resolve-Route {
    # HTTP パス + メソッド → ルート種別を返す純粋関数（COM / HttpListener に触れない）。
    # 分類順序は Watch-RunningPresentation の従来の if/elseif チェーンと 1:1 で一致させること。
    #   Kind : 'auth'|'status'|'elapsed'|'slide-state'|'lock-on'|'lock-steal'|'lock-off'|'slide'|'stop'|'other'
    #   Cmd  : Kind='slide' のときのみ有効（'/slide/' 以降の文字列）
    #   Valid: Kind='slide' のときのみ有効（許可コマンド集合に含まれるか）
    param (
        [string]$Path,
        [string]$Method
    )

    $p      = if ($Path) { $Path.ToLower() } else { '' }
    $isPost = ($Method -eq 'POST')
    $kind   = 'other'
    $cmd    = ''
    $valid  = $false

    if     ($p -eq '/auth'        -and $isPost) { $kind = 'auth' }
    elseif ($p -eq '/status')                   { $kind = 'status' }        # 現状メソッド非依存（挙動保存）
    elseif ($p -eq '/elapsed')                  { $kind = 'elapsed' }       # 現状メソッド非依存（挙動保存）
    elseif ($p -eq '/slide/state')              { $kind = 'slide-state' }   # '/slide/*' より必ず先に判定
    elseif ($p -eq '/lock/on'     -and $isPost) { $kind = 'lock-on' }
    elseif ($p -eq '/lock/steal'  -and $isPost) { $kind = 'lock-steal' }
    elseif ($p -eq '/lock/off'    -and $isPost) { $kind = 'lock-off' }
    elseif (($p -like '/slide/*') -and $isPost) {
        $kind  = 'slide'
        $cmd   = $p.Substring(7)   # '/slide/'.Length = 7
        $valid = (@('next','prev','first','last','blackout','whiteout') -contains $cmd)
    }
    elseif ($p -eq '/stop'        -and $isPost) { $kind = 'stop' }

    return [pscustomobject]@{ Kind = $kind; Cmd = $cmd; Valid = $valid }
}
