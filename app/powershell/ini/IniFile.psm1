<#
.SYNOPSIS
    通用 ini 文件读写底层模块（纯机制，不含任何本项目业务语义）。

.DESCRIPTION
    - 读取：自动识别 BOM（UTF-16 LE / UTF-8），按 Section/Key 解析；
    - 写入：走 Win32 WritePrivateProfileString（与 AHK IniWrite 同一系统语义）；
    - 重试：仅对 System.IO.IOException（文件占用/共享冲突）重试 200ms×3；
      文件不存在、权限不足等终态错误不重试；键缺失不算失败，返回默认值；
    - 留痕：最终失败写一行 JSONL 到 app/logs/AIProcess_error.log，不弹窗、不抛给调用方；
    - 依赖：本模块不依赖任何项目模块（单向依赖的最底层）。
#>

# ---------- 错误留痕（自包含，任何失败都静默） ----------
function Write-IniErrorLog {
    param(
        [Parameter(Mandatory = $true)][string]$Op,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Error
    )
    try {
        $caller = ''
        try {
            $frames = @(Get-PSCallStack)
            # 取调用链上第一个非 .psm1 的脚本（跳过本模块与领域层模块，定位到真实业务脚本）
            foreach ($f in $frames) {
                if ($f.ScriptName -and $f.ScriptName -notmatch '\.psm1$') { $caller = Split-Path -Leaf $f.ScriptName; break }
            }
        } catch { }
        $logDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $record = [ordered]@{
            time   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            script = $caller
            op     = $Op
            target = $Target
            error  = $Error
        }
        $line = ($record | ConvertTo-Json -Compress) + "`n"
        [System.IO.File]::AppendAllText((Join-Path $logDir 'AIProcess_error.log'), $line, [System.Text.Encoding]::UTF8)
    } catch {
        # 留痕本身失败则放弃，绝不影响调用方
    }
}

# ---------- 读取：单键 ----------
function Read-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $false)][string]$Default = ''
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }   # 终态：不重试不留痕

    $content = $null
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            # ReadAllText 自动识别 BOM（无 BOM 按 UTF-8），统一兼容 UTF-16 LE 与 UTF-8
            $content = [System.IO.File]::ReadAllText($Path)
            break
        } catch [System.IO.IOException] {
            if ($attempt -ge 3) {
                Write-IniErrorLog -Op 'read' -Target "$Path [$Section] $Key" -Error $_.Exception.Message
                return $Default
            }
            Start-Sleep -Milliseconds 200
        } catch {
            return $Default   # 权限/路径等终态错误：不重试，维持原静默语义
        }
    }

    $currentSection = $null
    foreach ($line in ($content -split "`r`n|`n", -1)) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t) -or $t.StartsWith(';')) { continue }
        if ($t -match '^\[(.+)\]$') { $currentSection = $matches[1]; continue }
        if ($currentSection -eq $Section -and $t -match '^(.+?)\s*=\s*(.*)$') {
            if ($matches[1].Trim() -eq $Key) { return $matches[2].Trim() }
        }
    }
    return $Default
}

# ---------- 写入：单键 ----------
if (-not ([System.Management.Automation.PSTypeName]'AiProcessIniNative').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class AiProcessIniNative {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool WritePrivateProfileString(string section, string key, string value, string filePath);
}
"@
}

function Write-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            # 文件不存在时先创建 UTF-16 LE 带 BOM 空文件：WritePrivateProfileStringW 对新文件默认写 ANSI，
            # 会导致中文乱码；带 BOM 的已存在文件则按 Unicode 写入（与 ConfigManager 的 ini 创建口径一致）
            if (-not (Test-Path -LiteralPath $Path)) {
                $dir = Split-Path -Parent $Path
                if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                [System.IO.File]::WriteAllText($Path, '', [System.Text.Encoding]::Unicode)
            }
            if ([AiProcessIniNative]::WritePrivateProfileString($Section, $Key, $Value, $Path)) { return $true }
            # 返回 false：多为文件占用（ERROR_SHARING_VIOLATION / ERROR_LOCK_VIOLATION），按瞬态处理
            if ($attempt -ge 3) {
                Write-IniErrorLog -Op 'write' -Target "$Path [$Section] $Key" -Error "WritePrivateProfileString returned false"
                return $false
            }
            Start-Sleep -Milliseconds 200
        } catch [System.IO.IOException] {
            if ($attempt -ge 3) {
                Write-IniErrorLog -Op 'write' -Target "$Path [$Section] $Key" -Error $_.Exception.Message
                return $false
            }
            Start-Sleep -Milliseconds 200
        } catch {
            Write-IniErrorLog -Op 'write' -Target "$Path [$Section] $Key" -Error $_.Exception.Message
            return $false   # 终态错误：不重试，但留痕（写入失败比读取失败更值得知道）
        }
    }
}

Export-ModuleMember -Function Read-IniValue, Write-IniValue
