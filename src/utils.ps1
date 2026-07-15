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
    return Get-ChildItem -Path $Path -File | Where-Object { $_.Extension -in @('.ppt', '.pptx') -and $_.Name -notlike '~$*' } | Sort-Object Name
}

function Move-ToFinishIfPending {
    param(
        [object]$TargetFileItem,
        [string]$FinishFolderPath,
        [object]$Presentation
    )

    if (-not $TargetFileItem -or -not $TargetFileItem.FullName) { return $TargetFileItem }

    # Idempotent guard: skip when source no longer exists or is already in finish folder.
    if (-not (Test-Path -LiteralPath $TargetFileItem.FullName)) { return $TargetFileItem }
    if ($TargetFileItem.DirectoryName -eq $FinishFolderPath) { return $TargetFileItem }

    # Close an open presentation before move to avoid file lock sharing violations.
    if ($Presentation) {
        try { $Presentation.Close() } catch {}
    }

    try {
        Write-Host " >> Moving to finished folder..." -ForegroundColor Gray
        return Move-Item -LiteralPath $TargetFileItem.FullName -Destination $FinishFolderPath -Force -PassThru
    } catch {
        Write-Warning "Move failed: $_"
        return $TargetFileItem
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
