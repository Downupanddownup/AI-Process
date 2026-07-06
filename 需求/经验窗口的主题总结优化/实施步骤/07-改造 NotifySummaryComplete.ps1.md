# 步骤 7：改造 NotifySummaryComplete.ps1

## 目标

让完成通知脚本兼容 `Summary.json` 产物。

## 修改文件

- `app/powershell/summary/NotifySummaryComplete.ps1`

## 改造内容

1. 校验文件从 `Summary.md` 改为 `Summary.json`：
   ```powershell
   $summaryJson = Join-Path $ThemePath '.aiprocess\Summary.json'
   if (-not (Test-Path $summaryJson)) {
       Write-Error "Summary.json 不存在"
       exit 1
   }
   ```

2. 如果存在 `Summary.md`，保留它；如果不存在，不强制生成（按需生成由 `ViewThemeSummary` 处理）。

3. 继续执行原有逻辑：
   - 写 `history/summary_log.jsonl`
   - 显示托盘通知
   - 发送 `0x8000` 刷新经验总结窗口
   - 清理 `_tmp` 目录

## 验收

Agent 生成 `Summary.json` 后调用此脚本，窗口正常刷新，无报错。
