param(
    [string]$TargetFolderPath = $(
        $cwd = (Get-Location).Path
        if (Get-ChildItem -Path $cwd -Filter '*.pptx' -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
            $cwd
        } elseif ($PSScriptRoot) {
            Split-Path $PSScriptRoot -Parent
        } else {
            $cwd
        }
    ),
    [string]$FinishFolderName = "finish",
    [int]$WebPort = 8090
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

$script:AuthPin             = Get-Random -Minimum 100000 -Maximum 999999
$script:SessionToken        = [guid]::NewGuid().ToString('N')
$script:LastAuthFailedTime  = [DateTime]::MinValue
$script:ContextTask         = $null
