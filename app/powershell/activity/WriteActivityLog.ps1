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

    失败时不再"整条丢"（2026-09-13 日志撞名主题）：
    - 失败时往 log.jsonl **补写一条带 error 标记的记录**，手上有什么字段就填什么
      （属性解析成功的场合能填完整属性；解析失败则只有动作与时刻）—— 时刻不丢，
      活跃/墙钟时长这类"用全部日志点"的指标不会因为丢一条而失真；
    - 失败时把**现场**记进 AIProcess_error.log：动作名 / 时刻 / 读到的属性原文 /
      临时文件路径。此前只记一句异常消息，查不出所以然；
    - 临时文件改由 finally 统一清理，先留痕再清盘。

    临时文件的命名由 AHK 侧负责（app/lib/Guid.ahk），本脚本只负责读与清。

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

# 名字与动作性格一律问单源（app\powershell\conventions\DomainConventions.psm1）
Import-Module (Join-Path $PSScriptRoot "..\conventions\DomainConventions.psm1") -ErrorAction Stop

# 脚本级状态：声明在 try 之外，失败路径（catch / finally）也要读得到
$script:Properties = @{}          # 解析成功的属性；失败时仍是空对象
$script:ContentText = ""          # 读到的 content
$script:RawProperties = ""        # 读到的属性原文（供错误日志留现场）
$script:PropFilePath = $PropertiesFile
$script:ContentFilePath = $ContentFile

# 留痕字段的截断上限：原文可能很长（多次调用被追加到一起），只留够诊断的量
$script:RawMaxChars = 800
$script:ReasonMaxChars = 200

function Write-ActivityErrorLog {
    param(
        [Parameter(Mandatory = $true)][string]$Error,
        [Parameter(Mandatory = $false)][string]$Raw = ""
    )
    try {
        $logDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $record = [ordered]@{
            time   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            script = 'WriteActivityLog.ps1'
            op     = "append $Action"
            target = $(if ([string]::IsNullOrWhiteSpace($CurrentDir)) { '(no CurrentDir)' } else { $CurrentDir })
            file   = $(if ([string]::IsNullOrWhiteSpace($script:PropFilePath)) { '(无)' } else { $script:PropFilePath })
            error  = $Error
        }
        # 原始内容放最后一个键：它最长，且只在真读到了内容的场合才有
        if (-not [string]::IsNullOrWhiteSpace($Raw)) {
            if ($Raw.Length -gt $script:RawMaxChars) {
                $record['raw'] = $Raw.Substring(0, $script:RawMaxChars) + "…（已截断）"
            } else {
                $record['raw'] = $Raw
            }
        }
        $line = ($record | ConvertTo-Json -Compress) + "`n"
        [System.IO.File]::AppendAllText((Join-Path $logDir 'AIProcess_error.log'), $line, [System.Text.Encoding]::UTF8)
    } catch {
        # 留痕本身失败则放弃
    }
}

# 失败时往 log.jsonl 补一条记录：能拿到的字段都填上，末尾加 error 标记。
# 与正常行的区别只有多一个 error 键——读日志的人一眼能看出"这是失败后的补记"。
# 契约：本函数绝不抛错（它在 catch 里被调用）。
function Write-CompensationLine {
    param([Parameter(Mandatory = $true)][string]$Reason)
    try {
        if ([string]::IsNullOrWhiteSpace($CurrentDir)) { return }
        $logDir = Join-Path $CurrentDir (Get-DataDirName)
        EnsureDirectory -Path $logDir

        $record = [ordered]@{
            time   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            window = "W$WindowId"
        }
        if (-not [string]::IsNullOrWhiteSpace($AgentName)) { $record['agent'] = $AgentName.Trim() }
        $record['action'] = $Action
        $record['properties'] = $script:Properties
        $record['content'] = $script:ContentText
        if ($Reason.Length -gt $script:ReasonMaxChars) {
            $record['error'] = $Reason.Substring(0, $script:ReasonMaxChars) + "…（已截断）"
        } else {
            $record['error'] = $Reason
        }

        $line = ($record | ConvertTo-Json -Compress) + "`n"
        [System.IO.File]::AppendAllText((Join-Path $logDir 'log.jsonl'), $line, [System.Text.Encoding]::UTF8)
    } catch {
        # 补记失败则放弃——错误日志里已经有现场了
    }
}

function EnsureDirectory {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Remove-TempFile {
    param([string]$Path)
    try {
        if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
            Remove-Item -LiteralPath $Path -Force
        }
    } catch {
        # 清理失败不影响主流程；残留无害（不会再被谁读到）
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($CurrentDir)) {
        exit 0
    }

    # 读属性：原文留一份供失败时记现场；解析结果进 $script:Properties
    if (-not [string]::IsNullOrWhiteSpace($PropertiesFile) -and (Test-Path -Path $PropertiesFile)) {
        $script:RawProperties = [System.IO.File]::ReadAllText($PropertiesFile, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrWhiteSpace($script:RawProperties)) {
            $script:Properties = $script:RawProperties | ConvertFrom-Json
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ContentFile) -and (Test-Path -Path $ContentFile)) {
        $script:ContentText = [System.IO.File]::ReadAllText($ContentFile, [System.Text.Encoding]::UTF8)
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
    # 轮次类型：由动作表决定（复执行=execute，其余主循环动作=discussion），供统计直读
    if (Test-IsMainRoundAction $Action) {
        $rt = Get-RoundType $Action
        if ($script:Properties -is [System.Collections.IDictionary]) {
            $script:Properties["round-type"] = $rt
        } else {
            $script:Properties | Add-Member -NotePropertyName 'round-type' -NotePropertyValue $rt -Force
        }
    }
    $record["properties"] = $script:Properties
    $record["content"] = $script:ContentText

    $jsonLine = ($record | ConvertTo-Json -Compress) + "`n"

    $logDir = Join-Path $CurrentDir (Get-DataDirName)
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
    # 不阻断主流程，但失败不再"整条丢"：先留现场、再补记，最后（finally）清盘。
    # （原"静默忽略"导致日志丢失 4 个月无人察觉，2026-09-01 起改为落错误日志；
    #   2026-09-13 起再补上"补记 + 现场"，见文件头 .DESCRIPTION）
    $reason = $_.Exception.Message
    Write-ActivityErrorLog -Error $reason -Raw $script:RawProperties
    Write-CompensationLine -Reason $reason
    exit 0
} finally {
    Remove-TempFile $script:PropFilePath
    Remove-TempFile $script:ContentFilePath
}
