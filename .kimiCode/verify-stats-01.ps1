# 临时验证脚本：核对 结果微调/01 的 stats.json / 统计.md 数值
param([string]$ThemePath)

# 1. 人文件字符数（含空白）
$req = Get-Content -Raw -Encoding UTF8 (Join-Path $ThemePath '需求.txt')
Write-Host ("req length = " + $req.Length)

# 2. v1.md 剥离 front matter 后的字符数
$v1raw = Get-Content -Raw -Encoding UTF8 (Join-Path $ThemePath 'v1.md')
$body = $v1raw -replace '(?s)^---\r?\n.*?\r?\n---\r?\n', ''
Write-Host ("v1 body length = " + $body.Length)

# 3. 目录文件清单（排除 .aiprocess 子目录与隐藏）
$files = Get-ChildItem -File $ThemePath | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) }
Write-Host ("root files now = " + ($files.Name -join ', '))
