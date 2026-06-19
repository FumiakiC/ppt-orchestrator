function Test-IsAuthenticated {
    param([System.Net.HttpListenerRequest]$Request)
    if ($Request.Cookies["SessionToken"]) {
        return ($Request.Cookies["SessionToken"].Value -eq $script:SessionToken)
    }
    return $false
}

function Invoke-AuthHandler {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Body
    )
    $ip = if ($Request.RemoteEndPoint) { $Request.RemoteEndPoint.Address.ToString() } else { "unknown" }

    foreach ($k in @($script:AuthFailedTracker.Keys)) {
        if (((Get-Date) - $script:AuthFailedTracker[$k]).TotalSeconds -gt 30) { $script:AuthFailedTracker.Remove($k) }
    }

    if ($script:AuthFailedTracker.ContainsKey($ip) -and (Get-Date) -lt $script:AuthFailedTracker[$ip].AddSeconds(1)) {
        $authHtml = $script:HtmlTemplates.AuthView.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', 'error')
        Send-HttpResponse -Response $Response -Content $authHtml
        return $false
    }
    if ($Body) {
        if ([System.Web.HttpUtility]::UrlDecode($Body) -match "pin=([0-9]{6})") {
            $submittedPin = $matches[1]
            if ($submittedPin -eq $script:AuthPin.ToString()) {
                $script:AuthFailedTracker.Remove($ip)
                $Response.Headers.Add("Set-Cookie", "SessionToken=$script:SessionToken; HttpOnly; Path=/; SameSite=Strict")
                $Response.StatusCode = 302
                $Response.Headers.Add("Location", "/")
                Send-HttpResponse -Response $Response -Content ""
                return $true
            }
        }
    }
    $script:AuthFailedTracker[$ip] = (Get-Date)
    $authHtml = $script:HtmlTemplates.AuthView.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', 'error')
    Send-HttpResponse -Response $Response -Content $authHtml
    return $false
}
