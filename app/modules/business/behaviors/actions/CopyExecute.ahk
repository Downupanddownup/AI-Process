#Requires AutoHotkey v2.0

; 复执行（AI 型）：复制执行指令并发送 AI（改吧/步目 两策略分支）
; 迁移自 PromptManager.CopyExecutePrompt（:285），逐行等价
; 分支语义：改吧 = 模板自带结束指令、不追加尾部；步目 = 须实施文档存在、追加执行通知（-Silent 随「完成通知」开关）

class CopyExecute extends AgentActionBase {
    ActionKey := "复执行"
    LogTag := "复执行"
    Type := "ai"
    FailLogText := "执行提示词复制失败"
    FailFeedbackText := "执行提示词复制失败"

    Execute() {
        global AppConfig, TemplateDir
        chain := VersionChain.Of(GetCurrentDir())
        selectedStrategy := ExecuteStrategyRegistry.GetSelected()
        strategyMeta := ExecuteStrategyRegistry.GetMeta(selectedStrategy)

        if (selectedStrategy = "tweak") {
            ; "改吧"策略：结果文档由 AI 按模板撰写，结果名 = 有实施文档→已实施.md 否则 v(N+1).md
            resultName := chain.ResultName()
            content := this.LoadTemplate(strategyMeta["template"])
            content := StrReplace(content, "{{resultFilePath}}", chain.Dir "\" resultName)
            this.EnsureTemplate("execute\result_doc.md")
            content := StrReplace(content, "{{resultTemplatePath}}", TemplateDir "\execute\result_doc.md")
            content := StrReplace(content, "{{openMdScriptPath}}", AppConfig["OpenMdScriptPath"])
            content := StrReplace(content, "{{windowId}}", GetActiveWindowId())
        } else {
            ; 步目策略：必须存在实施文档.md
            implementationPath := chain.ImplDocPath()
            if !FileExist(implementationPath) {
                ShowFeedback("当前目录下未找到 实施文档.md", true)
                this.SkipAutoHide := true  ; 对齐旧函数提前 return：不触发自动隐藏
                return
            }
            content := this.LoadTemplate(strategyMeta["template"])
            content := StrReplace(content, "{{filePath}}", implementationPath)
        }

        if (selectedStrategy != "tweak") {
            content := PromptElements.ExecuteNotification(content)
        }

        properties := Map("执行策略", strategyMeta["label"])
        if (selectedStrategy = "tweak") {
            ; 改吧会产出结果 md：target 复用上面已算出的 resultName
            properties["target"] := resultName
        }

        this.Dispatch(content, properties, strategyMeta["feedback"])
    }
}
