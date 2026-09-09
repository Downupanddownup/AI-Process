#Requires AutoHotkey v2.0

; 执行策略注册表：改吧/步目 策略清单与选择
; 收编自 PromptManager 的 ExecuteStrategies 全局数据与三个函数，逐行等价
; 命名说明：不叫 ExecuteStrategies，因 PromptManager 已有同名全局变量（并行期冲突，步骤 08 删旧后不回收该名）

class ExecuteStrategyRegistry {

    static Strategies := [
        Map("key", "tweak", "label", "改吧", "template", "execute\tweak.txt", "feedback", "改吧提示词已复制"),
        Map("key", "steps_dir", "label", "步目", "template", "execute\steps_dir.txt", "feedback", "步目提示词已复制")
    ]

    ; = 原 BuildExecuteStrategyOptions
    static BuildOptions() {
        options := []
        for strategy in ExecuteStrategyRegistry.Strategies {
            options.Push(strategy["label"])
        }
        return options
    }

    ; = 原 GetSelectedExecuteStrategy
    static GetSelected() {
        return GetSession(GetActiveWindowId(), "ExecuteStrategy")
    }

    ; = 原 GetExecuteStrategyMeta
    static GetMeta(strategyKey) {
        for strategy in ExecuteStrategyRegistry.Strategies {
            if (strategy["key"] = strategyKey) {
                return strategy
            }
        }
        return ExecuteStrategyRegistry.Strategies[1]
    }
}
