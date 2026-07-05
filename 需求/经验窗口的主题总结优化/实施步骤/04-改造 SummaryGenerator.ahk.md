# 步骤 4：改造 SummaryGenerator.ahk

## 目标

让生成流程从「Agent 直接写 Markdown」改为「Agent 基于素材和规则写 JSON」。

## 修改文件

- `app/modules/business/summary/SummaryGenerator.ahk`

## 改造内容

### 4.1 GenerateSummary()

1. 校验文件从 `Summary.md` 改为 `Summary.json`：
   ```ahk
   summaryFile := themePath "\.aiprocess\Summary.json"
   ```

2. 调用 `CollectSummaryData(themePath)` 获取素材后，确保 `summary_input.json` 已生成。

3. 把三份规则文件复制到 `{themePath}\.aiprocess\_tmp\`：
   - `summary_input_guide.md`
   - `summary_template.json`
   - `summary_rules.md`

4. 构造 Agent 短消息：
   ```
   请基于以下素材和规则生成 Summary.json：
   1. 素材文件：{themePath}\.aiprocess\_tmp\summary_input.json
   2. 素材说明：{themePath}\.aiprocess\_tmp\summary_input_guide.md
   3. 输出模板：{themePath}\.aiprocess\_tmp\summary_template.json
   4. 生成规则：{themePath}\.aiprocess\_tmp\summary_rules.md
   
   请按规则生成 Summary.json 并保存到 {themePath}\.aiprocess\Summary.json，
   然后执行：powershell -ExecutionPolicy Bypass -File "{AppRoot}\powershell\summary\NotifySummaryComplete.ps1" -ThemePath "{themePath}" -Status "done"
   ```

5. 将完整短消息写入临时文件，通过 `AgentDispatcherSend` 发送。

### 4.2 BuildSummaryPrompt()

- 直接返回上面构造的 Agent 短消息。
- 删除旧模板读取和占位符替换逻辑。
- 保留辅助函数 `BuildCoreFilesText`、`BuildSubThemesText`、`BuildTweakBreakdownText` 暂不删除，但不再使用。

## 验收

点击「生成总结」后，Agent 收到的消息包含正确的素材路径和规则路径。
