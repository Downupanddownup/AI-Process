#Requires AutoHotkey v2.0

; 复需求（AI 型）：复制需求提示词并发送 AI
; 阶段 1 空壳：实现于步骤 04 从 PromptManager.CopyRequirementPrompt 逐行迁移

class CopyRequirement extends AgentActionBase {
    ActionKey := "复需求"
    LogTag := "复需求"
    Type := "ai"

    Execute() {
        throw Error("未实现：步骤 04 迁移")
    }
}
