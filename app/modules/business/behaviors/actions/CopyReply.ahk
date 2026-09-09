#Requires AutoHotkey v2.0

; 复回复（AI 型）：复制回复提示词并发送 AI（分 普通/勾实 两分支）
; 阶段 1 空壳：实现于步骤 05 从 PromptManager.CopyReplyPrompt 逐行迁移

class CopyReply extends AgentActionBase {
    ActionKey := "复回复"
    LogTag := "复回复"
    Type := "ai"

    Execute() {
        throw Error("未实现：步骤 05 迁移")
    }
}
