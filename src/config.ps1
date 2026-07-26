param(
    [ValidateNotNullOrEmpty()]
    [string]$TargetFolderPath = $(
        $cwd = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
        if (Get-ChildItem -LiteralPath $cwd -Filter '*.pptx' -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $cwd
        } elseif ($PSScriptRoot) {
            Split-Path $PSScriptRoot -Parent
        } else {
            $cwd
        }
    ),
    [string]$FinishFolderName = "finish",
    [int]$WebPort = 8090,
    [ValidateNotNullOrEmpty()]
    [string]$StatePath = (Join-Path $env:ProgramData 'ppt-orchestrator\session.json'),
    [ValidateSet('change','all')][string]$SlideLogMode = 'change',
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

function Protect-StateAcl {
    param([Parameter(Mandatory)][string]$Path)
    # Harden ACL to Administrators (S-1-5-32-544) + SYSTEM (S-1-5-18), inheritance broken.
    # Default ProgramData\ppt-orchestrator -> harden the folder; custom path -> harden the file only.
    try {
        $dir = Split-Path -Parent $Path
        $isDefaultDir = ($dir -eq (Join-Path $env:ProgramData 'ppt-orchestrator'))
        if ($isDefaultDir) {
            $acl = New-Object System.Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($sidStr in @('S-1-5-32-544','S-1-5-18')) {
                $sid  = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $dir -AclObject $acl
        } elseif (Test-Path -LiteralPath $Path) {
            $fileAcl = New-Object System.Security.AccessControl.FileSecurity
            $fileAcl.SetAccessRuleProtection($true, $false)
            foreach ($sidStr in @('S-1-5-32-544','S-1-5-18')) {
                $sid  = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')
                $fileAcl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $Path -AclObject $fileAcl
        }
    } catch {
        Write-Host " [Warning] Could not (re)harden state ACL: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function New-DirectoryIfMissing {
    # Defined here (not utils.ps1) because config.ps1 is concatenated first and its
    # top-level state block below calls this at load time, before utils.ps1 exists.
    # New-Item has no -LiteralPath, so bracketed paths would be treated as wildcards.
    # .NET CreateDirectory is literal, idempotent, and creates intermediate directories.
    # Called unconditionally on purpose: a Test-Path guard would be a TOCTOU race, and it
    # also reports True for an existing *file*, which would silently skip creation and
    # defer the failure to a later, vaguer error. CreateDirectory fails here instead.
    # The raw .NET message ('The file ... already exists.') does not say a folder was being
    # created, so it is rethrown with context. Rethrow (not Write-Error + exit) is required:
    # the state-file caller catches this and degrades to a warning instead of aborting.
    param([ValidateNotNullOrEmpty()][string]$Path)
    try {
        [void][System.IO.Directory]::CreateDirectory($Path)
    } catch {
        $reason = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        throw "Could not create folder '$Path'. A file with the same name may already exist, or the location may not be writable. ($reason)"
    }
}

# --- Append-only NDJSON logging foundation ---
# Defined here (not utils.ps1) because config.ps1 is concatenated first; keeping the
# writer state and lifecycle functions together with New-DirectoryIfMissing (which
# Open-LogFile depends on) avoids forward references at load time.
# This block only *defines* the machinery. No execution path is instrumented yet;
# call sites (Write-Log invocations) are intentionally added in a later change.
$script:LogSchema = 1                # bump when the NDJSON line shape changes
$script:LogWriter = $null           # [System.IO.StreamWriter] or $null when closed
$script:LogDir    = $null           # directory that holds the dated log files
$script:LogDate   = $null           # 'yyyyMMdd' of the currently open file (rollover key)
$script:LogSid    = $null           # session id stamped on every line ('<date>-<HHmmss>')
$script:LogStart  = $null           # [datetime] baseline for the per-line elapsed (t) field
$script:LogSeq    = 0               # monotonically increasing line counter (see Write-Log)
$script:LogWarned = $false          # ensures the write-failure warning is emitted at most once
$script:LogMeta   = $null           # log.meta payload replayed at the start of each opened file

function Open-LogFile {
    # (Re)opens the dated log file for append. Called by Initialize-Log and, on a date
    # change, by Write-Log to perform day-boundary rollover. Closes any previous writer.
    param([Parameter(Mandatory)][string]$Date)
    Close-Log
    New-DirectoryIfMissing -Path $script:LogDir
    $path = Join-Path $script:LogDir ("events-{0}.jsonl" -f $Date)
    # append=true: never truncate an existing day's file (multiple runs share one file).
    # UTF8Encoding($false): NO BOM — a BOM in the middle of an append-only stream would
    #   corrupt the line-delimited format, so it must be suppressed (unlike the .ps1 files).
    # AutoFlush=true: each WriteLine reaches the OS immediately so a crash keeps prior
    #   lines. This is a buffer flush, NOT a physical disk sync (Flush(true)); the latter
    #   is deliberately avoided as unnecessary and costly for a diagnostic log.
    $enc = New-Object System.Text.UTF8Encoding($false)
    $sw  = New-Object System.IO.StreamWriter($path, $true, $enc)
    $sw.AutoFlush = $true
    $script:LogWriter = $sw
    $script:LogDate   = $Date
    if ($script:LogMeta) { Write-Log -EventName 'log.meta' -Data $script:LogMeta }
}

function Initialize-Log {
    # Establishes session identity and opens today's file. Safe to call once at startup.
    param(
        [Parameter(Mandatory)][string]$Directory,
        [System.Collections.IDictionary]$Meta
    )
    $now = Get-Date
    $script:LogDir   = $Directory
    $script:LogMeta  = $Meta
    $script:LogStart = $now
    $script:LogSid   = $now.ToString('yyyyMMdd-HHmmss')
    $script:LogSeq   = 0
    try {
        Open-LogFile -Date $now.ToString('yyyyMMdd')
    } catch {
        $script:LogWriter = $null
        Write-Host " [Warning] Logging is disabled for this run: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
}

function Write-Log {
    # Formats one NDJSON line via the pure Format-LogEvent and appends it.
    param(
        [Parameter(Mandatory)][string]$EventName,
        [ValidateSet('info','warn','error')][string]$Level = 'info',
        [string]$Cid,
        [string]$Ip,
        [System.Collections.IDictionary]$Data
    )
    if ($null -eq $script:LogWriter) { return }
    $now = Get-Date
    try {
        # Day-boundary rollover: switch to the new dated file before writing. This is inside
        # the logging catch so rollover/open failures are also diagnostic-only failures.
        # Do this before taking the event seq because Open-LogFile intentionally emits its
        # own log.meta line through Write-Log for the newly opened file.
        $date = $now.ToString('yyyyMMdd')
        if ($date -ne $script:LogDate) { Open-LogFile -Date $date }
        # Increment BEFORE attempting the line write so a failed WriteLine leaves a *gap*
        # in the seq sequence rather than silently reusing a number.
        $script:LogSeq++
        $seq = $script:LogSeq
        $elapsed = [long]($now - $script:LogStart).TotalMilliseconds
        $line = Format-LogEvent -Timestamp $now -ElapsedMs $elapsed -Sid $script:LogSid `
            -Seq $seq -Level $Level -EventName $EventName -Cid $Cid -Ip $Ip -Data $Data
        $script:LogWriter.WriteLine($line)
    } catch {
        # Intentional swallow: logging is a diagnostic side channel and must never break
        # the presentation flow. There is deliberately no 'log.write.fail' event — if we
        # cannot write, we cannot write that either. Warn once on the host (best effort)
        # so the operator has a hint, then stay silent to avoid flooding the console.
        if (-not $script:LogWarned) {
            $script:LogWarned = $true
            Write-Host " [Warning] Logging disabled after write failure: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Close-Log {
    # Flushes and releases the writer. Idempotent; safe to call when already closed.
    # Keep this as resource release only: Open-LogFile also calls Close-Log during
    # day-boundary rollover, so writing app.stop here would emit a false app.stop on
    # every rollover. The real app.stop line belongs to the caller in a later change.
    if ($null -ne $script:LogWriter) {
        try { $script:LogWriter.Flush(); $script:LogWriter.Dispose() } catch { }
        $script:LogWriter = $null
    }
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
    # Re-apply/repair ACL in case it was created or later modified with weak permissions.
    Protect-StateAcl -Path $StatePath
} else {
    $script:AuthPin      = New-SecurePin
    $script:SessionToken = [guid]::NewGuid().ToString('N')
    try {
        $dir = Split-Path -Parent $StatePath
        New-DirectoryIfMissing -Path $dir

        $isDefaultDir = ($dir -eq (Join-Path $env:ProgramData 'ppt-orchestrator'))
        if (-not $isDefaultDir) {
            Write-Host " [Warning] Custom -StatePath in use; hardening the state FILE only, not the parent folder. Use an admin-only location." -ForegroundColor Yellow
        }

        $payload = [ordered]@{ Date = $today; Pin = $script:AuthPin; Token = $script:SessionToken } | ConvertTo-Json

        # Delete any pre-existing file so the recreated file inherits the secure ACL instead of preserving a weak one.
        if (Test-Path -LiteralPath $StatePath) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
        Set-Content -LiteralPath $StatePath -Value $payload -Encoding UTF8 -ErrorAction Stop
        Protect-StateAcl -Path $StatePath
    } catch {
        Write-Host " [Warning] Could not persist session state (using in-memory values for this run): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
$script:AuthFailedTracker   = @{}
$script:ContextTask         = $null
$script:SlideLogMode        = $SlideLogMode
