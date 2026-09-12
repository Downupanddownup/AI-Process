#Requires AutoHotkey v2.0

; 复回复（AI 型）：复制回复提示词并发送 AI（分 普通/勾实 两分支）
; 逐行等价迁出（旧件已删）
; 分支语义：勾「实」→ 实施文档模板、尾部无提问模板段；普通 → 回复模板、尾部含提问模板段

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

        currentReplyFile := chain.LatestReplyPath()
        nextVersionFile := "v" chain.NextVersion() ".md"  ; 裸文件名（不是全路径）
        implChecked := GetSession(GetActiveWindowId(), "AppendImplementationTail")

        if (implChecked) {
            content := this.LoadTemplate("reply_prompt_impl_tail.txt")
            content := StrReplace(content, "{{filePath}}", currentReplyFile)
        } else {
            content := this.LoadTemplate("reply_prompt.txt")
            content := StrReplace(content, "{{filePath}}", currentReplyFile)
            content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
        }

        content := PromptElements.NoModify(content)
        if (!implChecked) {
            content := PromptElements.QuestionTemplate(content)
        }
        content := PromptElements.OpenMd(content)

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
