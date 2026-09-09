#Requires AutoHotkey v2.0

; 复执行（AI 型）：复制执行指令并发送 AI（改吧/步目 两策略分支）
; 阶段 1 空壳：实现于步骤 05 从 PromptManager.CopyExecutePrompt 逐行迁移

class CopyExecute extends AgentActionBase {
    ActionKey := "复执行"
    LogTag := "复执行"
    Type := "ai"

    Execute() {
        throw Error("未实现：步骤 05 迁移")
    }
}
