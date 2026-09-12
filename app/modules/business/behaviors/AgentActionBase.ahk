#Requires AutoHotkey v2.0

; 领域行为公共基类：Run 骨架 + 技术机制（LoadTemplate / Dispatch / OpenInTool）
; 原则：动作骨架用继承，外部能力用组合；业务组成留行为类，技术机制才外包

class AgentActionBase {

    ActionKey := ""
    LogTag => this.ActionKey   ; 日志标签 = 动作键：名字只写一遍（子类只写 ActionKey）
    Type := "ai"
    ; 异常兜底文案（各行为未覆盖时用这一对）
    FailLogText := "操作失败"
    FailFeedbackText := "操作失败"
    ; 前置校验未通过（如无 vN、步目无实施文档）时置 true：跳过 AutoHidePanel
    SkipAutoHide := false

    ; 模板方法骨架：守卫 → Execute → 自动隐藏
    Run(*) {
        try {
            if !ActionGuard.EnsureCurrentDirectory() {
                return
            }
            this.Execute()
            if !this.SkipAutoHide {
                AutoHidePanel()
            }
        } catch Error as err {
            LogError(this.FailLogText "：" err.Message)
            ShowFeedback(this.FailFeedbackText "：" err.Message, true)
        }
    }

    ; 变化点：由子类实现
    Execute() {
        throw Error("Execute 必须由子类实现")
    }

    ; ---- 纯技术：模板加载 ----
    LoadTemplate(fileName) {
        global TemplateDir
        path := TemplateDir "\" fileName
        if !FileExist(path) {
            LogError("模板文件不存在：" path)
            throw Error("模板文件不存在：" path)
        }
        return FileRead(path, "UTF-8")
    }

    ; ---- 纯技术：模板存在性检查（只检查不读取） ----
    EnsureTemplate(fileName) {
        global TemplateDir
        path := TemplateDir "\" fileName
        if !FileExist(path) {
            LogError("模板文件不存在：" path)
            throw Error("模板文件不存在：" path)
        }
    }

    ; ---- 纯技术：剪贴板 → 日志 → 反馈 → 发 Agent（保持旧调用顺序） ----
    Dispatch(content, properties, feedbackMsg) {
        A_Clipboard := content
        LogActivity(this.LogTag, content, properties)
        ShowFeedback(feedbackMsg)
        HandleAgentWindowAfterCopy()
    }

    ; ---- 纯技术：用编辑器打开（恒备：创建类行为完成后固定打开） ----
    OpenInTool(filePath) {
        EditorOpener.Open(filePath)
    }
}
