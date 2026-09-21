#Requires AutoHotkey v2.0

; 复盘模式注册表：答辩/技炼 的模式清单与选择
; 形态对齐 ExecuteStrategyRegistry

class ReviewModeRegistry {

    static Modes := [
        Map("key", "defense", "label", "答辩", "template", "review\defense.txt", "feedback", "答辩提示词已复制"),
        Map("key", "tech", "label", "技炼", "template", "review\tech.txt", "feedback", "技炼提示词已复制")
    ]

    ; 选项清单（下拉框用）
    static BuildOptions() {
        options := []
        for mode in ReviewModeRegistry.Modes {
            options.Push(mode["label"])
        }
        return options
    }

    ; 当前窗口选中的模式 key
    static GetSelected() {
        return GetSession(GetActiveWindowId(), "ReviewMode")
    }

    ; 按 key 取模式元数据；key 不认识时记一条日志再回退（不静默）
    static GetMeta(modeKey) {
        for mode in ReviewModeRegistry.Modes {
            if (mode["key"] = modeKey) {
                return mode
            }
        }
        fallback := ReviewModeRegistry.Modes[1]
        LogError("复盘模式 key 不认识：" modeKey "（回退到 " fallback["label"] "）")
        return fallback
    }
}
