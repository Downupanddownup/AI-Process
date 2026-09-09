#Requires AutoHotkey v2.0

; 建回复（本地型）：基于最新 vN.md 生成 对vN的回复.txt
; 阶段 1 空壳：实现于步骤 03 从 FileManager.CreateReplyFile 逐行迁移

class CreateReply extends AgentActionBase {
    ActionKey := "建回复"
    LogTag := "建回复"
    Type := "local"

    Execute() {
        throw Error("未实现：步骤 03 迁移")
    }
}
