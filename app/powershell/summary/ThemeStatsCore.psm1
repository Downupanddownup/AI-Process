<#
.SYNOPSIS
    统计内核：根据本主题的日志与直接子主题的发布数据，汇总出 stats 对象。

.DESCRIPTION
    纯计算 + 只读采集，不落盘、不渲染、不级联——那些是编排层（ComputeThemeStats.ps1）的职责。
    "给我主题路径，还我一个 stats 对象"是这一层的全部契约，便于直接调用与比对。

    依赖（均为工具侧叶子，单向）：RoundResolver.psm1（读日志与轮次配对）、TimeCalculator.psm1（时长换算）、
    ThemeAggregation.psm1（子主题发现与汇总）、DomainConventions.psm1（名字与动作性格）、
    ActiveDurationCalculator.ps1（活跃时长）。

    前置条件：ThemePath 下存在 .aiprocess 目录（由编排层确认；本层不重复判断）。

    ⚠ 本层是"口径"的落点：数值语义一律照搬原实现，逐行等价。改动前先看 test\ 的快照对照工具。
#>

# ---------- 依赖：名字/性格单源与工具模块 ----------
Import-Module (Join-Path $PSScriptRoot "..\conventions\DomainConventions.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\time\TimeCalculator.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\time\RoundResolver.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "ThemeAggregation.psm1") -ErrorAction Stop
. (Join-Path $PSScriptRoot "ActiveDurationCalculator.ps1")

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
    return ($Name -eq (Get-RequirementFileName) -or $Name -match (Get-ReplyFilePattern))
}
function Test-AiFile {
    param([string]$Name)
    return ($Name -match (Get-VersionFilePattern) -or $Name -eq (Get-ImplDocFileName) -or $Name -eq (Get-ExecutedFileName))
}

# ---------- 内核入口 ----------
function Get-ThemeStats {
    param(
        [Parameter(Mandatory = $true)][string]$ThemePath,
        [Parameter(Mandatory = $true)][int]$ThresholdMinutes,
        [Parameter(Mandatory = $true)][datetime]$Now
    )

    $threshold = $ThresholdMinutes
    $aiProcessDir = Join-Path $ThemePath (Get-DataDirName)
    $logFile = Join-Path $aiProcessDir "log.jsonl"
    $entries = @(Get-LogEntries -LogFile $logFile)

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

    # ---------- 轮次明细：遍历主循环动作，按 target 拆候选逐文件配对 ----------
    $sendActions = Get-MainRoundActionNames
    $discussion = 0; $execute = 0; $unknown = 0
    $executeByStrategy = [ordered]@{}
    $roundDetail = @()
    # 重复发送去重：同 target 且配对同一完成通知 → 合并为一轮（取首次发送数值）；$pairedNotifKeyByTarget 登记 target→通知键，$dupSendCountByTarget 记重复次数供统计.md 标注
    $pairedNotifKeyByTarget = @{}
    $dupSendCountByTarget = @{}

    foreach ($e in $entries) {
        if ($sendActions -notcontains $e.action) { continue }

        # 去重判定（仅单 target 发送参与；多 target 含 '|' 的维持逐文件配对现状）
        $targetParts = @($e.target -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($targetParts.Count -eq 1) {
            $dupCheckEnd = Get-FirstTargetNotificationAfter -Entries $entries -FileName $targetParts[0] -After $e.time
            if ($null -ne $dupCheckEnd) {
                $notifKey = $dupCheckEnd.ToString('yyyyMMddHHmmss')
                if ($pairedNotifKeyByTarget.ContainsKey($targetParts[0]) -and $pairedNotifKeyByTarget[$targetParts[0]] -eq $notifKey) {
                    $dupSendCountByTarget[$targetParts[0]]++
                    continue
                }
                $pairedNotifKeyByTarget[$targetParts[0]] = $notifKey
            }
        }

        # 轮次类型直读日志 round-type 字段；老日志缺字段 → 计“未标注”，不报错
        $roundType = '未标注'
        if (-not [string]::IsNullOrWhiteSpace($e.roundType)) { $roundType = $e.roundType }
        if ($roundType -eq 'execute') {
            $execute++
            $strategyKey = if ([string]::IsNullOrWhiteSpace($e.strategy)) { '未标注' } else { $e.strategy }
            if (-not $executeByStrategy.Contains($strategyKey)) { $executeByStrategy[$strategyKey] = 0 }
            $executeByStrategy[$strategyKey]++
        } elseif ($roundType -eq 'discussion') {
            $discussion++
        }
        if ([string]::IsNullOrWhiteSpace($e.target)) { $unknown++; continue }

        $isExecute = ($roundType -eq 'execute')
        $human = $null
        if (-not $isExecute) { $human = Get-HumanStartForSend -Entries $entries -Send $e }

        # 轮间间隔：本轮起点（建X，配不上则复X）− 此前最近一条完成通知；首轮恒 0（与打标同调 RoundResolver.Get-RoundGap）
        $roundStart = $e.time
        if ($null -ne $human -and -not $human.humanUnknown -and $null -ne $human.humanStart) { $roundStart = $human.humanStart }
        $gapSec = Get-RoundGap -Entries $entries -RoundStart $roundStart

        # 人文件字符数：讨论轮取 source 文件（无 source 时按动作表给的兜底）；无输入文件的动作 → 0
        $srcChars = $null
        if (-not $isExecute) {
            $src = $e.source
            $defaultSrc = Get-DefaultSourceFor $e.action
            if ($defaultSrc -ne '' -and [string]::IsNullOrWhiteSpace($src)) { $src = $defaultSrc }
            if (Test-HasNoInputFile $e.action) {
                $srcChars = 0
            } elseif (-not [string]::IsNullOrWhiteSpace($src)) {
                $srcChars = Get-FileCharCount -Path (Join-Path $ThemePath $src)
            }
        }

        # 多 target 逐文件配对：先判定各 target 是否有效（文件存在或有完成通知）；
        # 虚空 target（文件不存在且无通知）剔除——统计只反映实际产出；全虚空时保留首个记"未闭环"（人的时间不丢账）；
        # 人耗时/轮间间隔只归属第一个有效行，其余有效行记 0（一条发送只有一份）；AI耗时/字数仍逐文件独立
        $partInfos = @()
        foreach ($part in ($e.target -split '\|')) {
            $fileName = $part.Trim()
            if ($fileName -eq '') { continue }
            $partEnd = Get-FirstTargetNotificationAfter -Entries $entries -FileName $fileName -After $e.time
            $partInfos += [PSCustomObject]@{
                fileName   = $fileName
                aiEnd      = $partEnd
                fileExists = (Test-Path -LiteralPath (Join-Path $ThemePath $fileName))
            }
        }
        $kept = @($partInfos | Where-Object { $_.fileExists -or $null -ne $_.aiEnd })
        if ($kept.Count -eq 0 -and $partInfos.Count -gt 0) { $kept = @($partInfos[0]) }
        $isFirstKept = $true
        foreach ($pi in $kept) {
            $fileName = $pi.fileName
            $aiEnd = $pi.aiEnd
            $aiEndKnown = ($null -ne $aiEnd)
            # 无完成通知 = 该轮未闭环：aiSec 记 null 不编造（统计脚本在完成通知后触发，缺通知即真未完成）；人耗时段不受影响照常计算
            $humanStart = if ($null -ne $human) { $human.humanStart } else { $null }
            $breakdown = Get-RoundBreakdown -HumanStart $humanStart -ThisSend $e.time -AiEnd $aiEnd -ThresholdMinutes $threshold
            $aiSec = $null
            if ($aiEndKnown) { $aiSec = $breakdown.aiSeconds }
            $humanSec = $null
            if (-not $isFirstKept) { $humanSec = 0 }
            elseif ($isExecute) { $humanSec = 0 }
            elseif (-not $human.humanUnknown) { $humanSec = $breakdown.humanSeconds }
            $rowGapSec = if ($isFirstKept) { $gapSec } else { 0 }
            $rowHumanChars = 0
            if ($isFirstKept -and -not $isExecute) { $rowHumanChars = $srcChars }
            $aiChars = Get-FileCharCount -Path (Join-Path $ThemePath $fileName) -AiBody $true
            $totalSec = $null
            if ($null -ne $humanSec -or $null -ne $aiSec) {
                $totalSec = 0
                if ($null -ne $humanSec) { $totalSec += $humanSec }
                if ($null -ne $aiSec) { $totalSec += $aiSec }
            }
            $isFirstKept = $false

            $roundDetail += [PSCustomObject][ordered]@{
                file       = $fileName
                type       = $roundType
                agent      = $e.agent
                sendTime   = $e.time.ToString('yyyy-MM-dd HH:mm:ss')
                humanSec   = $humanSec
                aiSec      = $aiSec
                totalSec   = $totalSec
                gapSec     = $rowGapSec
                humanChars = $rowHumanChars
                aiChars    = $aiChars
                known      = ($aiEndKnown -and ($isExecute -or -not $human.humanUnknown))
            }
        }
    }

    # ---------- 重建轮：复关系 → 上下文重建完成通知；人耗时/字数恒 0；按发送时间并入明细 ----------
    $rebuildRows = @(Get-RebuildRoundRows -Entries $entries)
    $rebuild = $rebuildRows.Count
    $roundDetail = @($roundDetail + $rebuildRows | Sort-Object sendTime)

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
    $gapTotalSec = 0
    foreach ($r in $roundDetail) {
        if ($null -ne $r.gapSec) { $gapTotalSec += $r.gapSec }
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
        rebuild       = $rebuild
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

    # ---------- stats 对象（键名与层级是消费接口，勿动） ----------
    $stats = [PSCustomObject][ordered]@{
        version    = 1
        computedAt = $Now.ToString('yyyy-MM-dd HH:mm:ss')
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
            rebuild           = $rebuild
            executeByStrategy = $executeByStrategy
            unknown           = $unknown
        }
        derived    = [PSCustomObject][ordered]@{
            avgHumanSec  = $avgHumanSec
            avgAiSec     = $avgAiSec
            longestRound = [PSCustomObject][ordered]@{ file = $longestFile; sec = $longestSec }
        }
        roundDetail = $roundDetail
        aggregate   = $aggregate
        children    = $children
    }

    return [PSCustomObject]@{
        Stats                = $stats
        DupSendCountByTarget = $dupSendCountByTarget
    }
}

Export-ModuleMember -Function Get-ThemeStats
