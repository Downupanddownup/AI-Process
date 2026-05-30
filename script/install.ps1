$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$ahkScript = Join-Path $projectRoot "app\AIProcess.ahk"

if (-not (Test-Path $ahkScript)) {
    Write-Error "Main script not found: $ahkScript"
    exit 1
}

Write-Host "Searching for AutoHotkey v2 ..."

$ahkExe = $null
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\AutoHotkey.exe',
    'HKLM:\SOFTWARE\AutoHotkey\v2',
    'HKLM:\SOFTWARE\AutoHotkey'
)

foreach ($rp in $regPaths) {
    if (Test-Path $rp) {
        $prop = Get-ItemProperty $rp -ErrorAction SilentlyContinue
        $p = if ($prop.'(default)') { $prop.'(default)' } else { $prop.InstallDir }
        if ($p) {
            $candidates = @()
            if (Test-Path $p -PathType Leaf) {
                $candidates += $p
            } else {
                $candidates += Join-Path $p "AutoHotkey64.exe"
                $candidates += Join-Path $p "AutoHotkey.exe"
                $candidates += Join-Path $p "v2\AutoHotkey64.exe"
                $candidates += Join-Path $p "v2\AutoHotkey.exe"
            }
            foreach ($c in $candidates) {
                if (Test-Path $c) {
                    $ahkExe = $c
                    break
                }
            }
            if ($ahkExe) { break }
        }
    }
}

if (-not $ahkExe) {
    $cmd = Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $ahkExe = $cmd.Source }
}

if (-not $ahkExe) {
    $cmd = Get-Command "AutoHotkey.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $ahkExe = $cmd.Source }
}

if (-not $ahkExe -or -not (Test-Path $ahkExe)) {
    Write-Error "AutoHotkey v2 not found. Please install it first."
    exit 1
}

$version = (Get-ItemProperty $ahkExe).VersionInfo.FileVersion
if ($version -notlike "2.*") {
    Write-Error "The detected AutoHotkey is not v2. Current version: $version"
    exit 1
}

$startMenu = [Environment]::GetFolderPath('StartMenu')
$programs = Join-Path $startMenu "Programs"
$shortcut = Join-Path $programs "AI Process.lnk"

$WshShell = New-Object -ComObject WScript.Shell
$s = $WshShell.CreateShortcut($shortcut)
$s.TargetPath = $ahkExe
$s.Arguments = '"' + $ahkScript + '"'
$s.WorkingDirectory = Join-Path $projectRoot "app"
$s.IconLocation = "$ahkExe,0"
$s.Description = "AIProcess 快捷面板"
$s.Save()

if (-not (Test-Path $shortcut)) {
    Write-Error "Failed to create the shortcut."
    exit 1
}

Write-Host "Created shortcut: $shortcut"
Write-Host "Install complete. Press Win and search for AI Process to launch it."
