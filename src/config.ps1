param(
    [string]$TargetFolderPath = $(
        $cwd = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
        if (Get-ChildItem -Path $cwd -Filter '*.pptx' -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $cwd
        } elseif ($PSScriptRoot) {
            Split-Path $PSScriptRoot -Parent
        } else {
            $cwd
        }
    ),
    [string]$FinishFolderName = "finish",
    [int]$WebPort = 8090,
    [string]$StatePath = (Join-Path $env:ProgramData 'ppt-orchestrator\session.json')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Web

if (-not ("ConsoleWindow" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ConsoleWindow {
    [DllImport("kernel32.dll", ExactSpelling = true)]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

    [DllImport("user32.dll")]
    public static extern int RemoveMenu(IntPtr hMenu, int nPosition, int wFlags);

    public const int SC_CLOSE = 0xF060;
    public const int MF_BYCOMMAND = 0x00000000;

    public static void DisableCloseButton() {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd != IntPtr.Zero) {
            IntPtr hMenu = GetSystemMenu(hWnd, false);
            if (hMenu != IntPtr.Zero) {
                RemoveMenu(hMenu, SC_CLOSE, MF_BYCOMMAND);
            }
        }
    }
}
"@
}

# --- Daily-persistent PIN / session token (admin-only state file) ---
function New-SecurePin {
    # Cryptographically secure, uniform 6-digit PIN (100000-999999), rejection-sampled to avoid modulo bias
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    try {
        $range = [uint32]900000
        $limit = [uint32]([uint32]::MaxValue - ([uint32]::MaxValue % $range))
        do {
            $bytes = [byte[]]::new(4)
            $rng.GetBytes($bytes)
            $val = [System.BitConverter]::ToUInt32($bytes, 0)
        } while ($val -ge $limit)
        return [int](100000 + ($val % $range))
    } finally { $rng.Dispose() }
}

$today     = (Get-Date).ToString('yyyy-MM-dd')
$loadedPin = $null
$loadedTok = $null
try {
    if (Test-Path -LiteralPath $StatePath) {
        $state = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($state.Date -eq $today -and $state.Pin -and $state.Token) {
            $loadedPin = [int]$state.Pin
            $loadedTok = [string]$state.Token
        }
    }
} catch {
    $loadedPin = $null; $loadedTok = $null   # corrupt/unreadable -> regenerate
}

if ($loadedPin -and $loadedTok) {
    $script:AuthPin      = $loadedPin
    $script:SessionToken = $loadedTok
} else {
    $script:AuthPin      = New-SecurePin
    $script:SessionToken = [guid]::NewGuid().ToString('N')
    try {
        $dir = Split-Path -Parent $StatePath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # restrict the folder to Administrators + SYSTEM (break inheritance)
        try {
            $acl = New-Object System.Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($sidStr in @('S-1-5-32-544','S-1-5-18')) {
                $sid  = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $dir -AclObject $acl
        } catch { Write-Host " [Warning] Could not harden state-folder ACL: $($_.Exception.Message)" -ForegroundColor Yellow }

        $payload = [ordered]@{ Date = $today; Pin = $script:AuthPin; Token = $script:SessionToken } | ConvertTo-Json
        Set-Content -LiteralPath $StatePath -Value $payload -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host " [Warning] Could not persist session state (using in-memory values for this run): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
$script:LastAuthFailedTime  = [DateTime]::MinValue
$script:ContextTask         = $null
