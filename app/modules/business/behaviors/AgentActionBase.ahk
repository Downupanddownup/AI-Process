#Requires AutoHotkey v2.0

; 领域行为公共基类：Run 骨架 + 技术机制（LoadTemplate / Dispatch / OpenInTool）
; 阶段 1 空壳：方法签名就位，实现于步骤 02 填充

class AgentActionBase {

    ActionKey := ""
    LogTag := ""
    Type := "ai"

    ; 模板方法骨架：守卫 → Execute → 自动隐藏（阶段 2 填充）
    Run(*) {
        throw Error("未实现：阶段 2 填充")
    }

    ; 变化点：由子类实现
    Execute() {
        throw Error("Execute 必须由子类实现")
    }
}
