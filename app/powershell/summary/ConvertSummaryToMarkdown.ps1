<#
.SYNOPSIS
    Convert Summary.json to Summary.md.

.DESCRIPTION
    Read the structured Summary.json and render a complete Markdown view.

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

function Format-RoundLabel {
    param([int]$RoundIndex, [string]$Source, [string]$SourceName)
    if ($Source -eq 'main') {
        return "R$RoundIndex"
    }
    elseif ($Source -eq 'resultFineTuning') {
        return "结果微调/$SourceName-R$RoundIndex"
    }
    elseif ($Source -eq 'subTheme') {
        return "子主题/$SourceName-R$RoundIndex"
    }
    return "R$RoundIndex"
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

    # 使用 breakdown 替代已删除的 stageTime
    if ($json.breakdown.main.rounds -gt 0) {
        Add-Line -Lines ([ref]$lines) ("- 主讨论：" + $json.breakdown.main.timeMinutes + " 分钟（" + $json.breakdown.main.rounds + " 轮）")
    }
    if ($json.breakdown.resultFineTunings.rounds -gt 0) {
        Add-Line -Lines ([ref]$lines) ("- 结果微调：" + $json.breakdown.resultFineTunings.timeMinutes + " 分钟（" + $json.breakdown.resultFineTunings.rounds + " 轮）")
    }
    if ($json.breakdown.subThemes.rounds -gt 0) {
        Add-Line -Lines ([ref]$lines) ("- 子主题：" + $json.breakdown.subThemes.timeMinutes + " 分钟（" + $json.breakdown.subThemes.rounds + " 轮）")
    }

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
    # 按轮次
    $r = $json.metrics.byRound
    $rSmooth = $r.normal + $r.refinement + $r.exploration + $r.idle
    $rTotal = $json.metrics.totalRounds
    Add-Line -Lines ([ref]$lines) "### 按轮次"
    Add-Line -Lines ([ref]$lines) ("- 意图匹配率：" + (Format-Percent $r.intentMatchRate) + "（顺畅 " + $rSmooth + "/" + $rTotal + " 轮）")
    Add-Line -Lines ([ref]$lines) ("- 纠偏率：" + (Format-Percent $r.correctionRate) + "（纠偏 " + ($r.correction + $r.extreme) + "/" + $rTotal + " 轮，含失控 " + $r.extreme + " 轮）")
    Add-Line -Lines ([ref]$lines) ("- 失控率：" + (Format-Percent $r.extremeRate) + "（失控 " + $r.extreme + "/" + $rTotal + " 轮）")
    Add-Empty -Lines ([ref]$lines)
    # 按时间
    $t = $json.metrics.byTime
    $tTotal = $json.metrics.totalTimeMinutes
    Add-Line -Lines ([ref]$lines) "### 按时间"
    Add-Line -Lines ([ref]$lines) ("- 意图匹配率：" + (Format-Percent $t.intentMatchRate) + "（顺畅 " + $t.smoothMinutes + "/" + $tTotal + " 分钟）")
    Add-Line -Lines ([ref]$lines) ("- 纠偏率：" + (Format-Percent $t.correctionRate) + "（纠偏 " + ($t.correctionMinutes + $t.extremeMinutes) + "/" + $tTotal + " 分钟，含失控 " + $t.extremeMinutes + " 分钟）")
    Add-Line -Lines ([ref]$lines) ("- 失控率：" + (Format-Percent $t.extremeRate) + "（失控 " + $t.extremeMinutes + "/" + $tTotal + " 分钟）")
    Add-Empty -Lines ([ref]$lines)
    # 按字数
    $c = $json.metrics.byChars
    $cTotal = $json.metrics.totalHumanChars
    Add-Line -Lines ([ref]$lines) "### 按字数"
    Add-Line -Lines ([ref]$lines) ("- 意图匹配率：" + (Format-Percent $c.intentMatchRate) + "（顺畅 " + $c.smoothHumanChars + "/" + $cTotal + " 字）")
    Add-Line -Lines ([ref]$lines) ("- 纠偏率：" + (Format-Percent $c.correctionRate) + "（纠偏 " + ($c.correctionHumanChars + $c.extremeHumanChars) + "/" + $cTotal + " 字，含失控 " + $c.extremeHumanChars + " 字）")
    Add-Line -Lines ([ref]$lines) ("- 失控率：" + (Format-Percent $c.extremeRate) + "（失控 " + $c.extremeHumanChars + "/" + $cTotal + " 字）")
    Add-Empty -Lines ([ref]$lines)

    # 3. 主讨论-阶段划分
    Add-Line -Lines ([ref]$lines) "## 3. 主讨论"
    Add-Empty -Lines ([ref]$lines)
    Add-Line -Lines ([ref]$lines) "### 阶段划分"
    foreach ($phase in $json.rounds.phases) {
        $indexes = $phase.roundIndexes -join ", "
        Add-Line -Lines ([ref]$lines) ("- **" + $phase.name + "**（R" + $indexes + "）：" + $phase.summary)
    }
    Add-Empty -Lines ([ref]$lines)

    # 3.1 主讨论-轮次时间轴
    Add-Line -Lines ([ref]$lines) "### 轮次时间轴"
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

    # 3.2 结果微调渲染
    if ($json.resultFineTunings -and $json.resultFineTunings.Count -gt 0) {
        Add-Line -Lines ([ref]$lines) "## 4. 结果微调"
        Add-Empty -Lines ([ref]$lines)

        $rfIndex = 0
        foreach ($rf in $json.resultFineTunings) {
            $rfIndex++
            $rfName = $rf.name
            Add-Line -Lines ([ref]$lines) ("### 4." + $rfIndex + " 结果微调/" + $rfName)
            if ($rf.totalTime) {
                Add-Line -Lines ([ref]$lines) ("- 总耗时：" + $rf.totalTime.display + "，共 " + $rf.rounds.total + " 轮")
            }
            Add-Empty -Lines ([ref]$lines)

            # 阶段
            if ($rf.rounds.phases -and $rf.rounds.phases.Count -gt 0) {
                Add-Line -Lines ([ref]$lines) "**阶段划分**"
                foreach ($phase in $rf.rounds.phases) {
                    $indexes = $phase.roundIndexes -join ", "
                    Add-Line -Lines ([ref]$lines) ("- **" + $phase.name + "**（R" + $indexes + "）：" + $phase.summary)
                }
                Add-Empty -Lines ([ref]$lines)
            }

            # 轮次时间轴
            if ($rf.rounds.items -and $rf.rounds.items.Count -gt 0) {
                Add-Line -Lines ([ref]$lines) "**轮次时间轴**"
                Add-Line -Lines ([ref]$lines) "| 轮次 | 类型 | 耗时 | 人输入摘要 | AI 回复摘要 |"
                Add-Line -Lines ([ref]$lines) "|---|---|---|---|---|"
                foreach ($round in $rf.rounds.items) {
                    $type = $round.category
                    if ($round.isExtreme) {
                        $type += "（极端失控）"
                    }
                    Add-Line -Lines ([ref]$lines) ("| R" + $round.roundIndex + " | " + $type + " | " + $round.durationMinutes + "分钟 | " + $round.humanSummary + " | " + $round.aiSummary + " |")
                }
                Add-Empty -Lines ([ref]$lines)
            }
        }
    }

    # 4. 子主题
    if ($json.subThemes -and $json.subThemes.Count -gt 0) {
        Add-Line -Lines ([ref]$lines) "## 5. 子主题"
        Add-Empty -Lines ([ref]$lines)
        Add-Line -Lines ([ref]$lines) "| 子主题 | 轮次 | 总耗时 | 人输入字数 | AI 输出字数 |"
        Add-Line -Lines ([ref]$lines) "|---|---|---|---|---|"
        foreach ($sub in $json.subThemes) {
            $timeDisplay = if ($sub.totalTime) { $sub.totalTime.display } else { "-" }
            Add-Line -Lines ([ref]$lines) ("| " + $sub.name + " | " + $sub.rounds.total + " | " + $timeDisplay + " | " + $sub.totalHumanChars + " | " + $sub.totalAiChars + " |")
        }
        Add-Empty -Lines ([ref]$lines)

        # 子主题轮次时间轴
        $stIndex = 0
        foreach ($sub in $json.subThemes) {
            $stIndex++
            Add-Line -Lines ([ref]$lines) ("### 5." + $stIndex + " " + $sub.name)
            if ($sub.rounds.items -and $sub.rounds.items.Count -gt 0) {
                Add-Line -Lines ([ref]$lines) "| 轮次 | 类型 | 耗时 | 人输入摘要 | AI 回复摘要 |"
                Add-Line -Lines ([ref]$lines) "|---|---|---|---|---|"
                foreach ($round in $sub.rounds.items) {
                    $type = $round.category
                    if ($round.isExtreme) {
                        $type += "（极端失控）"
                    }
                    Add-Line -Lines ([ref]$lines) ("| R" + $round.roundIndex + " | " + $type + " | " + $round.durationMinutes + "分钟 | " + $round.humanSummary + " | " + $round.aiSummary + " |")
                }
                Add-Empty -Lines ([ref]$lines)
            }
        }
    }

    # 5. 纠偏分析
    $correctionSectionIndex = if ($json.resultFineTunings -and $json.resultFineTunings.Count -gt 0) { 6 } elseif ($json.subThemes -and $json.subThemes.Count -gt 0) { 5 } else { 4 }
    Add-Line -Lines ([ref]$lines) ("## " + $correctionSectionIndex + ". 纠偏分析")
    if ($json.analysis.correctionAnalysis.perRound -and $json.analysis.correctionAnalysis.perRound.Count -gt 0) {
        foreach ($item in $json.analysis.correctionAnalysis.perRound) {
            $label = Format-RoundLabel -RoundIndex $item.roundIndex -Source 'main' -SourceName ''
            Add-Line -Lines ([ref]$lines) ("### " + $label + " —— " + $item.summary)
            Add-Line -Lines ([ref]$lines) ("- 根因：" + $item.rootCause)
            Add-Line -Lines ([ref]$lines) ("- 影响：" + $item.impact)
            Add-Line -Lines ([ref]$lines) ("- 经验：" + $item.lesson)
            Add-Empty -Lines ([ref]$lines)
        }
        Add-Line -Lines ([ref]$lines) ("**总体规律**：" + $json.analysis.correctionAnalysis.summary.mainPattern)
        Add-Line -Lines ([ref]$lines) ("**核心经验**：" + $json.analysis.correctionAnalysis.summary.keyLesson)
    }
    else {
        Add-Line -Lines ([ref]$lines) "无"
    }
    Add-Empty -Lines ([ref]$lines)

    # 6. 失控分析
    $extremeSectionIndex = $correctionSectionIndex + 1
    Add-Line -Lines ([ref]$lines) ("## " + $extremeSectionIndex + ". 失控分析")
    if ($json.analysis.extremeAnalysis.perRound -and $json.analysis.extremeAnalysis.perRound.Count -gt 0) {
        foreach ($item in $json.analysis.extremeAnalysis.perRound) {
            $label = Format-RoundLabel -RoundIndex $item.roundIndex -Source 'main' -SourceName ''
            Add-Line -Lines ([ref]$lines) ("### " + $label + " —— " + $item.summary)
            Add-Line -Lines ([ref]$lines) ("- 触发点：" + $item.trigger)
            Add-Line -Lines ([ref]$lines) ("- 升级路径：" + $item.escalation)
            Add-Line -Lines ([ref]$lines) ("- 解决方式：" + $item.resolution)
            Add-Line -Lines ([ref]$lines) ("- 经验：" + $item.lesson)
            Add-Empty -Lines ([ref]$lines)
        }
        Add-Line -Lines ([ref]$lines) ("**总体规律**：" + $json.analysis.extremeAnalysis.summary.mainPattern)
        Add-Line -Lines ([ref]$lines) ("**核心经验**：" + $json.analysis.extremeAnalysis.summary.keyLesson)
    }
    else {
        Add-Line -Lines ([ref]$lines) "无"
    }
    Add-Empty -Lines ([ref]$lines)

    # 7. 元信息
    $metaSectionIndex = $extremeSectionIndex + 1
    Add-Line -Lines ([ref]$lines) ("## " + $metaSectionIndex + ". 元信息")
    Add-Line -Lines ([ref]$lines) ("- 主题路径：" + $json.themePath)
    Add-Line -Lines ([ref]$lines) ("- 生成时间：" + $json.generatedAt)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($outputPath, $lines, $utf8NoBom)
    Write-Output $outputPath
}
catch {
    throw
}
