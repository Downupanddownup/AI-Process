#Requires AutoHotkey v2.0

; 建需求（本地型）：创建/打开 需求.txt
; 逐行等价迁出（旧件已删）；守卫与自动隐藏由基类 Run 承担

class CreateRequirement extends AgentActionBase {
    ActionKey := "建需求"
    Type := "local"
    FailLogText := "建需求 操作失败"
    FailFeedbackText := "操作失败"

    Execute() {
        filePath := DomainConventions.RequirementPath(GetCurrentDir())
        existed := FileExist(filePath)
        if !existed {
            FileAppend("", filePath, "UTF-8")
            ShowFeedback("已创建：需求.txt")
        } else {
            ShowFeedback("文件已存在：需求.txt", true)
        }

        LogActivity(this.LogTag, "", Map("target", DomainConventions.RequirementFile))

        this.OpenInTool(filePath)
    }
}
