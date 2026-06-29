<#
.SYNOPSIS
    收集 AI Process 主题的基础信息，为「经验总结」生成 Prompt 数据。

.DESCRIPTION
    只读扫描主题目录，计算文件数、字符数、阶段耗时等指标，
    将结果以 JSON 格式写入指定文件。

.PARAMETER ThemePath
    主题目录的绝对路径。

.PARAMETER OutputFile
    输出 JSON 文件路径。若为空，则自动生成到 {ThemePath}\.aiprocess\_tmp\ 下。
#>

param(
    [Parameter(Mandatory = $true)][string]$ThemePath,
    [Parameter(Mandatory = $false)][string]$OutputFile = ""
)

$ErrorActionPreference = "Stop"

# ============ 配置 ============

$excludedDirs = @('.aiprocess', '.git', '.idea')
$binaryExtensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.ico', '.exe', '.dll', '.zip', '.rar', '.7z', '.pdf', '.docx', '.xlsx', '.pptx', '.mp3', '.mp4', '.avi', '.mkv')

# ============ 工具函数 ============

function Resolve-ThemePath {
    if (-not (Test-Path -Path $ThemePath -PathType Container)) {
        throw "主题目录不存在：$ThemePath"
    }
    return (Resolve-Path -Path $ThemePath).Path
}

function Test-TextFile {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    if ($binaryExtensions -contains $ext) {
        return $false
    }
    try {
        [void][System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        return $true
    }
    catch {
        return $false
    }
}

function Sort-FilesByConvention {
    param([array]$Files)
    $requirementFile = $Files | Where-Object { $_.Name -eq '需求.txt' }
    $implDocFile = $Files | Where-Object { $_.Name -eq '实施文档.md' }
    $vMap = @{}
    $replyMap = @{}
    $otherFiles = @()

    foreach ($file in $Files) {
        $name = $file.Name
        if ($name -eq '需求.txt' -or $name -eq '实施文档.md') {
            continue
        }
        if ($name -match '^v(\d+)\.md$') {
            $vMap[[int]$matches[1]] = $file
        }
        elseif ($name -match '^对v(\d+)的回复\.txt$') {
            $replyMap[[int]$matches[1]] = $file
        }
        else {
            $otherFiles += $file
        }
    }

    $versions = @($vMap.Keys) + @($replyMap.Keys) | Select-Object -Unique | Sort-Object

    $result = @()
    if ($requirementFile) { $result += $requirementFile }
    foreach ($ver in $versions) {
        if ($vMap.ContainsKey($ver)) { $result += $vMap[$ver] }
        if ($replyMap.ContainsKey($ver)) { $result += $replyMap[$ver] }
    }
    if ($implDocFile) { $result += $implDocFile }
    $result += $otherFiles | Sort-Object Name
    return $result
}

function Sort-SubdirsByConvention {
    param([array]$Dirs)
    $stepsDir = $Dirs | Where-Object { $_.Name -eq '实施步骤' }
    $tweakDir = $Dirs | Where-Object { $_.Name -eq '结果微调' }
    $otherDirs = $Dirs | Where-Object { $_.Name -ne '实施步骤' -and $_.Name -ne '结果微调' } | Sort-Object Name

    $result = @()
    if ($stepsDir) { $result += $stepsDir }
    if ($tweakDir) { $result += $tweakDir }
    $result += $otherDirs
    return $result
}

function Get-TreeLines {
    param(
        [string]$Dir,
        [string]$BaseDir,
        [string]$Indent = ""
    )
    $lines = @()
    $items = Get-ChildItem -LiteralPath $Dir -Force
    $dirs = $items | Where-Object { $_.PSIsContainer -and ($excludedDirs -notcontains $_.Name) }
    $files = $items | Where-Object { -not $_.PSIsContainer }

    foreach ($d in (Sort-SubdirsByConvention $dirs)) {
        $lines += "$Indent$($d.Name)/"
        $lines += (Get-TreeLines -Dir $d.FullName -BaseDir $BaseDir -Indent "$Indent  ")
    }
    foreach ($f in (Sort-FilesByConvention $files)) {
        $lines += "$Indent$($f.Name)"
    }
    return $lines
}

function Get-CoreFilesRecursive {
    param(
        [string]$Dir,
        [string]$BaseDir
    )
    $result = @()
    $items = Get-ChildItem -LiteralPath $Dir -Force
    $dirs = $items | Where-Object { $_.PSIsContainer -and ($excludedDirs -notcontains $_.Name) }
    $files = $items | Where-Object { -not $_.PSIsContainer }

    foreach ($f in (Sort-FilesByConvention $files)) {
        $result += $f
    }
    foreach ($d in (Sort-SubdirsByConvention $dirs)) {
        $result += (Get-CoreFilesRecursive -Dir $d.FullName -BaseDir $BaseDir)
    }
    return $result
}

function Format-Duration {
    param([TimeSpan]$Duration)
    $days = [math]::Floor($Duration.TotalDays)
    $hours = $Duration.Hours
    $minutes = $Duration.Minutes
    return "${days}天 ${hours}小时 ${minutes}分钟"
}

function Read-LogEntries {
    param([string]$Dir)
    $logFile = Join-Path (Join-Path $Dir '.aiprocess') 'log.jsonl'
    $entries = @()
    if (Test-Path -Path $logFile) {
        $lines = Get-Content -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            try {
                $obj = $trimmed | ConvertFrom-Json
                $entries += [PSCustomObject]@{
                    time   = $obj.time
                    action = $obj.action
                }
            }
            catch {
                # 忽略解析失败的行
            }
        }
    }
    return $entries
}

function Get-FirstLogTime {
    param([array]$Entries, [string]$Action)
    $match = $Entries | Where-Object { $_.action -eq $Action } | Select-Object -First 1
    if ($match) {
        return [datetime]::ParseExact($match.time, 'yyyy-MM-dd HH:mm:ss', $null)
    }
    return $null
}

function Get-LastLogTimeBefore {
    param([array]$Entries, [string]$Action, [datetime]$Before)
    $matches = $Entries | Where-Object { $_.action -eq $Action -and ([datetime]::ParseExact($_.time, 'yyyy-MM-dd HH:mm:ss', $null) -lt $Before) }
    if ($matches) {
        $latest = $matches | Sort-Object { [datetime]::ParseExact($_.time, 'yyyy-MM-dd HH:mm:ss', $null) } -Descending | Select-Object -First 1
        return [datetime]::ParseExact($latest.time, 'yyyy-MM-dd HH:mm:ss', $null)
    }
    return $null
}

function Get-DiscussionEnd {
    param(
        [string]$Dir,
        [array]$LogEntries,
        [datetime]$FallbackEnd
    )
    $candidates = @()

    $implDoc = Join-Path $Dir '实施文档.md'
    if (Test-Path -Path $implDoc) {
        $candidates += (Get-Item $implDoc).LastWriteTime
    }

    $stepsDir = Join-Path $Dir '实施步骤'
    if (Test-Path -Path $stepsDir -PathType Container) {
        $latest = Get-ChildItem -LiteralPath $stepsDir -Recurse -Force | Where-Object { -not $_.PSIsContainer } | Sort-Object CreationTime -Descending | Select-Object -First 1
        if ($latest) { $candidates += $latest.CreationTime }
    }

    $executeStart = Get-FirstLogTime -Entries $LogEntries -Action '复执行'
    if ($executeStart) { $candidates += $executeStart }

    if ($candidates.Count -gt 0) {
        return ($candidates | Sort-Object -Descending | Select-Object -First 1)
    }
    return $FallbackEnd
}

function Get-ExecuteEnd {
    param(
        [string]$Dir,
        [array]$LogEntries,
        [datetime]$LastModifiedTime
    )
    $boundaryTimes = @()

    $tweakRoot = Join-Path $Dir '结果微调'
    if (Test-Path -Path $tweakRoot -PathType Container) {
        $firstTweakDir = Get-ChildItem -LiteralPath $tweakRoot -Directory -Force | Sort-Object CreationTime | Select-Object -First 1
        if ($firstTweakDir) { $boundaryTimes += $firstTweakDir.CreationTime }
    }

    $stepsDir = Join-Path $Dir '实施步骤'
    if (Test-Path -Path $stepsDir -PathType Container) {
        $subThemes = Get-ChildItem -LiteralPath $stepsDir -Directory -Force | Where-Object {
            (Test-Path (Join-Path $_.FullName '需求.txt')) -or
            (Get-ChildItem -LiteralPath $_.FullName -Filter 'v*.md' -File -Force) -or
            (Test-Path (Join-Path $_.FullName '实施文档.md'))
        } | Sort-Object CreationTime
        if ($subThemes) { $boundaryTimes += $subThemes[0].CreationTime }
    }

    $boundary = $LastModifiedTime
    if ($boundaryTimes.Count -gt 0) {
        $boundary = ($boundaryTimes | Sort-Object | Select-Object -First 1)
    }

    $lastNotify = Get-LastLogTimeBefore -Entries $LogEntries -Action '完成通知' -Before $boundary
    if ($lastNotify) { return $lastNotify }
    return $boundary
}

function Get-TweakTime {
    param(
        [string]$Dir,
        [array]$LogEntries,
        [datetime]$LastModifiedTime
    )
    $tweakRoot = Join-Path $Dir '结果微调'
    if (-not (Test-Path -Path $tweakRoot -PathType Container)) {
        return [TimeSpan]::Zero
    }

    $tweakDirs = Get-ChildItem -LiteralPath $tweakRoot -Directory -Force
    if (-not $tweakDirs) {
        return [TimeSpan]::Zero
    }

    $startCandidates = @($tweakDirs | Select-Object -ExpandProperty CreationTime)

    # 也考虑结果微调目录下最早的操作日志时间
    foreach ($td in $tweakDirs) {
        $subLog = Read-LogEntries -Dir $td.FullName
        if ($subLog) {
            $first = $subLog | Sort-Object time | Select-Object -First 1
            $startCandidates += [datetime]::ParseExact($first.time, 'yyyy-MM-dd HH:mm:ss', $null)
        }
    }

    $start = ($startCandidates | Sort-Object | Select-Object -First 1)

    $endCandidates = @()
    $allTweakFiles = Get-ChildItem -LiteralPath $tweakRoot -Recurse -File -Force
    if ($allTweakFiles) {
        $endCandidates += ($allTweakFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }

    # 根日志中的完成通知如果在结果微调之后，也可能把结束时间推后
    $notifyAfterTweak = $LogEntries | Where-Object {
        $_.action -eq '完成通知' -and
        ([datetime]::ParseExact($_.time, 'yyyy-MM-dd HH:mm:ss', $null) -gt $start)
    } | Sort-Object time -Descending | Select-Object -First 1
    if ($notifyAfterTweak) {
        $endCandidates += [datetime]::ParseExact($notifyAfterTweak.time, 'yyyy-MM-dd HH:mm:ss', $null)
    }

    if ($endCandidates.Count -eq 0) {
        return [TimeSpan]::Zero
    }
    $end = $endCandidates | Sort-Object -Descending | Select-Object -First 1

    $duration = $end - $start
    if ($duration -lt [TimeSpan]::Zero) { $duration = [TimeSpan]::Zero }
    return $duration
}

function Get-ThemeMetrics {
    param([string]$Dir)
    $allFiles = Get-CoreFilesRecursive -Dir $Dir -BaseDir $Dir
    $textFiles = $allFiles | Where-Object { Test-TextFile -Path $_.FullName }

    $fileCount = $allFiles.Count
    $charCount = 0
    foreach ($tf in $textFiles) {
        try {
            $content = [System.IO.File]::ReadAllText($tf.FullName, [System.Text.Encoding]::UTF8)
            $charCount += $content.Length
        }
        catch {
            # 忽略无法读取的文件
        }
    }

    $lastModifiedFileObj = $allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $lastModifiedFile = if ($lastModifiedFileObj) { $lastModifiedFileObj.FullName.Substring($Dir.Length + 1) } else { '' }
    $lastModifiedTime = if ($lastModifiedFileObj) { $lastModifiedFileObj.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    $lastModifiedDateTime = if ($lastModifiedFileObj) { $lastModifiedFileObj.LastWriteTime } else { [datetime]::MinValue }

    $requirementFile = Join-Path $Dir '需求.txt'
    $startCandidates = @()
    if (Test-Path $requirementFile) {
        $startCandidates += (Get-Item $requirementFile).CreationTime
    }
    if ($allFiles) {
        $startCandidates += ($allFiles | Sort-Object CreationTime | Select-Object -First 1).CreationTime
    }

    $logEntries = Read-LogEntries -Dir $Dir
    if ($logEntries) {
        $firstLog = $logEntries | Sort-Object time | Select-Object -First 1
        $startCandidates += [datetime]::ParseExact($firstLog.time, 'yyyy-MM-dd HH:mm:ss', $null)
    }

    $startTime = if ($startCandidates.Count -gt 0) { $startCandidates | Sort-Object | Select-Object -First 1 } else { [datetime]::MinValue }

    $totalTime = $lastModifiedDateTime - $startTime
    if ($totalTime -lt [TimeSpan]::Zero) { $totalTime = [TimeSpan]::Zero }

    $discussionEnd = Get-DiscussionEnd -Dir $Dir -LogEntries $logEntries -FallbackEnd $lastModifiedDateTime
    $discussionTime = $discussionEnd - $startTime
    if ($discussionTime -lt [TimeSpan]::Zero) { $discussionTime = [TimeSpan]::Zero }

    $executeStart = Get-FirstLogTime -Entries $logEntries -Action '复执行'
    if (-not $executeStart) {
        $executeStart = $discussionEnd
    }
    $executeEnd = Get-ExecuteEnd -Dir $Dir -LogEntries $logEntries -LastModifiedTime $lastModifiedDateTime
    if ($executeEnd -lt $executeStart) { $executeEnd = $executeStart }
    $executeTime = $executeEnd - $executeStart
    if ($executeTime -lt [TimeSpan]::Zero) { $executeTime = [TimeSpan]::Zero }

    $tweakTime = Get-TweakTime -Dir $Dir -LogEntries $logEntries -LastModifiedTime $lastModifiedDateTime

    # 独立子主题
    $subThemesList = @()
    $stepsDir = Join-Path $Dir '实施步骤'
    if (Test-Path $stepsDir -PathType Container) {
        $subThemeDirs = Get-ChildItem -LiteralPath $stepsDir -Directory -Force | Where-Object {
            (Test-Path (Join-Path $_.FullName '需求.txt')) -or
            (Get-ChildItem -LiteralPath $_.FullName -Filter 'v*.md' -File -Force) -or
            (Test-Path (Join-Path $_.FullName '实施文档.md'))
        }
        foreach ($std in $subThemeDirs) {
            $subMetrics = Get-ThemeMetrics -Dir $std.FullName
            $subThemesList += [PSCustomObject]@{
                path           = $std.FullName.Substring($Dir.Length + 1)
                totalTime      = Format-Duration -Duration $subMetrics.totalTime
                discussionTime = Format-Duration -Duration $subMetrics.discussionTime
                executeTime    = Format-Duration -Duration $subMetrics.executeTime
                tweakTime      = Format-Duration -Duration $subMetrics.tweakTime
            }
        }
    }

    $treeLines = Get-TreeLines -Dir $Dir -BaseDir $Dir
    $coreFilePaths = $allFiles | ForEach-Object { $_.FullName.Substring($Dir.Length + 1) }

    return [PSCustomObject]@{
        themePath        = $Dir
        themeName        = (Split-Path -Leaf $Dir)
        fileCount        = $fileCount
        charCount        = $charCount
        lastModifiedFile = $lastModifiedFile
        lastModifiedTime = $lastModifiedTime
        totalTime        = Format-Duration -Duration $totalTime
        discussionTime   = Format-Duration -Duration $discussionTime
        executeTime      = Format-Duration -Duration $executeTime
        tweakTime        = Format-Duration -Duration $tweakTime
        fileTree         = ($treeLines -join "`n")
        coreFiles        = ($coreFilePaths -join "`n")
        logEntries       = ($logEntries | ConvertTo-Json -Compress)
        subThemes        = $subThemesList
    }
}

# ============ 主流程 ============

$themePath = Resolve-ThemePath
$metrics = Get-ThemeMetrics -Dir $themePath

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $tmpDir = Join-Path (Join-Path $themePath '.aiprocess') '_tmp'
    if (-not (Test-Path $tmpDir)) {
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $OutputFile = Join-Path $tmpDir "summary_data_$timestamp.json"
}

$outputDir = Split-Path -Parent $OutputFile
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$json = $metrics | ConvertTo-Json -Depth 5 -Compress
[System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.Encoding]::UTF8)

Write-Output $OutputFile
