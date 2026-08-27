<#
.SYNOPSIS
    改吧（复执行-tweak）执行结果文档生成脚本。

.DESCRIPTION
    在改吧执行完成后由 AI 调用。按上一份文档生成结果 md（vN.md→v(N+1).md、实施文档.md→已实施.md），
    正文取自模板 templates\execute\result_doc.md（替换 {{prevDocName}}），随后走 OpenMarkdown
    打开（由 OpenMarkdown 注入 ai-agent 与统一耗时标记），并按配置决定是否弹完成通知。

    复用优先：本脚本只做"创建结果 md"，其余（打标/打开/时间）复用现有；
    失败隔离：任何异常仅警告、退出码 0，不阻断调用方。

.PARAMETER WindowId
    窗口编号，1/2/3。
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("1", "2", "3")]
    [string]$WindowId
)

trap {
    Write-Warning "WriteExecResultDoc failed: $_"
    exit 0
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path (Split-Path $scriptDirectory -Parent) -Parent   # powershell/execute -> powershell -> app
$settingsPath = Join-Path $appRoot "config\settings.ini"
$templatePath = Join-Path $appRoot "templates\execute\result_doc.md"
$openMarkdownScript = Join-Path (Join-Path $appRoot "powershell\markdown") "OpenMarkdown.ps1"
$notifyScript = Join-Path (Join-Path $appRoot "powershell\notification") "ShowCenterNotification.ps1"

if (-not (Test-Path -LiteralPath $settingsPath)) { exit 0 }

function Read-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $currentSection = $null
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith(";")) {
            continue
        }
        if ($trimmedLine -match "^\[(.+)\]$") {
            $currentSection = $matches[1]
            continue
        }
        if ($currentSection -eq $Section -and $trimmedLine -match "^(.+?)\s*=\s*(.*)$") {
            $currentKey = $matches[1].Trim()
            if ($currentKey -eq $Key) {
                return $matches[2].Trim()
            }
        }
    }
    return $null
}

$section = "Window" + $WindowId
$currentDir = Read-IniValue -Path $settingsPath -Section $section -Key "CurrentDir"
if ([string]::IsNullOrWhiteSpace($currentDir) -or (-not (Test-Path -LiteralPath $currentDir -PathType Container))) {
    exit 0
}

# 确定结果 md 名：存在实施文档.md -> 已实施.md；否则取最大 vN.md -> v(N+1).md
$resultName = ""
$prevDocName = ""
$implDoc = Join-Path $currentDir "实施文档.md"
if (Test-Path -LiteralPath $implDoc) {
    $resultName = "已实施.md"
    $prevDocName = "实施文档.md"
} else {
    $vFiles = @(Get-ChildItem -LiteralPath $currentDir -File -Filter "v*.md" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match '^v(\d+)$' })
    if ($vFiles.Count -eq 0) { exit 0 }
    $maxN = ($vFiles | ForEach-Object { [int]($_.BaseName -replace '^v(\d+)$', '$1') } | Measure-Object -Maximum).Maximum
    $resultName = "v" + ($maxN + 1) + ".md"
    $prevDocName = "v" + $maxN + ".md"
}

$resultPath = Join-Path $currentDir $resultName

# 已存在则不覆盖（防多次执行互相覆盖）
if (Test-Path -LiteralPath $resultPath) {
    Write-Host "Result doc already exists: $resultName (skip creating)."
    exit 0
}

# 读模板并替换占位符
if (-not (Test-Path -LiteralPath $templatePath)) { exit 0 }
$body = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)
$body = $body.Replace("{{prevDocName}}", $prevDocName)

# 落盘结果 md（UTF-8 BOM 更稳妥）
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($resultPath, $body, $utf8Bom)

# 走 OpenMarkdown：注入 ai-agent、统一耗时标记，并按 MdActivationMode 打开
if (Test-Path -LiteralPath $openMarkdownScript) {
    & powershell -ExecutionPolicy Bypass -File "`"$openMarkdownScript`"" -FilePath "`"$resultPath`"" -WindowId "`"$WindowId`""
}

# 完成通知：仅 activate 模式且 ShowExecuteNotification 开启时自行弹；background 由 OpenMarkdown 自带，避免双弹
$mode = Read-IniValue -Path $settingsPath -Section "Behavior" -Key "MdActivationMode"
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "activate" }
$showNotify = Read-IniValue -Path $settingsPath -Section $section -Key "ShowExecuteNotification"
if ($mode -ne "background" -and $showNotify -eq "1" -and (Test-Path -LiteralPath $notifyScript)) {
    & powershell -ExecutionPolicy Bypass -File "`"$notifyScript`"" -WindowId "`"$WindowId`""
}

Write-Host "Created '$resultName' as '$prevDocName' execution result."
exit 0
