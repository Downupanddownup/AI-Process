<#
.SYNOPSIS
    主题统计编排入口：取配置 → 调内核算 → 写 stats.json → 调展示层写 统计.md → 级联向上。

.DESCRIPTION
    本脚本只做编排，不含任何计算与排版逻辑：
      - 数值一律由 ThemeStatsCore.psm1（内核）产出；
      - 文本一律由 RenderStatsMarkdown.psm1（展示层）产出；
      - 本身负责：读阈值配置、全量覆盖落盘、以及"算完自己触发父重算"的级联。

    口径要点（见《跨天BUG以及重构\实施文档.md》与 v8.md §三）：
      - 人思考时长：候选 = 同 source 的每一次 建X，取"第一个不超阈值的候选"；降到底记 0；
      - AI 处理时长：候选 = 同 target 的每一次发送（同一条完成通知为一轮），规则同上；
      - 剔除时长/次数：被放弃的跨度（第一候选 → 采用候选）与发生剔除的段数（一轮最多 2）；
      - 认知时长：人思考 + 落在 ≤{认知阈值}min 的轮间间隔（估计值，保守下界）；它与「人思考」并列，人思考与间隔本身不变；
      - 轮间间隔：本轮起点 − 上一轮最近完成通知，原样记不做剔除；
      - 未知轮数：仅发送类动作中无 target 的计数；
      - 复关系（上下文重建）：计为重建轮（与讨论/执行并列），人耗时/字数恒 0，其完成通知参与轮间间隔锚点；
      - 老日志无 agent 字段记空串；配不上对的轮次时长记 null，不编造。

    成功路径与失败路径的约定：
      - 幂等全量覆盖；产出 {ThemePath}/.aiprocess/stats.json（机器可读）+ 统计.md（人类友好），均 UTF-8 无 BOM；
      - 级联联动：算完自己后若存在父主题则自调用触发父重算（只触发不写父文件，深度保护 10 层）；
      - 失败隔离：任何异常仅输出警告，退出码始终为 0，不阻断调用方主流程；
      - .aiprocess 目录不存在时直接跳过（不主动创建）。

    ⚠ 本脚本的路径是调用契约（完成通知与 test\Verify-Output.ps1 都指向它），勿改名或挪目录。

.PARAMETER ThemePath
    主题目录绝对路径。

.PARAMETER CascadeDepth
    级联深度（内部自调用用），外部调用勿传。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath,

    [Parameter(Mandatory = $false)]
    [int]$CascadeDepth = 0
)

# 失败隔离：本脚本为增强功能，任何情况下都不以非零退出码阻断调用方
trap {
    Write-Warning "ComputeThemeStats failed: $_"
    exit 0
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$corePath = Join-Path $scriptDirectory "ThemeStatsCore.psm1"
$renderPath = Join-Path $scriptDirectory "RenderStatsMarkdown.psm1"
$appSettingsPath = Join-Path $scriptDirectory "..\config\AppSettings.psm1"
$conventionsPath = Join-Path $scriptDirectory "..\conventions\DomainConventions.psm1"   # 名字与动作性格单源

foreach ($p in @($corePath, $renderPath, $appSettingsPath, $conventionsPath)) {
    if (-not (Test-Path -LiteralPath $p)) { exit 0 }
}
try {
    Import-Module $corePath -ErrorAction Stop
    Import-Module $renderPath -ErrorAction Stop
    Import-Module $appSettingsPath -ErrorAction Stop
    Import-Module $conventionsPath -ErrorAction Stop
} catch {
    exit 0
}

$aiProcessDir = Join-Path $ThemePath (Get-DataDirName)
if (-not (Test-Path -LiteralPath $aiProcessDir)) { exit 0 }

# ---------- 算（阈值是配置，由编排层读、以参数下发给内核） ----------
$threshold = Get-IdleThresholdMinutes
$thinkThreshold = Get-ThinkThresholdMinutes
$result = Get-ThemeStats -ThemePath $ThemePath -ThresholdMinutes $threshold -ThinkThresholdMinutes $thinkThreshold -Now (Get-Date)

# ---------- 落 stats.json ----------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$json = ConvertTo-Json $result.Stats -Depth 6 -Compress
[System.IO.File]::WriteAllText((Join-Path $aiProcessDir "stats.json"), $json, $utf8NoBom)

# ---------- 渲染并落 统计.md ----------
$markdown = ConvertTo-StatsMarkdown -Stats $result.Stats -Context @{
    ThresholdMinutes      = $threshold
    ThinkThresholdMinutes = $thinkThreshold
    DupSendCountByTarget  = $result.DupSendCountByTarget
    DupExecCountByTarget  = $result.DupExecCountByTarget
}
[System.IO.File]::WriteAllText((Join-Path $aiProcessDir "统计.md"), $markdown, $utf8NoBom)

# ---------- 级联向上：子算完触发父重算（父自身数据幂等不变，仅重新聚合）；子只触发不写父文件 ----------
# 必须在写完自己的 stats.json 之后——父主题读子的 stats.json 取 aggregate，写晚了父就读到旧值
# 父主题定位：父目录为"结果微调"等容器时上跳；第一个含 .aiprocess 的祖先即父主题。目录树无环 + 深度保护双保险
$parentDir = Split-Path -Parent $ThemePath
while ($parentDir -and -not (Test-Path -LiteralPath (Join-Path $parentDir '.aiprocess'))) {
    $next = Split-Path -Parent $parentDir
    if ($next -eq $parentDir) { $parentDir = $null; break }
    $parentDir = $next
}
if ($CascadeDepth -lt 10 -and $parentDir) {
    & $PSCommandPath -ThemePath $parentDir -CascadeDepth ($CascadeDepth + 1)
}

exit 0
