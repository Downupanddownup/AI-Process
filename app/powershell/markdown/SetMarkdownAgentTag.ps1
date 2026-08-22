<#
.SYNOPSIS
    向 Markdown 文件写入/更新 AI-AGENT 身份标识（YAML Front Matter 的 ai-agent 键）。

.DESCRIPTION
    按 WindowId 从 settings.ini [WindowN] 读取 AgentName，
    将其以 YAML Front Matter 形式写入 Markdown 文件头部：

        ---
        ai-agent: "<AgentName>"
        ---

    - 文件已有 front matter：在其中追加/更新 ai-agent 键，其余键与正文不动；
    - 文件无 front matter：在文件头插入新的 front matter 块；
    - 幂等：同值重复执行不产生任何变化；
    - 保留原文件 BOM 与换行风格（LF/CRLF）；
    - 失败隔离：任何异常仅输出警告，退出码始终为 0，不阻断调用方主流程。

.PARAMETER FilePath
    要写入标识的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1/2/3。为空时直接跳过。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3", "")]
    [string]$WindowId = ""
)

# 失败隔离：本脚本为增强功能，任何情况下都不以非零退出码阻断调用方
trap {
    Write-Warning "SetMarkdownAgentTag failed: $_"
    exit 0
}

if ($WindowId -eq "") {
    exit 0
}

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

if (-not (Test-Path -Path $settingsPath)) {
    Write-Warning "settings.ini not found: $settingsPath"
    exit 0
}
if (-not (Test-Path -Path $FilePath)) {
    Write-Warning "Markdown file not found: $FilePath"
    exit 0
}

$section = "Window" + $WindowId
$agentName = Read-IniValue -Path $settingsPath -Section $section -Key "AgentName"
if ([string]::IsNullOrWhiteSpace($agentName)) {
    exit 0
}
$agentName = $agentName.Trim()

# YAML 双引号标量转义（兜底：窗口标题剥离特殊字符后一般无需转义）
$yamlValue = '"' + ($agentName -replace '\\', '\\' -replace '"', '\"') + '"'
$tagLine = "ai-agent: $yamlValue"

# 读取全文并检测 BOM（StreamReader 自动识别并剥离 BOM；BOM 状态以首字节实测为准）
$rawBytes = [System.IO.File]::ReadAllBytes($FilePath)
$hasBom = ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF)
$content = [System.IO.File]::ReadAllText($FilePath)

# 换行风格：以首个换行为准，默认 CRLF（Windows）
$newLine = if ($content -match "`r`n") { "`r`n" } else { "`n" }

$lines = $content -split "`r`n|`n", -1

$changed = $false
$newContent = $null

# 判定 front matter：首行（可带 BOM 已由读取剥离）恰为 ---，且其后 50 行内存在独立闭合行 ---
$closingIndex = -1
if ($lines.Length -ge 2 -and $lines[0].Trim() -eq "---") {
    $limit = [Math]::Min($lines.Length - 1, 50)
    for ($i = 1; $i -le $limit; $i++) {
        if ($lines[$i].Trim() -eq "---") {
            $closingIndex = $i
            break
        }
    }
}

if ($closingIndex -gt 0) {
    # 已有 front matter：查找 ai-agent 键
    $keyIndex = -1
    for ($i = 1; $i -lt $closingIndex; $i++) {
        if ($lines[$i] -match '^\s*ai-agent\s*:') {
            $keyIndex = $i
            break
        }
    }

    if ($keyIndex -ge 0) {
        # 解析现有值（兼容无引号写法），相同则不动（幂等）
        $existingRaw = ($lines[$keyIndex] -replace '^\s*ai-agent\s*:\s*', '').Trim()
        $existingValue = $existingRaw
        if ($existingRaw.Length -ge 2 -and $existingRaw.StartsWith('"') -and $existingRaw.EndsWith('"')) {
            $existingValue = $existingRaw.Substring(1, $existingRaw.Length - 2) -replace '\\"', '"' -replace '\\\\', '\'
        }
        if ($existingValue -ne $agentName) {
            $lines[$keyIndex] = $tagLine
            $changed = $true
        }
    } else {
        # 在闭合行前插入 ai-agent 键
        $before = $lines[0..($closingIndex - 1)]
        $after = $lines[$closingIndex..($lines.Length - 1)]
        $lines = @($before) + @($tagLine) + @($after)
        $changed = $true
    }
} else {
    # 无 front matter：文件头插入新块
    $block = @("---", $tagLine, "---", "")
    $lines = @($block) + @($lines)
    $changed = $true
}

if ($changed) {
    $newContent = [string]::Join($newLine, $lines)
    $encoding = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($FilePath, $newContent, $encoding)
    Write-Host "Tagged '$FilePath' with ai-agent: $yamlValue"
} else {
    Write-Host "ai-agent tag already up to date in '$FilePath'."
}

exit 0
