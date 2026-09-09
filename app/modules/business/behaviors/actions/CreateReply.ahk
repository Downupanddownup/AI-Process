#Requires AutoHotkey v2.0

; 建回复（本地型）：基于最新 vN.md 生成 对vN的回复.txt
; 迁移自 FileManager.CreateReplyFile（:215），逐行等价；守卫与自动隐藏由基类 Run 承担
; 提问提取（ExtractQuestionsFromMd / BuildReplyText）由 QuestionCollector 原样提供

class CreateReply extends AgentActionBase {
    ActionKey := "建回复"
    LogTag := "建回复"
    Type := "local"
    FailLogText := "建回复 操作失败"
    FailFeedbackText := "操作失败"

    Execute() {
        currentDir := GetCurrentDir()
        latestVersion := DomainConventions.GetLatestVersionNumber(currentDir)
        if (latestVersion = 0) {
            ShowFeedback("当前目录下未找到 vX.md 文件", true)
            this.SkipAutoHide := true  ; 对齐旧函数提前 return：不触发自动隐藏
            return
        }

        replyPath := DomainConventions.ReplyPath(currentDir, latestVersion)
        existed := FileExist(replyPath)
        if !existed {
            content := ""
            if GetSession(GetActiveWindowId(), "AppendQuestionTemplate") {
                mdPath := DomainConventions.VersionPath(currentDir, latestVersion)
                questions := ExtractQuestionsFromMd(mdPath)
                if (questions.Length > 0) {
                    content := BuildReplyText(questions)
                }
            }
            FileAppend(content, replyPath, "UTF-8")
            ShowFeedback("已创建：" ExtractFileName(replyPath))
        } else {
            ShowFeedback("文件已存在：" ExtractFileName(replyPath), true)
        }

        LogActivity(this.LogTag, "", Map("target", ExtractFileName(replyPath)))

        this.OpenInTool(replyPath)
    }
}
