# 活跃时长计算工具
# 对给定时间范围，按相邻活跃点间隔是否超过阈值来累计真实工作时间

function Get-ActiveDuration {
    param(
        [Parameter(Mandatory = $true)][datetime]$Start,
        [Parameter(Mandatory = $true)][datetime]$End,
        [array]$FileCreationTimes = @(),
        [array]$LogTimes = @(),
        [int]$ThresholdMinutes = 60
    )

    if ($End -le $Start) {
        return [TimeSpan]::Zero
    }

    $points = @($Start, $End)

    foreach ($t in $FileCreationTimes) {
        if ($t -ge $Start -and $t -le $End) {
            $points += $t
        }
    }

    foreach ($t in $LogTimes) {
        if ($t -ge $Start -and $t -le $End) {
            $points += $t
        }
    }

    # 按秒去重并排序
    $uniqueMap = @{}
    foreach ($t in $points) {
        $key = $t.ToString('yyyyMMddHHmmss')
        if (-not $uniqueMap.ContainsKey($key)) {
            $uniqueMap[$key] = $t
        }
    }
    $deduped = @($uniqueMap.Values | Sort-Object)

    if ($deduped.Count -lt 2) {
        return [TimeSpan]::Zero
    }

    $totalSeconds = 0
    $thresholdSeconds = $ThresholdMinutes * 60
    for ($i = 0; $i -lt $deduped.Count - 1; $i++) {
        $diff = ($deduped[$i + 1] - $deduped[$i]).TotalSeconds
        if ($diff -gt 0 -and $diff -le $thresholdSeconds) {
            $totalSeconds += $diff
        }
    }

    return [TimeSpan]::FromSeconds($totalSeconds)
}
