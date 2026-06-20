# Get-UserAction のメインループから抽出したWebリクエスト処理。
# 戻り値: @{ ShouldContinue; ResultAction; ResultFile; ActionSetTime; ShuttingDown; ShutdownDeadline }
function Invoke-WebRequestProcessor {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$MainHtml,
        [string]$ProcessingHtml,
        [string]$ExitHtml,
        [System.Net.HttpListener]$Listener,
        [bool]$ShuttingDown,
        [object]$ResultAction,
        [object]$ShutdownDeadline
    )

    $req = $Context.Request
    $res = $Context.Response
    $url = $req.Url.LocalPath.ToLower()

    # --- 認証ミドルウェア ---
    $isAuthenticated = Test-IsAuthenticated -Request $req
    if (-not $isAuthenticated -and $url -ne "/auth" -and $url -ne "/status") {
        $authHtml = $script:HtmlTemplates.AuthView.Replace('%%BGCOLOR%%', '#0f2027').Replace('%%AUTH_ERROR%%', '')
        Send-HttpResponse -Response $res -Content $authHtml
        $script:ContextTask = Get-SafeContextAsync -Listener $Listener
        return @{ ShouldContinue = $true; ResultAction = $ResultAction; ResultFile = $null; ActionSetTime = $null; ShuttingDown = $ShuttingDown; ShutdownDeadline = $ShutdownDeadline }
    }

    # --- POSTボディ一括読み込み ---
    $body = $null
    if ($req.HttpMethod -eq "POST") {
        $body = Read-RequestBody -Request $req
    }

    # --- /auth POST ---
    if ($url -eq "/auth" -and $req.HttpMethod -eq "POST") {
        Invoke-AuthHandler -Request $req -Response $res -Body $body | Out-Null
        $script:ContextTask = Get-SafeContextAsync -Listener $Listener
        return @{ ShouldContinue = $true; ResultAction = $ResultAction; ResultFile = $null; ActionSetTime = $null; ShuttingDown = $ShuttingDown; ShutdownDeadline = $ShutdownDeadline }
    }

    # --- 認証済み GET /auth → / へリダイレクト ---
    if ($isAuthenticated -and $url -eq "/auth" -and $req.HttpMethod -eq "GET") {
        try {
            $res.StatusCode = 302
            $res.KeepAlive  = $false
            $res.AddHeader("Location", "/")
            $res.Close()
        } catch {}
        $script:ContextTask = Get-SafeContextAsync -Listener $Listener
        return @{ ShouldContinue = $false; ResultAction = $ResultAction; ResultFile = $null; ActionSetTime = $null; ShuttingDown = $ShuttingDown; ShutdownDeadline = $ShutdownDeadline }
    }

    $resHtml          = $MainHtml
    $newResultAction  = $ResultAction
    $newResultFile    = $null
    $newActionSetTime = $null
    $newShuttingDown  = $ShuttingDown
    $newShutdownDeadline = $ShutdownDeadline

    # --- /status ---
    if ($url -eq "/status") {
        $statusText = if ($ShuttingDown) {
            "stopping"
        } elseif ($ResultAction -ne $null) {
            "changing"
        } else {
            "waiting"
        }
        Send-HttpResponse -Response $res -Content $statusText -ContentType "text/plain"
        $script:ContextTask = Get-SafeContextAsync -Listener $Listener
        return @{ ShouldContinue = $true; ResultAction = $ResultAction; ResultFile = $null; ActionSetTime = $null; ShuttingDown = $ShuttingDown; ShutdownDeadline = $ShutdownDeadline }
    }

    # --- POST アクション ---
    if ($req.HttpMethod -eq "POST") {
        switch ($url) {
            "/start"  { $newResultAction = "Start"; $newActionSetTime = Get-Date; $resHtml = $ProcessingHtml }
            "/next"   { $newResultAction = "Next";  $newActionSetTime = Get-Date; $resHtml = $ProcessingHtml }
            "/retry"  { $newResultAction = "Retry"; $newActionSetTime = Get-Date; $resHtml = $ProcessingHtml }
            "/lobby"  { $newResultAction = "Lobby"; $newActionSetTime = Get-Date; $resHtml = $ProcessingHtml }
            "/exit"   {
                $now = Get-Date
                try {
                    $res.StatusCode = 303
                    $res.KeepAlive  = $false
                    $res.AddHeader("Location", "/exit")
                    $res.Close()
                } catch {}
                $script:ContextTask = Get-SafeContextAsync -Listener $Listener
                return @{
                    ShouldContinue   = $false
                    ResultAction     = "Exit"
                    ResultFile       = $null
                    ActionSetTime    = $now
                    ShuttingDown     = $true
                    ShutdownDeadline = $now.AddSeconds(5)
                }
            }
            "/select" {
                if ([System.Web.HttpUtility]::UrlDecode($body) -match "filename=(.*)") {
                    $newResultAction = "Select"; $newResultFile = $matches[1]; $newActionSetTime = Get-Date
                }
                $resHtml = $ProcessingHtml
            }
        }
    } elseif ($url -eq "/exit") {
        if ($ShuttingDown) {
            $resHtml = $ExitHtml
        } else {
            try {
                $res.StatusCode = 302
                $res.KeepAlive  = $false
                $res.AddHeader("Location", "/")
                $res.Close()
            } catch {}
            $script:ContextTask = Get-SafeContextAsync -Listener $Listener
            return @{ ShouldContinue = $false; ResultAction = $ResultAction; ResultFile = $null; ActionSetTime = $null; ShuttingDown = $ShuttingDown; ShutdownDeadline = $ShutdownDeadline }
        }
    }

    # --- 状態変化中のGETにはprocessing/exit画面を返す（他端末操作時のチカチカ防止） ---
    if ($req.HttpMethod -eq "GET" -and $url -ne "/status" -and $url -ne "/exit") {
        if ($ShuttingDown) {
            $resHtml = $ExitHtml
        } elseif ($ResultAction -ne $null) {
            $resHtml = $ProcessingHtml
        }
    }

    Send-HttpResponse -Response $res -Content $resHtml
    $script:ContextTask = Get-SafeContextAsync -Listener $Listener

    return @{
        ShouldContinue   = $false
        ResultAction     = $newResultAction
        ResultFile       = $newResultFile
        ActionSetTime    = $newActionSetTime
        ShuttingDown     = $newShuttingDown
        ShutdownDeadline = $newShutdownDeadline
    }
}
