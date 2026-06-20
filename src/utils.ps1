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
