#Requires AutoHotkey v2.0

; 复关系（AI 型）：复制上下文重建说明并发送 AI
; 阶段 1 空壳：实现于步骤 04 从 PromptManager.CopyContextRelations 逐行迁移

class CopyRelations extends AgentActionBase {
    ActionKey := "复关系"
    LogTag := "复关系"
    Type := "ai"

    Execute() {
        throw Error("未实现：步骤 04 迁移")
    }
}
