#Requires AutoHotkey v2.0

; 复关系（AI 型）：复制上下文重建说明并发送 AI
; 提示词由 ContextRebuildPromptBuilder 构建；本类只负责行为约束、通知与发送

class CopyRelations extends AgentActionBase {
    ActionKey := "复关系"
    Type := "ai"
    FailLogText := "文件关系说明复制失败"
    FailFeedbackText := "文件关系说明复制失败"

    Execute() {
        content := ContextRebuildPromptBuilder.Build(GetCurrentDir())
        content := PromptElements.NoModify(content)
        content := PromptElements.ContextRelationTail(content)
        this.Dispatch(content, Map("target", "上下文重建"), "文件关系说明已复制")
    }
}
