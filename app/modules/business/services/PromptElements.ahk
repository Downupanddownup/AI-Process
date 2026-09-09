#Requires AutoHotkey v2.0

; 提示词元素库：可复用业务元素（不修改/提问规则/提问模板/打开md/执行通知/完成通知）
; 每个元素自包含"内容 + 生效条件"；模板从 app/templates/elements/ 加载
; 阶段 1 空壳：实现于步骤 02（收编 PromptManager 的 6 个 AppendXxxIfNeeded）

class PromptElements {
}
