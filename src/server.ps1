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
    $isAuthPost = ($url -eq "/auth" -and $req.HttpMethod -eq "POST")
    if (-not $isAuthenticated -and -not $isAuthPost -and $url -ne "/status") {
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

    # --- GET 正規化 ---
    # URLバーを常に / に固定する。/status 以外のすべてのGETパス
    # （/auth・/exit の旧特例を含む）は 302 で / へ戻す。
    # 未認証は先頭の認証ミドルウェアが AuthView を返すため、ここへは認証済みのみ到達する。
    if ($req.HttpMethod -eq "GET" -and $url -ne "/" -and $url -ne "/status") {
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
    # Processing HTML を 200 で直接返すと URL バーがアクションパスのまま残り、
    # その画面のリロードが POST 再送信（アクション二重発火）になり得るため、
    # 常に 303 で / へ戻し、状態に応じた画面は GET / 側の分岐に委ねる。
    # 依存: リダイレクト先の GET / が Processing を受け取れるのは、ui-console.ps1 の
    # 「アクション確定後 800ms はループを抜けない」猶予の内に届くため。猶予を縮めないこと。
    if ($req.HttpMethod -eq "POST") {
        switch ($url) {
            "/start"  { $newResultAction = "Start"; $newActionSetTime = Get-Date }
            "/next"   { $newResultAction = "Next";  $newActionSetTime = Get-Date }
            "/retry"  { $newResultAction = "Retry"; $newActionSetTime = Get-Date }
            "/lobby"  { $newResultAction = "Lobby"; $newActionSetTime = Get-Date }
            "/exit"   {
                $now = Get-Date
                $newResultAction = "Exit"
                $newActionSetTime = $now
                $newShuttingDown = $true
                $newShutdownDeadline = $now.AddSeconds(5)
            }
            "/select" {
                if ([System.Web.HttpUtility]::UrlDecode($body) -match "filename=(.*)") {
                    $newResultAction = "Select"; $newResultFile = $matches[1]; $newActionSetTime = Get-Date
                }
            }
        }

        try {
            $res.StatusCode = 303
            $res.KeepAlive  = $false
            $res.AddHeader("Location", "/")
            $res.Close()
        } catch {}
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

    # --- GET / の状態表示 ---
    # ここへ到達するのは GET / のみ（/status・POST・他パス GET は上で応答済み）。
    # 他端末操作時のチカチカ防止のため、状態変化中は本体でなく Processing を返す。
    if ($ShuttingDown) {
        $resHtml = $ExitHtml
    } elseif ($ResultAction -ne $null) {
        $resHtml = $ProcessingHtml
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
