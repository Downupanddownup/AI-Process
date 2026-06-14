$ErrorActionPreference = "Stop"

$startMenu = [Environment]::GetFolderPath('StartMenu')
$programs = Join-Path $startMenu "Programs"
$shortcut = Join-Path $programs "AI Process.lnk"

# 检查 AIProcess 是否仍在运行
$running = Get-Process -Name "AIProcess" -ErrorAction SilentlyContinue
if ($running) {
    Write-Warning "AIProcess 仍在运行，请先手动结束进程，然后再运行卸载脚本。"
    Write-Host "你可以右键任务栏托盘图标选择退出，或按 Ctrl+Alt+Del 结束进程。" -ForegroundColor Yellow
    exit 1
}

# 清理右键菜单注册表项
$regPath = "Registry::HKEY_CLASSES_ROOT\Directory\shell\AIProcessSetDir"
try {
    if (Test-Path $regPath) {
        Remove-Item -Path $regPath -Recurse -Force
        Write-Host "已清理右键菜单：AIProcess 目录" -ForegroundColor Green
    } else {
        Write-Host "右键菜单项不存在，无需清理。" -ForegroundColor Gray
    }
} catch {
    Write-Warning "清理右键菜单失败：$_"
}

if (Test-Path $shortcut) {
    Remove-Item $shortcut -Force
    Write-Host "Removed shortcut: $shortcut"
} else {
    Write-Host "Shortcut not found: $shortcut"
}
