<#
.SYNOPSIS
    生成产物验证工具：同一批输入、跑两遍、比对产物差异（快照 / 对照）。

.DESCRIPTION
    用途：改了某个"生成脚本"之后，证明它对同一批输入产出的结果没变（或变了哪些行）。
    做法：把输入复制到临时工作区 → 在副本上跑生成脚本 → 收集产物 → 归一化后与快照逐文件比对。
    改前先存快照，改完再对照；两次之间只差你改的那部分，所以差异就指向改动。

    四条铁律（本工具自动保证）：
      1. 一律在副本上跑——生成脚本多数原地写产物，直接在真实目录跑会覆盖真数据；
      2. 一律子进程调用——生成脚本里常有 exit，进程内调用会把本工具一起退掉；
      3. 产物先归一化再比——时间戳、绝对路径这类每次都变的内容不参与比对；
      4. 输入指纹入清单——对照时若发现输入本身变了会明确警告（差异不一定来自脚本）。

.PARAMETER Case
    预设：Stats（统计：ComputeThemeStats → stats.json / 统计.md）
          Tag  （打标：SetMarkdownTimeTag → 轮次 md 的 front matter）

.PARAMETER Script
    要验证的生成脚本路径。给了就覆盖预设。

.PARAMETER Inputs
    输入目录（主题目录）列表。给了就覆盖预设语料，且跳过代表集挑选。

.PARAMETER Artifacts
    要收集比对的产物（相对输入目录的路径，支持通配）。覆盖预设。

.PARAMETER Normalize
    额外归一化规则，形如 '正则=替换'，可重复；在预设规则之后应用。

.PARAMETER Snapshot
    存快照，参数为标签（如 before）。

.PARAMETER Compare
    与指定标签的快照对照（须先前用同一标签存过）。

.PARAMETER Full
    语料用全量（默认只跑代表集：覆盖"重建轮 / 质检轮 / 执行轮 / 老日志缺 agent"各一支 + 最近的几个）。

.PARAMETER SnapshotRoot
    快照根目录。默认 %TEMP%\AIProcess-VerifyOutput——不进版本库、不污染工作区。

.EXAMPLE
    # 1) 改动前存基线
    .\Verify-Output.ps1 -Case Stats -Snapshot before

.EXAMPLE
    # 2) 改完脚本后对照：无差异会明确打印；有差异列出变动行并以退出码 1 结束
    .\Verify-Output.ps1 -Case Stats -Compare before

.EXAMPLE
    # 3) 全量语料 + 打标
    .\Verify-Output.ps1 -Case Tag -Full -Snapshot tag1

.EXAMPLE
    # 4) 指定多个输入。注意：从 shell（bash/cmd）调用时要用 -Command + @(...)，
    #    否则 "a,b" 会被当成一个路径
    powershell -Command "& '.\test\Verify-Output.ps1' -Case Stats -Inputs @('D:\p\a\01','D:\p\b\01') -Snapshot x"
#>
param(
    [ValidateSet('Stats', 'Tag')]
    [string]$Case = 'Stats',
    [string]$Script = "",
    [string[]]$Inputs = @(),
    [string[]]$Artifacts = @(),
    [string[]]$Normalize = @(),
    [string]$Snapshot = "",
    [string]$Compare = "",
    [switch]$Full,
    [string]$SnapshotRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot          # test\ 的上一级 = 仓库根
$appRoot = Join-Path $repoRoot "app"
if ($SnapshotRoot -eq "") { $SnapshotRoot = Join-Path $env:TEMP "AIProcess-VerifyOutput" }

# ---------- 预设 ----------
$presets = @{
    Stats = @{
        Script    = (Join-Path $appRoot "powershell\summary\ComputeThemeStats.ps1")
        Artifacts = @(".aiprocess\stats.json", ".aiprocess\统计.md")
        Clean     = $true    # 产物是"新生成"的：先删掉副本里的旧产物，避免旧文件被误当成本次产出
        Normalize = @(
            '"computedAt":"[^"]*"="computedAt":"<T>"',     # 计算时刻：每次都变
            '(?m)^- 计算时间：.*$=""'                       # 统计.md 的"计算时间"整行
        )
    }
    Tag   = @{
        Script    = (Join-Path $appRoot "powershell\markdown\SetMarkdownTimeTag.ps1")
        Artifacts = @("v*.md", "实施文档.md", "已实施.md")
        Clean     = $false   # 产物是"原地改写"的（md 既是输入也是产物）：删了就没得打标，且它们的改前内容已入输入指纹
        Normalize = @(
            # 打标时长依赖"打标时刻"（进行中的那轮会取当前时间），不是名字收编能影响的东西
            # → 时长的值抹掉，只留键与其它字段（round-type / ai-agent 照验）
            '(?m)^(gap|human|ai|total):\s*"[^"]*"=$1: "<T>"'
        )
    }
}
$cfg = $presets[$Case]
if ($Script -ne "") { $cfg.Script = $Script }
if ($Artifacts.Count -gt 0) { $cfg.Artifacts = $Artifacts }
$rules = @($cfg.Normalize) + @($Normalize)
$genScript = $cfg.Script
if (-not (Test-Path -LiteralPath $genScript)) { Write-Host "生成脚本不存在：$genScript" -ForegroundColor Red; exit 2 }

$roundMdPattern = '^v\d+\.md$|^实施文档\.md$|^已实施\.md$'

function Get-FileHashText([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return "" }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

# 输入的唯一键：叶子名 + 源路径短哈希（语料里同名目录很多，如 31 个 "01"）
function Get-InputKey([string]$src) {
    $leaf = Split-Path -Leaf $src
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hex = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($src.ToLower())))).Replace("-", "").Substring(0, 8)
    return ($leaf + "__" + $hex)
}

function Get-RoundMdFiles([string]$dir) {
    return @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $roundMdPattern })
}

# ---------- 语料：候选主题目录（含 .aiprocess 的目录） ----------
function Get-ThemeCandidates {
    $found = Get-ChildItem -LiteralPath $repoRoot -Recurse -Directory -Filter ".aiprocess" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\' }
    return @($found | ForEach-Object { $_.Parent } | Where-Object { $_ -and (Test-Path -LiteralPath $_.FullName) })
}

# ---------- 代表集：先按分支特征各挑一支，再用最近修改的补足 ----------
function Get-RepresentativeThemes([int]$limit = 8) {
    $picked = New-Object System.Collections.ArrayList
    $why = @{}
    $bucket = @{}
    $all = New-Object System.Collections.ArrayList
    foreach ($t in (Get-ThemeCandidates)) {
        $log = Join-Path $t.FullName ".aiprocess\log.jsonl"
        if (-not (Test-Path -LiteralPath $log)) { continue }
        [void]$all.Add($t.FullName)
        $text = Get-Content -LiteralPath $log -Raw -Encoding UTF8
        if ($text -match '"action":"复关系"') { if (-not $bucket.ContainsKey("重建轮")) { $bucket["重建轮"] = $t.FullName } }
        if ($text -match '"action":"质检码"') { if (-not $bucket.ContainsKey("质检轮")) { $bucket["质检轮"] = $t.FullName } }
        if ($text -match '"action":"复执行"') { if (-not $bucket.ContainsKey("执行轮")) { $bucket["执行轮"] = $t.FullName } }
        if (($text -match '"action":"') -and ($text -notmatch '"agent"')) { if (-not $bucket.ContainsKey("老日志缺agent")) { $bucket["老日志缺agent"] = $t.FullName } }
    }
    foreach ($feature in $bucket.Keys) {
        $p = $bucket[$feature]
        if (-not ($picked -contains $p)) { [void]$picked.Add($p); $why[$p] = $feature }
    }
    $recent = $all | Sort-Object { (Get-Item -LiteralPath $_).LastWriteTime } -Descending
    foreach ($p in $recent) {
        if ($picked.Count -ge $limit) { break }
        if (-not ($picked -contains $p)) { [void]$picked.Add($p); $why[$p] = "补最近" }
    }
    return @{ Paths = @($picked); Why = $why }
}

# ---------- 归一化：先按规则替换，再把"本次工作区路径"抹成占位符 ----------
function Get-NormalizedText([string]$path, [string]$workDir) {
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach ($r in $rules) {
        $i = $r.IndexOf("=")
        if ($i -le 0) { continue }
        $text = [regex]::Replace($text, $r.Substring(0, $i), $r.Substring($i + 1))
    }
    if ($workDir -ne "") {
        # 用字面量替换（不走正则），两种形态都要抹：普通路径、以及 JSON 里转义过的路径（\\）
        $escaped = $workDir.Replace('\', '\\')
        $text = $text.Replace($escaped, "<WORK>")
        $text = $text.Replace($workDir, "<WORK>")
    }
    return $text
}

# ---------- 调用生成脚本（一律子进程） ----------
function Invoke-Generator([string]$inputPath) {
    if ($Case -eq 'Stats') {
        $out = @(& powershell -ExecutionPolicy Bypass -File $genScript -ThemePath $inputPath 2>&1)
        if ($LASTEXITCODE -ne 0) { $script:genFail++ }
        return $out
    }
    $out = @()
    foreach ($md in (Get-RoundMdFiles $inputPath)) {
        $out += & powershell -ExecutionPolicy Bypass -File $genScript -FilePath $md.FullName -WindowId $script:windowId 2>&1
        if ($LASTEXITCODE -ne 0) { $script:genFail++ }
    }
    return $out
}

# ---------- 跑一遍，把归一化后的产物收进目标目录 ----------
function Invoke-Run([string]$destRoot, [string]$tag) {
    $work = Join-Path $SnapshotRoot (".work-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $manifestInputs = New-Object System.Collections.ArrayList
    $artifactCount = 0
    $started = Get-Date
    $scriptHashAtStart = Get-FileHashText $genScript   # 快照期间若生成脚本被改，快照就不可信

    try {
        foreach ($src in $script:corpus) {
            $name = Split-Path -Leaf $src
            $key = Get-InputKey $src        # 唯一键：同名目录（如一堆 01）不能共用副本/快照目录
            $copy = Join-Path $work $key
            Copy-Item -LiteralPath $src -Destination $copy -Recurse -Force

        # 输入指纹：生成脚本真正读的文件 —— Stats 要连"子主题的日志"一起算，
        # 因为父主题的统计含子主题聚合：子主题日志一涨，父主题产物就变（不是回归，是漂移）
        $readFiles = @{}
        if ($Case -eq 'Stats') {
            foreach ($lg in @(Get-ChildItem -LiteralPath $copy -Recurse -File -Filter "log.jsonl" -ErrorAction SilentlyContinue |
                    Where-Object { $_.DirectoryName -like '*\.aiprocess' })) {
                $relLog = $lg.FullName.Substring($copy.Length).TrimStart("\")
                $readFiles[$relLog] = Get-FileHashText $lg.FullName
            }
        }
        else { foreach ($md in (Get-RoundMdFiles $copy)) { $readFiles[$md.Name] = Get-FileHashText $md.FullName } }
            [void]$manifestInputs.Add(@{ key = $key; name = $name; source = $src; readFiles = $readFiles })

            # 新生成类产物：先删掉副本里的旧产物，这样"有产物"= "本次生成的"（Tag 是原地改写，不删）
            if ($cfg.Clean) {
                foreach ($pattern in $cfg.Artifacts) {
                    foreach ($old in @(Get-Item -Path (Join-Path $copy $pattern) -ErrorAction SilentlyContinue)) {
                        if (-not $old.PSIsContainer) { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue }
                    }
                }
            }

            $genOut = Invoke-Generator -inputPath $copy
            if ($genOut.Count -gt 0) { $script:genOutput += ("[" + $name + "] " + ($genOut -join " / ")) }
            foreach ($pattern in $cfg.Artifacts) {
                $target = Join-Path $copy $pattern
                $matched = @(Get-Item -Path $target -ErrorAction SilentlyContinue)
                foreach ($f in $matched) {
                    if ($f.PSIsContainer) { continue }
                    $rel = $f.FullName.Substring($copy.Length).TrimStart("\")
                    $dest = Join-Path (Join-Path $destRoot $key) $rel
                    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
                    [System.IO.File]::WriteAllText($dest, (Get-NormalizedText $f.FullName $work), (New-Object System.Text.UTF8Encoding($false)))
                    $artifactCount++
                }
            }
        }

        $manifest = @{
            tag        = $tag
            case       = $Case
            script     = $genScript
            scriptHash = (Get-FileHashText $genScript)
            scriptStable = ($scriptHashAtStart -eq (Get-FileHashText $genScript))
            fingerprint  = $(if ($Case -eq 'Stats') { 'nested-logs' } else { 'round-md' })   # 指纹口径；与快照不一致就不能比
            full       = [bool]$Full
            inputs     = $manifestInputs
            artifacts  = $artifactCount
            at         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        [System.IO.File]::WriteAllText((Join-Path $destRoot "manifest.json"), ($manifest | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    }
    finally {
        # 工作副本用完即删（含中途出错的情况）：不留垃圾
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return @{ Inputs = $manifestInputs.Count; Artifacts = $artifactCount; Seconds = [int]((Get-Date) - $started).TotalSeconds }
}

# ---------- 启动检查 ----------
if (($Snapshot -eq "") -and ($Compare -eq "")) {
    Write-Host "请指定 -Snapshot <标签> 或 -Compare <标签>（-? 看说明）。" -ForegroundColor Yellow
    exit 2
}

$script:windowId = "3"
if ($Case -eq 'Tag') {
    Import-Module (Join-Path $appRoot "powershell\config\AppSettings.psm1") -ErrorAction SilentlyContinue
    $found = ""
    foreach ($id in @("1", "2", "3")) {
        try { if (Get-WindowAgentName -WindowId $id) { $found = $id; break } } catch { }
    }
    if ($found -eq "") {
        Write-Host "三个窗口的 AgentName 都为空——打标会被跳过，Tag 预设无意义。先在面板给某个窗口绑定 Agent。" -ForegroundColor Yellow
        exit 2
    }
    $script:windowId = $found
    Write-Host ("Tag 用 WindowId={0}（该窗口 AgentName 非空）" -f $found)
}

# ---------- 语料 ----------
if ($Inputs.Count -gt 0) {
    $script:corpus = $Inputs
}
elseif ($Full) {
    $script:corpus = @(Get-ThemeCandidates | ForEach-Object { $_.FullName })
}
else {
    $rep = Get-RepresentativeThemes
    $script:corpus = $rep.Paths
    Write-Host ("代表集（{0} 个）：" -f $rep.Paths.Count)
    foreach ($p in $rep.Paths) { Write-Host ("  - " + (Split-Path -Leaf $p) + "  [" + $rep.Why[$p] + "]") }
}
# 排除"正在被写"的活动主题：它们自己的日志在验证期间还在增长，输入天然漂移
try {
    Import-Module (Join-Path $appRoot "powershell\config\AppSettings.psm1") -ErrorAction SilentlyContinue
    $activeSet = @{}
    foreach ($id in @("1", "2", "3")) {
        try { $d = Get-WindowCurrentDir -WindowId $id; if ($d) { $activeSet[$d.TrimEnd('\')] = $true } } catch { }
    }
    if ($activeSet.Count -gt 0) {
        # 活动主题的**祖先**也要排除：父主题的统计包含子主题聚合，子主题在长，父主题产物就会变
        foreach ($k in @($activeSet.Keys)) {
            $p = $k
            while ($p -and ($p.Length -gt $repoRoot.Length)) {
                $p = Split-Path -Parent $p
                if ($p -and ($p.Length -ge $repoRoot.Length)) { $activeSet[$p.TrimEnd('\')] = $true }
            }
        }
        $before = @($script:corpus).Count
        $removed = @($script:corpus | Where-Object { $activeSet.ContainsKey($_.TrimEnd('\')) })
        $script:corpus = @($script:corpus | Where-Object { -not $activeSet.ContainsKey($_.TrimEnd('\')) })
        if ($removed.Count -gt 0) {
            Write-Host ("已排除活动主题（含其祖先）{0} 个——它们的日志正在被写、输入会漂移：" -f $removed.Count) -ForegroundColor Yellow
            foreach ($r in $removed) { Write-Host ("  - " + $r) }
        }
    }
}
catch { }

if ($script:corpus.Count -eq 0) { Write-Host "语料为空，没什么可验证的。" -ForegroundColor Yellow; exit 2 }

$script:genOutput = @()
$script:genFail = 0

# ---------- 存快照 ----------
if ($Snapshot -ne "") {
    $dest = Join-Path $SnapshotRoot $Snapshot
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $stat = Invoke-Run -destRoot $dest -tag $Snapshot
    Write-Host ""
    Write-Host ("快照已存：{0}" -f $dest) -ForegroundColor Green
    Write-Host ("输入 {0} 个 / 产物 {1} 个 / 耗时 {2} 秒" -f $stat.Inputs, $stat.Artifacts, $stat.Seconds)
    $m = Get-Content -LiteralPath (Join-Path $dest "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $m.scriptStable) {
        Write-Host "警告：生成脚本在本次快照期间被改过——这份快照不可信，请重做" -ForegroundColor Red
    }
    if ($script:genFail -gt 0) {
        Write-Host ("注意：生成脚本有 {0} 次非零退出（产物可能因此缺失）" -f $script:genFail) -ForegroundColor Yellow
        foreach ($g in ($script:genOutput | Select-Object -First 3)) { Write-Host ("  " + $g) }
    }
    exit 0
}

# ---------- 对照 ----------
$base = Join-Path $SnapshotRoot $Compare
if (-not (Test-Path -LiteralPath $base)) { Write-Host ("找不到快照：{0}" -f $base) -ForegroundColor Red; exit 2 }

$cmpDir = Join-Path $SnapshotRoot (".cmp-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $cmpDir -Force | Out-Null
$stat = Invoke-Run -destRoot $cmpDir -tag $Compare

$baseManifest = Get-Content -LiteralPath (Join-Path $base "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$curManifest = Get-Content -LiteralPath (Join-Path $cmpDir "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$changedInputs = @()
$fpNow = $(if ($Case -eq 'Stats') { 'nested-logs' } else { 'round-md' })
if ($baseManifest.fingerprint -ne $fpNow) {
    Write-Host ("快照的指纹口径（{0}）与本次（{1}）不同——旧版工具存的快照不可比，请重存快照。" -f $baseManifest.fingerprint, $fpNow) -ForegroundColor Red
    exit 2
}
foreach ($cur in $curManifest.inputs) {
    $old = @($baseManifest.inputs | Where-Object { $_.key -eq $cur.key })[0]
    if ($null -eq $old) { $changedInputs += ($cur.name + "（快照里没有）"); continue }
    foreach ($k in $cur.readFiles.PSObject.Properties.Name) {
        if ($old.readFiles.$k -ne $cur.readFiles.$k) { $changedInputs += ($cur.name + " / " + $k) }
    }
}

Write-Host ""
Write-Host ("对照快照：{0}（存于 {1}）" -f $Compare, $baseManifest.at)
Write-Host ("本次：输入 {0} 个 / 产物 {1} 个 / 耗时 {2} 秒" -f $stat.Inputs, $stat.Artifacts, $stat.Seconds)
if ($script:genFail -gt 0) {
    Write-Host ("注意：生成脚本有 {0} 次非零退出（产物可能因此缺失）" -f $script:genFail) -ForegroundColor Yellow
    foreach ($g in ($script:genOutput | Select-Object -First 3)) { Write-Host ("  " + $g) }
}
if ($baseManifest.scriptHash -ne (Get-FileHashText $genScript)) {
    Write-Host ("生成脚本：有变化（{0}）——正是要验的场景" -f (Split-Path -Leaf $genScript)) -ForegroundColor Yellow
}
else {
    Write-Host ("生成脚本：与快照时一致（{0}）——对照仍应无差异" -f (Split-Path -Leaf $genScript)) -ForegroundColor Yellow
}
if ($changedInputs.Count -gt 0) {
    Write-Host ("警告：输入本身有变化（{0} 处）→ 差异不一定来自脚本：" -f $changedInputs.Count) -ForegroundColor Yellow
    foreach ($c in $changedInputs) { Write-Host ("  - " + $c) }
}

# ---------- 逐文件比对 ----------
$diffs = @()
foreach ($oldFile in @(Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object { $_.Name -ne "manifest.json" })) {
    $rel = $oldFile.FullName.Substring($base.Length).TrimStart("\")
    $newFile = Join-Path $cmpDir $rel
    if (-not (Test-Path -LiteralPath $newFile)) { $diffs += @{ rel = $rel; kind = "缺失（本次没产出）"; lines = @() }; continue }
    $d = Compare-Object -ReferenceObject (Get-Content -LiteralPath $oldFile.FullName -Encoding UTF8) -DifferenceObject (Get-Content -LiteralPath $newFile -Encoding UTF8)
    if ($d) { $diffs += @{ rel = $rel; kind = "内容不同"; lines = $d } }
}
foreach ($newFile in @(Get-ChildItem -LiteralPath $cmpDir -Recurse -File | Where-Object { $_.Name -ne "manifest.json" })) {
    $rel = $newFile.FullName.Substring($cmpDir.Length).TrimStart("\")
    if (-not (Test-Path -LiteralPath (Join-Path $base $rel))) { $diffs += @{ rel = $rel; kind = "新增（快照里没有）"; lines = @() } }
}

Write-Host ""
if ($diffs.Count -eq 0) {
    Write-Host ("无差异：{0} 个产物与快照逐行一致。" -f $stat.Artifacts) -ForegroundColor Green
    Remove-Item -LiteralPath $cmpDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
Write-Host ("有差异：{0} 个产物" -f $diffs.Count) -ForegroundColor Red
foreach ($d in $diffs) {
    Write-Host ("  [变动] {0}  —— {1}" -f $d.rel, $d.kind) -ForegroundColor Red
    $i = 0
    foreach ($line in $d.lines) {
        if ($i -ge 6) { Write-Host "         …（其余略）" ; break }
        $shown = [string]$line.InputObject
        if ($shown.Length -gt 160) { $shown = $shown.Substring(0, 160) + "…（本行过长，已截断）" }
        Write-Host ("         {0} {1}" -f $line.SideIndicator, $shown)
        $i++
    }
}
Write-Host ""
Write-Host ("本次结果留在：{0}（供你细看）" -f $cmpDir) -ForegroundColor Yellow
exit 1
