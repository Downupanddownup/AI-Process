#Requires AutoHotkey v2.0

; 执行策略注册表：改吧/步目 策略清单与选择
; 逐行等价迁出（旧件已删）
; 命名说明：类名不用 ExecuteStrategies，避开历史重名（旧实现已删，此处仅留名）

class ExecuteStrategyRegistry {

    static Strategies := [
        Map("key", "tweak", "label", "改吧", "template", "execute\tweak.txt", "feedback", "改吧提示词已复制"),
        Map("key", "steps_dir", "label", "步目", "template", "execute\steps_dir.txt", "feedback", "步目提示词已复制")
    ]

    ; 选项清单（下拉框用）
    static BuildOptions() {
        options := []
        for strategy in ExecuteStrategyRegistry.Strategies {
            options.Push(strategy["label"])
        }
        return options
    }

    ; 当前窗口选中的策略 key
    static GetSelected() {
        return GetSession(GetActiveWindowId(), "ExecuteStrategy")
    }

    ; 按 key 取策略元数据；key 不认识时记一条日志再回退（不静默）
    static GetMeta(strategyKey) {
        for strategy in ExecuteStrategyRegistry.Strategies {
            if (strategy["key"] = strategyKey) {
                return strategy
            }
        }
        fallback := ExecuteStrategyRegistry.Strategies[1]
        LogError("执行策略 key 不认识：" strategyKey "（回退到 " fallback["label"] "）")
        return fallback
    }
}
