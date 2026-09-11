#Requires AutoHotkey v2.0

; 复执行（AI 型）：复制执行指令并发送 AI（改吧/步目 两策略分支）
; 迁移自 PromptManager.CopyExecutePrompt（:285），逐行等价
; 分支语义：改吧 = 不校验前置；步目 = 须实施文档存在；两条策略都由模板自带"打开结果文档"的结束指令，不再追加尾部

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

        ; 两条策略都产出结果文档：有实施文档 → 已实施.md，否则 v(N+1).md
        resultName := chain.ResultName()
        resultTemplateFile := "execute\result_doc.md"
        if (selectedStrategy != "tweak") {
            resultTemplateFile := "execute\steps_result_doc.md"
        }

        if (selectedStrategy = "tweak") {
            content := this.LoadTemplate(strategyMeta["template"])
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

        ; 两条策略共有：结果文档路径 / 结果模板路径 / 打开脚本 / 窗口号
        this.EnsureTemplate(resultTemplateFile)
        content := StrReplace(content, "{{resultFilePath}}", chain.Dir "\" resultName)
        content := StrReplace(content, "{{resultTemplatePath}}", TemplateDir "\" resultTemplateFile)
        content := StrReplace(content, "{{openMdScriptPath}}", AppConfig["OpenMdScriptPath"])
        content := StrReplace(content, "{{windowId}}", GetActiveWindowId())

        ; 结果 md 的 target：统计靠它把这一轮纳入轮次明细（两条策略一致）
        properties := Map("执行策略", strategyMeta["label"])
        properties["target"] := resultName

        this.Dispatch(content, properties, strategyMeta["feedback"])
    }
}
