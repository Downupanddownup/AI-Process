<#
.SYNOPSIS
    Markdown 文件打开路由脚本。

.DESCRIPTION
    读取 settings.ini 中的 MdActivationMode 配置，决定调用激活模式还是后台模式执行文件。

.PARAMETER FilePath
    要打开的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1 或 2。可选。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2")]
    [string]$WindowId = ""
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "..\..\config\settings.ini"

function Read-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $currentSection = $null
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith(";")) {
            continue
        }
        if ($trimmedLine -match "^\[(.+)\]$") {
            $currentSection = $matches[1]
            continue
        }
        if ($currentSection -eq $Section -and $trimmedLine -match "^(.+?)\s*=\s*(.*)$") {
            $currentKey = $matches[1].Trim()
            if ($currentKey -eq $Key) {
                return $matches[2].Trim()
            }
        }
    }
    return $null
}

function Assert-PathExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -Path $Path)) {
        Write-Error "$Description not found: $Path"
        exit 1
    }
}

Assert-PathExists -Path $settingsPath -Description "settings.ini"

$mode = Read-IniValue -Path $settingsPath -Section "Behavior" -Key "MdActivationMode"
if ([string]::IsNullOrWhiteSpace($mode)) {
    $mode = "activate"
}

$activateScript = Join-Path $scriptDirectory "OpenMarkdownActivate.ps1"
$backgroundScript = Join-Path $scriptDirectory "OpenMarkdownBackground.ps1"

$arguments = @("-FilePath", "`"$FilePath`"")
if ($WindowId -ne "") {
    $arguments += @("-WindowId", "`"$WindowId`"")
}

if ($mode -eq "background") {
    $targetScript = $backgroundScript
} else {
    $targetScript = $activateScript
}

Assert-PathExists -Path $targetScript -Description "Target script"

& powershell -ExecutionPolicy Bypass -File "`"$targetScript`"" @arguments
