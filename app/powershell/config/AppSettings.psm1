<#
.SYNOPSIS
    本项目 settings.ini 的领域配置访问模块。

.DESCRIPTION
    唯一认识 settings.ini 的地方：路径推导、键语义与默认值集中于此。
    读写机制（解析/重试/错误留痕）委托通用层 ini/IniFile.psm1（单向依赖）。
    业务脚本只调用本模块的类型化函数，不再自行解析 ini。
#>

Import-Module (Join-Path $PSScriptRoot '..\ini\IniFile.psm1')

function Get-AppSettingsPath {
    return Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config\settings.ini'
}

# ---------- [WindowN] 窗口会话 ----------
function Get-WindowCurrentDir {
    param([Parameter(Mandatory = $true)][string]$WindowId)
    return Read-IniValue -Path (Get-AppSettingsPath) -Section "Window$WindowId" -Key 'CurrentDir'
}

function Get-WindowAgentName {
    param([Parameter(Mandatory = $true)][string]$WindowId)
    return Read-IniValue -Path (Get-AppSettingsPath) -Section "Window$WindowId" -Key 'AgentName'
}

function Get-WindowShowExecuteNotification {
    param([Parameter(Mandatory = $true)][string]$WindowId)
    return Read-IniValue -Path (Get-AppSettingsPath) -Section "Window$WindowId" -Key 'ShowExecuteNotification'
}

# ---------- [Behavior] 全局行为 ----------
function Get-MdActivationMode {
    # 缺省/未配置一律按 activate（沿用各脚本原有回退语义）
    $v = Read-IniValue -Path (Get-AppSettingsPath) -Section 'Behavior' -Key 'MdActivationMode'
    if ([string]::IsNullOrWhiteSpace($v)) { return 'activate' }
    return $v
}

# ---------- [FileTool] 编辑器 ----------
function Get-FileToolPath {
    return Read-IniValue -Path (Get-AppSettingsPath) -Section 'FileTool' -Key 'FileToolPath'
}

# ---------- [Report] 统计/总结 ----------
function Get-IdleThresholdMinutes {
    # 默认值 60 的语义唯一收编于此（原 4 份副本的公共出处）
    $v = Read-IniValue -Path (Get-AppSettingsPath) -Section 'Report' -Key 'IdleThresholdMinutes'
    if ($v -match '^\d+$' -and [int]$v -gt 0) { return [int]$v }
    return 60
}

# ---------- [PendingMd] 后台打开缓存（写） ----------
function Set-PendingMd {
    param(
        [Parameter(Mandatory = $true)][string]$WindowId,
        [Parameter(Mandatory = $true)][string]$FilePath
    )
    return Write-IniValue -Path (Get-AppSettingsPath) -Section 'PendingMd' -Key "Window${WindowId}PendingMd" -Value $FilePath
}

Export-ModuleMember -Function Get-AppSettingsPath, Get-WindowCurrentDir, Get-WindowAgentName,
    Get-WindowShowExecuteNotification, Get-MdActivationMode, Get-FileToolPath,
    Get-IdleThresholdMinutes, Set-PendingMd
