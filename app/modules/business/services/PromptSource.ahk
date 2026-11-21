#Requires AutoHotkey v2.0

; 新拼装的唯一入口：动作×策略 → 整份提示词
; 只做两件事：解析流程、调 PromptAssembler
; 依赖方向：business → promptflow（promptflow 不反向依赖本文件所在的层）
; 失败不回落：解析错、拼装错一律抛出，由 AgentActionBase.Run 的统一兜底处理

class PromptSource {

    ; 整份提示词
    static Build(actionKey, policyKey) {
        env := Environment.Of()
        r := FlowResolver.Resolve(env.TopicDir)

        if (r["status"] = "missing")
            throw Error("该主题指定的流程不存在：" r["flowKey"] "，请先切换流程")
        if (r["status"] = "broken-default")
            throw Error("默认流程不存在，请检查配置：" r["flowKey"])

        return PromptAssembler.Build(actionKey, policyKey, env)
    }
}

; 注入给 Environment：主题 → 流程 key
FlowKeyOf(topicDir) => FlowResolver.Resolve(topicDir)["flowKey"]
