<#
.SYNOPSIS
    主题总体统计：基于 .aiprocess/log.jsonl + 文件系统全量重算，产出 stats.json 与 统计.md。

.DESCRIPTION
    纯脚本计算（无 AI 参与），幂等全量覆盖：
      - 轮次配对复用 RoundResolver.psm1（与单文档打标同一口径）；
      - 活跃时长复用 ActiveDurationCalculator.ps1（剔除超阈值空闲段）；
      - 友好时长复用 TimeCalculator.psm1 Format-FriendlyDuration；
      - 产出：{ThemePath}/.aiprocess/stats.json（机器可读）+ 统计.md（人类友好），均 UTF-8 无 BOM；
      - 失败隔离：任何异常仅输出警告，退出码始终为 0，不阻断调用方主流程；
      - .aiprocess 目录不存在时直接跳过（不主动创建）。

    口径要点（实施文档 §三）：
      - 人思考时长：仅讨论轮（建X→复X）；执行轮恒 0；
      - 未知轮数：仅 复需求/复回复/复执行 三类发送中无 target 的计数；
      - 复关系（交接指令）：单列 handoff 指标，不计轮次/unknown/人字符串数；
      - 老日志无 agent 字段记空串；配不上对的轮次时长记 null，不编造。

.PARAMETER ThemePath
    主题目录绝对路径。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath
)

# 失败隔离：本脚本为增强功能，任何情况下都不以非零退出码阻断调用方
trap {
    Write-Warning "ComputeThemeStats failed: $_"
    exit 0
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "..\..\config\settings.ini"
$timeModulePath = Join-Path $scriptDirectory "..\time\TimeCalculator.psm1"
$resolverPath = Join-Path $scriptDirectory "..\time\RoundResolver.psm1"
$activeCalcPath = Join-Path $scriptDirectory "ActiveDurationCalculator.ps1"

$aiProcessDir = Join-Path $ThemePath ".aiprocess"
if (-not (Test-Path -LiteralPath $aiProcessDir)) { exit 0 }
foreach ($p in @($timeModulePath, $resolverPath, $activeCalcPath)) {
    if (-not (Test-Path -LiteralPath $p)) { exit 0 }
}
try {
    Import-Module $timeModulePath -ErrorAction Stop
    Import-Module $resolverPath -ErrorAction Stop
    . $activeCalcPath
} catch {
    exit 0
}

$logFile = Join-Path $aiProcessDir "log.jsonl"

# ---------- 读取阈值 ----------
function Get-IdleThresholdMinutes {
    param([string]$SettingsPath)
    $defaultValue = 60
    try {
        $lines = [System.IO.File]::ReadAllLines($SettingsPath, [System.Text.Encoding]::Unicode)
        $inReport = $false
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ($t -eq "[Report]") { $inReport = $true; continue }
            if ($t -match "^\[.*\]$") { $inReport = $false; continue }
            if ($inReport -and $t -match "^IdleThresholdMinutes\s*=\s*(\d+)") {
                $v = [int]$matches[1]
                if ($v -gt 0) { return $v }
            }
        }
    } catch {
        # 使用默认
    }
    return $defaultValue
}

# ---------- 字符数：isAiBody=$true 时剥离 front matter（首行 --- 起 50 行内闭合 --- 的块，与打标同一判定） ----------
function Get-FileCharCount {
    param(
        [string]$Path,
        [bool]$AiBody = $false
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $content = [System.IO.File]::ReadAllText($Path)
        if (-not $AiBody) { return $content.Length }
        $lines = @($content -split "`r`n|`n", -1)
        $closingIndex = -1
        if ($lines.Length -ge 2 -and $lines[0].Trim() -eq "---") {
            $limit = [Math]::Min($lines.Length - 1, 50)
            for ($i = 1; $i -le $limit; $i++) {
                if ($lines[$i].Trim() -eq "---") { $closingIndex = $i; break }
            }
        }
        if ($closingIndex -gt 0) {
            $body = [string]::Join("`n", $lines[($closingIndex + 1)..($lines.Length - 1)])
            return $body.Length
        }
        return $content.Length
    } catch {
        return $null
    }
}

# ---------- 文件分类 ----------
function Test-HumanFile {
    param([string]$Name)
    return ($Name -eq '需求.txt' -or $Name -match '^对v\d+的回复\.txt$')
}
function Test-AiFile {
    param([string]$Name)
    return ($Name -match '^v\d+\.md$' -or $Name -eq '实施文档.md' -or $Name -eq '已实施.md')
}

# ============ main ============

$threshold = Get-IdleThresholdMinutes -SettingsPath $settingsPath
$entries = @(Get-LogEntries -LogFile $logFile)
$now = Get-Date

# ---------- 文件系统扫描（仅主题根目录顶层文件；排除 .aiprocess 子目录与隐藏文件；子主题独立统计不进本主题） ----------
$fileTotal = 0; $humanFiles = 0; $aiFiles = 0; $humanCharsTotal = 0; $aiCharsTotal = 0
foreach ($f in (Get-ChildItem -LiteralPath $ThemePath -File -ErrorAction SilentlyContinue)) {
    if ($f.Attributes -band [System.IO.FileAttributes]::Hidden) { continue }
    $fileTotal++
    if (Test-HumanFile -Name $f.Name) {
        $humanFiles++
        $c = Get-FileCharCount -Path $f.FullName
        if ($null -ne $c) { $humanCharsTotal += $c }
    } elseif (Test-AiFile -Name $f.Name) {
        $aiFiles++
        $c = Get-FileCharCount -Path $f.FullName -AiBody $true
        if ($null -ne $c) { $aiCharsTotal += $c }
    }
}

# ---------- 轮次明细：遍历三类发送，按 target 拆候选逐文件配对 ----------
$sendActions = @('复需求', '复回复', '复执行')
$discussion = 0; $execute = 0; $unknown = 0
$executeByStrategy = [ordered]@{}
$roundDetail = @()

foreach ($e in $entries) {
    if ($sendActions -notcontains $e.action) { continue }
    if ($e.action -eq '复执行') {
        $execute++
        $strategyKey = if ([string]::IsNullOrWhiteSpace($e.strategy)) { '未标注' } else { $e.strategy }
        if (-not $executeByStrategy.Contains($strategyKey)) { $executeByStrategy[$strategyKey] = 0 }
        $executeByStrategy[$strategyKey]++
    } else {
        $discussion++
    }
    if ([string]::IsNullOrWhiteSpace($e.target)) { $unknown++; continue }

    $isExecute = ($e.action -eq '复执行')
    $human = $null
    if (-not $isExecute) { $human = Get-HumanStartForSend -Entries $entries -Send $e }

    # 人文件字符数：讨论轮取 source 文件（复需求无 source 按 需求.txt）
    $srcChars = $null
    if (-not $isExecute) {
        $src = $e.source
        if ($e.action -eq '复需求' -and [string]::IsNullOrWhiteSpace($src)) { $src = '需求.txt' }
        if (-not [string]::IsNullOrWhiteSpace($src)) {
            $srcChars = Get-FileCharCount -Path (Join-Path $ThemePath $src)
        }
    }

    foreach ($part in ($e.target -split '\|')) {
        $fileName = $part.Trim()
        if ($fileName -eq '') { continue }
        $aiEnd = Get-FirstTargetNotificationAfter -Entries $entries -FileName $fileName -After $e.time
        $aiEndKnown = ($null -ne $aiEnd)
        # 无完成通知 = 该轮未闭环：aiSec 记 null 不编造（统计脚本在完成通知后触发，缺通知即真未完成）；人耗时段不受影响照常计算
        $humanStart = if ($null -ne $human) { $human.humanStart } else { $null }
        $breakdown = Get-RoundBreakdown -HumanStart $humanStart -ThisSend $e.time -AiEnd $aiEnd -ThresholdMinutes $threshold
        $aiSec = $null
        if ($aiEndKnown) { $aiSec = $breakdown.aiSeconds }
        $humanSec = $null
        if ($isExecute) { $humanSec = 0 }
        elseif (-not $human.humanUnknown) { $humanSec = $breakdown.humanSeconds }
        $aiChars = Get-FileCharCount -Path (Join-Path $ThemePath $fileName) -AiBody $true

        $roundDetail += [PSCustomObject][ordered]@{
            file       = $fileName
            type       = $(if ($isExecute) { 'execute' } else { 'discussion' })
            agent      = $e.agent
            humanSec   = $humanSec
            aiSec      = $aiSec
            humanChars = $(if ($isExecute) { 0 } else { $srcChars })
            aiChars    = $aiChars
            known      = ($aiEndKnown -and ($isExecute -or -not $human.humanUnknown))
        }
    }
}

# ---------- 复关系（交接指令）：单列，不进轮次/unknown/人字符串 ----------
$handoffCount = 0; $handoffChars = 0
foreach ($e in $entries) {
    if ($e.action -eq '复关系') { $handoffCount++; $handoffChars += $e.contentChars }
}

# ---------- 时长类 ----------
$activeSec = 0; $wallClockSec = 0; $idleIgnoredSec = 0; $idleIgnoredCount = 0
$createdAt = $null; $lastAt = $null
if ($entries.Count -gt 0) {
    $sorted = @($entries | Sort-Object time)
    $first = $sorted[0].time
    $last = $sorted[$sorted.Count - 1].time
    $createdAt = $first.ToString('yyyy-MM-dd HH:mm:ss')
    $lastAt = $last.ToString('yyyy-MM-dd HH:mm:ss')
    if ($last -gt $first) {
        $wallClockSec = [int][Math]::Round(($last - $first).TotalSeconds)
        $logTimes = @($sorted | ForEach-Object { $_.time })
        $activeSec = [int][Math]::Round((Get-ActiveDuration -Start $first -End $last -LogTimes $logTimes -ThresholdMinutes $threshold).TotalSeconds)
        $idleIgnoredSec = $wallClockSec - $activeSec
        # 忽略段数：相邻日志点间隔超阈值的次数（按秒去重后）
        $uniqueMap = @{}
        foreach ($t in $logTimes) { $k = $t.ToString('yyyyMMddHHmmss'); if (-not $uniqueMap.ContainsKey($k)) { $uniqueMap[$k] = $t } }
        $deduped = @($uniqueMap.Values | Sort-Object)
        $thresholdSec = $threshold * 60
        for ($i = 0; $i -lt $deduped.Count - 1; $i++) {
            if (($deduped[$i + 1] - $deduped[$i]).TotalSeconds -gt $thresholdSec) { $idleIgnoredCount++ }
        }
    }
}

# ---------- 人/AI 时长合计（raw 秒数求和；null 不计） ----------
$humanSecTotal = 0; $aiSecTotal = 0
foreach ($r in $roundDetail) {
    if ($null -ne $r.humanSec) { $humanSecTotal += $r.humanSec }
    if ($null -ne $r.aiSec) { $aiSecTotal += $r.aiSec }
}

# ---------- 派生 ----------
$avgHumanSec = 0; $avgAiSec = 0
$discussionKnown = @($roundDetail | Where-Object { $_.type -eq 'discussion' -and $null -ne $_.humanSec })
if ($discussionKnown.Count -gt 0) {
    $avgHumanSec = [int][Math]::Round(($discussionKnown | Measure-Object humanSec -Sum).Sum / $discussionKnown.Count)
}
$aiKnown = @($roundDetail | Where-Object { $null -ne $_.aiSec })
if ($aiKnown.Count -gt 0) {
    $avgAiSec = [int][Math]::Round(($aiKnown | Measure-Object aiSec -Sum).Sum / $aiKnown.Count)
}
$longestFile = ''; $longestSec = 0
foreach ($r in $roundDetail) {
    $sum = 0
    if ($null -ne $r.humanSec) { $sum += $r.humanSec }
    if ($null -ne $r.aiSec) { $sum += $r.aiSec }
    if ($sum -gt $longestSec) { $longestSec = $sum; $longestFile = $r.file }
}

$agents = @($entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.agent) } | ForEach-Object { $_.agent } | Select-Object -Unique)

# ---------- stats.json ----------
$stats = [PSCustomObject][ordered]@{
    version    = 1
    computedAt = $now.ToString('yyyy-MM-dd HH:mm:ss')
    theme      = [PSCustomObject][ordered]@{ path = $ThemePath; name = (Split-Path -Leaf $ThemePath) }
    agents     = $agents
    time       = [PSCustomObject][ordered]@{
        activeSec        = $activeSec
        wallClockSec     = $wallClockSec
        humanSec         = $humanSecTotal
        aiSec            = $aiSecTotal
        idleIgnoredSec   = $idleIgnoredSec
        idleIgnoredCount = $idleIgnoredCount
        createdAt        = $createdAt
        lastActiveAt     = $lastAt
    }
    files      = [PSCustomObject][ordered]@{
        total      = $fileTotal
        humanFiles = $humanFiles
        aiFiles    = $aiFiles
        humanChars = $humanCharsTotal
        aiChars    = $aiCharsTotal
    }
    rounds     = [PSCustomObject][ordered]@{
        discussion        = $discussion
        execute           = $execute
        executeByStrategy = $executeByStrategy
        unknown           = $unknown
    }
    handoff    = [PSCustomObject][ordered]@{ count = $handoffCount; chars = $handoffChars }
    derived    = [PSCustomObject][ordered]@{
        avgHumanSec  = $avgHumanSec
        avgAiSec     = $avgAiSec
        longestRound = [PSCustomObject][ordered]@{ file = $longestFile; sec = $longestSec }
    }
    roundDetail = $roundDetail
}

$json = ConvertTo-Json $stats -Depth 6 -Compress
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $aiProcessDir "stats.json"), $json, $utf8NoBom)

# ---------- 统计.md ----------
function Format-Stat {
    param([object]$Seconds)
    if ($null -eq $Seconds) { return '未知' }
    return Format-FriendlyDuration -Seconds ([int]$Seconds)
}

$themeName = Split-Path -Leaf $ThemePath
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# $themeName — 总体统计")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> 本文件由 ComputeThemeStats.ps1 脚本自动生成，每次重算全量覆盖，请勿手改。")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 总览")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| 指标 | 值 |")
[void]$sb.AppendLine("|---|---|")
[void]$sb.AppendLine("| 总时长（活跃，剔除 >${threshold}min 空闲段） | $(Format-Stat $activeSec) |")
[void]$sb.AppendLine("| 墙钟时长（首末日志原始跨度） | $(Format-Stat $wallClockSec) |")
[void]$sb.AppendLine("| 人思考时长（讨论轮合计） | $(Format-Stat $humanSecTotal) |")
[void]$sb.AppendLine("| AI 执行时长（合计） | $(Format-Stat $aiSecTotal) |")
[void]$sb.AppendLine("| 忽略时长 / 段数 | $(Format-Stat $idleIgnoredSec) / $idleIgnoredCount 段 |")
[void]$sb.AppendLine("| 文件数（总 / 人 / AI） | $fileTotal / $humanFiles / $aiFiles |")
[void]$sb.AppendLine("| 字符串数（人 / AI） | $humanCharsTotal / $aiCharsTotal |")
$strategyText = @($executeByStrategy.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join '、'
if ($strategyText -eq '') { $strategyText = '无' }
[void]$sb.AppendLine("| 讨论轮 / 执行轮 | $discussion / $execute（$strategyText） |")
[void]$sb.AppendLine("| 未知轮数（老日志配不上对） | $unknown |")
[void]$sb.AppendLine("| 平均每轮耗时（人 / AI） | $(Format-Stat $avgHumanSec) / $(Format-Stat $avgAiSec) |")
$longestText = if ($longestFile -eq '') { '无' } else { "$longestFile（$(Format-Stat $longestSec)）" }
[void]$sb.AppendLine("| 最长轮次 | $longestText |")
[void]$sb.AppendLine("| 交接提示（复关系） | $handoffCount 次 / $handoffChars 字符 |")
$agentsText = if ($agents.Count -gt 0) { $agents -join '、' } else { '未知' }
[void]$sb.AppendLine("| 参与 Agent | $agentsText |")
[void]$sb.AppendLine("| 主题创建 / 最后活动 | $(if ($createdAt) { $createdAt } else { '未知' }) / $(if ($lastAt) { $lastAt } else { '未知' }) |")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 轮次明细")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| 文件 | 类型 | 人耗时 | AI耗时 | 人字数 | AI字数 | Agent |")
[void]$sb.AppendLine("|---|---|---|---|---|---|---|")
foreach ($r in $roundDetail) {
    $typeText = if ($r.type -eq 'execute') { '执行' } else { '讨论' }
    $hc = if ($null -eq $r.humanChars) { '未知' } else { $r.humanChars }
    $ac = if ($null -eq $r.aiChars) { '未知' } else { $r.aiChars }
    $ag = if ([string]::IsNullOrWhiteSpace($r.agent)) { '' } else { $r.agent }
    [void]$sb.AppendLine("| $($r.file) | $typeText | $(Format-Stat $r.humanSec) | $(Format-Stat $r.aiSec) | $hc | $ac | $ag |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("口径：人思考=建X→复X（仅讨论轮，执行轮恒 0）；AI执行=复X→同 target 完成通知；活跃时长剔除 >${threshold}min 空闲段；人字数=需求.txt+对vN回复.txt；AI字数=vN.md+实施/已实施.md 正文（剥离 front matter）；复关系单列不计轮次。计算时间：$($now.ToString('yyyy-MM-dd HH:mm:ss'))")

[System.IO.File]::WriteAllText((Join-Path $aiProcessDir "统计.md"), $sb.ToString(), $utf8NoBom)

exit 0
