#Requires AutoHotkey v2.0

; 质检码（AI 型）：复制代码质检提示词并发送 AI，产出 v(N+1).md
; 提示词由 PromptSource 统一拼装；本类只负责守卫、properties 与发送

class QualityCheck extends AgentActionBase {
    ActionKey := "质检码"
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

        content := PromptSource.Build("质检码", "single")

        this.Dispatch(content, Map("target", nextVersionFile), "质检提示词已复制")
    }
}
