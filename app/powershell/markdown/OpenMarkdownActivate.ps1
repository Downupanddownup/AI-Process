<#
.SYNOPSIS
    MD 激活模式：用 IDEA 打开 Markdown 文件并激活窗口。

.DESCRIPTION
    读取 settings.ini 中的 FileToolPath，使用 Start-Process 打开 Markdown 文件。
    文件处理工具窗口会被激活并置到最前台。

.PARAMETER FilePath
    要打开的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1 或 2。可选，本模式下不使用。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3")]
    [string]$WindowId = ""
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "..\..\config\settings.ini"

Import-Module (Join-Path $scriptDirectory "..\config\AppSettings.psm1")

function Assert-PathExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -Path $Path)) {
        Write-Error "$Description not found: $Path"
        exit 1
    }
}

Assert-PathExists -Path $settingsPath -Description "settings.ini"

$fileToolPath = Get-FileToolPath
if ([string]::IsNullOrWhiteSpace($fileToolPath)) {
    Write-Error "FileToolPath is not configured in settings.ini [FileTool] section."
    exit 1
}

Assert-PathExists -Path $fileToolPath -Description "File tool executable"
Assert-PathExists -Path $FilePath -Description "Markdown file"

Start-Process -FilePath $fileToolPath -ArgumentList "`"$FilePath`"" -NoNewWindow

Write-Host "Opened '$FilePath' with file tool."
