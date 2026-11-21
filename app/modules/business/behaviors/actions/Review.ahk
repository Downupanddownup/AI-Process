#Requires AutoHotkey v2.0

; 复盘（AI 型）：复制出题提示词并发送 AI，产出 v(N+1).md（题面）
; 提示词由 PromptSource 统一拼装；本类只负责守卫、properties 与发送。评价在下一轮「复回复」

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

        content := PromptSource.Build("复盘", ReviewModeRegistry.GetSelected())

        properties := Map("target", nextVersionFile, "复盘模式", mode["label"])
        this.Dispatch(content, properties, mode["feedback"])
    }
}
