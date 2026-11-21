#Requires AutoHotkey v2.0

; 复回复（AI 型）：复制回复提示词并发送 AI（分 普通 / 勾实 两分支）
; 提示词由 PromptSource 统一拼装；本类只负责守卫、properties 与发送

class CopyReply extends AgentActionBase {
    ActionKey := "复回复"
    Type := "ai"
    FailLogText := "复回复提示词复制失败"
    FailFeedbackText := "提示词复制失败"

    Execute() {
        chain := VersionChain.Of(GetCurrentDir())
        if (chain.LatestVersion = 0) {
            ShowFeedback("当前目录下未找到 vX.md 文件", true)
            this.SkipAutoHide := true  ; 前置校验未通过：不触发自动隐藏
            return
        }

        nextVersionFile := "v" chain.NextVersion() ".md"  ; 裸文件名（不是全路径）
        implChecked := GetSession(GetActiveWindowId(), "AppendImplementationTail")

        content := PromptSource.Build("复回复", implChecked ? "impl" : "direct")

        properties := Map()
        properties["source"] := "对v" chain.LatestVersion "的回复.txt"
        if (implChecked) {
            properties["实"] := true
            properties["target"] := DomainConventions.ImplDocFile
        } else {
            properties["target"] := nextVersionFile
        }

        this.Dispatch(content, properties, "回复提示词已复制")
    }
}
