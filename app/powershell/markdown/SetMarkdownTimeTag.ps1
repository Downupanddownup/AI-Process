<#
.SYNOPSIS
    向 Markdown 文件写入/更新耗时标记（YAML Front Matter）。

.DESCRIPTION
    仅处理"轮次 md"（vN.md / 实施文档.md / 已实施.md）。

    数据**不再自己配对计算**：从主题目录 .aiprocess\stats.json 的 roundDetail 里取本文件那一行
    （同名多行时取 sendTime 最新的一行）——统计与打标因此是同一套口径、同一个来源，打标只负责写文件。

    写入八个键：gap / human / ai / total / excluded-human / excluded-ai / excluded-count / round-type。
    行内值为 null 时写"未知"（不编造）；roundDetail 里没有本文件的行时不写盘（保持原样）。

    边界语义：
      - 幂等：键值均未变化则不写盘；
      - 保留原文件 BOM 与换行风格（LF/CRLF）；
      - 失败隔离：任何异常仅输出警告，退出码始终为 0，不阻断调用方主流程。

.PARAMETER FilePath
    要写入的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1/2/3。本脚本逻辑不依赖，仅做参数签名对齐。
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
    Write-Warning "SetMarkdownTimeTag failed: $_"
    exit 0
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$timeModulePath = Join-Path $scriptDirectory "..\time\TimeCalculator.psm1"              # 友好时长换算（展示口径同源）
$conventionsPath = Join-Path $scriptDirectory "..\conventions\DomainConventions.psm1"   # 名字与正则单源

if (-not (Test-Path -LiteralPath $FilePath)) {
    exit 0
}
if (-not (Test-Path -LiteralPath $timeModulePath)) {
    exit 0
}
if (-not (Test-Path -LiteralPath $conventionsPath)) {
    exit 0
}
try {
    Import-Module $timeModulePath -ErrorAction Stop
    Import-Module $conventionsPath -ErrorAction Stop
} catch {
    exit 0
}

$themeDir = Split-Path -Parent $FilePath
$fileName = Split-Path -Leaf $FilePath
$statsFile = Join-Path (Join-Path $themeDir (Get-DataDirName)) 'stats.json'

# ---------- 只处理轮次 md ----------
function Test-RoundMdName {
    param([string]$Name)
    return ($Name -match (Get-VersionFilePattern) -or $Name -eq (Get-ImplDocFileName) -or $Name -eq (Get-ExecutedFileName))
}
if (-not (Test-RoundMdName $fileName)) {
    exit 0
}

# ---------- 取本文件在统计产物里的那一行（同名多行取 sendTime 最新） ----------
function Get-StatsRowForFile {
    param(
        [string]$StatsPath,
        [string]$Name
    )
    if (-not (Test-Path -LiteralPath $StatsPath)) { return $null }
    try {
        $data = [System.IO.File]::ReadAllText($StatsPath) | ConvertFrom-Json
    } catch {
        return $null
    }
    if ($null -eq $data.roundDetail) { return $null }
    $hit = $null
    foreach ($r in @($data.roundDetail)) {
        if ($r.file -ne $Name) { continue }
        # sendTime 形如 yyyy-MM-dd HH:mm:ss，字典序即时间序
        if ($null -eq $hit -or [string]$r.sendTime -gt [string]$hit.sendTime) { $hit = $r }
    }
    return $hit
}

# 秒 → 显示文本；null 记"未知"（不编造）
function Format-TagDuration {
    param([object]$Seconds)
    if ($null -eq $Seconds) { return '未知' }
    return Format-FriendlyDuration -Seconds ([int]$Seconds)
}

# ---------- 合并写入 front matter ----------
function Write-FrontMatterTag {
    param(
        [string]$Path,
        [hashtable]$Tags,
        [string]$RoundType = ""
    )
    # 英文短键，冒号/值对齐到同一列（最长的 excluded-count 有 14 字符，故值列 = 17）
    $padWidth = 16
    $order = @('gap', 'human', 'ai', 'total', 'cognition', 'excluded-human', 'excluded-ai', 'excluded-count')
    $tagLines = @()
    foreach ($k in $order) {
        if (-not $Tags.ContainsKey($k)) { continue }
        $tagLines += (("$k" + ":").PadRight($padWidth) + '"' + [string]$Tags[$k] + '"')
    }
    if ($RoundType -ne "") {
        $tagLines += (('round-type:').PadRight($padWidth) + '"' + $RoundType + '"')
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF)
    $content = [System.IO.File]::ReadAllText($Path)
    $newLine = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($content -split "`r`n|`n", -1)

    # 判定 front matter：首行（BOM 已由 ReadAllText 剥离）恰为 ---，其后 50 行内存在独立闭合行 ---
    $closingIndex = -1
    if ($lines.Length -ge 2 -and $lines[0].Trim() -eq "---") {
        $limit = [Math]::Min($lines.Length - 1, 50)
        for ($i = 1; $i -le $limit; $i++) {
            if ($lines[$i].Trim() -eq "---") { $closingIndex = $i; break }
        }
    }

    $newContent = $null

    if ($closingIndex -gt 0) {
        # 已有 front matter：移除旧的标记键（含中文旧键），保留其余键（含 ai-agent），再统一插入 new 键组
        $built = [System.Collections.Generic.List[string]]::new()
        $built.Add($lines[0])   # 开 ---

        $bodyStart = 1
        $bodyEnd = $closingIndex - 1
        if ($bodyEnd -ge $bodyStart) {
            foreach ($kv in $lines[$bodyStart..$bodyEnd]) {
                $t = $kv.Trim()
                if ($t -match "^(gap|human|ai|total|excluded-human|excluded-ai|excluded-count|round-type)\s*:") { continue }
                $built.Add($kv)
            }
        }
        foreach ($tl in $tagLines) { $built.Add($tl) }

        for ($i = $closingIndex; $i -lt $lines.Length; $i++) { $built.Add($lines[$i]) }

        $newLines = @($built)
        if ([string]::Join("`n", $newLines) -ne [string]::Join("`n", $lines)) {
            $newContent = [string]::Join($newLine, $newLines)
        }
    } else {
        # 无 front matter：文件头插入新块
        $block = @("---") + $tagLines + @("---", "")
        $combined = @($block) + @($lines)
        $newContent = [string]::Join($newLine, $combined)
    }

    if ($null -ne $newContent) {
        $encoding = New-Object System.Text.UTF8Encoding($hasBom)
        [System.IO.File]::WriteAllText($Path, $newContent, $encoding)
    }
}

# ============ main ============

$row = Get-StatsRowForFile -StatsPath $statsFile -Name $fileName
if ($null -eq $row) {
    # 统计产物里没有这个文件的结果 → 没有可写的东西，保持原样
    exit 0
}

# 轮次类型：明细直读日志 round-type；"未标注"（老日志缺字段）不写这个键
$roundTypeValue = [string]$row.type
if ($roundTypeValue -eq '未标注') { $roundTypeValue = '' }

$tags = @{
    'gap'            = (Format-FriendlyDuration -Seconds ([int]$row.gapSec))
    'human'          = (Format-TagDuration $row.humanSec)
    'ai'             = (Format-TagDuration $row.aiSec)
    'total'          = (Format-TagDuration $row.totalSec)
    'cognition'      = (Format-FriendlyDuration -Seconds ([int]$row.humanCognitionSec))
    'excluded-human' = (Format-FriendlyDuration -Seconds ([int]$row.humanExcludedSec))
    'excluded-ai'    = (Format-FriendlyDuration -Seconds ([int]$row.aiExcludedSec))
    'excluded-count' = ([string][int]$row.excludedCount)
}

Write-FrontMatterTag -Path $FilePath -Tags $tags -RoundType $roundTypeValue

exit 0
