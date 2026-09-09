<#
.SYNOPSIS
    Markdown 文件打开路由脚本（恒定后台模式）。

.DESCRIPTION
    恒定走后台模式：将 Markdown 文件路径缓存到 [PendingMd] 段并弹通知，
    由 AHK 在用户切换到对应窗口（F2/F3/F4）时用编辑器打开。
    不再读取 MdActivationMode 配置、不再存在激活模式。

.PARAMETER FilePath
    要打开的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1、2 或 3。可选。
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

Import-Module (Join-Path $scriptDirectory "..\config\AppSettings.psm1")

function Assert-PathExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -Path $Path)) {
        Write-Error "$Description not found: $Path"
        exit 1
    }
}

Assert-PathExists -Path $settingsPath -Description "settings.ini"

$backgroundScript = Join-Path $scriptDirectory "OpenMarkdownBackground.ps1"

# 写入 AI-AGENT 标识（独立业务脚本，作为子进程调用，失败不影响打开流程）
$tagScript = Join-Path $scriptDirectory "SetMarkdownAgentTag.ps1"
if ((Test-Path $tagScript) -and $WindowId -ne "") {
    & powershell -ExecutionPolicy Bypass -File "`"$tagScript`"" -FilePath "`"$FilePath`"" -WindowId "`"$WindowId`""
}

# 写入耗时标记（人思考时长/AI处理时长；独立业务脚本，失败不影响打开流程）
$timeTagScript = Join-Path $scriptDirectory "SetMarkdownTimeTag.ps1"
if (Test-Path $timeTagScript) {
    & powershell -ExecutionPolicy Bypass -File "`"$timeTagScript`"" -FilePath "`"$FilePath`"" -WindowId "`"$WindowId`""
}

$arguments = @("-FilePath", "`"$FilePath`"")
if ($WindowId -ne "") {
    $arguments += @("-WindowId", "`"$WindowId`"")
}

# 恒定后台模式：直接走 background 链路（写 PendingMd + 通知），无模式分支
Assert-PathExists -Path $backgroundScript -Description "Target script"

& powershell -ExecutionPolicy Bypass -File "`"$backgroundScript`"" @arguments
