$ErrorActionPreference = "Stop"

# 需要管理员权限才能写入注册表和开始菜单
if (-not (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $scriptDir = Split-Path -Parent $scriptPath
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"" -WorkingDirectory $scriptDir -WindowStyle Hidden
    exit
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$ahkScript = Join-Path $projectRoot "app\AIProcess.ahk"

# 轻量 INI 读取辅助函数
function Get-IniContent ($filePath) {
    $ini = @{}
    $section = ""
    switch -regex -file $filePath {
        "^\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        "^(.+?)\s*=\s*(.*)$" {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($section -ne "") {
                $ini[$section][$name] = $value
            }
        }
    }
    return $ini
}

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

# 注册资源管理器右键菜单
$regPath = "Registry::HKEY_CLASSES_ROOT\Directory\shell\AIProcessSetDir"
$commandPath = "$regPath\command"

try {
    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force
    }

    # 读取图标配置
    $settingsFile = Join-Path $projectRoot "app\config\settings.ini"
    $iconSource = "shell32.dll"
    $iconIndex = "44"
    if (Test-Path $settingsFile) {
        $ini = Get-IniContent $settingsFile
        if ($ini["App"]) {
            if ($ini["App"]["IconSource"]) { $iconSource = $ini["App"]["IconSource"] }
            if ($ini["App"]["IconIndex"]) { $iconIndex = $ini["App"]["IconIndex"] }
        }
    }
    if ($iconSource -and ($iconSource -notmatch '\\')) {
        $iconSource = Join-Path $env:SystemRoot "System32\$iconSource"
    }
    $iconValue = "$iconSource," + ([int]$iconIndex - 1)

    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "AIProcess 目录"
    Set-ItemProperty -Path $regPath -Name "Icon" -Value $iconValue
    New-Item -Path $commandPath -Force | Out-Null
    Set-ItemProperty -Path $commandPath -Name "(Default)" -Value "`"$ahkExe`" `"$ahkScript`" /setdir `"%1`""

    Write-Host "已注册右键菜单：AIProcess 目录"
} catch {
    Write-Warning "注册右键菜单失败：$_"
}

Write-Host "Install complete. Press Win and search for AI Process to launch it."
