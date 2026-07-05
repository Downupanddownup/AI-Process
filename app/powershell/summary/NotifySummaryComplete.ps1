<#
.SYNOPSIS
    经验总结完成通知脚本。

.DESCRIPTION
    AI Agent 生成 Summary.json 后调用此脚本。
    负责写入独立日志、显示通知、刷新 AI Process 的「经验总结」窗口。

.PARAMETER ThemePath
    主题目录绝对路径。

.PARAMETER Status
    完成状态：done 或 failed。
#>

param(
    [Parameter(Mandatory = $true)][string]$ThemePath,
    [Parameter(Mandatory = $true)][string]$Status
)

$ErrorActionPreference = "Stop"

# 校验产物
$summaryJson = Join-Path $ThemePath '.aiprocess\Summary.json'
if ($Status -eq "done" -and -not (Test-Path $summaryJson)) {
    throw "Summary.json 不存在：$summaryJson"
}

# 定位项目根目录
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..\..")

# 1. 写入独立日志
$historyDir = Join-Path $projectRoot "history"
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
}
$logFile = Join-Path $historyDir "summary_log.jsonl"

$record = [ordered]@{
    time      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    themePath = $ThemePath
    status    = $Status
}
$jsonLine = ($record | ConvertTo-Json -Compress) + "`n"
[System.IO.File]::AppendAllText($logFile, $jsonLine, [System.Text.Encoding]::UTF8)

# 2. 显示通知
Add-Type -AssemblyName System.Windows.Forms

$themeName = Split-Path -Leaf $ThemePath
$message = if ($Status -eq "done") { "主题 [$themeName] 的经验总结已生成" } else { "主题 [$themeName] 的经验总结生成失败" }

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$notifyIcon.Visible = $true
$notifyIcon.ShowBalloonTip(1500, "AI Process", $message, [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Milliseconds 200
$notifyIcon.Dispose()

# 3. 刷新「经验总结」窗口
$signature = @"
using System;
using System.Runtime.InteropServices;
public class WindowHelper {
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@

Add-Type -TypeDefinition $signature -Language CSharp

$hwnd = [WindowHelper]::FindWindow($null, "经验总结")
if ($hwnd -ne [IntPtr]::Zero) {
    [void][WindowHelper]::PostMessage($hwnd, 0x8000, [IntPtr]::Zero, [IntPtr]::Zero)
}

# 4. 安全清空主题临时目录（仅删除 {ThemePath}\.aiprocess\_tmp 下的内容，不越界）
$tmpDir = Join-Path $ThemePath '.aiprocess\_tmp'
if (Test-Path -Path $tmpDir -PathType Container) {
    $expectedParent = Join-Path $ThemePath '.aiprocess'
    try {
        $resolvedTmpDir = (Resolve-Path -Path $tmpDir).Path
        $resolvedExpectedParent = (Resolve-Path -Path $expectedParent).Path
        $expectedTmpDir = Join-Path $resolvedExpectedParent '_tmp'

        if ($resolvedTmpDir -eq $expectedTmpDir) {
            $items = Get-ChildItem -LiteralPath $resolvedTmpDir -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        # 路径解析或删除异常时静默忽略，不影响主流程
    }
}
