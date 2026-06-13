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
    [string]$StatePath = (Join-Path $env:ProgramData 'ppt-orchestrator\session.json'),
    [switch]$KillStalePowerPoint
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

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

    public const int  STD_INPUT_HANDLE      = -10;
    public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    public const uint ENABLE_EXTENDED_FLAGS  = 0x0080;

    public static void DisableQuickEdit() {
        IntPtr h = GetStdHandle(STD_INPUT_HANDLE);
        uint mode;
        if (h != IntPtr.Zero && h != (IntPtr)(-1) && GetConsoleMode(h, out mode)) {
            mode = (mode & ~ENABLE_QUICK_EDIT_MODE) | ENABLE_EXTENDED_FLAGS;
            SetConsoleMode(h, mode);
        }
    }
}
"@
}

if (-not ("JobGuard" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class JobGuard {
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public Int64 PerProcessUserTimeLimit;
        public Int64 PerJobUserTimeLimit;
        public UInt32 LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public UInt32 ActiveProcessLimit;
        public UIntPtr Affinity;
        public UInt32 PriorityClass;
        public UInt32 SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS {
        public UInt64 ReadOperationCount;
        public UInt64 WriteOperationCount;
        public UInt64 OtherOperationCount;
        public UInt64 ReadTransferCount;
        public UInt64 WriteTransferCount;
        public UInt64 OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    static extern IntPtr CreateJobObject(IntPtr a, string lpName);
    [DllImport("kernel32.dll")]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpInfo, uint cbLen);
    [DllImport("kernel32.dll")]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr hObject);
    [DllImport("user32.dll", SetLastError=true)]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    const int  JobObjectExtendedLimitInformation = 9;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    const uint PROCESS_TERMINATE  = 0x0001;
    const uint PROCESS_SET_QUOTA  = 0x0100;

    // Held open for the controller's whole lifetime; when the process exits the handle
    // closes and the kill-on-close job terminates the assigned PowerPoint.
    static IntPtr _job = IntPtr.Zero;

    public static int GetProcessIdFromHwnd(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return 0;
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return (int)pid;
    }

    public static bool Guard(int pid) {
        if (_job == IntPtr.Zero) {
            _job = CreateJobObject(IntPtr.Zero, null);
            if (_job == IntPtr.Zero) return false;
            var ext = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            ext.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            int len = Marshal.SizeOf(ext);
            IntPtr p = Marshal.AllocHGlobal(len);
            try {
                Marshal.StructureToPtr(ext, p, false);
                if (!SetInformationJobObject(_job, JobObjectExtendedLimitInformation, p, (uint)len)) {
                    CloseHandle(_job);
                    _job = IntPtr.Zero;
                    return false;
                }
            } finally {
                Marshal.FreeHGlobal(p);
            }
        }
        IntPtr hProc = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, false, pid);
        if (hProc == IntPtr.Zero) return false;
        try { return AssignProcessToJobObject(_job, hProc); }
        finally { CloseHandle(hProc); }
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

        # Only harden the parent directory if it is the default ProgramData\ppt-orchestrator folder.
        # Hardening an arbitrary user-specified directory (e.g. Documents) could corrupt its permissions.
        $isDefaultDir = ($dir -eq (Join-Path $env:ProgramData 'ppt-orchestrator'))
        if (-not $isDefaultDir) {
            Write-Host " [Warning] Custom -StatePath in use; hardening the state FILE only, not the parent folder. Use an admin-only location." -ForegroundColor Yellow
        }
        if ($isDefaultDir) {
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
        }

        $payload = [ordered]@{ Date = $today; Pin = $script:AuthPin; Token = $script:SessionToken } | ConvertTo-Json

        # Delete any pre-existing file so the recreated file inherits the secure ACL instead of preserving a weak one.
        if (Test-Path -LiteralPath $StatePath) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
        Set-Content -LiteralPath $StatePath -Value $payload -Encoding UTF8 -ErrorAction Stop

        # If the parent folder was NOT hardened (custom path), harden the file itself.
        if (-not $isDefaultDir) {
            try {
                $fileAcl = New-Object System.Security.AccessControl.FileSecurity
                $fileAcl.SetAccessRuleProtection($true, $false)
                foreach ($sidStr in @('S-1-5-32-544','S-1-5-18')) {
                    $sid  = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')
                    $fileAcl.AddAccessRule($rule)
                }
                Set-Acl -LiteralPath $StatePath -AclObject $fileAcl
            } catch { Write-Host " [Warning] Could not harden state-file ACL: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    } catch {
        Write-Host " [Warning] Could not persist session state (using in-memory values for this run): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
$script:AuthFailedTracker   = @{}
$script:ContextTask         = $null
