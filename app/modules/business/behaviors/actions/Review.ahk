#Requires AutoHotkey v2.0

; 复盘（AI 型）：复制出题提示词并发送 AI，产出 v(N+1).md（题面）
; 组成 = 模式模板 + 不修改 → 提问模板 → 打开md（顺序即业务，与质检码同构）；评价在下一轮「复回复」

class Review extends AgentActionBase {
    ActionKey := "复盘"
    Type := "ai"
    FailLogText := "复盘提示词复制失败"
    FailFeedbackText := "提示词复制失败"

    Execute() {
        chain := VersionChain.Of(GetCurrentDir())
        if (chain.LatestVersion = 0) {
            ShowFeedback("当前目录下还没有任何 vN.md，复盘需要先完成至少一轮沟通", true)
            this.SkipAutoHide := true  ; 前置校验未通过：不触发自动隐藏（对齐复回复/质检码写法）
            return
        }
        nextVersionFile := "v" chain.NextVersion() ".md"   ; 裸文件名（对齐复回复口径）
        mode := ReviewModeRegistry.GetMeta(ReviewModeRegistry.GetSelected())
        content := this.LoadTemplate(mode["template"])
        content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
        content := PromptElements.NoModify(content)
        content := PromptElements.QuestionTemplate(content)
        content := PromptElements.OpenMd(content)
        properties := Map("target", nextVersionFile, "复盘模式", mode["label"])
        this.Dispatch(content, properties, mode["feedback"])
    }
}
