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
    $currentTime = Get-Date
    if ($currentTime -lt $script:LastAuthFailedTime.AddSeconds(1)) {
        $authHtml = $script:HtmlTemplates.AuthView -f "#0f2027", "error"
        Send-HttpResponse -Response $Response -Content $authHtml
        return $false
    }
    if ($Body) {
        if ([System.Web.HttpUtility]::UrlDecode($Body) -match "pin=([0-9]{6})") {
            $submittedPin = $matches[1]
            if ($submittedPin -eq $script:AuthPin.ToString()) {
                $Response.Headers.Add("Set-Cookie", "SessionToken=$script:SessionToken; HttpOnly; Path=/; SameSite=Strict")
                $Response.StatusCode = 302
                $Response.Headers.Add("Location", "/")
                Send-HttpResponse -Response $Response -Content ""
                return $true
            }
        }
    }
    $script:LastAuthFailedTime = Get-Date
    $authHtml = $script:HtmlTemplates.AuthView -f "#0f2027", "error"
    Send-HttpResponse -Response $Response -Content $authHtml
    return $false
}
