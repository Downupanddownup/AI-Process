#Requires AutoHotkey v2.0

; 复需求（AI 型）：复制需求提示词并发送 AI
; 逐行等价迁出（旧件已删）
; 组成 = requirement_prompt + 不修改 → 提问规则 → 提问模板 → 打开md（顺序即业务）

class CopyRequirement extends AgentActionBase {
    ActionKey := "复需求"
    Type := "ai"
    FailLogText := "复需求提示词复制失败"
    FailFeedbackText := "提示词复制失败"

    Execute() {
        chain := VersionChain.Of(GetCurrentDir())
        content := this.LoadTemplate("requirement_prompt.txt")
        content := StrReplace(content, "{{filePath}}", chain.RequirementPath())
        content := PromptElements.NoModify(content)
        content := PromptElements.QuestionRules(content)
        content := PromptElements.QuestionTemplate(content)
        content := PromptElements.OpenMd(content)
        this.Dispatch(content, Map("target", "v1.md", "source", DomainConventions.RequirementFile), "需求提示词已复制")
    }
}
