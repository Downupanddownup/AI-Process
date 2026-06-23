<#
.SYNOPSIS
    Displays a simple Windows notification indicating which AI Process window has finished execution.

.DESCRIPTION
    Shows a non-interactive balloon tip notification in the system tray area.
    The script exits immediately after showing the notification and does not wait for user interaction.

.PARAMETER WindowId
    The AI Process window identifier (1 or 2) whose task has completed.
#>
[CmdletBinding()]
param(
    [Parameter(
        Mandatory = $true,
        Position = 0,
        HelpMessage = "AI Process window identifier (1 or 2)"
    )]
    [ValidateSet("1", "2")]
    [string]$WindowId
)

Add-Type -AssemblyName System.Windows.Forms

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$notifyIcon.Visible = $true
$notifyIcon.ShowBalloonTip(
    1500,
    "AI Process",
    "窗口 $WindowId 已完成",
    [System.Windows.Forms.ToolTipIcon]::Info
)

$notifyIcon.Dispose()
