<#
.SYNOPSIS
    轮次配对共享模块：纯逻辑（不读/写业务文件），供单文档打标与总体统计同调一份口径。

.DESCRIPTION
    提供四个导出函数：
      - Get-LogEntries：读取操作日志 log.jsonl（含归属标识 target/source、agent、执行策略 strategy 与 content 长度；损坏行静默跳过）。
      - Test-TargetMatch：target 匹配，支持 "|" 分隔的候选（如 "v5.md|实施文档.md"），精确匹配文件名。
      - Get-TargetRoundInfo：按 target/source 定位本轮；非轮次 md 返回 $null；配对失败返回 matched=$false。
      - Get-FirstTargetNotificationAfter：thisSend 之后第一条同 target 的完成通知。
      - Get-HumanStartForSend：按发送动作的 source 定位人思考起点（建X）；复执行恒无（人耗时 0）。
      - Get-RoundGap：轮间间隔 = 本轮起点 − 此前最近一条完成通知；首轮或无先例通知时为 0。

    兼容 Windows PowerShell 5.1。保持单向依赖：本模块不引用任何调用方/业务模块。
#>

# ---------- 读取操作日志（含归属标识 target/source 与 agent；损坏行静默跳过） ----------
function Get-LogEntries {
    param([string]$LogFile)
    $result = @()
    if (-not (Test-Path -LiteralPath $LogFile)) {
        return $result
    }
    foreach ($line in (Get-Content -LiteralPath $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $t = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        try {
            $obj = $t | ConvertFrom-Json
            $time = [datetime]::ParseExact($obj.time, "yyyy-MM-dd HH:mm:ss", $null)
            $target = ""
            $source = ""
            if ($obj.properties) {
                if ($obj.properties.target) { $target = [string]$obj.properties.target }
                if ($obj.properties.source) { $source = [string]$obj.properties.source }
            }
            $agent = ""
            if ($obj.agent) { $agent = [string]$obj.agent }
            $strategy = ""
            $contentChars = 0
            $roundType = ""
            if ($obj.properties) {
                if ($obj.properties.'执行策略') { $strategy = [string]$obj.properties.'执行策略' }
                if ($obj.properties.'round-type') { $roundType = [string]$obj.properties.'round-type' }
            }
            if ($null -ne $obj.content) { $contentChars = ([string]$obj.content).Length }
            $result += [PSCustomObject]@{
                time         = $time
                action       = [string]$obj.action
                target       = $target
                source       = $source
                agent        = $agent
                strategy     = $strategy
                roundType    = $roundType
                contentChars = $contentChars
            }
        } catch {
            # 忽略无效行
        }
    }
    return $result
}

# ---------- target 匹配：支持"|"分隔的候选（如 "v5.md|实施文档.md"），精确匹配文件名 ----------
function Test-TargetMatch {
    param(
        [string]$TargetValue,
        [string]$FileName
    )
    if ([string]::IsNullOrWhiteSpace($TargetValue)) { return $false }
    foreach ($part in ($TargetValue -split '\|')) {
        if ($part.Trim() -eq $FileName) { return $true }
    }
    return $false
}

# ---------- 人思考起点：按发送动作的 source 定位同 source 最近的 建X ----------
function Get-HumanStartForSend {
    param(
        [array]$Entries,
        [object]$Send
    )
    if ($Send.action -eq '复执行') {
        # 执行类文件（改吧结果 / 已实施.md）：human 恒 0
        return [PSCustomObject]@{ humanStart = $null; humanUnknown = $false }
    }
    # 讨论轮：source 定位人思考段（复需求无 source 时按 需求.txt）
    $src = $Send.source
    if ($Send.action -eq '复需求' -and [string]::IsNullOrWhiteSpace($src)) { $src = '需求.txt' }
    if ([string]::IsNullOrWhiteSpace($src)) {
        return [PSCustomObject]@{ humanStart = $null; humanUnknown = $true }
    }
    $buildAction = if ($src -eq '需求.txt') { '建需求' } else { '建回复' }
    $humanStart = $null
    foreach ($e in $Entries) {
        if ($e.action -ne $buildAction) { continue }
        if ($e.target -ne $src) { continue }
        if ($e.time -le $Send.time -and ($null -eq $humanStart -or $e.time -gt $humanStart)) {
            $humanStart = $e.time
        }
    }
    return [PSCustomObject]@{ humanStart = $humanStart; humanUnknown = ($null -eq $humanStart) }
}

# ---------- 按 target/source 定位本轮：非轮次 md 返回 $null；配对失败返回 matched=$false ----------
function Get-TargetRoundInfo {
    param(
        [array]$Entries,
        [string]$FileName
    )
    # 仅处理轮次 md
    if ($FileName -notmatch '^v\d+\.md$' -and $FileName -ne '实施文档.md' -and $FileName -ne '已实施.md') {
        return $null
    }

    # 找指向本文件的发送动作；同 target 多次 → 配最后一次（消歧）
    $send = $null
    foreach ($e in $Entries) {
        if ($e.action -ne '复需求' -and $e.action -ne '复回复' -and $e.action -ne '复执行') { continue }
        if (-not (Test-TargetMatch -TargetValue $e.target -FileName $FileName)) { continue }
        if ($null -eq $send -or $e.time -gt $send.time) { $send = $e }
    }
    if ($null -eq $send) {
        return [PSCustomObject]@{ matched = $false }
    }

    $human = Get-HumanStartForSend -Entries $Entries -Send $send

    return [PSCustomObject]@{
        matched      = $true
        humanStart   = $human.humanStart
        humanUnknown = $human.humanUnknown
        thisSend     = $send.time
        sendAction   = $send.action
    }
}

# ---------- aiEnd：thisSend 之后第一条同 target 的完成通知 ----------
function Get-FirstTargetNotificationAfter {
    param(
        [array]$Entries,
        [string]$FileName,
        [datetime]$After
    )
    $first = $null
    foreach ($e in $Entries) {
        if ($e.action -ne '完成通知') { continue }
        if (-not (Test-TargetMatch -TargetValue $e.target -FileName $FileName)) { continue }
        if ($e.time -ge $After -and ($null -eq $first -or $e.time -lt $first)) { $first = $e.time }
    }
    return $first
}

# ---------- 轮间间隔：本轮起点（建X，无则复X）− 此前最近一条完成通知；首轮为 0 ----------
# 完成通知按 target 锚定到具体轮次：非 round 文件（如 复关系 的 target=上下文重建）不算轮次结束，不参与轮间间隔
function Test-RoundFileTarget {
    param([string]$TargetValue)
    if ([string]::IsNullOrWhiteSpace($TargetValue)) { return $false }
    foreach ($part in ($TargetValue -split '\|')) {
        $p = $part.Trim()
        if ($p -match '^v\d+\.md$' -or $p -eq '实施文档.md' -or $p -eq '已实施.md') { return $true }
    }
    return $false
}

function Get-RoundGap {
    param(
        [array]$Entries,
        [datetime]$RoundStart
    )
    $prevEnd = $null
    foreach ($e in $Entries) {
        if ($e.action -ne '完成通知') { continue }
        if (-not (Test-RoundFileTarget $e.target)) { continue }
        if ($e.time -lt $RoundStart -and ($null -eq $prevEnd -or $e.time -gt $prevEnd)) { $prevEnd = $e.time }
    }
    if ($null -eq $prevEnd) { return 0 }
    return [int][Math]::Round(($RoundStart - $prevEnd).TotalSeconds)
}

Export-ModuleMember -Function Get-LogEntries, Test-TargetMatch, Get-TargetRoundInfo, Get-FirstTargetNotificationAfter, Get-HumanStartForSend, Get-RoundGap
