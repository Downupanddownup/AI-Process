<#
.SYNOPSIS
    统计内核：根据本主题的日志与直接子主题的发布数据，汇总出 stats 对象。

.DESCRIPTION
    纯计算 + 只读采集，不落盘、不渲染、不级联——那些是编排层（ComputeThemeStats.ps1）的职责。
    "给我主题路径，还我一个 stats 对象"是这一层的全部契约，便于直接调用与比对。

    依赖（均为工具侧叶子，单向）：RoundResolver.psm1（读日志、轮次配对与逐档降级）、TimeCalculator.psm1（时长换算）、
    ThemeAggregation.psm1（子主题发现与汇总）、DomainConventions.psm1（名字与动作性格）。

    前置条件：ThemePath 下存在 .aiprocess 目录（由编排层确认；本层不重复判断）。

    ⚠ 本层是"口径"的落点：数值语义一律照搬原实现，逐行等价。改动前先看 test\ 的快照对照工具。
#>

# ---------- 依赖：名字/性格单源与工具模块 ----------
Import-Module (Join-Path $PSScriptRoot "..\conventions\DomainConventions.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\time\TimeCalculator.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\time\RoundResolver.psm1") -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "ThemeAggregation.psm1") -ErrorAction Stop

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
        [Parameter(Mandatory = $true)][int]$ThinkThresholdMinutes,
        [Parameter(Mandatory = $true)][datetime]$Now
    )

    $threshold = $ThresholdMinutes
    $thinkThresholdSec = $ThinkThresholdMinutes * 60
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
    # 重复发送合并标注：被合并的次数（展示层 +1 显示总数）、其中执行类几次
    $dupSendCountByTarget = @{}
    $dupExecCountByTarget = @{}

    # 发送侧候选窗口（RoundResolver 单源）：同 target 且配同一条完成通知的发送 = 一轮；
    # 该轮时长取自"第一个不超阈值的候选"，被放弃的跨度记剔除——重复发送的合并与逐档降级都在窗口里完成
    $sendWindows = Get-SendWindows -Entries $entries -ThresholdMinutes $threshold

    foreach ($e in $entries) {
        if ($sendActions -notcontains $e.action) { continue }

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

        # 逐 target 取本轮窗口：只有"该 target 那一组的首次发送"才落成明细行；
        # 被合并的重复发送查不到窗口键，自然跳过（合并次数与逐档降级都由窗口承载）
        $rows = @()
        foreach ($part in ($e.target -split '\|')) {
            $fileName = $part.Trim()
            if ($fileName -eq '') { continue }
            $winKey = "$fileName|" + $e.time.ToString('yyyyMMddHHmmss')
            if (-not $sendWindows.ContainsKey($winKey)) { continue }
            $rows += [PSCustomObject]@{
                fileName   = $fileName
                win        = $sendWindows[$winKey]
                fileExists = (Test-Path -LiteralPath (Join-Path $ThemePath $fileName))
            }
        }
        if ($rows.Count -eq 0) { continue }

        # 虚空 target（文件不存在且无通知）剔除——统计只反映实际产出；全虚空时保留首个记"未闭环"（人的时间不丢账）
        $kept = @($rows | Where-Object { $_.fileExists -or $null -ne $_.win.aiEnd })
        if ($kept.Count -eq 0) { $kept = @($rows[0]) }

        # 人段：终点 = 本轮真正生效的那次发送（有采用候选时取它，否则退回本轮首次发送）
        $humanEnd = $e.time
        foreach ($r in $rows) {
            if ($null -ne $r.win.pickedSendTime) { $humanEnd = $r.win.pickedSendTime; break }
        }
        $human = Get-HumanWindow -Entries $entries -Send $e -EndTime $humanEnd -ThresholdMinutes $threshold

        # 轮间间隔：本轮起点（建X，配不上则复X）− 此前最近一条完成通知；首轮恒 0（与打标同调 RoundResolver.Get-RoundGap）
        $roundStart = $e.time
        if (-not $human.unknown -and $null -ne $human.pickedStart) { $roundStart = $human.pickedStart }
        $gapSec = Get-RoundGap -Entries $entries -RoundStart $roundStart

        # 人文件字符数：讨论轮取 source 文件（无 source 时按动作表给的兜底）；无输入文件的动作 → 0
        $isExecute = ($roundType -eq 'execute')
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

        # 人耗时/轮间间隔只归属第一个有效行，其余有效行记 0（一条发送只有一份）；AI耗时/字数仍逐文件独立
        $isFirstKept = $true
        foreach ($pi in $kept) {
            $fileName = $pi.fileName
            $win = $pi.win
            # 无完成通知 = 该轮未闭环：aiSec 记 null 不编造（统计脚本在完成通知后触发，缺通知即真未完成）
            $aiSec = $win.aiSec
            $humanSec = $null
            if (-not $isFirstKept) { $humanSec = 0 }
            elseif ($isExecute) { $humanSec = 0 }
            elseif (-not $human.unknown) { $humanSec = $human.sec }
            # 剔除：人段只在第一个有效行归属一次；AI 段逐文件独立
            $humanExcluded = 0
            $rowExcludedCount = 0
            if ($isFirstKept) { $humanExcluded = $human.excludedSec; $rowExcludedCount += $human.excludedCount }
            $aiExcluded = $win.excludedSec
            $rowExcludedCount += $win.excludedCount
            $rowGapSec = if ($isFirstKept) { $gapSec } else { 0 }
            # 认知时长 = 人思考 + 落在阈值内的轮间间隔（估计值：≤阈值的间隔视为"人在读在想"）
            # 人段为 null 的轮只计间隔、不因未知而丢账；多 target 时间隔只归第一有效行，故此处同此
            $rowCognitionSec = 0
            if ($null -ne $humanSec) { $rowCognitionSec += $humanSec }
            if ($rowGapSec -le $thinkThresholdSec) { $rowCognitionSec += $rowGapSec }
            $rowHumanChars = 0
            if ($isFirstKept -and -not $isExecute) { $rowHumanChars = $srcChars }
            $aiChars = Get-FileCharCount -Path (Join-Path $ThemePath $fileName) -AiBody $true
            $totalSec = $null
            if ($null -ne $humanSec -or $null -ne $aiSec) {
                $totalSec = 0
                if ($null -ne $humanSec) { $totalSec += $humanSec }
                if ($null -ne $aiSec) { $totalSec += $aiSec }
            }
            # 重复发送合并标注（展示层按"次数 + 1"显示总数，并带出被合并的执行类次数）
            if ($win.itemCount -gt 1 -and -not $dupSendCountByTarget.ContainsKey($fileName)) {
                $dupSendCountByTarget[$fileName] = $win.itemCount - 1
                if ($win.mergedExecCount -gt 0) { $dupExecCountByTarget[$fileName] = $win.mergedExecCount }
            }
            $isFirstKept = $false

            $roundDetail += [PSCustomObject][ordered]@{
                file             = $fileName
                type             = $roundType
                agent            = $e.agent
                sendTime         = $e.time.ToString('yyyy-MM-dd HH:mm:ss')
                humanSec         = $humanSec
                aiSec            = $aiSec
                totalSec         = $totalSec
                gapSec           = $rowGapSec
                humanCognitionSec = $rowCognitionSec
                humanExcludedSec = $humanExcluded
                aiExcludedSec    = $aiExcluded
                excludedCount    = $rowExcludedCount
                humanChars       = $rowHumanChars
                aiChars          = $aiChars
                known            = (($null -ne $win.aiEnd) -and ($isExecute -or -not $human.unknown))
            }
        }
    }

    # ---------- 重建轮：复关系 → 上下文重建完成通知；人耗时/字数恒 0；按发送时间并入明细 ----------
    $rebuildRows = @(Get-RebuildRoundRows -Entries $entries -ThinkThresholdMinutes $ThinkThresholdMinutes)
    $rebuild = $rebuildRows.Count
    $roundDetail = @($roundDetail + $rebuildRows | Sort-Object sendTime)

    # ---------- 时长类 ----------
    $wallClockSec = 0
    $createdAt = $null; $lastAt = $null
    if ($entries.Count -gt 0) {
        $sorted = @($entries | Sort-Object time)
        $first = $sorted[0].time
        $last = $sorted[$sorted.Count - 1].time
        $createdAt = $first.ToString('yyyy-MM-dd HH:mm:ss')
        $lastAt = $last.ToString('yyyy-MM-dd HH:mm:ss')
        if ($last -gt $first) {
            $wallClockSec = [int][Math]::Round(($last - $first).TotalSeconds)
        }
    }

    # ---------- 人/AI 时长合计（raw 秒数求和；null 不计）与剔除/认知合计 ----------
    $humanSecTotal = 0; $aiSecTotal = 0; $humanCognitionTotal = 0
    $humanExcludedTotal = 0; $aiExcludedTotal = 0; $excludedCountTotal = 0
    foreach ($r in $roundDetail) {
        if ($null -ne $r.humanSec) { $humanSecTotal += $r.humanSec }
        if ($null -ne $r.aiSec) { $aiSecTotal += $r.aiSec }
        if ($null -ne $r.humanCognitionSec) { $humanCognitionTotal += $r.humanCognitionSec }
        if ($null -ne $r.humanExcludedSec) { $humanExcludedTotal += $r.humanExcludedSec }
        if ($null -ne $r.aiExcludedSec) { $aiExcludedTotal += $r.aiExcludedSec }
        if ($null -ne $r.excludedCount) { $excludedCountTotal += $r.excludedCount }
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
        humanSec          = $humanSecTotal
        aiSec             = $aiSecTotal
        roundTotalSec     = $roundTotalSec
        gapTotalSec       = $gapTotalSec
        humanCognitionSec = $humanCognitionTotal
        humanExcludedSec  = $humanExcludedTotal
        aiExcludedSec     = $aiExcludedTotal
        excludedCount     = $excludedCountTotal
        files             = $fileTotal
        humanFiles        = $humanFiles
        aiFiles           = $aiFiles
        humanChars        = $humanCharsTotal
        aiChars           = $aiCharsTotal
        discussion        = $discussion
        execute           = $execute
        unknown           = $unknown
        rebuild           = $rebuild
        createdAt         = $createdAt
        lastActiveAt      = $lastAt
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
            humanCognitionSec = $humanCognitionTotal
            humanExcludedSec = $humanExcludedTotal
            aiExcludedSec    = $aiExcludedTotal
            excludedCount    = $excludedCountTotal
            wallClockSec     = $wallClockSec
            humanSec         = $humanSecTotal
            aiSec            = $aiSecTotal
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
        DupExecCountByTarget = $dupExecCountByTarget
    }
}

Export-ModuleMember -Function Get-ThemeStats
