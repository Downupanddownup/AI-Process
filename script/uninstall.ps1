$ErrorActionPreference = "Stop"

$startMenu = [Environment]::GetFolderPath('StartMenu')
$programs = Join-Path $startMenu "Programs"
$shortcut = Join-Path $programs "AI Process.lnk"

if (Test-Path $shortcut) {
    Remove-Item $shortcut -Force
    Write-Host "Removed shortcut: $shortcut"
} else {
    Write-Host "Shortcut not found: $shortcut"
}
