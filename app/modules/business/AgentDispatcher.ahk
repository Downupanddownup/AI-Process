#Requires AutoHotkey v2.0

; AgentDispatcher.ahk
; 通用 Agent 绑定、激活、发送模块
; 不依赖 WindowSessions，直接读写 settings.ini 中指定配置段

global AgentDispatcherSettingsFile := ConfigDir "\settings.ini"

; 读取指定配置段的 Agent 配置
AgentDispatcherGetConfig(agentConfigKey) {
    global AgentDispatcherSettingsFile
    section := agentConfigKey
    return Map(
        "TitleContains", IniRead(AgentDispatcherSettingsFile, section, "AgentTitleContains", ""),
        "ProcessName", IniRead(AgentDispatcherSettingsFile, section, "AgentProcessName", ""),
        "ClassName", IniRead(AgentDispatcherSettingsFile, section, "AgentClassName", ""),
        "Hwnd", IniRead(AgentDispatcherSettingsFile, section, "AgentHwnd", ""),
        "AfterCopyAction", IniRead(AgentDispatcherSettingsFile, section, "AgentAfterCopyAction", "4") + 0
    )
}

; 保存指定配置段的 Agent 配置
AgentDispatcherSetConfig(agentConfigKey, config) {
    global AgentDispatcherSettingsFile
    section := agentConfigKey
    IniWrite(config["TitleContains"], AgentDispatcherSettingsFile, section, "AgentTitleContains")
    IniWrite(config["ProcessName"], AgentDispatcherSettingsFile, section, "AgentProcessName")
    IniWrite(config["ClassName"], AgentDispatcherSettingsFile, section, "AgentClassName")
    IniWrite(config["Hwnd"], AgentDispatcherSettingsFile, section, "AgentHwnd")
    IniWrite(config["AfterCopyAction"], AgentDispatcherSettingsFile, section, "AgentAfterCopyAction")
}

; 获取绑定状态
AgentDispatcherGetStatus(agentConfigKey) {
    config := AgentDispatcherGetConfig(agentConfigKey)
    isBound := config["ProcessName"] != "" && config["ClassName"] != ""
    hwnd := AgentDispatcherFindWindow(agentConfigKey)
    return Map(
        "IsBound", isBound,
        "IsOnline", hwnd != 0,
        "TitleContains", config["TitleContains"],
        "ProcessName", config["ProcessName"],
        "ClassName", config["ClassName"],
        "Hwnd", config["Hwnd"],
        "AfterCopyAction", config["AfterCopyAction"]
    )
}

; 绑定当前活动窗口到指定配置段
AgentDispatcherBind(agentConfigKey) {
    hwnd := WinGetID("A")
    if (!hwnd) {
        return Map("Success", false, "Message", "无窗口")
    }

    title := WinGetTitle(hwnd)
    title := RegExReplace(title, "^[^\p{L}\p{N}]+")
    title := RegExReplace(title, "[^\p{L}\p{N}]$")

    proc := WinGetProcessName(hwnd)
    class := WinGetClass(hwnd)

    if (class = "Progman" || class = "WorkerW" || class = "Shell_TrayWnd") {
        return Map("Success", false, "Message", "无效窗口")
    }
    if (InStr(title, "AIProcess") != 0 || proc = "AutoHotkey.exe" || proc = "AutoHotkey64.exe") {
        return Map("Success", false, "Message", "不能绑定自身")
    }
    if (title = "" || proc = "" || class = "") {
        return Map("Success", false, "Message", "绑定失败")
    }

    config := AgentDispatcherGetConfig(agentConfigKey)
    config["TitleContains"] := title
    config["ProcessName"] := proc
    config["ClassName"] := class
    config["Hwnd"] := hwnd
    if (config["AfterCopyAction"] < 1 || config["AfterCopyAction"] > 4) {
        config["AfterCopyAction"] := 4
    }
    AgentDispatcherSetConfig(agentConfigKey, config)

    return Map("Success", true, "Message", "绑定成功", "Title", title, "Process", proc, "Hwnd", hwnd)
}

; 解绑指定配置段
AgentDispatcherUnbind(agentConfigKey) {
    config := AgentDispatcherGetConfig(agentConfigKey)
    config["TitleContains"] := ""
    config["ProcessName"] := ""
    config["ClassName"] := ""
    config["Hwnd"] := ""
    config["AfterCopyAction"] := 4
    AgentDispatcherSetConfig(agentConfigKey, config)
}

; 查找已绑定的窗口，返回 HWND
AgentDispatcherFindWindow(agentConfigKey) {
    config := AgentDispatcherGetConfig(agentConfigKey)
    titleContains := config["TitleContains"]
    procName := config["ProcessName"]
    className := config["ClassName"]
    storedHwnd := config["Hwnd"]

    if (procName = "" || className = "") {
        return 0
    }

    hwnd := 0

    ; 阶段一：HWND 优先
    if (storedHwnd != "") {
        hwnd := WinExist("ahk_id " storedHwnd)
        if (hwnd) {
            try {
                currentProc := WinGetProcessName(hwnd)
                currentClass := WinGetClass(hwnd)
                if (currentProc = procName && currentClass = className) {
                    return hwnd
                }
            } catch {
                hwnd := 0
            }
        }
        hwnd := 0
    }

    ; 阶段二：兜底规则
    DetectHiddenWindows(true)
    ids := WinGetList("ahk_exe " procName " ahk_class " className)
    for id in ids {
        title := WinGetTitle(id)
        if (hwnd = 0) {
            if (titleContains = "" || InStr(title, titleContains) || title = "") {
                hwnd := id
                ; 兜底命中后更新 HWND
                config["Hwnd"] := hwnd
                AgentDispatcherSetConfig(agentConfigKey, config)
            }
        }
    }
    DetectHiddenWindows(false)

    return hwnd
}

; 激活已绑定的窗口
AgentDispatcherActivate(agentConfigKey) {
    hwnd := AgentDispatcherFindWindow(agentConfigKey)
    if (!hwnd) {
        return false
    }
    WinActivate(hwnd)
    return true
}

; 向已绑定的 Agent 发送内容
AgentDispatcherSend(agentConfigKey, content) {
    hwnd := AgentDispatcherFindWindow(agentConfigKey)
    if (!hwnd) {
        return Map("Success", false, "Message", "未找到绑定的 Agent 窗口")
    }

    config := AgentDispatcherGetConfig(agentConfigKey)
    action := config["AfterCopyAction"]
    if (action < 1 || action > 4) {
        action := 4
    }

    if (action <= 1) {
        return Map("Success", true, "Message", "已设置为不操作")
    }

    A_Clipboard := content
    WinActivate(hwnd)

    if (action >= 3) {
        Send "^v"
        Sleep 150
    }

    if (action >= 4) {
        Send "{Enter}"
    }

    return Map("Success", true, "Message", "已发送")
}
