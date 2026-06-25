<#
.SYNOPSIS
    MD background mode: cache Markdown path instead of opening IDEA immediately.

.DESCRIPTION
    Writes the Markdown file path to [PendingMd] section in settings.ini
    based on WindowId. AHK will open it later when user switches to the window via F2/F3.
    If WindowId is empty, only shows generic notification.

.PARAMETER FilePath
    Absolute path of the Markdown file.

.PARAMETER WindowId
    Window number, 1 or 2. Optional.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3")]
    [string]$WindowId = ""
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "..\..\config\settings.ini"
$notificationScript = Join-Path $scriptDirectory "..\..\powershell\notification\ShowCenterNotification.ps1"

function Assert-PathExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -Path $Path)) {
        Write-Error "$Description not found: $Path"
        exit 1
    }
}

Assert-PathExists -Path $settingsPath -Description "settings.ini"
Assert-PathExists -Path $notificationScript -Description "Notification script"
Assert-PathExists -Path $FilePath -Description "Markdown file"

function Invoke-CenterNotification {
    param([string]$Id = "")
    $notifyArgs = @("-ExecutionPolicy", "Bypass", "-File", "`"$notificationScript`"")
    if ($Id -ne "") {
        $notifyArgs += @("-WindowId", "`"$Id`"")
    }
    Start-Process -FilePath "powershell" -ArgumentList $notifyArgs -NoNewWindow
}

if ($WindowId -eq "") {
    Invoke-CenterNotification
    exit 0
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class IniUtil {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool WritePrivateProfileString(string section, string key, string value, string filePath);
}
"@

$pendingKey = "Window" + $WindowId + "PendingMd"
[void][IniUtil]::WritePrivateProfileString("PendingMd", $pendingKey, $FilePath, $settingsPath)

Write-Host "Cached '$FilePath' to [PendingMd] $pendingKey for Window $WindowId."

Invoke-CenterNotification -Id $WindowId
