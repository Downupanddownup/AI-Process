#Requires AutoHotkey v2.0

; 复执行（AI 型）：复制执行指令并发送 AI（改吧 / 步目 两策略）
; 提示词由 PromptSource 统一拼装；本类只负责守卫、properties 与发送

class CopyExecute extends AgentActionBase {
    ActionKey := "复执行"
    Type := "ai"
    FailLogText := "执行提示词复制失败"
    FailFeedbackText := "执行提示词复制失败"

    Execute() {
        chain := VersionChain.Of(GetCurrentDir())
        selectedStrategy := ExecuteStrategyRegistry.GetSelected()
        strategyMeta := ExecuteStrategyRegistry.GetMeta(selectedStrategy)

        ; 两条策略都产出结果文档：有实施文档 → 已实施.md，否则 v(N+1).md
        resultName := chain.ResultName()

        ; 步目：依据三档（实施文档 → 最新回复 → 最新版本文档）
        ; 守卫必须在发送前：不满足时提示并保留面板，而不是让拼装抛错后被打包成"执行失败"
        if (selectedStrategy != "tweak" && chain.StepsSource() = "") {
            ShowFeedback("步目需要实施文档、最新回复或版本文档作为拆分依据，当前都没有", true)
            this.SkipAutoHide := true  ; 前置校验未通过：不触发自动隐藏
            return
        }

        content := PromptSource.Build("复执行", selectedStrategy)

        ; 结果 md 的 target：统计靠它把这一轮纳入轮次明细（两条策略一致）
        properties := Map("执行策略", strategyMeta["label"])
        properties["target"] := resultName

        this.Dispatch(content, properties, strategyMeta["feedback"])
    }
}
