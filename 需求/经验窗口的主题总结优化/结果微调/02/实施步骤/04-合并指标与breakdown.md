# 步骤 04：合并指标与 breakdown

## 目标

将根目录、结果微调、子主题三部分的轮次合并，统一计算总时间、总字数，并新增 `breakdown` 字段拆分各部分贡献。

## 涉及文件

- `app/powershell/summary/PrepareSummaryInput.ps1`

## 具体操作

### 1. 合并所有轮次

在主流程中，生成子单元后，合并所有轮次：

```powershell
$allRounds = @($rounds) + 
             @($resultFineTunings | ForEach-Object { $_.rounds.items }) + 
             @($subThemes | ForEach-Object { $_.rounds.items })

$totalHumanChars = ($allRounds | Measure-Object -Property humanChars -Sum).Sum
$totalAiChars = ($allRounds | Measure-Object -Property aiChars -Sum).Sum
```

### 2. 计算总时间

`Get-TotalTime` 和 `Get-StageTime` 传入合并后的轮次：

```powershell
$stageTime = Get-StageTime -Dir $themePath -Rounds $allRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
$totalTime = Get-TotalTime -Dir $themePath -Rounds $allRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
```

### 3. 计算 breakdown

新增 breakdown 计算逻辑：

```powershell
$mainTime = Get-TotalTime -Dir $themePath -Rounds $rounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
$rtRounds = @($resultFineTunings | ForEach-Object { $_.rounds.items })
$stRounds = @($subThemes | ForEach-Object { $_.rounds.items })
$rtTime = if ($rtRounds.Count -gt 0) {
    Get-TotalTime -Dir $themePath -Rounds $rtRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
} else {
    [PSCustomObject]@{ minutes = 0; display = '0分钟' }
}
$stTime = if ($stRounds.Count -gt 0) {
    Get-TotalTime -Dir $themePath -Rounds $stRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
} else {
    [PSCustomObject]@{ minutes = 0; display = '0分钟' }
}

$breakdown = [PSCustomObject]@{
    main = [PSCustomObject]@{
        rounds      = $rounds.Count
        timeMinutes = $mainTime.minutes
        humanChars  = ($rounds | Measure-Object -Property humanChars -Sum).Sum
        aiChars     = ($rounds | Measure-Object -Property aiChars -Sum).Sum
    }
    resultFineTunings = [PSCustomObject]@{
        rounds      = $rtRounds.Count
        timeMinutes = $rtTime.minutes
        humanChars  = ($rtRounds | Measure-Object -Property humanChars -Sum).Sum
        aiChars     = ($rtRounds | Measure-Object -Property aiChars -Sum).Sum
    }
    subThemes = [PSCustomObject]@{
        rounds      = $stRounds.Count
        timeMinutes = $stTime.minutes
        humanChars  = ($stRounds | Measure-Object -Property humanChars -Sum).Sum
        aiChars     = ($stRounds | Measure-Object -Property aiChars -Sum).Sum
    }
}
```

### 4. 更新输出结构

将 `breakdown` 加入 `$output`：

```powershell
$output = [PSCustomObject]@{
    themeName         = Split-Path -Leaf $themePath
    themePath         = $themePath
    generatedAt       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    files             = [PSCustomObject]@{ ... }
    rounds            = [PSCustomObject]@{ ... }
    resultFineTunings = $resultFineTunings
    subThemes         = $subThemes
    stageTime         = $stageTime
    totalTime         = $totalTime
    totalHumanChars   = $totalHumanChars
    totalAiChars      = $totalAiChars
    breakdown         = $breakdown
}
```

## 验证

在「周报时间」主题上运行 `PrepareSummaryInput.ps1`，检查：

- `totalHumanChars` = 根目录 + 结果微调 + 子主题的 `humanChars` 之和。
- `totalAiChars` = 根目录 + 结果微调 + 子主题的 `aiChars` 之和。
- `breakdown.main.rounds` + `breakdown.resultFineTunings.rounds` + `breakdown.subThemes.rounds` = `rounds.total` + 子单元轮次总数。
- `breakdown` 中三部分的 `humanChars` / `aiChars` 之和分别等于 `totalHumanChars` / `totalAiChars`。
