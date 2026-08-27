<#
.SYNOPSIS
    向 Markdown 文件写入/更新"人思考时长 / AI处理时长"耗时标记（YAML Front Matter）。

.DESCRIPTION
    仅处理"轮次 md"（vN.md / 实施文档.md）。依据主题目录 .aiprocess/log.jsonl，
    计算本轮"人思考/AI处理"时长；若某段 > 阈值（默认 60 分钟）视为跨天/离开则标记忽略
    （显示"忽略·X..."）。其余文件直接跳过。

    以 YAML Front Matter 形式写入 md 头部：
        ---
        ai-agent: "..."
        人思考时长: "5 分 12 秒"
        AI处理时长: "1 分 3 秒"
        ---

    - 文件已有 front matter：在其中合并/更新这两个键，其余键（含 ai-agent）与正文不动；
    - 文件无 front matter：在头部插入新块；
    - 幂等：两键值均未变化则不写盘；
    - 保留原文件 BOM 与换行风格（LF/CRLF）；
    - 失败隔离：任何异常仅输出警告，退出码始终为 0，不阻断调用方主流程。

.PARAMETER FilePath
    要写入的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1/2/3。本脚本逻辑不依赖，仅做参数签名对齐。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3", "")]
    [string]$WindowId = ""
)

# 失败隔离：本脚本为增强功能，任何情况下都不以非零退出码阻断调用方
trap {
    Write-Warning "SetMarkdownTimeTag failed: $_"
    exit 0
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "..\..\config\settings.ini"
$modulePath = Join-Path $scriptDirectory "..\time\TimeCalculator.psm1"

if (-not (Test-Path -LiteralPath $FilePath)) {
    exit 0
}
if (-not (Test-Path -LiteralPath $modulePath)) {
    exit 0
}
try {
    Import-Module $modulePath -ErrorAction Stop
} catch {
    exit 0
}

$themeDir = Split-Path -Parent $FilePath
$fileName = Split-Path -Leaf $FilePath
$logFile = Join-Path (Join-Path $themeDir ".aiprocess") "log.jsonl"

# ---------- 读取阈值 ----------
function Get-IdleThresholdMinutes {
    param([string]$SettingsPath)
    $defaultValue = 60
    try {
        $lines = [System.IO.File]::ReadAllLines($SettingsPath, [System.Text.Encoding]::Unicode)
        $inReport = $false
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ($t -eq "[Report]") { $inReport = $true; continue }
            if ($t -match "^\[.*\]$") { $inReport = $false; continue }
            if ($inReport -and $t -match "^IdleThresholdMinutes\s*=\s*(\d+)") {
                $v = [int]$matches[1]
                if ($v -gt 0) { return $v }
            }
        }
    } catch {
        # 使用默认
    }
    return $defaultValue
}

# ---------- 读取操作日志 ----------
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
            $result += [PSCustomObject]@{ time = $obj.time; action = $obj.action }
        } catch {
            # 忽略无效行
        }
    }
    return $result
}

# ---------- 在指定动作里找距参考时间最近且在窗口内的记录时间 ----------
function Get-LogBestTime {
    param(
        [array]$Entries,
        [string]$Action,
        [datetime]$Reference,
        [int]$WindowSeconds = 300
    )
    $best = $null
    $bestDiff = [double]::MaxValue
    foreach ($e in $Entries) {
        if ($e.action -ne $Action) { continue }
        try {
            $t = [datetime]::ParseExact($e.time, "yyyy-MM-dd HH:mm:ss", $null)
            $diff = [math]::Abs(($t - $Reference).TotalSeconds)
            if ($diff -lt $bestDiff -and $diff -le $WindowSeconds) {
                $best = $t
                $bestDiff = $diff
            }
        } catch {
            # 忽略无效时间
        }
    }
    return $best
}

# ---------- 定位轮次并提取时间点；非轮次 md 返回 $null，无法定位时相应时间点取 $null ----------
function Get-ThemeRoundInfo {
    param(
        [array]$Entries,
        [string]$ThemeDir,
        [string]$FileName
    )
    if ($FileName -match '^v(\d+)\.md$') {
        $n = [int]$matches[1]
        if ($n -eq 1) {
            $req = Join-Path $ThemeDir "需求.txt"
            if (-not (Test-Path -LiteralPath $req)) { return $null }
            $reqItem = Get-Item -LiteralPath $req
            $creation = $reqItem.CreationTime
            $lastWrite = $reqItem.LastWriteTime

            $humanStart = Get-LogBestTime -Entries $Entries -Action "建需求" -Reference $creation
            $hsFallback = ($null -eq $humanStart)
            if ($hsFallback) { $humanStart = $creation }

            $thisSend = Get-LogBestTime -Entries $Entries -Action "复需求" -Reference $lastWrite
            $tsFallback = ($null -eq $thisSend)
            if ($tsFallback) { $thisSend = $lastWrite }

            return [PSCustomObject]@{
                humanStart = $humanStart
                thisSend   = $thisSend
                realLog    = (-not ($hsFallback -or $tsFallback))
            }
        }
        elseif ($n -ge 2) {
            $humanFile = Join-Path $ThemeDir ("对v" + ($n - 1) + "的回复.txt")
            if (-not (Test-Path -LiteralPath $humanFile)) { return $null }
            $humanItem = Get-Item -LiteralPath $humanFile

            $humanStart = Get-LogBestTime -Entries $Entries -Action "建回复" -Reference $humanItem.CreationTime
            $hsFallback = ($null -eq $humanStart)
            if ($hsFallback) { $humanStart = $humanItem.CreationTime }

            $thisSend = Get-LogBestTime -Entries $Entries -Action "复回复" -Reference $humanItem.LastWriteTime
            $tsFallback = ($null -eq $thisSend)
            if ($tsFallback) { $thisSend = $humanItem.LastWriteTime }

            return [PSCustomObject]@{
                humanStart = $humanStart
                thisSend   = $thisSend
                realLog    = (-not ($hsFallback -or $tsFallback))
            }
        }
        else {
            return $null
        }
    }
    elseif ($FileName -eq "实施文档.md") {
        $replyFiles = @(Get-ChildItem -LiteralPath $ThemeDir -File -Filter "对v*.回复.txt" -ErrorAction SilentlyContinue)
        $humanFile = $null

        if ($replyFiles.Count -gt 0) {
            $maxReply = $replyFiles | Sort-Object { [int]($_.BaseName -replace "^对v(\d+)的回复$", "$1") } -Descending | Select-Object -First 1
            $humanFile = $maxReply.FullName
        }
        else {
            $req = Join-Path $ThemeDir "需求.txt"
            if (Test-Path -LiteralPath $req) {
                $humanFile = $req
            }
        }

        if ($null -eq $humanFile) { return $null }
        $humanItem = Get-Item -LiteralPath $humanFile

        if ($humanItem.Name -eq "需求.txt") {
            # 无上一轮（仅需求.txt）：人思考起点用需求.txt 创建时间（同第 1 轮）
            $humanStart = Get-LogBestTime -Entries $Entries -Action "建需求" -Reference $humanItem.CreationTime
            $hsFallback = ($null -eq $humanStart)
            if ($hsFallback) { $humanStart = $humanItem.CreationTime }
        } else {
            # 实施确认轮：人思考起点用该轮 建回复（人类文件创建）
            $humanStart = Get-LogBestTime -Entries $Entries -Action "建回复" -Reference $humanItem.CreationTime
            $hsFallback = ($null -eq $humanStart)
            if ($hsFallback) { $humanStart = $humanItem.CreationTime }
        }

        $sendAction = if ($humanItem.Name -eq "需求.txt") { "复需求" } else { "复回复" }
        $thisSend = Get-LogBestTime -Entries $Entries -Action $sendAction -Reference $humanItem.LastWriteTime
        $tsFallback = ($null -eq $thisSend)
        if ($tsFallback) { $thisSend = $humanItem.LastWriteTime }

        return [PSCustomObject]@{
            humanStart = $humanStart
            thisSend   = $thisSend
            realLog    = (-not ($hsFallback -or $tsFallback))
        }
    }
    return $null
}

# ---------- 合并写入 front matter ----------
function Write-FrontMatterTag {
    param(
        [string]$Path,
        [string]$Human,
        [string]$Ai,
        [string]$Total
    )
    # 英文短键，冒号/值对齐到同一列（与 ai-agent: "..." 的单空格布局对齐，值列 = 11）
    $padWidth = 10
    $humanLine = ("human:").PadRight($padWidth) + '"' + $Human + '"'
    $aiLine = ("ai:").PadRight($padWidth) + '"' + $Ai + '"'
    $totalLine = ("total:").PadRight($padWidth) + '"' + $Total + '"'

    $rawBytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF)
    $content = [System.IO.File]::ReadAllText($Path)
    $newLine = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($content -split "`r`n|`n", -1)

    # 判定 front matter：首行（BOM 已由 ReadAllText 剥离）恰为 ---，其后 50 行内存在独立闭合行 ---
    $closingIndex = -1
    if ($lines.Length -ge 2 -and $lines[0].Trim() -eq "---") {
        $limit = [Math]::Min($lines.Length - 1, 50)
        for ($i = 1; $i -le $limit; $i++) {
            if ($lines[$i].Trim() -eq "---") { $closingIndex = $i; break }
        }
    }

    $newContent = $null

    if ($closingIndex -gt 0) {
        # 已有 front matter：移除旧的 human/ai/total 及中文旧键，保留其余键（含 ai-agent），再统一插入 new 三键
        $built = [System.Collections.Generic.List[string]]::new()
        $built.Add($lines[0])   # 开 ---

        $bodyStart = 1
        $bodyEnd = $closingIndex - 1
        if ($bodyEnd -ge $bodyStart) {
            foreach ($kv in $lines[$bodyStart..$bodyEnd]) {
                $t = $kv.Trim()
                # 新的 human/ai/total 键：跳过，稍后统一插回
                if ($t -match "^(human|ai|total)\s*:") { continue }
                # 旧中文键：跳过（迁移为英文键）
                if ($t -match "^(人思考时长|AI处理时长|本轮合计)\s*:") { continue }
                $built.Add($kv)
            }
        }
        $built.Add($humanLine)
        $built.Add($aiLine)
        $built.Add($totalLine)

        for ($i = $closingIndex; $i -lt $lines.Length; $i++) { $built.Add($lines[$i]) }

        $newLines = @($built)
        if ([string]::Join("`n", $newLines) -ne [string]::Join("`n", $lines)) {
            $newContent = [string]::Join($newLine, $newLines)
        }
    } else {
        # 无 front matter：文件头插入新块
        $block = @("---", $humanLine, $aiLine, $totalLine, "---", "")
        $combined = @($block) + @($lines)
        $newContent = [string]::Join($newLine, $combined)
    }

    if ($null -ne $newContent) {
        $encoding = New-Object System.Text.UTF8Encoding($hasBom)
        [System.IO.File]::WriteAllText($Path, $newContent, $encoding)
    }
}

# ============ main ============

$threshold = Get-IdleThresholdMinutes -SettingsPath $settingsPath
$entries = Get-LogEntries -LogFile $logFile
$round = Get-ThemeRoundInfo -Entries $entries -ThemeDir $themeDir -FileName $fileName
if ($null -eq $round) {
    exit 0
}

$aiEnd = Get-Date
$breakdown = Get-RoundBreakdown -HumanStart $round.humanStart -ThisSend $round.thisSend -AiEnd $aiEnd -ThresholdMinutes $threshold

# 无 log（时间点来自文件时间戳近似）时：只显示、不标忽略
if (-not $round.realLog) {
    $breakdown.humanIgnored = $false
    $breakdown.aiIgnored = $false
}

$humanDisplay = Format-FriendlyDuration -Seconds $breakdown.humanSeconds -Ignored $breakdown.humanIgnored
$aiDisplay = Format-FriendlyDuration -Seconds $breakdown.aiSeconds -Ignored $breakdown.aiIgnored
$totalDisplay = Format-FriendlyDuration -Seconds $breakdown.totalSeconds -Ignored $false

Write-FrontMatterTag -Path $FilePath -Human $humanDisplay -Ai $aiDisplay -Total $totalDisplay

exit 0
