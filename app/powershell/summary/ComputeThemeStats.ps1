<#
.SYNOPSIS
    主题总体统计：基于 .aiprocess/log.jsonl + 文件系统全量重算，产出 stats.json 与 统计.md。

.DESCRIPTION
    纯脚本计算（无 AI 参与），幂等全量覆盖：
      - 轮次配对复用 RoundResolver.psm1（与单文档打标同一口径）；
      - 活跃时长复用 ActiveDurationCalculator.ps1（剔除超阈值空闲段）；
      - 友好时长复用 TimeCalculator.psm1 Format-FriendlyDuration；
      - 产出：{ThemePath}/.aiprocess/stats.json（机器可读）+ 统计.md（人类友好），均 UTF-8 无 BOM；
      - 父子聚合：stats.json 恒带 aggregate（自身+全部后代汇总）与 children（直接子摘要）；
        父.aggregate = 父自身 + Σ 直接子.aggregate（孙已含在子内，不穿透）；
      - 级联联动：算完自己后若存在父主题则自调用触发父重算（只触发不写父文件，深度保护 10 层）；
      - 失败隔离：任何异常仅输出警告，退出码始终为 0，不阻断调用方主流程；
      - .aiprocess 目录不存在时直接跳过（不主动创建）。

    口径要点（实施文档 §三 + 测试/对整体统计的测试 v4 定稿）：
      - 人思考时长：仅讨论轮（建X→复X）；执行轮恒 0；
      - 未知轮数：仅 复需求/复回复/复执行 三类发送中无 target 的计数；
      - 复关系（交接指令）：单列 handoff 指标，不计轮次/unknown/人字符串数；
      - 老日志无 agent 字段记空串；配不上对的轮次时长记 null，不编造；
      - 轮次总耗时（人+AI）= 各轮 humanSec+aiSec 合计；轮间间隔 = 本轮起点（建X，无则复X）− 上一轮完成通知，首轮恒 0。

.PARAMETER ThemePath
    主题目录绝对路径。

.PARAMETER CascadeDepth
    级联深度（内部自调用用），外部调用勿传。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath,

    [Parameter(Mandatory = $false)]
    [int]$CascadeDepth = 0
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
$aggModulePath = Join-Path $scriptDirectory "ThemeAggregation.psm1"

$aiProcessDir = Join-Path $ThemePath ".aiprocess"
if (-not (Test-Path -LiteralPath $aiProcessDir)) { exit 0 }
foreach ($p in @($timeModulePath, $resolverPath, $activeCalcPath, $aggModulePath)) {
    if (-not (Test-Path -LiteralPath $p)) { exit 0 }
}
try {
    Import-Module $timeModulePath -ErrorAction Stop
    Import-Module $resolverPath -ErrorAction Stop
    Import-Module $aggModulePath -ErrorAction Stop
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

# ---------- 字符数友好显示：<1万 原样+千分位；>=1万 按万/亿缩写（3 位有效数字）；stats.json 恒为精确整数 ----------
function Format-FriendlyCount {
    param([object]$Number)
    if ($null -eq $Number) { return '未知' }
    $v = [double]$Number
    if ($v -lt 10000) { return ([int64]$v).ToString('N0') }
    if ($v -lt 100000000) {
        $w = $v / 10000
        if ($w -lt 10) { return $w.ToString('0.00') + '万' }
        if ($w -lt 100) { return $w.ToString('0.0') + '万' }
        return ([int64][Math]::Round($w)).ToString('N0') + '万'
    }
    $y = $v / 100000000
    if ($y -lt 10) { return $y.ToString('0.00') + '亿' }
    if ($y -lt 100) { return $y.ToString('0.0') + '亿' }
    return ([int64][Math]::Round($y)).ToString('N0') + '亿'
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

    # 轮间间隔：本轮起点（建X，配不上则复X）− 此前最近一条完成通知；首轮恒 0（与打标同调 RoundResolver.Get-RoundGap）
    $roundStart = $e.time
    if ($null -ne $human -and -not $human.humanUnknown -and $null -ne $human.humanStart) { $roundStart = $human.humanStart }
    $gapSec = Get-RoundGap -Entries $entries -RoundStart $roundStart

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
        $totalSec = $null
        if ($null -ne $humanSec -or $null -ne $aiSec) {
            $totalSec = 0
            if ($null -ne $humanSec) { $totalSec += $humanSec }
            if ($null -ne $aiSec) { $totalSec += $aiSec }
        }

        $roundDetail += [PSCustomObject][ordered]@{
            file       = $fileName
            type       = $(if ($isExecute) { 'execute' } else { 'discussion' })
            agent      = $e.agent
            humanSec   = $humanSec
            aiSec      = $aiSec
            totalSec   = $totalSec
            gapSec     = $gapSec
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
$roundTotalSec = $humanSecTotal + $aiSecTotal
$gapTotalSec = 0; $detailHumanChars = 0; $detailAiChars = 0
foreach ($r in $roundDetail) {
    if ($null -ne $r.gapSec) { $gapTotalSec += $r.gapSec }
    if ($null -ne $r.humanChars) { $detailHumanChars += $r.humanChars }
    if ($null -ne $r.aiChars) { $detailAiChars += $r.aiChars }
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

# ---------- 父子聚合：父.aggregate = 自身 + Σ 直接子.aggregate（子的发布数据，不翻子的日志） ----------
$selfAgg = [PSCustomObject][ordered]@{
    humanSec      = $humanSecTotal
    aiSec         = $aiSecTotal
    roundTotalSec = $roundTotalSec
    gapTotalSec   = $gapTotalSec
    activeSec     = $activeSec
    files         = $fileTotal
    humanFiles    = $humanFiles
    aiFiles       = $aiFiles
    humanChars    = $humanCharsTotal
    aiChars       = $aiCharsTotal
    discussion    = $discussion
    execute       = $execute
    unknown       = $unknown
    handoffCount  = $handoffCount
    createdAt     = $createdAt
    lastActiveAt  = $lastAt
}
$children = @()
$childAggs = @()
foreach ($childPath in @(Get-ChildThemes -Dir $ThemePath)) {
    $pub = Get-ChildAggregate -ChildPath $childPath
    if ($null -eq $pub) { continue }   # 子未就绪：跳过，其下次轮次级联补齐
    $childAggs += $pub.aggregate
    $children += [PSCustomObject][ordered]@{
        name       = Split-Path -Leaf $childPath
        relPath    = $childPath.Substring($ThemePath.Length).TrimStart('\', '/')
        aggregate  = $pub.aggregate
        computedAt = $pub.computedAt
    }
}
$aggregate = Merge-Aggregate -Self $selfAgg -ChildAggs $childAggs

# ---------- stats.json ----------
$stats = [PSCustomObject][ordered]@{
    version    = 1
    computedAt = $now.ToString('yyyy-MM-dd HH:mm:ss')
    theme      = [PSCustomObject][ordered]@{ path = $ThemePath; name = (Split-Path -Leaf $ThemePath) }
    agents     = $agents
    time       = [PSCustomObject][ordered]@{
        roundTotalSec    = $roundTotalSec
        gapTotalSec      = $gapTotalSec
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
    aggregate   = $aggregate
    children    = $children
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
# 三列对照（自身 | 子主题 | 总）：行定义数组驱动，加指标=加一行；子值=aggregate−自身，有子无子同一套
$childRound = $aggregate.roundTotalSec - $roundTotalSec
$childHuman = $aggregate.humanSec - $humanSecTotal
$childAi = $aggregate.aiSec - $aiSecTotal
$childDisc = $aggregate.discussion - $discussion
$childExec = $aggregate.execute - $execute
$childFiles = $aggregate.files - $fileTotal
$childHChars = $aggregate.humanChars - $humanCharsTotal
$childAChars = $aggregate.aiChars - $aiCharsTotal
$spanText = '未知'
$spanSec = $null
if ($aggregate.createdAt -and $aggregate.lastActiveAt) {
    $spanD0 = [datetime]::ParseExact($aggregate.createdAt, 'yyyy-MM-dd HH:mm:ss', $null)
    $spanD1 = [datetime]::ParseExact($aggregate.lastActiveAt, 'yyyy-MM-dd HH:mm:ss', $null)
    $spanSec = [int][Math]::Round(($spanD1 - $spanD0).TotalSeconds)
    $spanText = "$($aggregate.createdAt) → $($aggregate.lastActiveAt)"
}
# 墙钟子主题列：全部子主题的首末跨度（不求和、取极值）
$childSpanSec = $null
if ($children.Count -gt 0) {
    $cCreated = @($children | ForEach-Object { $_.aggregate.createdAt } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
    $cLast = @($children | ForEach-Object { $_.aggregate.lastActiveAt } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
    if ($cCreated.Count -gt 0 -and $cLast.Count -gt 0) {
        $cD0 = [datetime]::ParseExact($cCreated[0], 'yyyy-MM-dd HH:mm:ss', $null)
        $cD1 = [datetime]::ParseExact($cLast[-1], 'yyyy-MM-dd HH:mm:ss', $null)
        $childSpanSec = [int][Math]::Round(($cD1 - $cD0).TotalSeconds)
    }
}
$childSpanText = if ($children.Count -eq 0) { '—' } else { Format-Stat $childSpanSec }
$overviewRows = @(
    @{ Label = '总投入（人+AI）'; S = (Format-Stat $roundTotalSec); C = (Format-Stat $childRound); T = (Format-Stat $aggregate.roundTotalSec) }
    @{ Label = '其中：人思考 / AI 执行'; S = "$(Format-Stat $humanSecTotal) / $(Format-Stat $aiSecTotal)"; C = "$(Format-Stat $childHuman) / $(Format-Stat $childAi)"; T = "$(Format-Stat $aggregate.humanSec) / $(Format-Stat $aggregate.aiSec)" }
    @{ Label = '轮次（讨论 / 执行）'; S = "$discussion / $execute"; C = "$childDisc / $childExec"; T = "$($aggregate.discussion) / $($aggregate.execute)" }
    @{ Label = '文件数'; S = "$fileTotal"; C = "$childFiles"; T = "$($aggregate.files)" }
    @{ Label = '字符数（人 / AI）'; S = "$(Format-FriendlyCount $humanCharsTotal) / $(Format-FriendlyCount $aiCharsTotal)"; C = "$(Format-FriendlyCount $childHChars) / $(Format-FriendlyCount $childAChars)"; T = "$(Format-FriendlyCount $aggregate.humanChars) / $(Format-FriendlyCount $aggregate.aiChars)" }
    @{ Label = '活跃时长（剔除空闲段）'; S = (Format-Stat $activeSec); C = (Format-Stat ($aggregate.activeSec - $activeSec)); T = (Format-Stat $aggregate.activeSec) }
    @{ Label = '墙钟时长（首末跨度）'; S = (Format-Stat $wallClockSec); C = $childSpanText; T = (Format-Stat $spanSec) }
    @{ Label = '总跨度（起 → 止）'; S = '—'; C = '—'; T = $spanText }
)
[void]$sb.AppendLine("| 指标 | 自身 | 子主题 | 总（含子主题） |")
[void]$sb.AppendLine("|---|---|---|---|")
foreach ($row in $overviewRows) {
    [void]$sb.AppendLine("| $($row.Label) | $($row.S) | $($row.C) | $($row.T) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 自身统计")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| 指标 | 值 |")
[void]$sb.AppendLine("|---|---|")
[void]$sb.AppendLine("| 轮次总耗时（人+AI） | $(Format-Stat $roundTotalSec) |")
[void]$sb.AppendLine("| 轮间间隔合计 | $(Format-Stat $gapTotalSec) |")
[void]$sb.AppendLine("| 总时长（活跃，剔除 >${threshold}min 空闲段） | $(Format-Stat $activeSec) |")
[void]$sb.AppendLine("| 墙钟时长（首末日志原始跨度） | $(Format-Stat $wallClockSec) |")
[void]$sb.AppendLine("| 人思考时长（讨论轮合计） | $(Format-Stat $humanSecTotal) |")
[void]$sb.AppendLine("| AI 执行时长（合计） | $(Format-Stat $aiSecTotal) |")
[void]$sb.AppendLine("| 忽略时长 / 段数 | $(Format-Stat $idleIgnoredSec) / $idleIgnoredCount 段 |")
[void]$sb.AppendLine("| 文件数（总 / 人 / AI） | $fileTotal / $humanFiles / $aiFiles |")
[void]$sb.AppendLine("| 字符数（人 / AI） | $(Format-FriendlyCount $humanCharsTotal) / $(Format-FriendlyCount $aiCharsTotal) 字符 |")
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
[void]$sb.AppendLine("| 文件 | 类型 | 人耗时 | AI耗时 | 合计耗时 | 轮间间隔 | 人字数 | AI字数 | Agent |")
[void]$sb.AppendLine("|---|---|---|---|---|---|---|---|---|")
foreach ($r in $roundDetail) {
    $typeText = if ($r.type -eq 'execute') { '执行' } else { '讨论' }
    $hc = Format-FriendlyCount $r.humanChars
    $ac = Format-FriendlyCount $r.aiChars
    $ag = if ([string]::IsNullOrWhiteSpace($r.agent)) { '' } else { $r.agent }
    [void]$sb.AppendLine("| $($r.file) | $typeText | $(Format-Stat $r.humanSec) | $(Format-Stat $r.aiSec) | $(Format-Stat $r.totalSec) | $(Format-Stat $r.gapSec) | $hc | $ac | $ag |")
}
if ($roundDetail.Count -gt 0) {
    [void]$sb.AppendLine("| **合计** | — | $(Format-Stat $humanSecTotal) | $(Format-Stat $aiSecTotal) | $(Format-Stat $roundTotalSec) | $(Format-Stat $gapTotalSec) | $(Format-FriendlyCount $detailHumanChars) | $(Format-FriendlyCount $detailAiChars) | — |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## 子主题汇总")
[void]$sb.AppendLine("")
if ($children.Count -gt 0) {
    [void]$sb.AppendLine("| 子主题 | 路径 | 轮次(讨/执) | 总投入 | 人 / AI | 文件数 | 字符数(人/AI) | 最后活动 |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|---|---|")
    foreach ($ch in $children) {
        $ca = $ch.aggregate
        $lastText = if ($ca.lastActiveAt) { $ca.lastActiveAt } else { '未知' }
        [void]$sb.AppendLine("| $($ch.name) | $($ch.relPath) | $($ca.discussion) / $($ca.execute) | $(Format-Stat $ca.roundTotalSec) | $(Format-Stat $ca.humanSec) / $(Format-Stat $ca.aiSec) | $($ca.files) | $(Format-FriendlyCount $ca.humanChars) / $(Format-FriendlyCount $ca.aiChars) | $lastText |")
    }
    # 合计行：与"总览"的"子主题"列数值一致，可互查
    [void]$sb.AppendLine("| **合计** | — | $childDisc / $childExec | $(Format-Stat $childRound) | $(Format-Stat $childHuman) / $(Format-Stat $childAi) | $childFiles | $(Format-FriendlyCount $childHChars) / $(Format-FriendlyCount $childAChars) | — |")
} else {
    [void]$sb.AppendLine("无子主题。")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**口径说明**")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- 轮次总耗时（人+AI）= 各轮 人耗时+AI耗时 合计；轮间间隔 = 本轮起点 − 上一轮完成通知（首轮为 0）")
[void]$sb.AppendLine("- 人思考=建X→复X（仅讨论轮，执行轮恒 0）；AI执行=复X→同 target 完成通知（无通知记未知，不编造）")
[void]$sb.AppendLine("- 总时长（活跃）= 首末日志剔除 >${threshold}min 空闲段；墙钟=首末日志原始跨度")
[void]$sb.AppendLine("- 人字数=需求.txt+对vN回复.txt；AI字数=vN.md+实施/已实施.md 正文（剥离 front matter）")
[void]$sb.AppendLine("- 字符数 >=1万 按量级缩写（如 2.05万），精确值见 stats.json")
[void]$sb.AppendLine("- 复关系单列不计轮次；未知轮数=三类发送中无 target 的计数
- 总览三列：总（含子主题）= 自身 + Σ 直接子主题的 aggregate（孙主题已含在子内）；活跃/墙钟类仅自身不求和，总跨度取最早创建→最晚活动
- 子主题识别：后代目录含 .aiprocess 即子主题（结果微调为容器），只聚合直接子")
[void]$sb.AppendLine("- 计算时间：$($now.ToString('yyyy-MM-dd HH:mm:ss'))（脚本自动生成，每次重算全量覆盖）")

[System.IO.File]::WriteAllText((Join-Path $aiProcessDir "统计.md"), $sb.ToString(), $utf8NoBom)

# ---------- 级联向上：子算完触发父重算（父自身数据幂等不变，仅重新聚合）；子只触发不写父文件 ----------
# 父主题定位：父目录为"结果微调"等容器时上跳；第一个含 .aiprocess 的祖先即父主题。目录树无环 + 深度保护双保险
$parentDir = Split-Path -Parent $ThemePath
while ($parentDir -and -not (Test-Path -LiteralPath (Join-Path $parentDir '.aiprocess'))) {
    $next = Split-Path -Parent $parentDir
    if ($next -eq $parentDir) { $parentDir = $null; break }
    $parentDir = $next
}
if ($CascadeDepth -lt 10 -and $parentDir) {
    & $PSCommandPath -ThemePath $parentDir -CascadeDepth ($CascadeDepth + 1)
}

exit 0
