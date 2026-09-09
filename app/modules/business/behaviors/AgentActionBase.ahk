#Requires AutoHotkey v2.0

; 领域行为公共基类：Run 骨架 + 技术机制（LoadTemplate / Dispatch / OpenInTool）
; 原则：动作骨架用继承，外部能力用组合；业务组成留行为类，技术机制才外包

class AgentActionBase {

    ActionKey := ""
    LogTag := ""
    Type := "ai"
    ; 异常兜底文案（对齐各旧函数 catch 原文；建X 旧函数无 catch，此处为骨架统一兜底）
    FailLogText := "操作失败"
    FailFeedbackText := "操作失败"

    ; 模板方法骨架：守卫 → Execute → 自动隐藏
    Run(*) {
        try {
            if !ActionGuard.EnsureCurrentDirectory() {
                return
            }
            this.Execute()
            MaybeAutoHide()
        } catch Error as err {
            LogError(this.FailLogText "：" err.Message)
            ShowFeedback(this.FailFeedbackText "：" err.Message, true)
        }
    }

    ; 变化点：由子类实现
    Execute() {
        throw Error("Execute 必须由子类实现")
    }

    ; ---- 纯技术：模板加载（= 原 PromptManager.LoadTemplate） ----
    LoadTemplate(fileName) {
        global TemplateDir
        path := TemplateDir "\" fileName
        if !FileExist(path) {
            LogError("模板文件不存在：" path)
            throw Error("模板文件不存在：" path)
        }
        return FileRead(path, "UTF-8")
    }

    ; ---- 纯技术：剪贴板 → 日志 → 反馈 → 发 Agent（保持旧调用顺序） ----
    Dispatch(content, properties, feedbackMsg) {
        A_Clipboard := content
        LogActivity(this.LogTag, content, properties)
        ShowFeedback(feedbackMsg)
        HandleAgentWindowAfterCopy()
    }

    ; ---- 纯技术：用编辑器打开（受 OpenWithIdea 开关控制） ----
    OpenInTool(filePath) {
        if GetSession(GetActiveWindowId(), "OpenWithIdea") {
            EditorOpener.Open(filePath)
        }
    }
}
