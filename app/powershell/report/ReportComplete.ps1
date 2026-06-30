param(
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$DateRange,
    [Parameter(Mandatory = $true)][string]$Status
)

$ErrorActionPreference = "Continue"

# Locate project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")

# 1. Show notification
Add-Type -AssemblyName System.Windows.Forms

$message = if ($Status -eq "done") { "Report done: $DateRange" } else { "Report failed: $DateRange" }

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$notifyIcon.Visible = $true
$notifyIcon.ShowBalloonTip(1500, "AI Process", $message, [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Milliseconds 200
$notifyIcon.Dispose()

# 2. Refresh summary window and report window via AHK PostMessage
# Use .NET reflection to avoid here-string parsing issues
$CSharpCode = "using System;" +
    "using System.Runtime.InteropServices;" +
    "public class WindowHelper {" +
    "    [DllImport(`"user32.dll`")]" +
    "    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);" +
    "    [DllImport(`"user32.dll`")]" +
    "    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);" +
    "}"

Add-Type -TypeDefinition $CSharpCode -Language CSharp

$summaryHwnd = [WindowHelper]::FindWindow($null, "经验总结")
if ($summaryHwnd -ne [IntPtr]::Zero) {
    [void][WindowHelper]::PostMessage($summaryHwnd, 0x8000, [IntPtr]::Zero, [IntPtr]::Zero)
}

$reportHwnd = [WindowHelper]::FindWindow($null, "报告管理")
if ($reportHwnd -ne [IntPtr]::Zero) {
    [void][WindowHelper]::PostMessage($reportHwnd, 0x8002, [IntPtr]::Zero, [IntPtr]::Zero)
}

# 3. Clean up temp prompt files (matches AHK AppRoot\_tmp location)
$tmpDir = Join-Path $projectRoot "app\_tmp"
if (Test-Path -Path $tmpDir -PathType Container) {
    Get-ChildItem $tmpDir -Filter "report_prompt_*.txt" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
