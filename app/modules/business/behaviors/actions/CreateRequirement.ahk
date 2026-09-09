#Requires AutoHotkey v2.0

; 建需求（本地型）：创建/打开 需求.txt
; 阶段 1 空壳：实现于步骤 03 从 FileManager.CreateRequirementFile 逐行迁移

class CreateRequirement extends AgentActionBase {
    ActionKey := "建需求"
    LogTag := "建需求"
    Type := "local"

    Execute() {
        throw Error("未实现：步骤 03 迁移")
    }
}
