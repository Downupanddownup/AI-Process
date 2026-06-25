#Requires AutoHotkey v2.0

; 窗口样式管理：集中管理各窗口的视觉样式

global WindowStyles := Map(
    1, Map(
        "Title", "一窗",
        "BackColor", "F5F5F5"
    ),
    2, Map(
        "Title", "二窗",
        "BackColor", "E2D9F2"
    ),
    3, Map(
        "Title", "三窗",
        "BackColor", "D0E8DA"
    )
)

; 按钮样式配置
global ButtonStyle := Map(
    "Border", true
)

; 获取指定窗口的样式配置 Map
GetWindowStyle(windowId) {
    global WindowStyles
    if (!WindowStyles.Has(windowId)) {
        return WindowStyles[1]
    }
    return WindowStyles[windowId]
}

; 应用样式到主窗口
ApplyMainWindowStyle(windowId, mainGui) {
    style := GetWindowStyle(windowId)
    mainGui.Title := style["Title"]
    mainGui.BackColor := style["BackColor"]
}

; 应用按钮样式
ApplyButtonStyle(ctrl) {
    global ButtonStyle
    if (!ctrl) {
        return
    }
    if (ButtonStyle["Border"]) {
        ctrl.Opt("+Border")
    } else {
        ctrl.Opt("-Border")
    }
}
