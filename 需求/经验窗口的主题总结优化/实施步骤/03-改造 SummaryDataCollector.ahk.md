# 步骤 3：改造 SummaryDataCollector.ahk

## 目标

让 AHK 数据收集层调用新的 `PrepareSummaryInput.ps1`，并读取 `summary_input.json`。

## 修改文件

- `app/modules/business/summary/SummaryDataCollector.ahk`

## 改造内容

1. 将 `psScript` 从：
   ```ahk
   psScript := AppRoot "\powershell\summary\PrepareSummaryData.ps1"
   ```
   改为：
   ```ahk
   psScript := AppRoot "\powershell\summary\PrepareSummaryInput.ps1"
   ```

2. 保持 `RunWait` 调用方式不变，但确认输出文件是 `summary_input.json`。

3. 读取输出文件后，用 `JSON.Load()` 解析为 Map 返回。

## 不改动

- 临时目录创建逻辑。
- 错误处理流程。
- JSON BOM 处理逻辑。

## 验收

调用 `CollectSummaryData(themePath)` 后返回的 Map 包含 `themeName`、`rounds`、`totalTime`、`totalHumanChars` 等字段。
