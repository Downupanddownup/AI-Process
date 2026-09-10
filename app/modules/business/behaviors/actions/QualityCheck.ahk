#Requires AutoHotkey v2.0

; 质检码（AI 型）：复制代码质检提示词并发送 AI，产出 v(N+1).md
; 组成 = 质检主模板 + 不修改 → 提问模板 → 打开md（顺序即业务）
; 与复需求/复回复同族：讨论环节、产 vN.md；不带提问规则，无输入文件故人耗时恒 0

class QualityCheck extends AgentActionBase {
    ActionKey := "质检码"
    LogTag := "质检码"
    Type := "ai"
    FailLogText := "质检提示词复制失败"
    FailFeedbackText := "提示词复制失败"

    Execute() {
        chain := VersionChain.Of(GetCurrentDir())
        if (chain.LatestVersion = 0) {
            ShowFeedback("当前目录下还没有任何 vN.md，质检需要先完成至少一轮沟通", true)
            this.SkipAutoHide := true  ; 前置校验未通过：不触发自动隐藏（对齐复回复写法）
            return
        }
        nextVersionFile := "v" chain.NextVersion() ".md"   ; 裸文件名（对齐复回复口径）
        content := this.LoadTemplate("quality_check_prompt.txt")
        content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
        content := PromptElements.NoModify(content)
        content := PromptElements.QuestionTemplate(content)
        content := PromptElements.OpenMd(content)
        this.Dispatch(content, Map("target", nextVersionFile), "质检提示词已复制")
    }
}
