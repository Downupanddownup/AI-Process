<#
.SYNOPSIS
    主题父子聚合原语：子主题发现 / 子的发布数据读取 / 汇总合并。

.DESCRIPTION
    供 ComputeThemeStats.ps1 使用的纯工具模块（不依赖任何业务模块）：
      - 递归模型：父.aggregate = 父自身基础数据 + Σ 直接子.aggregate（孙已含在子内，父不穿透）；
      - 子主题识别：每支下探到第一个含 .aiprocess 的目录为止（结果微调等容器目录无 .aiprocess，自然被下探）；
      - 缺数据规则：子的 stats.json 不存在或无 aggregate 字段 → 返回 $null，由调用方跳过
        （子的下次轮次会级联触发父重算自动补齐；不做任何老格式合成/迁移）。
#>

# ---------- 子主题发现：递归下探，每支遇到第一个含 .aiprocess 的目录即收录并停止下探 ----------
function Get-ChildThemes {
    param([Parameter(Mandatory = $true)][string]$Dir)
    $result = @()
    foreach ($sub in (Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction SilentlyContinue)) {
        if ($sub.Attributes -band [System.IO.FileAttributes]::Hidden) { continue }
        if (Test-Path -LiteralPath (Join-Path $sub.FullName '.aiprocess')) {
            $result += $sub.FullName
            continue
        }
        $result += @(Get-ChildThemes -Dir $sub.FullName)
    }
    return $result
}

# ---------- 子的发布数据：读 stats.json 取 aggregate；未就绪返回 $null ----------
function Get-ChildAggregate {
    param([Parameter(Mandatory = $true)][string]$ChildPath)
    $statsFile = Join-Path (Join-Path $ChildPath '.aiprocess') 'stats.json'
    if (-not (Test-Path -LiteralPath $statsFile)) { return $null }
    try {
        $data = [System.IO.File]::ReadAllText($statsFile) | ConvertFrom-Json
    } catch {
        return $null
    }
    if ($null -eq $data.aggregate) { return $null }
    return [PSCustomObject]@{
        aggregate  = $data.aggregate
        computedAt = $data.computedAt
    }
}

# ---------- 汇总合并：纯函数。求和类相加；createdAt 取最早、lastActiveAt 取最晚 ----------
function Merge-Aggregate {
    param(
        [Parameter(Mandatory = $true)]$Self,
        [array]$ChildAggs = @()
    )
    $sumFields = @(
        'humanSec', 'aiSec', 'roundTotalSec', 'gapTotalSec',
        'files', 'humanFiles', 'aiFiles', 'humanChars', 'aiChars',
        'discussion', 'execute', 'unknown', 'handoffCount'
    )
    $merged = [ordered]@{}
    foreach ($f in $sumFields) {
        $v = [int64]0
        if ($null -ne $Self.$f) { $v += [int64]$Self.$f }
        foreach ($c in $ChildAggs) {
            if ($null -ne $c -and $null -ne $c.$f) { $v += [int64]$c.$f }
        }
        $merged[$f] = $v
    }
    $createdList = @(); $lastList = @()
    foreach ($a in (@($Self) + $ChildAggs)) {
        if ($null -ne $a) {
            if (-not [string]::IsNullOrWhiteSpace($a.createdAt)) { $createdList += [string]$a.createdAt }
            if (-not [string]::IsNullOrWhiteSpace($a.lastActiveAt)) { $lastList += [string]$a.lastActiveAt }
        }
    }
    # 时间字符串为 yyyy-MM-dd HH:mm:ss，字典序即时间序
    $merged['createdAt'] = if ($createdList.Count -gt 0) { @($createdList | Sort-Object)[0] } else { $null }
    $merged['lastActiveAt'] = if ($lastList.Count -gt 0) { @($lastList | Sort-Object)[-1] } else { $null }
    return [PSCustomObject]$merged
}

Export-ModuleMember -Function Get-ChildThemes, Get-ChildAggregate, Merge-Aggregate
