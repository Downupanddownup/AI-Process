<#
.SYNOPSIS
    统计指标定义单源（PS 侧）：指标名 / JSON 键 / 含义 / 口径 / 形态。

.DESCRIPTION
    "一眼看全"的落点：一个指标的中文名、它在 stats.json 里的键、它是什么意思、怎么算出来的，
    只在本文件写一遍。内核组装 stats.json 仍用字面量键名（可读性优先），一致性由
    test\Verify-StatsSchema.ps1 的集合对照保证——定义单源 + 校验兜底，不用映射表驱动取数。

    Key 两种：
      Storage  落 stats.json 的指标，Key 是 JSON 键路径（点号分层，数组用 []）
      Display  只在 统计.md 出现的派生值（渲染层现算），Key 形如 display.xxx，不是 JSON 路径

    Summed 标出"可求和字段"：aggregate 就是这些字段按
    "父.aggregate = 父自身 + Σ 直接子.aggregate" 求出来的形态。

    三条规矩（与 conventions\DomainConventions.psm1 同款）：
      1. 每样东西只在本文件出现一次；别处一律调本模块的函数，不再写字面量；
      2. 只导出函数、不导出变量（模块内数组跨模块不可见）；
      3. 本模块是叶子：不 import 任何项目模块。

    口径文本里的占位符：{threshold} = 空闲阈值分钟，{now} = 本轮计算时刻。
#>

# ---------- 指标表（全项目唯一一处） ----------
# 字段：Key  JSON 键路径 / Name 中文名 / Meaning 含义 / Rule 口径 / Form 形态 / Group 分组 / Summed 是否进 aggregate
$script:Metrics = @(

    # ============ 时长 ============
    [ordered]@{ Key='time.roundTotalSec'; Name='轮次总耗时（人+AI）'; Form='Storage'; Group='时长'; Summed=$true
        Meaning='全部轮次的人耗时与 AI 耗时合计'
        Rule='各轮 humanSec + aiSec 求和；null 不计' }
    [ordered]@{ Key='time.gapTotalSec'; Name='轮间间隔合计'; Form='Storage'; Group='时长'; Summed=$true
        Meaning='轮与轮之间的空档合计'
        Rule='各轮 gapSec 求和' }
    [ordered]@{ Key='time.activeSec'; Name='总时长（活跃，剔除 >{threshold}min 空闲段）'; Form='Storage'; Group='时长'; Summed=$true
        Meaning='剔除大段离开后的真实投入'
        Rule='首末日志点之间，相邻日志点间隔 ≤{threshold}min 的段累加，超阈值的整段剔除' }
    [ordered]@{ Key='time.wallClockSec'; Name='墙钟时长（首末日志原始跨度）'; Form='Storage'; Group='时长'; Summed=$false
        Meaning='首末日志的原始跨度，不剔除任何空闲'
        Rule='末条日志时刻 − 首条日志时刻' }
    [ordered]@{ Key='time.humanSec'; Name='人思考时长（讨论轮合计）'; Form='Storage'; Group='时长'; Summed=$true
        Meaning='人从开始写输入到发出的时长合计'
        Rule='各轮 humanSec 求和；执行轮与重建轮恒 0，故实等于讨论轮合计' }
    [ordered]@{ Key='time.aiSec'; Name='AI 执行时长（合计）'; Form='Storage'; Group='时长'; Summed=$true
        Meaning='AI 从收到到完成的时长合计'
        Rule='各轮 aiSec 求和（含重建轮）；无完成通知的轮记未知、不计入' }
    [ordered]@{ Key='time.idleIgnoredSec'; Name='忽略时长'; Form='Storage'; Group='时长'; Summed=$false
        Meaning='被活跃时长剔除掉的那部分'
        Rule='墙钟时长 − 活跃时长。⚠ 不进 aggregate（父级没有"忽略"这个视角）' }
    [ordered]@{ Key='time.idleIgnoredCount'; Name='忽略段数'; Form='Storage'; Group='时长'; Summed=$false
        Meaning='超阈值空闲段的个数'
        Rule='相邻日志点（按秒去重）间隔 >{threshold}min 的次数。⚠ 不进 aggregate' }
    [ordered]@{ Key='time.createdAt'; Name='主题创建'; Form='Storage'; Group='时长'; Summed=$false
        Meaning='首条日志时刻'
        Rule='最早一条日志的 time' }
    [ordered]@{ Key='time.lastActiveAt'; Name='最后活动'; Form='Storage'; Group='时长'; Summed=$false
        Meaning='末条日志时刻'
        Rule='最晚一条日志的 time' }

    # ============ 文件与字符 ============
    [ordered]@{ Key='files.total'; Name='文件数（总）'; Form='Storage'; Group='文件与字符'; Summed=$true
        Meaning='主题根目录顶层文件数'
        Rule='仅主题根目录顶层文件；排除隐藏文件与 .aiprocess 子目录。⚠ 在 aggregate 里叫 files（短名，历史命名，产物接口不动）' }
    [ordered]@{ Key='files.humanFiles'; Name='文件数（人）'; Form='Storage'; Group='文件与字符'; Summed=$true
        Meaning='人文件数'
        Rule='需求.txt + 对vN的回复.txt' }
    [ordered]@{ Key='files.aiFiles'; Name='文件数（AI）'; Form='Storage'; Group='文件与字符'; Summed=$true
        Meaning='AI 文件数'
        Rule='vN.md + 实施文档.md + 已实施.md' }
    [ordered]@{ Key='files.humanChars'; Name='字符数（人，文件扫描口径）'; Form='Storage'; Group='文件与字符'; Summed=$true
        Meaning='人文件的全文长度合计'
        Rule='需求.txt + 对vN的回复.txt 的全文长度求和。⚠ 与轮次明细的人字数合计不是同一个数（那是轮次求和口径）' }
    [ordered]@{ Key='files.aiChars'; Name='字符数（AI，文件扫描口径）'; Form='Storage'; Group='文件与字符'; Summed=$true
        Meaning='AI 文件的正文长度合计'
        Rule='vN.md + 实施文档.md + 已实施.md 剥离 front matter（首行 --- 起 50 行内闭合）后的正文长度求和' }

    # ============ 轮次计数 ============
    [ordered]@{ Key='rounds.discussion'; Name='讨论轮'; Form='Storage'; Group='轮次计数'; Summed=$true
        Meaning='round-type=discussion 的发送数'
        Rule='直读日志 round-type；动作表里复需求 / 复回复 / 质检码属之' }
    [ordered]@{ Key='rounds.execute'; Name='执行轮'; Form='Storage'; Group='轮次计数'; Summed=$true
        Meaning='round-type=execute 的发送数'
        Rule='直读日志 round-type；复执行属之' }
    [ordered]@{ Key='rounds.rebuild'; Name='重建轮'; Form='Storage'; Group='轮次计数'; Summed=$true
        Meaning='复关系轮次数'
        Rule='复关系发送 → target=上下文重建 的完成通知，配对成一轮' }
    [ordered]@{ Key='rounds.unknown'; Name='未知轮数（老日志配不上对）'; Form='Storage'; Group='轮次计数'; Summed=$true
        Meaning='没有 target 的发送数'
        Rule='三类发送中 target 为空的计数' }
    [ordered]@{ Key='rounds.executeByStrategy'; Name='执行轮按策略'; Form='Storage'; Group='轮次计数'; Summed=$false
        Meaning='执行轮按执行策略的分布'
        Rule='rounds.execute 的子计数，按日志"执行策略"字段分组；缺字段记"未标注"' }

    # ============ 派生 ============
    [ordered]@{ Key='derived.avgHumanSec'; Name='平均每轮耗时（人）'; Form='Storage'; Group='派生'; Summed=$false
        Meaning='讨论轮人耗时的均值'
        Rule='仅讨论轮且 humanSec 非 null 的轮求平均' }
    [ordered]@{ Key='derived.avgAiSec'; Name='平均每轮耗时（AI）'; Form='Storage'; Group='派生'; Summed=$false
        Meaning='各轮 AI 耗时的均值'
        Rule='所有 aiSec 非 null 的轮求平均' }
    [ordered]@{ Key='derived.longestRound.file'; Name='最长轮次（文件）'; Form='Storage'; Group='派生'; Summed=$false
        Meaning='单轮 human+ai 之和最大的那一轮'
        Rule='按 humanSec + aiSec 之和取最大；全为 0 时为空' }
    [ordered]@{ Key='derived.longestRound.sec'; Name='最长轮次（秒）'; Form='Storage'; Group='派生'; Summed=$false
        Meaning='该轮的人+AI 秒数'
        Rule='同上；全为 0 时为 0' }

    # ============ 其他 ============
    [ordered]@{ Key='agents[]'; Name='参与 Agent'; Form='Storage'; Group='其他'; Summed=$false
        Meaning='写过日志的 Agent 名去重列表'
        Rule='日志 agent 字段去重；老日志缺该字段记空串、不参与去重' }

    # ============ 轮次明细（roundDetail 数组的列） ============
    [ordered]@{ Key='roundDetail[].file'; Name='明细-文件'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮对应的目标文件名'
        Rule='多 target 时每个有效 target 一行；重复发送合并后在展示层标注' }
    [ordered]@{ Key='roundDetail[].type'; Name='明细-类型'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮类型'
        Rule='直读日志 round-type；缺字段记"未标注"，展示层按"讨论"显示' }
    [ordered]@{ Key='roundDetail[].agent'; Name='明细-Agent'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='该轮执行的 Agent'
        Rule='取自发送日志的 agent 字段' }
    [ordered]@{ Key='roundDetail[].sendTime'; Name='明细-发送时刻'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='该轮复X 的时刻'
        Rule='发送日志的 time' }
    [ordered]@{ Key='roundDetail[].humanSec'; Name='明细-人耗时'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮人思考秒数'
        Rule='讨论轮=建X→复X；执行轮/重建轮=0；多 target 只有第一有效行记值、其余 0；配不上建X 记 null' }
    [ordered]@{ Key='roundDetail[].aiSec'; Name='明细-AI耗时'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮 AI 执行秒数'
        Rule='复X → 其后第一条同 target 完成通知；无通知记 null（不编造）' }
    [ordered]@{ Key='roundDetail[].totalSec'; Name='明细-合计耗时'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮人+AI'
        Rule='humanSec + aiSec；null 不计；两者皆 null 记 null' }
    [ordered]@{ Key='roundDetail[].gapSec'; Name='明细-轮间间隔'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮起点与上一轮结束之间的空档'
        Rule='本轮起点（建X，配不上则复X）− 此前最近一条完成通知；首轮 0；多 target 只有第一有效行记值' }
    [ordered]@{ Key='roundDetail[].humanChars'; Name='明细-人字数'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮输入文件的字符数（轮次求和口径）'
        Rule='第一有效行的 source 文件全文长度；无输入文件的动作记 0。⚠ 与 files.humanChars 不是同一个数' }
    [ordered]@{ Key='roundDetail[].aiChars'; Name='明细-AI字数'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮目标文件正文的字符数'
        Rule='该 target 文件剥离 front matter 后的长度' }
    [ordered]@{ Key='roundDetail[].known'; Name='明细-是否闭环'; Form='Storage'; Group='轮次明细'; Summed=$false
        Meaning='本轮配对是否成功'
        Rule='完成通知与建X 都配上了才为真' }

    # ============ 父子聚合（children 数组的列） ============
    [ordered]@{ Key='children[].name'; Name='子主题-名称'; Form='Storage'; Group='父子聚合'; Summed=$false
        Meaning='直接子主题的目录名'
        Rule='目录叶子名' }
    [ordered]@{ Key='children[].relPath'; Name='子主题-相对路径'; Form='Storage'; Group='父子聚合'; Summed=$false
        Meaning='相对父主题的路径'
        Rule='去掉父主题前缀后的相对路径' }
    [ordered]@{ Key='children[].aggregate'; Name='子主题-汇总'; Form='Storage'; Group='父子聚合'; Summed=$false
        Meaning='该子主题含其全部后代的汇总'
        Rule='读子的 stats.json 的 aggregate 段；子未发布则为空、不进父的 aggregate' }

    # ============ 展示层派生（只在 统计.md 出现，不落 stats.json） ============
    [ordered]@{ Key='display.overview.childColumn'; Name='总览-子主题列'; Form='Display'; Group='展示层派生'; Summed=$false
        Meaning='总览表"子主题"整列的各项'
        Rule='aggregate − 自身（逐字段相减，渲染时现算）' }
    [ordered]@{ Key='display.overview.percent'; Name='总览-占比'; Form='Display'; Group='展示层派生'; Summed=$false
        Meaning='各指标在分母中的占比'
        Rule='总览三列统一分母 = 总跨度；自身统计与轮次明细分母 = 自身墙钟；分母 ≤0 或值为 0 时不挂百分比' }
    [ordered]@{ Key='display.rebuild.aiTotal'; Name='重建轮（复关系）'; Form='Display'; Group='展示层派生'; Summed=$false
        Meaning='重建轮单独的 AI 耗时合计'
        Rule='Σ roundDetail[type=rebuild].aiSec' }
    [ordered]@{ Key='display.detail.totalRow'; Name='轮次明细-合计行'; Form='Display'; Group='展示层派生'; Summed=$false
        Meaning='轮次明细的小计'
        Rule='人/AI/合计/间隔/字数分别对明细各列求和；其中字数为轮次求和口径，与 files.* 不是同一个数' }
    [ordered]@{ Key='display.overview.childSpan'; Name='总览-墙钟-子主题列'; Form='Display'; Group='展示层派生'; Summed=$false
        Meaning='全部子主题的首末跨度'
        Rule='子主题 createdAt 最早 → lastActiveAt 最晚（取极值，不求和）' }
)

# ---------- 口径约定（跨指标的规则，统计.md 尾部"口径说明"段逐条来自这里） ----------
# 占位符：{threshold} / {now}
$script:RuleNotes = @(
    '- 轮次总耗时（人+AI）= 各轮 人耗时+AI耗时 合计；轮间间隔 = 本轮起点 − 上一轮完成通知（首轮为 0）'
    '- 人思考=建X→复X（仅讨论轮，执行轮恒 0）；AI执行=复X→同 target 完成通知（无通知记未知，不编造）'
    '- 总时长（活跃）= 首末日志剔除 >{threshold}min 空闲段；墙钟=首末日志原始跨度'
    '- 人字数=需求.txt+对vN回复.txt；AI字数=vN.md+实施/已实施.md 正文（剥离 front matter）'
    '- 字符数 >=1万 按量级缩写（如 2.05万），精确值见 stats.json'
    '- 重复发送去重：同 target 且配对同一完成通知的重复发送合并为一轮，取首次发送数值（明细文件列标注已合并）'
    '- 多 target 发送：人耗时/轮间间隔只计入第一个有效文件行，其余记 0；文件不存在且无通知的虚空行不列入明细（全虚空时保留首行记未闭环）'
    '- 百分比分母：总览三列统一为总跨度（可跨列相加：自身+子主题≈总）；自身统计与轮次明细为自身墙钟；无发送记录的孤儿时段不计轮，故百分比合计可能不足 100%'
    "- 重建轮=复关系发送→上下文重建完成通知（人耗时/字数恒 0，轮间间隔照常，其完成通知参与轮间锚点）；未知轮数=三类发送中无 target 的计数
- 总览三列：总（含子主题）= 自身 + Σ 直接子主题的 aggregate（孙主题已含在子内）；活跃/墙钟类仅自身不求和，总跨度取最早创建→最晚活动
- 子主题识别：后代目录含 .aiprocess 即子主题（结果微调为容器），只聚合直接子"
    '- 计算时间：{now}（脚本自动生成，每次重算全量覆盖）'
)

# ---------- 内部：占位符替换 ----------
function Expand-StatsRuleText {
    param([string]$Text, [int]$ThresholdMinutes, [string]$ComputedAt)
    $t = $Text.Replace('{threshold}', [string]$ThresholdMinutes)
    if ($ComputedAt -ne '') { $t = $t.Replace('{now}', $ComputedAt) }
    return $t
}

# ---------- 指标查询 ----------
function Get-StatsMetrics {
    # 取全部指标；-Form Storage|Display 可按形态过滤
    param([string]$Form = '')
    if ($Form -eq '') { return @($script:Metrics) }
    return @($script:Metrics | Where-Object { $_.Form -eq $Form })
}

function Get-StatsStorageKeys {
    # 全部落盘指标的键集合（校验脚本用）
    return @($script:Metrics | Where-Object { $_.Form -eq 'Storage' } | ForEach-Object { $_.Key })
}

function Get-StatsSummedKeys {
    # 可求和字段的键集合 —— aggregate 的来源
    return @($script:Metrics | Where-Object { $_.Form -eq 'Storage' -and $_.Summed } | ForEach-Object { $_.Key })
}

function Get-StatsAggregateKeys {
    # aggregate 段的键集合（扁平，不带分组前缀）
    # ⚠ 短名不是简单取叶子：files.total 在 aggregate 里叫 files（历史命名，已登记在该条的 Rule 里）。
    #    产物接口不动，故映射写在这里，让校验脚本与定义表对得上。
    $shortNameOverride = @{ 'files.total' = 'files' }
    $keys = @()
    foreach ($m in @($script:Metrics | Where-Object { $_.Form -eq 'Storage' -and $_.Summed })) {
        if ($shortNameOverride.ContainsKey($m.Key)) { $keys += $shortNameOverride[$m.Key] }
        else { $keys += ($m.Key -split '\.')[-1] }
    }
    return @($keys + @('createdAt', 'lastActiveAt'))
}

function Get-StatsRuleText {
    # 统计.md 尾部"口径说明"的条目文本（占位符已替换）
    param(
        [Parameter(Mandatory = $true)][int]$ThresholdMinutes,
        [Parameter(Mandatory = $false)][string]$ComputedAt = ''
    )
    return @($script:RuleNotes | ForEach-Object { Expand-StatsRuleText -Text $_ -ThresholdMinutes $ThresholdMinutes -ComputedAt $ComputedAt })
}

Export-ModuleMember -Function Get-StatsMetrics,
    Get-StatsStorageKeys, Get-StatsSummedKeys, Get-StatsAggregateKeys, Get-StatsRuleText
