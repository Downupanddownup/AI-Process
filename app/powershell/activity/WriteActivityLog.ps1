<#
.SYNOPSIS
    统一写入 AI Process 操作日志。

.DESCRIPTION
    将操作记录以 JSON Lines 格式追加到 {CurrentDir}\.aiprocess\log.jsonl。

    竞态根除（2026-09-01 流程效果主题）：
    - CurrentDir / AgentName 由调用方（AHK / 其他脚本）作为参数传入，
      本脚本不再读取 settings.ini —— 历史上"异步启动读 ini 撞上 AHK 写 ini"
      导致日志静默丢失，参数下发后该竞态窗口不存在；
    - log.jsonl 追加对 IOException（文件占用）重试 200ms×3；
    - 任何失败写一行 JSONL 到 app/logs/AIProcess_error.log（留痕但不阻断主流程）。

.PARAMETER WindowId
    窗口编号，1 / 2 / 3（仅用于日志的 window 字段）。

.PARAMETER Action
    动作名称，如 "复需求"、"复执行"、"完成通知"。

.PARAMETER CurrentDir
    当前主题目录绝对路径。为空时直接退出（与原"读不到配置即退出"语义一致）。

.PARAMETER AgentName
    窗口绑定的 AI 名称。为空时省略 agent 键（与原语义一致）。

.PARAMETER PropertiesFile
    附加属性 JSON 临时文件路径。如果提供，读取其内容作为 properties。

.PARAMETER ContentFile
    内容临时文件路径。如果提供，读取其内容作为 content。
#>

param(
    [Parameter(Mandatory = $true)][string]$WindowId,
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $false)][string]$CurrentDir = "",
    [Parameter(Mandatory = $false)][string]$AgentName = "",
    [Parameter(Mandatory = $false)][string]$PropertiesFile = "",
    [Parameter(Mandatory = $false)][string]$ContentFile = ""
)

$ErrorActionPreference = "Stop"

function Write-ActivityErrorLog {
    param([Parameter(Mandatory = $true)][string]$Error)
    try {
        $logDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $record = [ordered]@{
            time   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            script = 'WriteActivityLog.ps1'
            op     = "append $Action"
            target = $(if ([string]::IsNullOrWhiteSpace($CurrentDir)) { '(no CurrentDir)' } else { $CurrentDir })
            error  = $Error
        }
        $line = ($record | ConvertTo-Json -Compress) + "`n"
        [System.IO.File]::AppendAllText((Join-Path $logDir 'AIProcess_error.log'), $line, [System.Text.Encoding]::UTF8)
    } catch {
        # 留痕本身失败则放弃
    }
}

function EnsureDirectory {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($CurrentDir)) {
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
    }
    if (-not [string]::IsNullOrWhiteSpace($AgentName)) {
        $record["agent"] = $AgentName.Trim()
    }
    $record["action"] = $Action
    $record["properties"] = $properties
    $record["content"] = $content

    $jsonLine = ($record | ConvertTo-Json -Compress) + "`n"

    $logDir = Join-Path $CurrentDir ".aiprocess"
    EnsureDirectory -Path $logDir

    $logFile = Join-Path $logDir "log.jsonl"
    # IOException（文件占用/共享冲突）属瞬态：200ms×3 重试；其余异常由外层 catch 留痕
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            [System.IO.File]::AppendAllText($logFile, $jsonLine, [System.Text.Encoding]::UTF8)
            break
        } catch [System.IO.IOException] {
            if ($attempt -ge 3) { throw }
            Start-Sleep -Milliseconds 200
        }
    }
} catch {
    # 不阻断主流程，但留痕（原"静默忽略"导致日志丢失 4 个月无人察觉，2026-09-01 起改为落错误日志）
    Write-ActivityErrorLog -Error $_.Exception.Message
    exit 0
}
