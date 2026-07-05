<#
.SYNOPSIS
    Collect round-based information for AI Process theme summary.

.DESCRIPTION
    Scan theme directory, extract rounds (human .txt -> AI .md),
    calculate time, char count and content preview, output summary_input.json.

.PARAMETER ThemePath
    Absolute path of theme directory.

.PARAMETER OutputFile
    Output JSON file path. If empty, auto-generate to {ThemePath}\.aiprocess\_tmp\.
#>

param(
    [Parameter(Mandatory = $true)][string]$ThemePath,
    [Parameter(Mandatory = $false)][string]$OutputFile = "",
    [Parameter(Mandatory = $false)][string]$ErrorFile = ""
)

$ErrorActionPreference = "Stop"

# Load active duration calculator
. "$PSScriptRoot\ActiveDurationCalculator.ps1"

$excludedDirs = @('.aiprocess', '.git', '.idea')

function Resolve-ThemePath {
    if (-not (Test-Path -Path $ThemePath -PathType Container)) {
        throw "Theme directory not found: $ThemePath"
    }
    return (Resolve-Path -Path $ThemePath).Path
}

function Get-IdleThresholdMinutes {
    $settingsFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config\settings.ini'
    $defaultValue = 60
    if (-not (Test-Path -Path $settingsFile)) {
        return $defaultValue
    }
    try {
        $lines = [System.IO.File]::ReadAllLines($settingsFile, [System.Text.Encoding]::Unicode)
        $inReportSection = $false
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed -eq '[Report]') {
                $inReportSection = $true
                continue
            }
            if ($trimmed -match '^\[.*\]$') {
                $inReportSection = $false
                continue
            }
            if ($inReportSection -and $trimmed -match '^IdleThresholdMinutes\s*=\s*(\d+)') {
                $value = [int]$matches[1]
                if ($value -gt 0) {
                    return $value
                }
            }
        }
    }
    catch {
        # use default
    }
    return $defaultValue
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
                # ignore invalid lines
            }
        }
    }
    return $entries
}

function Get-LogTimeForFile {
    param(
        [array]$LogEntries,
        [string]$FileName,
        [datetime]$FallbackTime
    )
    $targetAction = $null
    if ($FileName -eq '需求.txt') {
        $targetAction = '建需求'
    }
    elseif ($FileName -match '^对v(\d+)的回复\.txt$') {
        $targetAction = '建回复'
    }
    elseif ($FileName -match '^v(\d+)\.md$' -or $FileName -eq '实施文档.md') {
        $targetAction = '完成通知'
    }

    if ($targetAction) {
        $best = $null
        $bestDiff = [double]::MaxValue
        foreach ($entry in $LogEntries) {
            if ($entry.action -ne $targetAction) { continue }
            try {
                $t = [datetime]::ParseExact($entry.time, 'yyyy-MM-dd HH:mm:ss', $null)
                $diff = [math]::Abs(($t - $FallbackTime).TotalSeconds)
                if ($diff -lt $bestDiff -and $diff -le 300) {
                    $best = $t
                    $bestDiff = $diff
                }
            }
            catch {
                # ignore invalid time
            }
        }
        if ($best) {
            return $best
        }
    }
    return $FallbackTime
}

function Get-TextPreview {
    param(
        [string]$Path,
        [int]$MaxChars = 200
    )
    try {
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $content = $content -replace '\r\n', ' ' -replace '\n', ' ' -replace '\s+', ' '
        $content = $content.Trim()
        if ($content.Length -gt $MaxChars) {
            return $content.Substring(0, $MaxChars) + "..."
        }
        return $content
    }
    catch {
        return ""
    }
}

function Get-CharCount {
    param([string]$Path)
    try {
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        return $content.Length
    }
    catch {
        return 0
    }
}

function Get-AllFilesRecursive {
    param([string]$Dir)
    $result = @()
    $items = Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue
    if (-not $items) { return $result }
    $dirs = $items | Where-Object { $_.PSIsContainer -and ($excludedDirs -notcontains $_.Name) }
    $files = $items | Where-Object { -not $_.PSIsContainer }
    $result += $files
    foreach ($d in $dirs) {
        $result += (Get-AllFilesRecursive -Dir $d.FullName)
    }
    return $result
}

function Get-ThemeRounds {
    param(
        [string]$Dir,
        [array]$LogEntries
    )
    $files = Get-ChildItem -LiteralPath $Dir -File -Force | Where-Object {
        $_.Name -eq '需求.txt' -or
        $_.Name -match '^v\d+\.md$' -or
        $_.Name -match '^对v\d+的回复\.txt$'
    }

    $requirementFile = $files | Where-Object { $_.Name -eq '需求.txt' } | Select-Object -First 1
    $vMap = @{}
    $replyMap = @{}

    foreach ($file in $files) {
        if ($file.Name -match '^v(\d+)\.md$') {
            $vMap[[int]$matches[1]] = $file
        }
        elseif ($file.Name -match '^对v(\d+)的回复\.txt$') {
            $replyMap[[int]$matches[1]] = $file
        }
    }

    $rounds = @()
    $versionNumbers = @($vMap.Keys) | Sort-Object

    foreach ($ver in $versionNumbers) {
        $aiFile = $vMap[$ver]
        $humanTime = $null
        [string]$humanFileName = ""

        if ($ver -eq 1 -and $requirementFile) {
            $humanFileName = $requirementFile.Name
            $humanTime = Get-LogTimeForFile -LogEntries $LogEntries -FileName $humanFileName -FallbackTime $requirementFile.CreationTime
        }
        elseif ($replyMap.ContainsKey($ver - 1)) {
            $humanFile = $replyMap[$ver - 1]
            $humanFileName = $humanFile.Name
            $humanTime = Get-LogTimeForFile -LogEntries $LogEntries -FileName $humanFileName -FallbackTime $humanFile.CreationTime
        }
        else {
            continue
        }

        $aiTime = Get-LogTimeForFile -LogEntries $LogEntries -FileName $aiFile.Name -FallbackTime $aiFile.CreationTime

        if ($humanTime -gt $aiTime) {
            $humanTime = $aiTime.AddSeconds(-1)
        }

        $duration = [math]::Ceiling(($aiTime - $humanTime).TotalMinutes)
        if ($duration -lt 1) { $duration = 1 }


        $rounds += [PSCustomObject]@{
            roundIndex      = $ver - 1
            stage           = '讨论'
            humanFile       = $humanFileName
            aiFile          = $aiFile.Name
            startTime       = $humanTime.ToString('yyyy-MM-dd HH:mm:ss')
            endTime         = $aiTime.ToString('yyyy-MM-dd HH:mm:ss')
            durationMinutes = $duration
            humanChars      = Get-CharCount -Path (Join-Path $Dir $humanFileName)
            aiChars         = Get-CharCount -Path $aiFile.FullName
        }
    }

    return @($rounds | Sort-Object roundIndex)
}

function Add-ImplementationRound {
    param(
        [string]$Dir,
        [array]$Rounds,
        [array]$LogEntries
    )
    $implDoc = Join-Path $Dir '实施文档.md'
    if (-not (Test-Path $implDoc)) {
        return $Rounds
    }

    $lastRound = $Rounds | Sort-Object roundIndex | Select-Object -Last 1

    # 实施确认轮次的人文件应取目录下编号最大的用户回复文件，而不是已配对轮次的 humanFile
    $replyFiles = Get-ChildItem -LiteralPath $Dir -File -Force | Where-Object {
        $_.Name -match '^对v(\d+)的回复\.txt$'
    } | Sort-Object { [int]($_.Name -replace '^对v(\d+)的回复\.txt$', '$1') } -Descending

    $requirementFile = Get-ChildItem -LiteralPath $Dir -File -Force | Where-Object { $_.Name -eq '需求.txt' } | Select-Object -First 1

    if ($replyFiles) {
        $lastHumanFile = $replyFiles[0].Name
        $humanTime = Get-LogTimeForFile -LogEntries $LogEntries -FileName $lastHumanFile -FallbackTime $replyFiles[0].CreationTime
    }
    elseif ($requirementFile) {
        $lastHumanFile = '需求.txt'
        $humanTime = Get-LogTimeForFile -LogEntries $LogEntries -FileName '需求.txt' -FallbackTime $requirementFile.CreationTime
    }
    else {
        $lastHumanFile = ''
        $humanTime = (Get-Item $implDoc).CreationTime.AddSeconds(-1)
    }

    $aiTime = Get-LogTimeForFile -LogEntries $LogEntries -FileName '实施文档.md' -FallbackTime (Get-Item $implDoc).CreationTime

    if ($humanTime -gt $aiTime) {
        $humanTime = $aiTime.AddSeconds(-1)
    }

    $duration = [math]::Ceiling(($aiTime - $humanTime).TotalMinutes)
    if ($duration -lt 1) { $duration = 1 }

    $newIndex = if ($lastRound) { $lastRound.roundIndex + 1 } else { 0 }

    $newRound = [PSCustomObject]@{
        roundIndex      = $newIndex
        stage           = '实施确认'
        humanFile       = $lastHumanFile
        aiFile          = '实施文档.md'
        startTime       = $humanTime.ToString('yyyy-MM-dd HH:mm:ss')
        endTime         = $aiTime.ToString('yyyy-MM-dd HH:mm:ss')
        durationMinutes = $duration
        humanChars      = 0
        aiChars         = Get-CharCount -Path $implDoc
        category        = '实施确认'
        isExtreme       = $false
        extremeReason   = ''
    }

    return $Rounds + @($newRound)
}

function Get-ThemeFileItems {
    param(
        [string]$Dir,
        [string]$RelativePrefix
    )
    $files = Get-ChildItem -LiteralPath $Dir -File -Force | Where-Object {
        $_.Name -eq '需求.txt' -or
        $_.Name -match '^v\d+\.md$' -or
        $_.Name -match '^对v\d+的回复\.txt$'
    } | Sort-Object CreationTime

    $humanFiles = @()
    $aiFiles = @()
    foreach ($file in $files) {
        $relativePath = if ($RelativePrefix) { "$RelativePrefix\$($file.Name)" } else { $file.Name }
        $item = [PSCustomObject]@{
            path      = $relativePath
            createdAt = $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            charCount = Get-CharCount -Path $file.FullName
        }
        if ($file.Name -eq '需求.txt' -or $file.Name -match '^对v\d+的回复\.txt$') {
            $humanFiles += $item
        }
        elseif ($file.Name -match '^v\d+\.md$') {
            $aiFiles += $item
        }
    }

    return [PSCustomObject]@{
        humanFiles = $humanFiles
        aiFiles    = $aiFiles
    }
}

function Get-SubUnits {
    param(
        [string]$Dir,
        [string]$SubDirName,
        [array]$LogEntries,
        [int]$ThresholdMinutes
    )
    $subUnits = @()
    $subRoot = Join-Path $Dir $SubDirName
    if (-not (Test-Path $subRoot -PathType Container)) {
        return $subUnits
    }

    $childDirs = Get-ChildItem -LiteralPath $subRoot -Directory -Force | Sort-Object Name
    foreach ($child in $childDirs) {
        $requirementFile = Join-Path $child.FullName '需求.txt'
        if (-not (Test-Path $requirementFile)) {
            continue
        }

        $childRounds = @(Get-ThemeRounds -Dir $child.FullName -LogEntries $LogEntries)
        $childRounds = @(Add-ImplementationRound -Dir $child.FullName -Rounds $childRounds -LogEntries $LogEntries)

        if ($childRounds.Count -eq 0) {
            continue
        }

        $childTotalTime = Get-TotalTime -Dir $child.FullName -Rounds $childRounds -LogEntries $LogEntries -ThresholdMinutes $ThresholdMinutes

        $subUnits += [PSCustomObject]@{
            name            = $child.Name
            path            = $child.FullName
            rounds          = [PSCustomObject]@{
                total  = $childRounds.Count
                items  = $childRounds
                phases = @()
            }
            totalTime       = $childTotalTime
            totalHumanChars = ($childRounds | Measure-Object -Property humanChars -Sum).Sum
            totalAiChars    = ($childRounds | Measure-Object -Property aiChars -Sum).Sum
        }
    }

    return $subUnits
}

function Format-Duration {
    param([TimeSpan]$Duration)
    $days = [math]::Floor($Duration.TotalDays)
    $hours = $Duration.Hours
    $minutes = $Duration.Minutes
    if ($days -gt 0) {
        return "${days}天 ${hours}小时 ${minutes}分钟"
    }
    elseif ($hours -gt 0) {
        return "${hours}小时 ${minutes}分钟"
    }
    else {
        return "${minutes}分钟"
    }
}

function Get-StageTime {
    param(
        [string]$Dir,
        [array]$Rounds,
        [array]$LogEntries,
        [int]$ThresholdMinutes
    )
    $allFiles = Get-AllFilesRecursive -Dir $Dir
    $creationTimes = @($allFiles | Select-Object -ExpandProperty CreationTime)
    $logDateTimes = @()
    foreach ($entry in $LogEntries) {
        try {
            $logDateTimes += [datetime]::ParseExact($entry.time, 'yyyy-MM-dd HH:mm:ss', $null)
        }
        catch {
            # ignore invalid time
        }
    }

    $firstRoundStart = [datetime]::ParseExact($Rounds[0].startTime, 'yyyy-MM-dd HH:mm:ss', $null)
    $lastRoundEnd = [datetime]::ParseExact($Rounds[$Rounds.Count - 1].endTime, 'yyyy-MM-dd HH:mm:ss', $null)

    $implDoc = Join-Path $Dir '实施文档.md'
    $discussionEnd = $lastRoundEnd
    if (Test-Path $implDoc) {
        $iw = (Get-Item $implDoc).LastWriteTime
        if ($iw -gt $discussionEnd) { $discussionEnd = $iw }
    }

    $discussionDuration = Get-ActiveDuration -Start $firstRoundStart -End $discussionEnd `
        -FileCreationTimes $creationTimes -LogTimes $logDateTimes -ThresholdMinutes $ThresholdMinutes

    return [PSCustomObject]@{
        discussion = [PSCustomObject]@{
            minutes = [int]$discussionDuration.TotalMinutes
            display = Format-Duration -Duration $discussionDuration
        }
        execution = [PSCustomObject]@{
            minutes = 0
            display = '0分钟'
        }
        tweak = [PSCustomObject]@{
            minutes = 0
            display = '0分钟'
        }
    }
}

function Get-TotalTime {
    param(
        [string]$Dir,
        [array]$Rounds,
        [array]$LogEntries,
        [int]$ThresholdMinutes
    )
    $allFiles = Get-AllFilesRecursive -Dir $Dir
    $creationTimes = @($allFiles | Select-Object -ExpandProperty CreationTime)
    $logDateTimes = @()
    foreach ($entry in $LogEntries) {
        try {
            $logDateTimes += [datetime]::ParseExact($entry.time, 'yyyy-MM-dd HH:mm:ss', $null)
        }
        catch {
            # ignore invalid time
        }
    }

    $start = [datetime]::ParseExact($Rounds[0].startTime, 'yyyy-MM-dd HH:mm:ss', $null)
    $end = [datetime]::ParseExact($Rounds[$Rounds.Count - 1].endTime, 'yyyy-MM-dd HH:mm:ss', $null)

    $lastModified = $end
    if ($allFiles) {
        $lm = ($allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        if ($lm -gt $lastModified) { $lastModified = $lm }
    }

    $duration = Get-ActiveDuration -Start $start -End $lastModified `
        -FileCreationTimes $creationTimes -LogTimes $logDateTimes -ThresholdMinutes $ThresholdMinutes

    return [PSCustomObject]@{
        minutes = [int]$duration.TotalMinutes
        display = Format-Duration -Duration $duration
    }
}

# ============ main ============

try {
    $themePath = Resolve-ThemePath
    $thresholdMinutes = Get-IdleThresholdMinutes
    $logEntries = Read-LogEntries -Dir $themePath
    $rounds = @(Get-ThemeRounds -Dir $themePath -LogEntries $logEntries)
    $rounds = @(Add-ImplementationRound -Dir $themePath -Rounds $rounds -LogEntries $logEntries)

    if ($rounds.Count -eq 0) {
        throw "No valid rounds found in theme directory"
    }

    $resultFineTunings = Get-SubUnits -Dir $themePath -SubDirName '结果微调' -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
    $subThemes = Get-SubUnits -Dir $themePath -SubDirName '实施步骤' -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes

    $allRounds = @($rounds) +
                 @($resultFineTunings | ForEach-Object { $_.rounds.items }) +
                 @($subThemes | ForEach-Object { $_.rounds.items })

    $totalHumanChars = ($allRounds | Measure-Object -Property humanChars -Sum).Sum
    $totalAiChars = ($allRounds | Measure-Object -Property aiChars -Sum).Sum

    $totalTime = Get-TotalTime -Dir $themePath -Rounds $allRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes

    $mainTime = Get-TotalTime -Dir $themePath -Rounds $rounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
    $rtRounds = @($resultFineTunings | ForEach-Object { $_.rounds.items })
    $stRounds = @($subThemes | ForEach-Object { $_.rounds.items })
    $rtTime = if ($rtRounds.Count -gt 0) {
        Get-TotalTime -Dir $themePath -Rounds $rtRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
    } else {
        [PSCustomObject]@{ minutes = 0; display = '0分钟' }
    }
    $stTime = if ($stRounds.Count -gt 0) {
        Get-TotalTime -Dir $themePath -Rounds $stRounds -LogEntries $logEntries -ThresholdMinutes $thresholdMinutes
    } else {
        [PSCustomObject]@{ minutes = 0; display = '0分钟' }
    }

    $breakdown = [PSCustomObject]@{
        main = [PSCustomObject]@{
            rounds      = $rounds.Count
            timeMinutes = $mainTime.minutes
            humanChars  = ($rounds | Measure-Object -Property humanChars -Sum).Sum
            aiChars     = ($rounds | Measure-Object -Property aiChars -Sum).Sum
        }
        resultFineTunings = [PSCustomObject]@{
            rounds      = $rtRounds.Count
            timeMinutes = $rtTime.minutes
            humanChars  = [int]($rtRounds | Measure-Object -Property humanChars -Sum).Sum
            aiChars     = [int]($rtRounds | Measure-Object -Property aiChars -Sum).Sum
        }
        subThemes = [PSCustomObject]@{
            rounds      = $stRounds.Count
            timeMinutes = $stTime.minutes
            humanChars  = [int]($stRounds | Measure-Object -Property humanChars -Sum).Sum
            aiChars     = [int]($stRounds | Measure-Object -Property aiChars -Sum).Sum
        }
    }

    $rootFiles = Get-ThemeFileItems -Dir $themePath -RelativePrefix ''

    $rtFiles = @()
    foreach ($rt in $resultFineTunings) {
        $relativePrefix = "结果微调\$($rt.name)"
        $rtItems = Get-ThemeFileItems -Dir $rt.path -RelativePrefix $relativePrefix
        $rtFiles += [PSCustomObject]@{
            name       = $rt.name
            humanFiles = $rtItems.humanFiles
            aiFiles    = $rtItems.aiFiles
        }
    }

    $stFiles = @()
    foreach ($st in $subThemes) {
        $relativePrefix = "实施步骤\$($st.name)"
        $stItems = Get-ThemeFileItems -Dir $st.path -RelativePrefix $relativePrefix
        $stFiles += [PSCustomObject]@{
            name       = $st.name
            humanFiles = $stItems.humanFiles
            aiFiles    = $stItems.aiFiles
        }
    }

    $output = [PSCustomObject]@{
        themeName         = Split-Path -Leaf $themePath
        themePath         = $themePath
        generatedAt       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        files             = [PSCustomObject]@{
            humanFiles        = $rootFiles.humanFiles
            aiFiles           = $rootFiles.aiFiles
            resultFineTunings = $rtFiles
            subThemes         = $stFiles
        }
        rounds            = [PSCustomObject]@{
            total  = $rounds.Count
            items  = $rounds
            phases = @()
        }
        resultFineTunings = $resultFineTunings
        subThemes         = $subThemes
        totalTime         = $totalTime
        totalHumanChars   = $totalHumanChars
        totalAiChars      = $totalAiChars
        breakdown         = $breakdown
    }

    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $tmpDir = Join-Path (Join-Path $themePath '.aiprocess') '_tmp'
        if (-not (Test-Path $tmpDir)) {
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        $OutputFile = Join-Path $tmpDir "summary_input_$timestamp.json"
    }

    $outputDir = Split-Path -Parent $OutputFile
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $json = $output | ConvertTo-Json -Depth 10 -Compress
    # PowerShell ConvertTo-Json 可能把空数组序列化为 {}，这里修正
    $json = $json -replace '"resultFineTunings":\{\}', '"resultFineTunings":[]'
    $json = $json -replace '"subThemes":\{\}', '"subThemes":[]'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputFile, $json, $utf8NoBom)

    Write-Output $OutputFile
}
catch {
    if (-not [string]::IsNullOrWhiteSpace($ErrorFile)) {
        $errMsg = $_.Exception.Message
        if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
            $errMsg += "`n" + $_.InvocationInfo.PositionMessage
        }
        [System.IO.File]::WriteAllText($ErrorFile, $errMsg, [System.Text.Encoding]::UTF8)
    }
    throw
}
