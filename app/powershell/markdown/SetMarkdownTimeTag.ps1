<#
.SYNOPSIS
    向 Markdown 文件写入/更新耗时标记（YAML Front Matter 的 human/ai/total 键）。

.DESCRIPTION
    仅处理"轮次 md"（vN.md / 实施文档.md / 已实施.md）。依据主题目录 .aiprocess/log.jsonl
    中动作的归属标识（properties.target / source）做确定性配对，计算本轮耗时：

      human = 同 source 的 建X → 复X          （执行类文件恒 0）
      ai    = 同 target 的 复X → 其后第一条同 target 的完成通知（无则用当前时刻兜底，重算收敛）
      消歧  = 同 target 多次发送 → 配最后一次
      total = 未忽略段之和；任一段 > 阈值（默认 60 分钟）标"忽略·<时长>"

    边界语义：
      - 允许重算：配对锚点是事实记录，重算幂等收敛；
      - 配对失败（日志无 target）→ 写"未知"四键，不编造数字。

    - 文件已有 front matter：在其中合并/更新这三个键，其余键（含 ai-agent）与正文不动；
    - 文件无 front matter：在头部插入新块；
    - 幂等：键值均未变化则不写盘；
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
$modulePath = Join-Path $scriptDirectory "..\time\TimeCalculator.psm1"
$resolverPath = Join-Path $scriptDirectory "..\time\RoundResolver.psm1"
$appSettingsPath = Join-Path $scriptDirectory "..\config\AppSettings.psm1"

if (-not (Test-Path -LiteralPath $FilePath)) {
    exit 0
}
if (-not (Test-Path -LiteralPath $modulePath)) {
    exit 0
}
if (-not (Test-Path -LiteralPath $resolverPath)) {
    exit 0
}
if (-not (Test-Path -LiteralPath $appSettingsPath)) {
    exit 0
}
try {
    Import-Module $modulePath -ErrorAction Stop
    Import-Module $resolverPath -ErrorAction Stop
    Import-Module $appSettingsPath -ErrorAction Stop
} catch {
    exit 0
}

$themeDir = Split-Path -Parent $FilePath
$fileName = Split-Path -Leaf $FilePath
$logFile = Join-Path (Join-Path $themeDir ".aiprocess") "log.jsonl"

# ---------- 轮次配对逻辑已抽取至 app/powershell/time/RoundResolver.psm1（顶部导入） ----------

# ---------- 合并写入 front matter ----------
function Write-FrontMatterTag {
    param(
        [string]$Path,
        [string]$Gap,
        [string]$Human,
        [string]$Ai,
        [string]$Total,
        [string]$RoundType = ""
    )
    # 英文短键，冒号/值对齐到同一列（与 ai-agent: "..." 的单空格布局对齐，值列 = 11）
    $padWidth = 10
    $tagLines = @()
    $tagLines += (("gap:").PadRight($padWidth) + '"' + $Gap + '"')
    $tagLines += (("human:").PadRight($padWidth) + '"' + $Human + '"')
    $tagLines += (("ai:").PadRight($padWidth) + '"' + $Ai + '"')
    $tagLines += (("total:").PadRight($padWidth) + '"' + $Total + '"')
    if ($RoundType -ne "") {
        $tagLines += ('round-type: ' + '"' + $RoundType + '"')
    }

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
        # 已有 front matter：移除旧的 gap/human/ai/total 及中文旧键，保留其余键（含 ai-agent），再统一插入 new 键组
        $built = [System.Collections.Generic.List[string]]::new()
        $built.Add($lines[0])   # 开 ---

        $bodyStart = 1
        $bodyEnd = $closingIndex - 1
        if ($bodyEnd -ge $bodyStart) {
            foreach ($kv in $lines[$bodyStart..$bodyEnd]) {
                $t = $kv.Trim()
                # 新的 gap/human/ai/total/round-type 键：跳过，稍后统一插回
                if ($t -match "^(gap|human|ai|total|round-type)\s*:") { continue }
                $built.Add($kv)
            }
        }
        foreach ($tl in $tagLines) { $built.Add($tl) }

        for ($i = $closingIndex; $i -lt $lines.Length; $i++) { $built.Add($lines[$i]) }

        $newLines = @($built)
        if ([string]::Join("`n", $newLines) -ne [string]::Join("`n", $lines)) {
            $newContent = [string]::Join($newLine, $newLines)
        }
    } else {
        # 无 front matter：文件头插入新块
        $block = @("---") + $tagLines + @("---", "")
        $combined = @($block) + @($lines)
        $newContent = [string]::Join($newLine, $combined)
    }

    if ($null -ne $newContent) {
        $encoding = New-Object System.Text.UTF8Encoding($hasBom)
        [System.IO.File]::WriteAllText($Path, $newContent, $encoding)
    }
}

# ============ main ============

$threshold = Get-IdleThresholdMinutes
$entries = Get-LogEntries -LogFile $logFile
$round = Get-TargetRoundInfo -Entries $entries -FileName $fileName
if ($null -eq $round) {
    exit 0
}

# 轮次类型：配对成功按发送动作派生；配对失败仅文件名可确定的（实施文档/已实施）才写，vN.md 不编造
$roundTypeValue = ""
if ($round.matched) {
    if ($round.sendAction -eq '复执行') { $roundTypeValue = 'execute' } else { $roundTypeValue = 'discussion' }
} else {
    if ($fileName -eq '已实施.md') { $roundTypeValue = 'execute' }
    elseif ($fileName -eq '实施文档.md') { $roundTypeValue = 'discussion' }
}

# 配对失败（日志无 target，如首轮直建实施文档.md）：写"未知"四键，不编造数字
if (-not $round.matched) {
    Write-FrontMatterTag -Path $FilePath -Gap "未知" -Human "未知" -Ai "未知" -Total "未知" -RoundType $roundTypeValue
    exit 0
}

# AI 处理终点：thisSend 之后第一条同 target 的完成通知；无则用当前时刻（创建当下≈AI 刚完成，重算时收敛到真实通知）
$aiEnd = Get-FirstTargetNotificationAfter -Entries $entries -FileName $fileName -After $round.thisSend
if ($null -eq $aiEnd) { $aiEnd = Get-Date }
$breakdown = Get-RoundBreakdown -HumanStart $round.humanStart -ThisSend $round.thisSend -AiEnd $aiEnd -ThresholdMinutes $threshold

# 轮间间隔：本轮起点（建X，配不上则复X）− 此前最近一条完成通知；打标时刻两端均已发生，一次写入终身准确
$gapStart = if ($null -ne $round.humanStart) { $round.humanStart } else { $round.thisSend }
$gapDisplay = Format-FriendlyDuration -Seconds (Get-RoundGap -Entries $entries -RoundStart $gapStart)

$aiDisplay = Format-FriendlyDuration -Seconds $breakdown.aiSeconds -Ignored $breakdown.aiIgnored
if ($round.humanUnknown) {
    # human 段配不齐：不编造，human/total 均显"未知"
    $humanDisplay = "未知"
    $totalDisplay = "未知"
} else {
    $humanDisplay = Format-FriendlyDuration -Seconds $breakdown.humanSeconds -Ignored $breakdown.humanIgnored
    $totalDisplay = Format-FriendlyDuration -Seconds $breakdown.totalSeconds -Ignored $false
}

Write-FrontMatterTag -Path $FilePath -Gap $gapDisplay -Human $humanDisplay -Ai $aiDisplay -Total $totalDisplay -RoundType $roundTypeValue

exit 0
