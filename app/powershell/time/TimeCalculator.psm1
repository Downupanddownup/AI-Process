<#
.SYNOPSIS
    耗时计算共享模块：纯逻辑（不读/写文件），供注入脚本与后续汇总复用。

.DESCRIPTION
    提供三个导出函数：
      - Get-RoundBreakdown：按给定的三个时间点计算某轮"人思考/AI处理"秒数及是否跨天忽略。
      - Format-FriendlyDuration：把秒数转换为友好字符串（自动缩放单位、精确到秒）。
      - Format-FriendlyCount：把字符数转换为友好字符串（<1万 原样+千分位；>=1万 按万/亿缩写）。

    兼容 Windows PowerShell 5.1。保持单向依赖：本模块不引用任何调用方/业务模块。
#>

function Get-RoundBreakdown {
    <#
    .SYNOPSIS
        计算一轮的人思考与 AI 处理时长（秒）。
    .PARAMETER HumanStart
        人思考起点时刻。可为 $null（无法定位时按 0 处理）。
    .PARAMETER ThisSend
        人把需求/回复发给 AI 的时刻。
    .PARAMETER AiEnd
        AI 处理终点（注入时传当前时刻；汇总时传真实"完成通知"时间）。
    .PARAMETER ThresholdMinutes
        跨天忽略阈值（分钟），默认 60。某段秒数若大于阈值则标记忽略。
    #>
    param(
        [object]$HumanStart,
        [object]$ThisSend,
        [object]$AiEnd,
        [int]$ThresholdMinutes = 60
    )
    $MAX = $ThresholdMinutes * 60
    $humanSeconds = 0
    $aiSeconds = 0
    $humanIgnored = $false
    $aiIgnored = $false

    # AI 处理：ThisSend -> AiEnd
    if ($null -ne $ThisSend -and $null -ne $AiEnd) {
        $diff = ([datetime]$AiEnd - [datetime]$ThisSend).TotalSeconds
        if ($diff -gt 0) {
            $aiSeconds = [int][Math]::Round($diff)
            if ($diff -gt $MAX) { $aiIgnored = $true }
        }
    }

    # 人思考：HumanStart -> ThisSend
    if ($null -ne $HumanStart -and $null -ne $ThisSend) {
        $diff = ([datetime]$ThisSend - [datetime]$HumanStart).TotalSeconds
        if ($diff -gt 0) {
            $humanSeconds = [int][Math]::Round($diff)
            if ($diff -gt $MAX) { $humanIgnored = $true }
        }
    }

    # 本轮合计 = 人思考 + AI处理 中【未忽略】部分之和（跨天忽略段不计入）
    $totalSeconds = 0
    if (-not $humanIgnored) { $totalSeconds += $humanSeconds }
    if (-not $aiIgnored) { $totalSeconds += $aiSeconds }

    return [PSCustomObject]@{
        humanSeconds = $humanSeconds
        aiSeconds    = $aiSeconds
        humanIgnored = $humanIgnored
        aiIgnored    = $aiIgnored
        totalSeconds = $totalSeconds
    }
}

function Format-FriendlyDuration {
    <#
    .SYNOPSIS
        把秒数转换为友好字符串，自动缩放单位并精确到秒。
        ⚠ AHK 侧 app/modules/business/services/ThemeStats.ahk 有等价换算（列表显示用），改口径时两边一起改。
    .PARAMETER Seconds
        秒数，负数按 0 处理。
    .PARAMETER Ignored
        该段是否被忽略，为真时前缀 "忽略·"。
    #>
    param(
        [int]$Seconds,
        [bool]$Ignored = $false
    )
    $sec = [int][Math]::Max(0, [int][Math]::Round($Seconds))
    $text = ""
    if ($sec -lt 60) {
        $text = "$sec 秒"
    } elseif ($sec -lt 3600) {
        $m = [int][Math]::Floor($sec / 60)
        $s = $sec % 60
        $text = "$m 分 $s 秒"
    } else {
        $h = [int][Math]::Floor($sec / 3600)
        $m = [int][Math]::Floor(($sec % 3600) / 60)
        $s = $sec % 60
        $text = "$h 时 $m 分 $s 秒"
    }
    if ($Ignored) {
        return "忽略·$text"
    }
    return $text
}

# ---------- 字符数友好显示：<1万 原样+千分位；>=1万 按万/亿缩写（3 位有效数字）；stats.json 恒为精确整数 ----------
# ⚠ AHK 侧 app/modules/business/services/ThemeStats.ahk 有等价换算（列表显示用），改口径时两边一起改。
function Format-FriendlyCount {
    <#
    .SYNOPSIS
        把字符数转换为友好显示文本（统计.md 与文件元数据打标共用同一口径）。
    .PARAMETER Number
        字符数，null 记 "未知"。
    #>
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

Export-ModuleMember -Function Get-RoundBreakdown, Format-FriendlyDuration, Format-FriendlyCount
