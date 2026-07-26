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
        Write-Log -EventName 'auth.throttled' -Level 'warn' -Ip $ip
        $authHtml = $script:HtmlTemplates.AuthView.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', 'error')
        Send-HttpResponse -Response $Response -Content $authHtml
        return $false
    }
    $submittedPin = Get-PinFromBody $Body
    if ($submittedPin -ne '' -and $submittedPin -eq [string]$script:AuthPin) {
        $script:AuthFailedTracker.Remove($ip)
        Write-Log -EventName 'auth.ok' -Ip $ip
        $Response.Headers.Add("Set-Cookie", "SessionToken=$script:SessionToken; HttpOnly; Path=/; SameSite=Strict")
        $Response.StatusCode = 302
        $Response.Headers.Add("Location", "/")
        Send-HttpResponse -Response $Response -Content ""
        return $true
    }
    $script:AuthFailedTracker[$ip] = (Get-Date)
    # 記録するのは「失敗した事実」と送信元 IP のみ。入力された PIN は決してログに載せない。
    Write-Log -EventName 'auth.fail' -Level 'warn' -Ip $ip
    $authHtml = $script:HtmlTemplates.AuthView.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', 'error')
    Send-HttpResponse -Response $Response -Content $authHtml
    return $false
}
