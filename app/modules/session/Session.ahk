#Requires AutoHotkey v2.0

; 窗口级运行时状态

; 临时保留，待业务模块全部迁移到 Session 接口后移除
global CurrentDir := ""

; 多窗口会话数据
global WindowSessions := Map(
    1, Map(
        "CurrentDir", "",
        "AgentTitleContains", "",
        "AgentProcessName", "",
        "AgentClassName", "",
        "AgentAfterCopyAction", 3,
        "OpenWithIdea", true,
        "OpenMdWithIdea", true,
        "AppendNoModifyPrompt", true,
        "AutoHideAfterCreate", false,
        "AppendImplementationTail", true,
        "ExecuteStrategy", "ai_judge",
        "ShowExecuteNotification", false
    ),
    2, Map(
        "CurrentDir", "",
        "AgentTitleContains", "",
        "AgentProcessName", "",
        "AgentClassName", "",
        "AgentAfterCopyAction", 3,
        "OpenWithIdea", true,
        "OpenMdWithIdea", true,
        "AppendNoModifyPrompt", true,
        "AutoHideAfterCreate", false,
        "AppendImplementationTail", true,
        "ExecuteStrategy", "ai_judge",
        "ShowExecuteNotification", false
    )
)

; 当前激活的窗口编号
global ActiveWindowId := 1

; 获取指定窗口的会话值
GetSession(windowId, key) {
    global WindowSessions
    if (!WindowSessions.Has(windowId) || !WindowSessions[windowId].Has(key)) {
        return ""
    }
    return WindowSessions[windowId][key]
}

; 设置指定窗口的会话值
SetSession(windowId, key, value) {
    global WindowSessions
    if (!WindowSessions.Has(windowId)) {
        return
    }
    WindowSessions[windowId][key] := value
}

; 获取当前窗口编号
GetActiveWindowId() {
    global ActiveWindowId
    return ActiveWindowId
}

; 设置当前窗口编号
SetActiveWindowId(windowId) {
    global ActiveWindowId
    ActiveWindowId := windowId
}

; 便捷访问当前窗口 CurrentDir
GetCurrentDir() {
    return GetSession(GetActiveWindowId(), "CurrentDir")
}

SetCurrentDir(dirPath) {
    global CurrentDir
    SetSession(GetActiveWindowId(), "CurrentDir", dirPath)
    ; 临时同步到旧变量，保证业务模块迁移期间的兼容性
    CurrentDir := dirPath
}

; 便捷访问当前窗口 Agent 配置
GetCurrentAgentConfig() {
    windowId := GetActiveWindowId()
    return Map(
        "TitleContains", GetSession(windowId, "AgentTitleContains"),
        "ProcessName", GetSession(windowId, "AgentProcessName"),
        "ClassName", GetSession(windowId, "AgentClassName"),
        "AfterCopyAction", GetSession(windowId, "AgentAfterCopyAction")
    )
}
