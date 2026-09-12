<#
.SYNOPSIS
    领域约定单源（PS 侧）：动作的"性格"、文件名/目录名常量、命名规则。

.DESCRIPTION
    与 AHK 侧 app\modules\business\services\DomainConventions.ahk 同名对应——两侧各一份，靠约定保持一致
    （PS 读不到 AHK 的类，这一点无解，如实说明）。

    三条规矩：
      1. 每样东西只在本文件出现一次；别处一律调本模块的函数，不再写字面量；
      2. 只导出函数、不导出变量（模块变量不跨模块可见——项目现有 5 个 psm1 都是这个写法）；
      3. 本模块是叶子：不 import 任何项目模块（保持单向依赖）。

    动作表（一个动作一行，性格都在这一行里）：
      Kind             Send=发送类动作；Local=本地动作（写日志，但不进轮次统计）
      RoundType        本轮的轮次类型；'' = 本表不给（查不到就是没定义）
      NoHumanTime      人耗时恒 0
      NoInputFile      无输入文件（人字数为 0）
      DefaultSource    无 source 时的兜底来源文件（'' = 无兜底）
      MainRound        是否进"主轮次循环"（日志注入 round-type、统计与配对都按它筛）。
                       复关系是发送类，但走独立重建路（Get-RebuildRoundRows），故为 false——
                       它若混进主循环会被重复计入（这条是静态对照表查出来的，不是想当然）。

    未定义的动作：各查询函数分别返回 $false / $null / ''，即"不在集合里、没有类型"——
    本模块不替没定义的动作编性格；各处按自己原来的兜底逻辑走。

    对话域判据（领域标准，登记在案）：
      标准 = 同时含 需求.txt 与 .aiprocess 两个标记；只有一个不算标准对话域。
      统计聚合侧（ThemeAggregation.Get-ChildThemes）现用的是单条"含 .aiprocess"判据，
      全库实测与上述标准等价（唯一差异目录无任何统计产出）。另一处差异：AHK 侧 IsDomainDir 用
      "含 需求.txt，或 父目录名 = 实施步骤"识别需求树里的"已实施 / 未实施"。三处收口留待独立需求，
      本文件只登记标准与常量，不在此实现判据函数（避免无人调用的死代码）。
#>

# ---------- 文件名 / 目录名常量（先于动作表定义：表里要引用它） ----------
$script:RequirementFile    = '需求.txt'
$script:ImplDocFile        = '实施文档.md'
$script:ExecutedFile       = '已实施.md'
$script:ContextRebuildName = '上下文重建'
$script:DataDirName        = '.aiprocess'
$script:ResultIssueRootName = '结果微调'
$script:StepsDirName       = '实施步骤'

# ---------- 命名规则（正则） ----------
$script:VersionFilePattern = '^v\d+\.md$'
$script:ReplyFilePattern   = '^对v\d+的回复\.txt$'
$script:IssueDirPattern    = '^\d{2}$'

# ---------- 动作表（全项目唯一一处） ----------
$script:Actions = @(
    @{ Name = '复需求'; Kind = 'Send';  MainRound = $true;  RoundType = 'discussion'; NoHumanTime = $false; NoInputFile = $false; DefaultSource = $script:RequirementFile }
    @{ Name = '复回复'; Kind = 'Send';  MainRound = $true;  RoundType = 'discussion'; NoHumanTime = $false; NoInputFile = $false; DefaultSource = '' }
    @{ Name = '复执行'; Kind = 'Send';  MainRound = $true;  RoundType = 'execute';    NoHumanTime = $true;  NoInputFile = $false; DefaultSource = '' }
    @{ Name = '质检码'; Kind = 'Send';  MainRound = $true;  RoundType = 'discussion'; NoHumanTime = $true;  NoInputFile = $true;  DefaultSource = '' }
    # 复关系：发送类，但走独立的重建路（Get-RebuildRoundRows 内部派生 rebuild）——RebuildPath 标出它，
    # 那条路本轮的逻辑不动，只是把它的名字也收进来。
    @{ Name = '复关系'; Kind = 'Send';  MainRound = $false; RoundType = 'rebuild';    NoHumanTime = $true;  NoInputFile = $false; DefaultSource = ''; RebuildPath = $true }
    # 本地动作：写日志，但不进轮次统计。建问题此前从未被任何清单登记过，这次补上。
    # BuildFor：人文件 → 该找哪个"建X"动作（'*' = 其余人文件的兜底）；没有这项的动作不参与该派生。
    @{ Name = '建需求'; Kind = 'Local'; MainRound = $false; RoundType = ''; NoHumanTime = $false; NoInputFile = $false; DefaultSource = ''; BuildFor = $script:RequirementFile }
    @{ Name = '建回复'; Kind = 'Local'; MainRound = $false; RoundType = ''; NoHumanTime = $false; NoInputFile = $false; DefaultSource = ''; BuildFor = '*' }
    @{ Name = '建问题'; Kind = 'Local'; MainRound = $false; RoundType = ''; NoHumanTime = $false; NoInputFile = $false; DefaultSource = '' }
)

# ---------- 内部：按名字取表行 ----------
function Get-ActionRow {
    param([string]$Name)
    foreach ($a in $script:Actions) {
        if ($a.Name -eq $Name) { return $a }
    }
    return $null
}

# ---------- 动作查询 ----------
function Get-MainRoundActionNames {
    # 主轮次循环里的动作清单（统计与配对按它筛；复关系走独立重建路，不在其中）
    return @($script:Actions | Where-Object { $_.MainRound } | ForEach-Object { $_.Name })
}

function Test-IsMainRoundAction {
    param([string]$Name)
    $a = Get-ActionRow $Name
    return ($null -ne $a -and $a.MainRound)
}

function Test-IsRebuildPathAction {
    # 走独立重建路的动作（复关系）：它的轮次由 Get-RebuildRoundRows 单独产出
    param([string]$Name)
    $a = Get-ActionRow $Name
    return ($null -ne $a -and $a.ContainsKey('RebuildPath') -and $a.RebuildPath)
}

function Get-BuildActionFor {
    # 由人文件名决定该找哪个"建X"动作：需求.txt → 建需求；其余（对vN的回复.txt）→ 建回复
    param([string]$SourceName)
    $fallback = ''
    foreach ($a in $script:Actions) {
        if (-not $a.ContainsKey('BuildFor')) { continue }
        if ($a.BuildFor -eq $SourceName) { return $a.Name }
        if ($a.BuildFor -eq '*') { $fallback = $a.Name }
    }
    return $fallback
}

function Get-RoundType {
    # 未定义 / 本表不给 → $null（调用方按自己的兜底走，别替它编）
    param([string]$Name)
    $a = Get-ActionRow $Name
    if ($null -eq $a) { return $null }
    if ($a.RoundType -eq '') { return $null }
    return $a.RoundType
}

function Test-HasNoHumanTime {
    param([string]$Name)
    $a = Get-ActionRow $Name
    return ($null -ne $a -and $a.NoHumanTime)
}

function Test-HasNoInputFile {
    param([string]$Name)
    $a = Get-ActionRow $Name
    return ($null -ne $a -and $a.NoInputFile)
}

function Get-DefaultSourceFor {
    # 无 source 时的兜底来源文件；无兜底或未定义 → ''
    param([string]$Name)
    $a = Get-ActionRow $Name
    if ($null -eq $a) { return '' }
    return $a.DefaultSource
}

# ---------- 名字常量（一个概念一个函数，调用点零字面量） ----------
function Get-RequirementFileName { return $script:RequirementFile }
function Get-ImplDocFileName { return $script:ImplDocFile }
function Get-ExecutedFileName { return $script:ExecutedFile }
function Get-ContextRebuildName { return $script:ContextRebuildName }
function Get-DataDirName { return $script:DataDirName }
function Get-VersionFilePattern { return $script:VersionFilePattern }
function Get-ReplyFilePattern { return $script:ReplyFilePattern }
function Get-ResultIssueRootName { return $script:ResultIssueRootName }
function Get-StepsDirName { return $script:StepsDirName }
function Get-IssueDirPattern { return $script:IssueDirPattern }

Export-ModuleMember -Function Get-MainRoundActionNames, Test-IsMainRoundAction, Test-IsRebuildPathAction, Get-BuildActionFor,
    Get-RoundType, Test-HasNoHumanTime, Test-HasNoInputFile, Get-DefaultSourceFor,
    Get-RequirementFileName, Get-ImplDocFileName, Get-ExecutedFileName, Get-ContextRebuildName,
    Get-DataDirName, Get-VersionFilePattern, Get-ReplyFilePattern,
    Get-ResultIssueRootName, Get-StepsDirName, Get-IssueDirPattern
