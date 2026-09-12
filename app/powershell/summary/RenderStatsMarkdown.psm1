<#
.SYNOPSIS
    统计展示层：把 stats 对象渲染成 统计.md 文本。

.DESCRIPTION
    只吃 stats 对象与一小份渲染上下文，不读日志、不碰文件系统、不落盘——落盘是编排层的职责。
    版式（表结构、行序、列数、百分比分母）由本文件决定；指标的口径说明段由 StatsSchema.psm1 生成。

    为什么指标名仍写在本文件里、不逐个向 StatsSchema 要：统计.md 的一张表里，
    一行往往合并多个指标（"轮次（讨论 / 执行 / 重建）"= 3 个键、"忽略时长 / 段数"= 2 个键），
    总览还给了同一指标另一个版式标签（"总投入（人+AI）"vs"轮次总耗时（人+AI）"）——
    版式标签与指标名不是一一对应。强行做成映射表只会造出一张假的对应关系。
    定义单源由 StatsSchema 承担，两边的一致性由 test\Verify-StatsSchema.ps1 对照清单兜底。

    依赖：StatsSchema.psm1（口径说明段）、TimeCalculator.psm1（Format-FriendlyDuration）。
    保持单向依赖：本模块不引用任何调用方/业务模块。
#>

# ---------- 依赖：均为工具侧叶子 ----------
Import-Module (Join-Path $PSScriptRoot "StatsSchema.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\time\TimeCalculator.psm1") -ErrorAction Stop

# ---------- 字符数友好显示：<1万 原样+千分位；>=1万 按万/亿缩写（3 位有效数字）；stats.json 恒为精确整数 ----------
# ⚠ AHK 侧 app/modules/business/services/ThemeStats.ahk 有等价换算（列表显示用），改口径时两边一起改。
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

function Format-Stat {
    param([object]$Seconds)
    if ($null -eq $Seconds) { return '未知' }
    return Format-FriendlyDuration -Seconds ([int]$Seconds)
}

# 百分比：友好时长后追加（xx.x%）；值为 null 显'未知'，分母 null/<=0 时不追加（除零保护）；SuppressZero 时 0 值不挂百分比。仅展示层现算，不落 stats.json
function Format-WithPercent {
    param([object]$Seconds, [object]$BaseSec, [bool]$SuppressZero = $false)
    if ($null -eq $Seconds) { return '未知' }
    $text = Format-FriendlyDuration -Seconds ([int]$Seconds)
    if ($SuppressZero -and [double]$Seconds -eq 0) { return $text }
    if ($null -eq $BaseSec -or [double]$BaseSec -le 0) { return $text }
    $pct = [double]$Seconds / [double]$BaseSec * 100
    return "$text（$($pct.ToString('0.0'))%）"
}

# ---------- 渲染入口 ----------
# Context.ThresholdMinutes    空闲阈值（分钟），用于"剔除 >Xmin 空闲段"的提示文字
# Context.DupSendCountByTarget  target → 被合并的重复发送次数（供明细标注）；不落 stats.json，故走参数
function ConvertTo-StatsMarkdown {
    param(
        [Parameter(Mandatory = $true)][object]$Stats,
        [Parameter(Mandatory = $true)][hashtable]$Context
    )

    $threshold = [int]$Context.ThresholdMinutes
    $dupSendCountByTarget = $Context.DupSendCountByTarget
    if ($null -eq $dupSendCountByTarget) { $dupSendCountByTarget = @{} }

    # 自身段
    $themeName = $Stats.theme.name
    $roundTotalSec = $Stats.time.roundTotalSec
    $gapTotalSec = $Stats.time.gapTotalSec
    $activeSec = $Stats.time.activeSec
    $wallClockSec = $Stats.time.wallClockSec
    $humanSecTotal = $Stats.time.humanSec
    $aiSecTotal = $Stats.time.aiSec
    $idleIgnoredSec = $Stats.time.idleIgnoredSec
    $idleIgnoredCount = $Stats.time.idleIgnoredCount
    $createdAt = $Stats.time.createdAt
    $lastAt = $Stats.time.lastActiveAt
    $fileTotal = $Stats.files.total
    $humanFiles = $Stats.files.humanFiles
    $aiFiles = $Stats.files.aiFiles
    $humanCharsTotal = $Stats.files.humanChars
    $aiCharsTotal = $Stats.files.aiChars
    $discussion = $Stats.rounds.discussion
    $execute = $Stats.rounds.execute
    $rebuild = $Stats.rounds.rebuild
    $unknown = $Stats.rounds.unknown
    $executeByStrategy = $Stats.rounds.executeByStrategy
    $avgHumanSec = $Stats.derived.avgHumanSec
    $avgAiSec = $Stats.derived.avgAiSec
    $longestFile = $Stats.derived.longestRound.file
    $longestSec = $Stats.derived.longestRound.sec
    $agents = @($Stats.agents)
    $roundDetail = @($Stats.roundDetail)
    $aggregate = $Stats.aggregate
    $children = @($Stats.children)

    # 明细合计（轮次求和口径，与 files.* 的文件扫描口径不是一个数）
    $rebuildAiSecTotal = 0
    $detailHumanChars = 0
    $detailAiChars = 0
    foreach ($r in $roundDetail) {
        if ($r.type -eq 'rebuild' -and $null -ne $r.aiSec) { $rebuildAiSecTotal += $r.aiSec }
        if ($null -ne $r.humanChars) { $detailHumanChars += $r.humanChars }
        if ($null -ne $r.aiChars) { $detailAiChars += $r.aiChars }
    }

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
    $childRebuild = $aggregate.rebuild - $rebuild
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
    # 总览三列统一分母 = 总跨度（$spanSec，三列中最大）：横向可比、自身+子主题可相加出总列；0 值不挂百分比
    $overviewRows = @(
        @{ Label = '总投入（人+AI）'; S = (Format-WithPercent $roundTotalSec $spanSec $true); C = (Format-WithPercent $childRound $spanSec $true); T = (Format-WithPercent $aggregate.roundTotalSec $spanSec $true) }
        @{ Label = '其中：人思考 / AI 执行'; S = "$(Format-WithPercent $humanSecTotal $spanSec $true) / $(Format-WithPercent $aiSecTotal $spanSec $true)"; C = "$(Format-WithPercent $childHuman $spanSec $true) / $(Format-WithPercent $childAi $spanSec $true)"; T = "$(Format-WithPercent $aggregate.humanSec $spanSec $true) / $(Format-WithPercent $aggregate.aiSec $spanSec $true)" }
        @{ Label = '轮间间隔合计'; S = (Format-WithPercent $gapTotalSec $spanSec $true); C = (Format-WithPercent ($aggregate.gapTotalSec - $gapTotalSec) $spanSec $true); T = (Format-WithPercent $aggregate.gapTotalSec $spanSec $true) }
        @{ Label = '活跃时长（剔除空闲段）'; S = (Format-WithPercent $activeSec $spanSec $true); C = (Format-WithPercent ($aggregate.activeSec - $activeSec) $spanSec $true); T = (Format-WithPercent $aggregate.activeSec $spanSec $true) }
        @{ Label = '墙钟时长（首末跨度）'; S = (Format-Stat $wallClockSec); C = $childSpanText; T = (Format-Stat $spanSec) }
        @{ Label = '总跨度（起 → 止）'; S = '—'; C = '—'; T = $spanText }
        @{ Label = '轮次（讨论 / 执行 / 重建）'; S = "$discussion / $execute / $rebuild"; C = "$childDisc / $childExec / $childRebuild"; T = "$($aggregate.discussion) / $($aggregate.execute) / $($aggregate.rebuild)" }
        @{ Label = '文件数'; S = "$fileTotal"; C = "$childFiles"; T = "$($aggregate.files)" }
        @{ Label = '字符数（人 / AI）'; S = "$(Format-FriendlyCount $humanCharsTotal) / $(Format-FriendlyCount $aiCharsTotal)"; C = "$(Format-FriendlyCount $childHChars) / $(Format-FriendlyCount $childAChars)"; T = "$(Format-FriendlyCount $aggregate.humanChars) / $(Format-FriendlyCount $aggregate.aiChars)" }
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
    [void]$sb.AppendLine("| 轮次总耗时（人+AI） | $(Format-WithPercent $roundTotalSec $wallClockSec) |")
    [void]$sb.AppendLine("| 人思考时长（讨论轮合计） | $(Format-WithPercent $humanSecTotal $wallClockSec) |")
    [void]$sb.AppendLine("| AI 执行时长（合计） | $(Format-WithPercent $aiSecTotal $wallClockSec) |")
    [void]$sb.AppendLine("| 轮间间隔合计 | $(Format-WithPercent $gapTotalSec $wallClockSec) |")
    [void]$sb.AppendLine("| 总时长（活跃，剔除 >${threshold}min 空闲段） | $(Format-WithPercent $activeSec $wallClockSec) |")
    [void]$sb.AppendLine("| 墙钟时长（首末日志原始跨度） | $(Format-Stat $wallClockSec) |")
    [void]$sb.AppendLine("| 忽略时长 / 段数 | $(Format-WithPercent $idleIgnoredSec $wallClockSec) / $idleIgnoredCount 段 |")
    $strategyText = @($executeByStrategy.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join '、'
    if ($strategyText -eq '') { $strategyText = '无' }
    [void]$sb.AppendLine("| 讨论轮 / 执行轮 / 重建轮 | $discussion / $execute / $rebuild（$strategyText） |")
    [void]$sb.AppendLine("| 文件数（总 / 人 / AI） | $fileTotal / $humanFiles / $aiFiles |")
    [void]$sb.AppendLine("| 字符数（人 / AI） | $(Format-FriendlyCount $humanCharsTotal) / $(Format-FriendlyCount $aiCharsTotal) 字符 |")
    [void]$sb.AppendLine("| 未知轮数（老日志配不上对） | $unknown |")
    [void]$sb.AppendLine("| 平均每轮耗时（人 / AI） | $(Format-Stat $avgHumanSec) / $(Format-Stat $avgAiSec) |")
    $longestText = if ($longestFile -eq '') { '无' } else { "$longestFile（$(Format-Stat $longestSec)）" }
    [void]$sb.AppendLine("| 最长轮次 | $longestText |")
    [void]$sb.AppendLine("| 重建轮（复关系） | $rebuild 次 / AI 耗时 $(Format-Stat $rebuildAiSecTotal) |")
    $agentsText = if ($agents.Count -gt 0) { $agents -join '、' } else { '未知' }
    [void]$sb.AppendLine("| 参与 Agent | $agentsText |")
    [void]$sb.AppendLine("| 主题创建 / 最后活动 | $(if ($createdAt) { $createdAt } else { '未知' }) / $(if ($lastAt) { $lastAt } else { '未知' }) |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 轮次明细")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| 文件 | 类型 | 人耗时 | AI耗时 | 合计耗时 | 轮间间隔 | 人字数 | AI字数 | Agent |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|---|---|---|")
    foreach ($r in $roundDetail) {
        $typeText = if ($r.type -eq 'execute') { '执行' } elseif ($r.type -eq 'rebuild') { '重建' } else { '讨论' }
        $hc = Format-FriendlyCount $r.humanChars
        $ac = Format-FriendlyCount $r.aiChars
        $ag = if ([string]::IsNullOrWhiteSpace($r.agent)) { '' } else { $r.agent }
        $fileText = $r.file
        if ($dupSendCountByTarget.ContainsKey($r.file) -and $dupSendCountByTarget[$r.file] -gt 0) {
            $fileText = "$($r.file)（重复发送 $($dupSendCountByTarget[$r.file] + 1) 次已合并）"
        }
        [void]$sb.AppendLine("| $fileText | $typeText | $(Format-Stat $r.humanSec) | $(Format-Stat $r.aiSec) | $(Format-WithPercent $r.totalSec $wallClockSec) | $(Format-WithPercent $r.gapSec $wallClockSec) | $hc | $ac | $ag |")
    }
    if ($roundDetail.Count -gt 0) {
        [void]$sb.AppendLine("| **合计** | — | $(Format-Stat $humanSecTotal) | $(Format-Stat $aiSecTotal) | $(Format-WithPercent $roundTotalSec $wallClockSec) | $(Format-WithPercent $gapTotalSec $wallClockSec) | $(Format-FriendlyCount $detailHumanChars) | $(Format-FriendlyCount $detailAiChars) | — |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## 子主题汇总")
    [void]$sb.AppendLine("")
    if ($children.Count -gt 0) {
        [void]$sb.AppendLine("| 子主题 | 路径 | 轮次(讨/执/建) | 总投入 | 人 / AI | 文件数 | 字符数(人/AI) | 最后活动 |")
        [void]$sb.AppendLine("|---|---|---|---|---|---|---|---|")
        foreach ($ch in $children) {
            $ca = $ch.aggregate
            $lastText = if ($ca.lastActiveAt) { $ca.lastActiveAt } else { '未知' }
            [void]$sb.AppendLine("| $($ch.name) | $($ch.relPath) | $($ca.discussion) / $($ca.execute) / $($ca.rebuild) | $(Format-Stat $ca.roundTotalSec) | $(Format-Stat $ca.humanSec) / $(Format-Stat $ca.aiSec) | $($ca.files) | $(Format-FriendlyCount $ca.humanChars) / $(Format-FriendlyCount $ca.aiChars) | $lastText |")
        }
        # 合计行：与"总览"的"子主题"列数值一致，可互查
        [void]$sb.AppendLine("| **合计** | — | $childDisc / $childExec / $childRebuild | $(Format-Stat $childRound) | $(Format-Stat $childHuman) / $(Format-Stat $childAi) | $childFiles | $(Format-FriendlyCount $childHChars) / $(Format-FriendlyCount $childAChars) | — |")
    } else {
        [void]$sb.AppendLine("无子主题。")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**口径说明**")
    [void]$sb.AppendLine("")
    # 条目文本来自 StatsSchema.psm1（定义单源），本文件只负责排版
    foreach ($note in @(Get-StatsRuleText -ThresholdMinutes $threshold -ComputedAt $Stats.computedAt)) {
        [void]$sb.AppendLine($note)
    }

    return $sb.ToString()
}

Export-ModuleMember -Function ConvertTo-StatsMarkdown, Format-FriendlyCount
