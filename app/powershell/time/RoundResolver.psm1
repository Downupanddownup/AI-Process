<#
.SYNOPSIS
    轮次配对共享模块：纯逻辑（不读/写业务文件），供单文档打标与总体统计同调一份口径。

.DESCRIPTION
    提供四个导出函数：
      - Get-LogEntries：读取操作日志 log.jsonl（含归属标识 target/source、agent、执行策略 strategy 与 content 长度；损坏行静默跳过）。
      - Test-TargetMatch：target 匹配，支持 "|" 分隔的候选（如 "v5.md|实施文档.md"），精确匹配文件名。
      - Get-TargetRoundInfo：按 target/source 定位本轮；非轮次 md 返回 $null；配对失败返回 matched=$false。
      - Get-FirstTargetNotificationAfter：thisSend 之后第一条同 target 的完成通知。
      - Get-HumanStartForSend：按发送动作的 source 定位人思考起点（建X）；复执行/质检码 恒无（人耗时 0）。
      - Get-RoundGap：轮间间隔 = 本轮起点 − 此前最近一条完成通知；首轮或无先例通知时为 0。
      - Get-RebuildRoundRows：重建轮（复关系 → 上下文重建完成通知）；人耗时/字数恒 0，轮间间隔照常。
      - Get-EffectiveRoundWindow：候选序列的逐档降级（"第一个不超阈值的候选"= 有效时长，被放弃的跨度 = 剔除）。
      - Get-SendWindows：AI 段候选分组（同 target + 配同一条完成通知的连续发送 = 一轮）。
      - Get-HumanWindow：人段候选分组与降级（同 source 的每一次 建X，终点为本轮真正生效的那次发送）。

    兼容 Windows PowerShell 5.1。保持单向依赖：本模块不引用任何调用方/业务模块。
#>

# ---------- 依赖：名字与动作性格单源（PS 侧） ----------
Import-Module (Join-Path $PSScriptRoot "..\conventions\DomainConventions.psm1") -ErrorAction Stop

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
    if (Test-HasNoHumanTime $Send.action) {
        # 执行类文件（改吧结果 / 已实施.md）与质检码（无输入文件）：human 恒 0
        return [PSCustomObject]@{ humanStart = $null; humanUnknown = $false }
    }
    # 讨论轮：source 定位人思考段（无 source 时按动作表给的兜底）
    $src = $Send.source
    $defaultSrc = Get-DefaultSourceFor $Send.action
    if ($defaultSrc -ne '' -and [string]::IsNullOrWhiteSpace($src)) { $src = $defaultSrc }
    if ([string]::IsNullOrWhiteSpace($src)) {
        return [PSCustomObject]@{ humanStart = $null; humanUnknown = $true }
    }
    $buildAction = Get-BuildActionFor $src
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
    if ($FileName -notmatch (Get-VersionFilePattern) -and $FileName -ne (Get-ImplDocFileName) -and $FileName -ne (Get-ExecutedFileName)) {
        return $null
    }

    # 找指向本文件的发送动作；同 target 多次 → 配最后一次（消歧）
    $send = $null
    foreach ($e in $Entries) {
        if (-not (Test-IsMainRoundAction $e.action)) { continue }
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
# 完成通知按 target 锚定到具体轮次：轮次文件与 上下文重建（复关系/重建轮）均算轮次结束，参与轮间间隔
function Test-RoundFileTarget {
    param([string]$TargetValue)
    if ([string]::IsNullOrWhiteSpace($TargetValue)) { return $false }
    foreach ($part in ($TargetValue -split '\|')) {
        $p = $part.Trim()
        if ($p -match (Get-VersionFilePattern) -or $p -eq (Get-ImplDocFileName) -or $p -eq (Get-ExecutedFileName) -or $p -eq (Get-ContextRebuildName)) { return $true }
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

# ---------- 重建轮：复关系发送 → target=上下文重建 完成通知；人耗时/字数恒 0；轮间间隔照常 ----------
# 重复发送去重：与讨论/执行轮同口径——配对同一完成通知的重复 复关系 发送合并为一轮（取首次）
function Get-RebuildRoundRows {
    param([array]$Entries)
    $rows = @()
    $pairedNotifKey = $null
    foreach ($e in $Entries) {
        if (-not (Test-IsRebuildPathAction $e.action)) { continue }
        $aiEnd = Get-FirstTargetNotificationAfter -Entries $Entries -FileName (Get-ContextRebuildName) -After $e.time
        if ($null -ne $aiEnd) {
            $notifKey = $aiEnd.ToString('yyyyMMddHHmmss')
            if ($notifKey -eq $pairedNotifKey) { continue }
            $pairedNotifKey = $notifKey
        }
        $aiSec = $null
        if ($null -ne $aiEnd) { $aiSec = [int][Math]::Round(($aiEnd - $e.time).TotalSeconds) }
        $rows += [PSCustomObject][ordered]@{
            file             = (Get-ContextRebuildName)
            type             = 'rebuild'
            agent            = $e.agent
            sendTime         = $e.time.ToString('yyyy-MM-dd HH:mm:ss')
            humanSec         = 0
            aiSec            = $aiSec
            totalSec         = $aiSec
            gapSec           = (Get-RoundGap -Entries $Entries -RoundStart $e.time)
            humanExcludedSec = 0
            aiExcludedSec    = 0
            excludedCount    = 0
            humanChars       = 0
            aiChars          = 0
            known            = ($null -ne $aiEnd)
        }
    }
    return $rows
}

# ---------- 逐档降级：候选序列里取"第一个不超阈值的候选" ----------
# 口径（与已确认的规则逐条对应）：
#   候选按 start 升序；采用 = 第一个 (end - start) ≤ 阈值的候选
#   降档成功 → 有效时长 = 采用候选的时长；剔除 = 第一候选起点 → 采用候选起点；剔除次数 1（仅当采用的不是第一个）
#   降档到底 → 有效时长 = 0；剔除 = 第一候选起点 → 最后候选终点；剔除次数 1
#   第一候选就合格 → 剔除 0、剔除次数 0（没发生剔除）
# 纯函数：不读日志、不碰文件系统。统计与打标两条链共用这一份判定。
function Get-EffectiveRoundWindow {
    param(
        [Parameter(Mandatory = $true)][array]$Candidates,
        [Parameter(Mandatory = $true)][int]$ThresholdMinutes
    )
    if ($Candidates.Count -eq 0) {
        return [PSCustomObject]@{ resolved = $false; effectiveSec = $null; pickedStart = $null; excludedSec = 0; excludedCount = 0 }
    }
    $thresholdSec = $ThresholdMinutes * 60
    $first = $Candidates[0]
    $picked = $null
    foreach ($c in $Candidates) {
        $sec = [int][Math]::Round(($c.end - $c.start).TotalSeconds)
        if ($sec -le $thresholdSec) { $picked = $c; break }
    }
    if ($null -ne $picked) {
        $count = 0
        if ($picked.start -gt $first.start) { $count = 1 }
        return [PSCustomObject]@{
            resolved      = $true
            effectiveSec  = [int][Math]::Round(($picked.end - $picked.start).TotalSeconds)
            pickedStart   = $picked.start
            excludedSec   = [int][Math]::Round(($picked.start - $first.start).TotalSeconds)
            excludedCount = $count
        }
    }
    $last = $Candidates[$Candidates.Count - 1]
    return [PSCustomObject]@{
        resolved      = $false
        effectiveSec  = 0
        pickedStart   = $null
        excludedSec   = [int][Math]::Round(($last.end - $first.start).TotalSeconds)
        excludedCount = 1
    }
}

# ---------- AI 段候选分组：同一 target 内，配到同一条完成通知的连续发送归为一轮 ----------
# 返回 hashtable：键 = "target|组内首次发送时刻键" → 该轮的窗口对象
#   窗口 = { target; firstTime; firstEntry; resolved; aiEnd; aiSec; pickedSendTime; excludedSec; excludedCount; itemCount; mergedExecCount }
#   - 组内全部配不到通知（本轮未闭环）→ aiSec = null（不编造）
#   - 被通知截断后另起一组（另一轮）→ 各自成组
function Get-SendWindows {
    param(
        [Parameter(Mandatory = $true)][array]$Entries,
        [Parameter(Mandatory = $true)][int]$ThresholdMinutes
    )
    $sendNames = Get-MainRoundActionNames
    $byTarget = @{}
    foreach ($e in $Entries) {
        if ($sendNames -notcontains $e.action) { continue }
        if ([string]::IsNullOrWhiteSpace($e.target)) { continue }
        foreach ($part in ($e.target -split '\|')) {
            $t = $part.Trim()
            if ($t -eq '') { continue }
            if (-not $byTarget.ContainsKey($t)) { $byTarget[$t] = New-Object System.Collections.ArrayList }
            [void]$byTarget[$t].Add($e)
        }
    }

    $groups = @()
    foreach ($t in $byTarget.Keys) {
        $sends = @($byTarget[$t] | Sort-Object time)
        $cur = $null
        foreach ($s in $sends) {
            $end = Get-FirstTargetNotificationAfter -Entries $Entries -FileName $t -After $s.time
            $notifKey = 'none'
            if ($null -ne $end) { $notifKey = $end.ToString('yyyyMMddHHmmss') }
            if ($null -eq $cur -or $cur.notifKey -ne $notifKey) {
                $cur = [PSCustomObject]@{
                    target     = $t
                    notifKey   = $notifKey
                    firstTime  = $s.time
                    firstEntry = $s
                    items      = New-Object System.Collections.ArrayList
                }
                $groups += $cur
            }
            [void]$cur.items.Add([PSCustomObject]@{ start = $s.time; end = $end; entry = $s })
        }
    }

    $result = @{}
    foreach ($g in $groups) {
        $key = "$($g.target)|" + $g.firstTime.ToString('yyyyMMddHHmmss')
        $mergedExec = 0
        $items = @($g.items | Sort-Object { $_.start })
        for ($i = 1; $i -lt $items.Count; $i++) {
            if ($items[$i].entry.action -eq '复执行') { $mergedExec++ }
        }
        if ($g.notifKey -eq 'none') {
            $result[$key] = [PSCustomObject]@{
                target = $g.target; firstTime = $g.firstTime; firstEntry = $g.firstEntry
                resolved = $false; aiEnd = $null; aiSec = $null; pickedSendTime = $null
                excludedSec = 0; excludedCount = 0
                itemCount = $items.Count; mergedExecCount = $mergedExec
            }
            continue
        }
        $win = Get-EffectiveRoundWindow -Candidates $items -ThresholdMinutes $ThresholdMinutes
        $result[$key] = [PSCustomObject]@{
            target = $g.target; firstTime = $g.firstTime; firstEntry = $g.firstEntry
            resolved = $win.resolved; aiEnd = $items[0].end; aiSec = $win.effectiveSec
            pickedSendTime = $win.pickedStart
            excludedSec = $win.excludedSec; excludedCount = $win.excludedCount
            itemCount = $items.Count; mergedExecCount = $mergedExec
        }
    }
    return $result
}

# ---------- 人段候选 + 降级：同 source 的每一次 建X，终点 = 本轮真正生效的那次发送 ----------
# 返回 { sec; excludedSec; excludedCount; pickedStart; unknown }
#   sec = 0       该动作无人的时间（执行类 / 质检码）
#   sec = null    定位不到 source 或没有任何 建X（未知，不编造）
#   sec = <int>   降级后的有效人时长（降档到底时记 0）
function Get-HumanWindow {
    param(
        [Parameter(Mandatory = $true)][array]$Entries,
        [Parameter(Mandatory = $true)][object]$Send,
        [Parameter(Mandatory = $true)][object]$EndTime,
        [Parameter(Mandatory = $true)][int]$ThresholdMinutes
    )
    if (Test-HasNoHumanTime $Send.action) {
        return [PSCustomObject]@{ sec = 0; excludedSec = 0; excludedCount = 0; pickedStart = $null; unknown = $false }
    }
    $src = $Send.source
    $defaultSrc = Get-DefaultSourceFor $Send.action
    if ($defaultSrc -ne '' -and [string]::IsNullOrWhiteSpace($src)) { $src = $defaultSrc }
    if ([string]::IsNullOrWhiteSpace($src)) {
        return [PSCustomObject]@{ sec = $null; excludedSec = 0; excludedCount = 0; pickedStart = $null; unknown = $true }
    }
    $buildAction = Get-BuildActionFor $src
    $candidates = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrWhiteSpace($buildAction)) {
        foreach ($e in $Entries) {
            if ($e.action -ne $buildAction) { continue }
            if ($e.target -ne $src) { continue }
            if ($e.time -gt $EndTime) { continue }
            [void]$candidates.Add([PSCustomObject]@{ start = $e.time; end = $EndTime })
        }
    }
    $list = @($candidates | Sort-Object { $_.start })
    if ($list.Count -eq 0) {
        return [PSCustomObject]@{ sec = $null; excludedSec = 0; excludedCount = 0; pickedStart = $null; unknown = $true }
    }
    $win = Get-EffectiveRoundWindow -Candidates $list -ThresholdMinutes $ThresholdMinutes
    return [PSCustomObject]@{
        sec           = $win.effectiveSec
        excludedSec   = $win.excludedSec
        excludedCount = $win.excludedCount
        pickedStart   = $win.pickedStart
        unknown       = $false
    }
}

Export-ModuleMember -Function Get-LogEntries, Test-TargetMatch, Get-TargetRoundInfo, Get-FirstTargetNotificationAfter, Get-HumanStartForSend, Get-RoundGap, Get-RebuildRoundRows, Get-EffectiveRoundWindow, Get-SendWindows, Get-HumanWindow
