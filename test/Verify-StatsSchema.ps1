<#
.SYNOPSIS
    统计定义对齐校验：指标定义表（StatsSchema.psm1）↔ stats.json ↔ 统计.md。

.DESCRIPTION
    把"一眼看全"变成能跑出对错的检查。纯读：不写任何文件、不跑生成脚本。

      检查 1  定义表的 Storage 键集合 == stats.json 的指标键集合（严格相等，双向）
      检查 2  aggregate 的键集合 == 定义表标了 Summed 的键 + createdAt + lastActiveAt（严格相等）
      对照清单 统计.md 的指标名 与 定义表的指标名 并排列出，供人过目（不判失败）

    为什么第三条不判失败：统计.md 的一张表里，一行常合并多个指标
    （"轮次（讨论 / 执行 / 重建）"是 3 个键、"忽略时长 / 段数"是 2 个键），
    总览还给同一指标另一个版式标签（"总投入（人+AI）"vs"轮次总耗时（人+AI）"）——
    版式标签与指标名不是一一对应，强行 1:1 只会造出一张假的映射表。
    能严格判定的是前两条：定义表与产物必须一个键都不差。

.PARAMETER StatsFile
    要校验的 stats.json 路径。默认自动挑仓库里最新的一个（排除 .claude 与 .git）。

.PARAMETER Dump
    额外打印完整的指标定义表（中文名 / JSON 键 / 形态 / 含义 / 口径）。

.EXAMPLE
    powershell -File test\Verify-StatsSchema.ps1
    powershell -File test\Verify-StatsSchema.ps1 -StatsFile "D:\...\.aiprocess\stats.json" -Dump
#>
param(
    [string]$StatsFile = "",
    [switch]$Dump
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$schemaPath = Join-Path $repoRoot "app\powershell\summary\StatsSchema.psm1"
if (-not (Test-Path -LiteralPath $schemaPath)) { Write-Host "找不到定义表：$schemaPath" -ForegroundColor Red; exit 2 }
Import-Module $schemaPath -ErrorAction Stop

# ---------- 定位样本 ----------
if ($StatsFile -eq "") {
    $found = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter "stats.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\\.claude\\' } |
        Sort-Object LastWriteTime -Descending
    if (@($found).Count -eq 0) { Write-Host "仓库里找不到 stats.json，请用 -StatsFile 指定。" -ForegroundColor Yellow; exit 2 }
    $StatsFile = @($found)[0].FullName
}
if (-not (Test-Path -LiteralPath $StatsFile)) { Write-Host "找不到 stats.json：$StatsFile" -ForegroundColor Red; exit 2 }
$stats = [System.IO.File]::ReadAllText($StatsFile) | ConvertFrom-Json
$mdPath = Join-Path (Split-Path -Parent $StatsFile) "统计.md"

Write-Host ""
Write-Host ("定义表：{0}" -f $schemaPath)
Write-Host ("样本  ：{0}" -f $StatsFile)

# ---------- 定义表侧 ----------
$schemaStorage = @(Get-StatsStorageKeys)
$schemaSummed = @(Get-StatsSummedKeys)
$aggKeys = @(Get-StatsAggregateKeys)
$schemaAggregate = @($aggKeys | ForEach-Object { 'aggregate.' + $_ })
$expected = @($schemaStorage + $schemaAggregate | Sort-Object -Unique)

# ---------- 产物侧：逐个分组显式枚举（不写通用递归，避免踩数组/动态键的坑） ----------
$actual = @()
foreach ($k in $stats.time.PSObject.Properties.Name) { $actual += "time.$k" }
foreach ($k in $stats.files.PSObject.Properties.Name) { $actual += "files.$k" }
foreach ($k in $stats.rounds.PSObject.Properties.Name) { $actual += "rounds.$k" }   # executeByStrategy 整体算一个键
foreach ($k in $stats.derived.PSObject.Properties.Name) {
    if ($k -eq 'longestRound') {
        foreach ($j in $stats.derived.longestRound.PSObject.Properties.Name) { $actual += "derived.longestRound.$j" }
    } else {
        $actual += "derived.$k"
    }
}
if ($null -ne $stats.agents) { $actual += 'agents[]' }
foreach ($k in $stats.aggregate.PSObject.Properties.Name) { $actual += "aggregate.$k" }
$skipNotes = @()
if (@($stats.roundDetail).Count -gt 0) {
    foreach ($k in $stats.roundDetail[0].PSObject.Properties.Name) { $actual += "roundDetail[].$k" }
} else {
    $skipNotes += "样本的 roundDetail 为空 —— roundDetail[] 一组未校验"
}
if (@($stats.children).Count -gt 0) {
    foreach ($k in $stats.children[0].PSObject.Properties.Name) {
        if ($k -ne 'computedAt') { $actual += "children[].$k" }   # computedAt 是结构字段
    }
} else {
    $skipNotes += "样本无子主题 —— children[] 一组未校验（aggregate 仍照验）"
}
$actual = @($actual | Sort-Object -Unique)

# ---------- 检查 1：定义表 ↔ 产物 ----------
Write-Host ""
Write-Host "== 检查 1：定义表 Storage 键 == stats.json 指标键 =="
Write-Host ("   定义表 {0} 个（含 aggregate 段 {1} 个）／产物 {2} 个" -f $expected.Count, $schemaAggregate.Count, $actual.Count)
$missing = @($expected | Where-Object { $actual -notcontains $_ })
$extra = @($actual | Where-Object { $expected -notcontains $_ })
$pass1 = ($missing.Count -eq 0 -and $extra.Count -eq 0)
if ($pass1) {
    Write-Host "   [PASS] 两边完全一致" -ForegroundColor Green
} else {
    Write-Host "   [FAIL]" -ForegroundColor Red
    foreach ($m in $missing) { Write-Host ("     定义里有、产物没有：" + $m) -ForegroundColor Red }
    foreach ($x in $extra) { Write-Host ("     产物里有、定义没有：" + $x) -ForegroundColor Red }
}

# ---------- 检查 2：aggregate ↔ 可求和字段 ----------
Write-Host ""
Write-Host "== 检查 2：aggregate 的键 == 定义表 Summed 字段 + 两个极值键 =="
$aggActual = @($stats.aggregate.PSObject.Properties.Name | ForEach-Object { $_ } | Sort-Object -Unique)
$aggExpected = @($aggKeys | Sort-Object -Unique)
$aggMissing = @($aggExpected | Where-Object { $aggActual -notcontains $_ })
$aggExtra = @($aggActual | Where-Object { $aggExpected -notcontains $_ })
$pass2 = ($aggMissing.Count -eq 0 -and $aggExtra.Count -eq 0)
if ($pass2) {
    Write-Host ("   [PASS] {0} 个键一致（可求和 {1} + 极值 2）" -f $aggActual.Count, $schemaSummed.Count) -ForegroundColor Green
} else {
    Write-Host "   [FAIL]" -ForegroundColor Red
    foreach ($m in $aggMissing) { Write-Host ("     aggregate 少了：" + $m) -ForegroundColor Red }
    foreach ($x in $aggExtra) { Write-Host ("     aggregate 多了：" + $x) -ForegroundColor Red }
}

# ---------- 对照清单（不判失败） ----------
Write-Host ""
Write-Host "== 对照清单：统计.md 的指标名 ／ 定义表的指标名（供人过目，不判失败）=="
# 收两侧的名字：统计.md 取「总览/自身统计」的行标签 + 「轮次明细/子主题汇总」的列名
$mdNames = @()
if (Test-Path -LiteralPath $mdPath) {
    $section = ''
    $headerTaken = $false
    foreach ($line in (Get-Content -LiteralPath $mdPath -Encoding UTF8)) {
        if ($line -match '^##\s+(.+)$') { $section = $Matches[1].Trim(); $headerTaken = $false; continue }
        if (-not $line.StartsWith('|')) { continue }
        $cells = @($line.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -eq 0) { continue }
        if (@($cells | Where-Object { $_ -notmatch '^[-: ]*$' }).Count -eq 0) { continue }   # 分隔行
        if ($section -eq '总览' -or $section -eq '自身统计') {
            if ($cells[0] -ne '' -and $cells[0] -ne '指标') { $mdNames += $cells[0] }
        } elseif (($section -eq '轮次明细' -or $section -eq '子主题汇总') -and -not $headerTaken) {
            foreach ($c in $cells) { if ($c -ne '') { $mdNames += $c } }   # 只收表头行
            $headerTaken = $true
        }
    }
} else {
    Write-Host ("   未找到统计.md（{0}），跳过对照" -f $mdPath) -ForegroundColor Yellow
}
# 名字的比对形态：原名 / 去掉「组-」前缀 / 去掉（补语）
function Get-NameVariants {
    param([string]$Name)
    $v = @($Name)
    if ($Name -match '^[^-]+-(.+)$') { $v += $Matches[1] }
    $stripped = ($Name -replace '（[^）]*）', '')
    if ($stripped -ne $Name -and $stripped -ne '') { $v += $stripped }
    return @($v | Where-Object { $_ -ne '' })
}
function Test-NameMatched {
    param([string]$Name, [array]$Others)
    foreach ($variant in (Get-NameVariants $Name)) {
        foreach ($o in $Others) {
            if ($variant -like ("*" + $o + "*") -or $o -like ("*" + $variant + "*")) { return $true }
        }
    }
    return $false
}
$schemaNames = @(Get-StatsMetrics -Form 'Storage' | ForEach-Object { $_.Name })
Write-Host ("   统计.md 名字 {0} 个 ／ 定义表指标名 {1} 个" -f $mdNames.Count, $schemaNames.Count)
Write-Host "   —— 统计.md 有、定义表没有的（大多是版式标签，如「总投入（人+AI）」是「轮次总耗时（人+AI）」的另一种写法）："
foreach ($n in $mdNames) {
    if (-not (Test-NameMatched -Name $n -Others $schemaNames)) { Write-Host ("      " + $n) }
}
Write-Host "   —— 定义表有、统计.md 未出现的（可能是没被展示的字段，也可能是命名待对齐）："
foreach ($n in $schemaNames) {
    if (-not (Test-NameMatched -Name $n -Others $mdNames)) { Write-Host ("      " + $n) }
}

if ($skipNotes.Count -gt 0) {
    Write-Host ""
    Write-Host "未校验分组：" -ForegroundColor Yellow
    foreach ($n in $skipNotes) { Write-Host ("   " + $n) -ForegroundColor Yellow }
}

# ---------- 可选：打印完整定义表 ----------
if ($Dump) {
    Write-Host ""
    Write-Host "== 指标定义表 =="
    foreach ($m in (Get-StatsMetrics)) {
        Write-Host ""
        Write-Host ("[{0}] {1}   {2}" -f $m.Form, $m.Key, $m.Name)
        Write-Host ("    含义：{0}" -f $m.Meaning)
        Write-Host ("    口径：{0}" -f $m.Rule)
    }
    Write-Host ""
    Write-Host "== 口径约定（统计.md 尾部「口径说明」段的来源） =="
    foreach ($n in (Get-StatsRuleText -ThresholdMinutes 60 -ComputedAt '<计算时刻>')) { Write-Host ("  " + $n) }
}

Write-Host ""
if ($pass1 -and $pass2) {
    Write-Host "结果：定义表与产物对齐。" -ForegroundColor Green
    exit 0
}
Write-Host "结果：有不对齐项，见上。" -ForegroundColor Red
exit 1
