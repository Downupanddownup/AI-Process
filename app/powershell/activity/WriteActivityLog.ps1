<#
.SYNOPSIS
    统一写入 AI Process 操作日志。

.DESCRIPTION
    根据 WindowId 从 settings.ini 中读取当前主题目录，
    将操作记录以 JSON Lines 格式追加到 .aiprocess/log.jsonl。

.PARAMETER WindowId
    窗口编号，1 / 2 / 3。

.PARAMETER Action
    动作名称，如 "复需求"、"复执行"、"完成通知"。

.PARAMETER PropertiesFile
    附加属性 JSON 临时文件路径。如果提供，读取其内容作为 properties。

.PARAMETER ContentFile
    内容临时文件路径。如果提供，读取其内容作为 content。
#>

param(
    [Parameter(Mandatory = $true)][string]$WindowId,
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $false)][string]$PropertiesFile = "",
    [Parameter(Mandatory = $false)][string]$ContentFile = ""
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
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::Unicode)
    foreach ($line in $lines) {
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

function EnsureDirectory {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

try {
    if (-not (Test-Path -Path $settingsPath)) {
        exit 0
    }

    $currentDir = Read-IniValue -Path $settingsPath -Section "Window$WindowId" -Key "CurrentDir"
    if ([string]::IsNullOrWhiteSpace($currentDir)) {
        exit 0
    }

    $properties = @{}
    if (-not [string]::IsNullOrWhiteSpace($PropertiesFile) -and (Test-Path -Path $PropertiesFile)) {
        $propertiesJson = [System.IO.File]::ReadAllText($PropertiesFile, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrWhiteSpace($propertiesJson)) {
            $properties = $propertiesJson | ConvertFrom-Json
        }
        try {
            Remove-Item -Path $PropertiesFile -Force
        } catch {
            # 忽略删除失败
        }
    }

    $content = ""
    if (-not [string]::IsNullOrWhiteSpace($ContentFile) -and (Test-Path -Path $ContentFile)) {
        $content = [System.IO.File]::ReadAllText($ContentFile, [System.Text.Encoding]::UTF8)
        try {
            Remove-Item -Path $ContentFile -Force
        } catch {
            # 忽略删除失败
        }
    }

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $window = "W$WindowId"

    # 构造 JSON 对象
    $record = [ordered]@{
        time = $time
        window = $window
        action = $Action
        properties = $properties
        content = $content
    }

    $jsonLine = ($record | ConvertTo-Json -Compress) + "`n"

    $logDir = Join-Path $currentDir ".aiprocess"
    EnsureDirectory -Path $logDir

    $logFile = Join-Path $logDir "log.jsonl"
    [System.IO.File]::AppendAllText($logFile, $jsonLine, [System.Text.Encoding]::UTF8)
} catch {
    # 静默忽略，不影响主流程
    exit 0
}
