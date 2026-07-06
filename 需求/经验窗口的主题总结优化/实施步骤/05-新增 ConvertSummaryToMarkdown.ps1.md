# 步骤 5：新增 ConvertSummaryToMarkdown.ps1

## 目标

将 `Summary.json` 渲染为 `Summary.md`，供用户查看。

## 新增文件

- `app/powershell/summary/ConvertSummaryToMarkdown.ps1`

## 输入输出

- 输入：`-JsonPath <path>`
- 输出：同目录下的 `Summary.md`

## 功能要求

1. 读取 `Summary.json`。
2. 按以下结构渲染 Markdown：
   - `# 经验总结：{themeName}`
   - `## 1. 总览`
   - `## 2. 核心指标`
   - `## 3. 阶段划分`
   - `## 4. 轮次时间轴`
   - `## 5. 纠偏分析`
   - `## 6. 失控分析`
   - `## 7. 经验教训`
3. 把 JSON 中所有字段都显示出来，样式先简单处理。
4. 写入 `{themePath}\.aiprocess\Summary.md`。

## 实现方式

使用 PowerShell 字符串拼接，不使用外部库。因为 JSON 结构固定，直接按字段渲染即可。

## 验收

对「闭环」的 `Summary.json` 执行脚本，生成可读的 `Summary.md`，所有 JSON 字段都有对应内容。
