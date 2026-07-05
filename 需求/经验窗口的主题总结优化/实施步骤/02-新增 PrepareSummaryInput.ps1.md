# 步骤 2：新增 PrepareSummaryInput.ps1

## 目标

替代旧版 `PrepareSummaryData.ps1`，生成本地素材文件 `summary_input.json`。

## 新增文件

- `app/powershell/summary/PrepareSummaryInput.ps1`

## 输入输出

- 输入：`-ThemePath <path>`
- 输出：`{ThemePath}\.aiprocess\_tmp\summary_input.json`

## 功能要求

1. 扫描主题目录，识别：
   - `需求.txt`
   - `v*.md`
   - `对v*.txt`
   - `实施文档.md`
   - `log.jsonl`
2. 按轮次规则配对：
   - R0：`需求.txt` → `v1.md`
   - RN：`对vN的回复.txt` → `v(N+1).md`
3. 计算每轮：
   - `startTime`：人输入文件创建时间（优先 log，fallback 文件时间）
   - `endTime`：AI 输出文件创建时间
   - `durationMinutes`：向上取整
   - `humanChars`、`aiChars`：字符数
4. 提取每轮人/AI 内容预览（前 200 字符）。
5. 复用 `ActiveDurationCalculator.ps1` 计算总活跃时长和阶段耗时。
6. 输出 `summary_input.json`。

## 复用旧逻辑

- 从 `PrepareSummaryData.ps1` 提取：
  - `Sort-FilesByConvention`
  - `Read-LogEntries`
  - `Get-IdleThresholdMinutes`
  - `Get-ActiveDuration` 调用方式

## 验收

对「闭环」主题执行脚本，生成的 `summary_input.json` 与手工验证版结构一致，字段完整。
