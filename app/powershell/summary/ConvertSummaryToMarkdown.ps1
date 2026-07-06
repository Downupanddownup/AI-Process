<#
.SYNOPSIS
    Convert Summary.json to Summary.md.

.DESCRIPTION
    Read the structured Summary.json and render a simple Markdown view.

.PARAMETER JsonPath
    Absolute path to Summary.json.
#>

param(
    [Parameter(Mandatory = $true)][string]$JsonPath
)

$ErrorActionPreference = "Stop"

function Format-Percent {
    param([double]$Value)
    return "{0:P0}" -f $Value
}

function Add-Line {
    param([ref]$Lines, [string]$Line)
    $Lines.Value += $Line
}

function Add-Empty {
    param([ref]$Lines)
    $Lines.Value += ""
}

try {
    if (-not (Test-Path $JsonPath)) {
        throw "Summary.json not found: $JsonPath"
    }

    $json = Get-Content -Path $JsonPath -Encoding UTF8 -Raw | ConvertFrom-Json
    $themeDir = Split-Path -Parent $JsonPath
    $outputPath = Join-Path $themeDir 'Summary.md'

    $lines = @()

    Add-Line -Lines ([ref]$lines) ("# 经验总结：" + $json.themeName)
    Add-Empty -Lines ([ref]$lines)

    # 1. 总览
    Add-Line -Lines ([ref]$lines) "## 1. 总览"
    Add-Line -Lines ([ref]$lines) $json.overview.abstract
    Add-Empty -Lines ([ref]$lines)
    Add-Line -Lines ([ref]$lines) ("- 总耗时：" + $json.overview.totalTime.display)
    Add-Line -Lines ([ref]$lines) ("- 讨论阶段：" + $json.overview.stageTime.discussion.display)
    Add-Line -Lines ([ref]$lines) ("- 执行阶段：" + $json.overview.stageTime.execution.display)
    Add-Line -Lines ([ref]$lines) ("- 结果微调阶段：" + $json.overview.stageTime.tweak.display)
    Add-Line -Lines ([ref]$lines) ("- 复杂程度：" + $json.overview.complexity + " —— " + $json.overview.complexityReason)
    Add-Line -Lines ([ref]$lines) ("- 协作顺畅度：" + $json.overview.collaboration + " —— " + $json.overview.collaborationReason)
    if ($json.overview.tags -and $json.overview.tags.Count -gt 0) {
        Add-Line -Lines ([ref]$lines) ("- 标签：" + ($json.overview.tags -join "、"))
    }
    Add-Empty -Lines ([ref]$lines)

    # 2. 核心指标
    Add-Line -Lines ([ref]$lines) "## 2. 核心指标"
    Add-Line -Lines ([ref]$lines) ("- 总轮次：" + $json.metrics.totalRounds)
    Add-Line -Lines ([ref]$lines) ("- 总耗时：" + $json.metrics.totalTimeMinutes + " 分钟")
    Add-Line -Lines ([ref]$lines) ("- 人输入总字数：" + $json.metrics.totalHumanChars)
    Add-Line -Lines ([ref]$lines) ("- AI 输出总字数：" + $json.metrics.totalAiChars)
    Add-Empty -Lines ([ref]$lines)
    Add-Line -Lines ([ref]$lines) "### 按轮次"
    Add-Line -Lines ([ref]$lines) ("- 意图匹配率：" + (Format-Percent $json.metrics.byRound.intentMatchRate))
    Add-Line -Lines ([ref]$lines) ("- 纠偏率：" + (Format-Percent $json.metrics.byRound.correctionRate))
    Add-Line -Lines ([ref]$lines) ("- 失控率：" + (Format-Percent $json.metrics.byRound.extremeRate))
    Add-Empty -Lines ([ref]$lines)
    Add-Line -Lines ([ref]$lines) "### 按时间"
    Add-Line -Lines ([ref]$lines) ("- 意图匹配率：" + (Format-Percent $json.metrics.byTime.intentMatchRate))
    Add-Line -Lines ([ref]$lines) ("- 纠偏率：" + (Format-Percent $json.metrics.byTime.correctionRate))
    Add-Line -Lines ([ref]$lines) ("- 失控率：" + (Format-Percent $json.metrics.byTime.extremeRate))
    Add-Empty -Lines ([ref]$lines)
    Add-Line -Lines ([ref]$lines) "### 按字数"
    Add-Line -Lines ([ref]$lines) ("- 意图匹配率：" + (Format-Percent $json.metrics.byChars.intentMatchRate))
    Add-Line -Lines ([ref]$lines) ("- 纠偏率：" + (Format-Percent $json.metrics.byChars.correctionRate))
    Add-Line -Lines ([ref]$lines) ("- 失控率：" + (Format-Percent $json.metrics.byChars.extremeRate))
    Add-Empty -Lines ([ref]$lines)

    # 3. 阶段划分
    Add-Line -Lines ([ref]$lines) "## 3. 阶段划分"
    foreach ($phase in $json.rounds.phases) {
        $indexes = $phase.roundIndexes -join ", "
        Add-Line -Lines ([ref]$lines) ("### " + $phase.name + "（R" + $indexes + "）")
        Add-Line -Lines ([ref]$lines) $phase.summary
        Add-Empty -Lines ([ref]$lines)
    }

    # 4. 轮次时间轴
    Add-Line -Lines ([ref]$lines) "## 4. 轮次时间轴"
    Add-Line -Lines ([ref]$lines) "| 轮次 | 类型 | 耗时 | 人输入摘要 | AI 回复摘要 |"
    Add-Line -Lines ([ref]$lines) "|---|---|---|---|---|"
    foreach ($round in $json.rounds.items) {
        $type = $round.category
        if ($round.isExtreme) {
            $type += "（极端失控）"
        }
        Add-Line -Lines ([ref]$lines) ("| R" + $round.roundIndex + " | " + $type + " | " + $round.durationMinutes + "分钟 | " + $round.humanSummary + " | " + $round.aiSummary + " |")
    }
    Add-Empty -Lines ([ref]$lines)

    # 5. 纠偏分析
    Add-Line -Lines ([ref]$lines) "## 5. 纠偏分析"
    if ($json.analysis.correctionAnalysis.perRound -and $json.analysis.correctionAnalysis.perRound.Count -gt 0) {
        foreach ($item in $json.analysis.correctionAnalysis.perRound) {
            Add-Line -Lines ([ref]$lines) ("### R" + $item.roundIndex + " —— " + $item.summary)
            Add-Line -Lines ([ref]$lines) ("- 根因：" + $item.rootCause)
            Add-Line -Lines ([ref]$lines) ("- 影响：" + $item.impact)
            Add-Line -Lines ([ref]$lines) ("- 经验：" + $item.lesson)
            Add-Empty -Lines ([ref]$lines)
        }
        Add-Line -Lines ([ref]$lines) "**总体规律**：" + $json.analysis.correctionAnalysis.summary.mainPattern
        Add-Line -Lines ([ref]$lines) "**核心经验**：" + $json.analysis.correctionAnalysis.summary.keyLesson
    }
    else {
        Add-Line -Lines ([ref]$lines) "无"
    }
    Add-Empty -Lines ([ref]$lines)

    # 6. 失控分析
    Add-Line -Lines ([ref]$lines) "## 6. 失控分析"
    if ($json.analysis.extremeAnalysis.perRound -and $json.analysis.extremeAnalysis.perRound.Count -gt 0) {
        foreach ($item in $json.analysis.extremeAnalysis.perRound) {
            Add-Line -Lines ([ref]$lines) ("### R" + $item.roundIndex + " —— " + $item.summary)
            Add-Line -Lines ([ref]$lines) ("- 触发点：" + $item.trigger)
            Add-Line -Lines ([ref]$lines) ("- 升级路径：" + $item.escalation)
            Add-Line -Lines ([ref]$lines) ("- 解决方式：" + $item.resolution)
            Add-Line -Lines ([ref]$lines) ("- 经验：" + $item.lesson)
            Add-Empty -Lines ([ref]$lines)
        }
        Add-Line -Lines ([ref]$lines) "**总体规律**：" + $json.analysis.extremeAnalysis.summary.mainPattern
        Add-Line -Lines ([ref]$lines) "**核心经验**：" + $json.analysis.extremeAnalysis.summary.keyLesson
    }
    else {
        Add-Line -Lines ([ref]$lines) "无"
    }
    Add-Empty -Lines ([ref]$lines)

    # 7. 子主题
    Add-Line -Lines ([ref]$lines) "## 7. 子主题耗时"
    if ($json.subThemes -and $json.subThemes.Count -gt 0) {
        Add-Line -Lines ([ref]$lines) "| 子主题 | 总耗时 | 讨论 | 执行 | 微调 |"
        Add-Line -Lines ([ref]$lines) "|---|---|---|---|---|"
        foreach ($sub in $json.subThemes) {
            Add-Line -Lines ([ref]$lines) ("| " + $sub.path + " | " + $sub.totalTime + " | " + $sub.discussionTime + " | " + $sub.executionTime + " | " + $sub.tweakTime + " |")
        }
    }
    else {
        Add-Line -Lines ([ref]$lines) "无"
    }
    Add-Empty -Lines ([ref]$lines)

    # 8. 元信息
    Add-Line -Lines ([ref]$lines) "## 8. 元信息"
    Add-Line -Lines ([ref]$lines) ("- 主题路径：" + $json.themePath)
    Add-Line -Lines ([ref]$lines) ("- 生成时间：" + $json.generatedAt)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($outputPath, $lines, $utf8NoBom)
    Write-Output $outputPath
}
catch {
    throw
}
