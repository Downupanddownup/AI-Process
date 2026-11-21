#Requires AutoHotkey v2.0

; 复需求（AI 型）：复制需求提示词并发送 AI
; 提示词由 PromptSource 统一拼装；本类只负责 properties 与发送

class CopyRequirement extends AgentActionBase {
    ActionKey := "复需求"
    Type := "ai"
    FailLogText := "复需求提示词复制失败"
    FailFeedbackText := "提示词复制失败"

    Execute() {
        content := PromptSource.Build("复需求", "single")
        this.Dispatch(content, Map("target", "v1.md", "source", DomainConventions.RequirementFile), "需求提示词已复制")
    }
}
