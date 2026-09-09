#Requires AutoHotkey v2.0

; 全局配置

global AppConfig := Map()
global SettingsFile := ConfigDir "\settings.ini"

; 确保默认文件和配置存在
EnsureDefaultFiles() {
    global ConfigDir, TemplateDir, SettingsFile
    DirCreate(ConfigDir)
    DirCreate(TemplateDir)
    executeTemplateDir := TemplateDir "\execute"
    DirCreate(executeTemplateDir)

    if !FileExist(SettingsFile) {
        ; 创建带 BOM 的 UTF-16 LE 空文件，确保后续 IniWrite 中文不乱码
        FileAppend("", SettingsFile, "UTF-16")
    }

    ; 确保 settings.ini 是 UTF-16 LE 带 BOM 格式
    EnsureIniUtf16Bom(SettingsFile)

    ; 写入默认配置
    if (IniRead(SettingsFile, "App", "Hotkey", "") = "") {
        IniWrite("F2", SettingsFile, "App", "Hotkey")
    }
    if (IniRead(SettingsFile, "Window", "Width", "") = "") {
        IniWrite("210", SettingsFile, "Window", "Width")
    }
    if (IniRead(SettingsFile, "Window", "Height", "") = "") {
        IniWrite("190", SettingsFile, "Window", "Height")
    }
    if (IniRead(SettingsFile, "Window", "PosX", "") = "") {
        IniWrite("", SettingsFile, "Window", "PosX")
    }
    if (IniRead(SettingsFile, "Window", "PosY", "") = "") {
        IniWrite("", SettingsFile, "Window", "PosY")
    }
    if (IniRead(SettingsFile, "Behavior", "AlwaysOnTop", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "AlwaysOnTop")
    }
    if (IniRead(SettingsFile, "Behavior", "StartVisible", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "StartVisible")
    }
    if (IniRead(SettingsFile, "Behavior", "CloseToTray", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "CloseToTray")
    }
    if (IniRead(SettingsFile, "Behavior", "MinimizeToTray", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "MinimizeToTray")
    }

    ; [PendingMd] 段：存储 MD 后台模式下待打开的 Markdown 文件路径
    if (IniRead(SettingsFile, "PendingMd", "Window1PendingMd", "__NOT_FOUND__") = "__NOT_FOUND__") {
        IniWrite("", SettingsFile, "PendingMd", "Window1PendingMd")
    }
    if (IniRead(SettingsFile, "PendingMd", "Window2PendingMd", "__NOT_FOUND__") = "__NOT_FOUND__") {
        IniWrite("", SettingsFile, "PendingMd", "Window2PendingMd")
    }
    if (IniRead(SettingsFile, "PendingMd", "Window3PendingMd", "__NOT_FOUND__") = "__NOT_FOUND__") {
        IniWrite("", SettingsFile, "PendingMd", "Window3PendingMd")
    }

    if (IniRead(SettingsFile, "Editor", "IdeaCommand", "") = "") {
        IniWrite("idea64.exe", SettingsFile, "Editor", "IdeaCommand")
    }

    ; [Report] 段：报告生成相关配置
    if (IniRead(SettingsFile, "Report", "IdleThresholdMinutes", "") = "") {
        IniWrite("60", SettingsFile, "Report", "IdleThresholdMinutes")
    }

    ; [FileTool] 首次迁移：旧 IdeaCommand → filetools.json
    toolsFile := ConfigDir "\filetools.json"
    if (!FileExist(toolsFile) && IniRead(SettingsFile, "Editor", "IdeaCommand", "") != "") {
        MigrateFromIdeaCommand()
    }

    ; [Hotkey] 段
    if (IniRead(SettingsFile, "Hotkey", "Window1Hotkey", "") = "") {
        IniWrite("F2", SettingsFile, "Hotkey", "Window1Hotkey")
    }
    if (IniRead(SettingsFile, "Hotkey", "Window2Hotkey", "") = "") {
        IniWrite("F3", SettingsFile, "Hotkey", "Window2Hotkey")
    }
    if (IniRead(SettingsFile, "Hotkey", "EnableWindow2", "") = "") {
        IniWrite("0", SettingsFile, "Hotkey", "EnableWindow2")
    }
    if (IniRead(SettingsFile, "Hotkey", "Window3Hotkey", "") = "") {
        IniWrite("F4", SettingsFile, "Hotkey", "Window3Hotkey")
    }
    if (IniRead(SettingsFile, "Hotkey", "EnableWindow3", "") = "") {
        IniWrite("0", SettingsFile, "Hotkey", "EnableWindow3")
    }

    ; [Window1] 段
    if (IniRead(SettingsFile, "Window1", "CurrentDir", "") = "") {
        IniWrite("", SettingsFile, "Window1", "CurrentDir")
    }
    if (IniRead(SettingsFile, "Window1", "AgentTitleContains", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentTitleContains")
    }
    if (IniRead(SettingsFile, "Window1", "AgentProcessName", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentProcessName")
    }
    if (IniRead(SettingsFile, "Window1", "AgentClassName", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentClassName")
    }
    if (IniRead(SettingsFile, "Window1", "AgentHwnd", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentHwnd")
    }
    if (IniRead(SettingsFile, "Window1", "AgentName", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentName")
    }
    if (IniRead(SettingsFile, "Window1", "AgentAfterCopyAction", "") = "") {
        IniWrite("3", SettingsFile, "Window1", "AgentAfterCopyAction")
    }
    if (IniRead(SettingsFile, "Window1", "AppendImplementationTail", "") = "") {
        IniWrite("1", SettingsFile, "Window1", "AppendImplementationTail")
    }
    if (IniRead(SettingsFile, "Window1", "ExecuteStrategy", "") = "") {
        IniWrite("tweak", SettingsFile, "Window1", "ExecuteStrategy")
    }

    ; [Window2] 段
    if (IniRead(SettingsFile, "Window2", "CurrentDir", "") = "") {
        IniWrite("", SettingsFile, "Window2", "CurrentDir")
    }
    if (IniRead(SettingsFile, "Window2", "AgentTitleContains", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentTitleContains")
    }
    if (IniRead(SettingsFile, "Window2", "AgentProcessName", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentProcessName")
    }
    if (IniRead(SettingsFile, "Window2", "AgentClassName", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentClassName")
    }
    if (IniRead(SettingsFile, "Window2", "AgentHwnd", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentHwnd")
    }
    if (IniRead(SettingsFile, "Window2", "AgentName", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentName")
    }
    if (IniRead(SettingsFile, "Window2", "AgentAfterCopyAction", "") = "") {
        IniWrite("3", SettingsFile, "Window2", "AgentAfterCopyAction")
    }
    if (IniRead(SettingsFile, "Window2", "AppendImplementationTail", "") = "") {
        IniWrite("1", SettingsFile, "Window2", "AppendImplementationTail")
    }
    if (IniRead(SettingsFile, "Window2", "ExecuteStrategy", "") = "") {
        IniWrite("tweak", SettingsFile, "Window2", "ExecuteStrategy")
    }

    ; [Window3] 段
    if (IniRead(SettingsFile, "Window3", "CurrentDir", "") = "") {
        IniWrite("", SettingsFile, "Window3", "CurrentDir")
    }
    if (IniRead(SettingsFile, "Window3", "AgentTitleContains", "") = "") {
        IniWrite("", SettingsFile, "Window3", "AgentTitleContains")
    }
    if (IniRead(SettingsFile, "Window3", "AgentProcessName", "") = "") {
        IniWrite("", SettingsFile, "Window3", "AgentProcessName")
    }
    if (IniRead(SettingsFile, "Window3", "AgentClassName", "") = "") {
        IniWrite("", SettingsFile, "Window3", "AgentClassName")
    }
    if (IniRead(SettingsFile, "Window3", "AgentHwnd", "") = "") {
        IniWrite("", SettingsFile, "Window3", "AgentHwnd")
    }
    if (IniRead(SettingsFile, "Window3", "AgentName", "") = "") {
        IniWrite("", SettingsFile, "Window3", "AgentName")
    }
    if (IniRead(SettingsFile, "Window3", "AgentAfterCopyAction", "") = "") {
        IniWrite("3", SettingsFile, "Window3", "AgentAfterCopyAction")
    }
    if (IniRead(SettingsFile, "Window3", "AppendImplementationTail", "") = "") {
        IniWrite("1", SettingsFile, "Window3", "AppendImplementationTail")
    }
    if (IniRead(SettingsFile, "Window3", "ExecuteStrategy", "") = "") {
        IniWrite("tweak", SettingsFile, "Window3", "ExecuteStrategy")
    }

    ; [SummaryAgent] 段：经验总结窗口专用 Agent 绑定配置
    if (IniRead(SettingsFile, "SummaryAgent", "AgentTitleContains", "__NOT_FOUND__") = "__NOT_FOUND__") {
        IniWrite("", SettingsFile, "SummaryAgent", "AgentTitleContains")
        IniWrite("", SettingsFile, "SummaryAgent", "AgentProcessName")
        IniWrite("", SettingsFile, "SummaryAgent", "AgentClassName")
        IniWrite("", SettingsFile, "SummaryAgent", "AgentHwnd")
        IniWrite("4", SettingsFile, "SummaryAgent", "AgentAfterCopyAction")
    }

}

; 加载配置
LoadConfig() {
    global AppConfig, SettingsFile, AppRoot
    AppConfig := Map()
    AppConfig["Hotkey"] := IniRead(SettingsFile, "App", "Hotkey", "F2")
    AppConfig["IconSource"] := IniRead(SettingsFile, "App", "IconSource", "shell32.dll")
    AppConfig["IconIndex"] := IniRead(SettingsFile, "App", "IconIndex", "44") + 0
    AppConfig["WindowWidth"] := IniRead(SettingsFile, "Window", "Width", "210") + 0
    AppConfig["WindowHeight"] := IniRead(SettingsFile, "Window", "Height", "150") + 0
    if (AppConfig["WindowHeight"] < 190) {
        AppConfig["WindowHeight"] := 190
    }
    AppConfig["WindowPosX"] := IniRead(SettingsFile, "Window", "PosX", "")
    AppConfig["WindowPosY"] := IniRead(SettingsFile, "Window", "PosY", "")
    LoadHotkeyConfig()
    LoadWindowSessions()
    AppConfig["AlwaysOnTop"] := IniRead(SettingsFile, "Behavior", "AlwaysOnTop", "1") = "1"
    AppConfig["StartVisible"] := IniRead(SettingsFile, "Behavior", "StartVisible", "1") = "1"
    AppConfig["CloseToTray"] := IniRead(SettingsFile, "Behavior", "CloseToTray", "1") = "1"
    AppConfig["MinimizeToTray"] := IniRead(SettingsFile, "Behavior", "MinimizeToTray", "1") = "1"
    AppConfig["OpenMdScriptPath"] := AppRoot "\powershell\markdown\OpenMarkdown.ps1"
    AppConfig["NotificationScriptPath"] := AppRoot "\powershell\notification\ShowCenterNotification.ps1"
    AppConfig["FileToolPath"] := IniRead(SettingsFile, "FileTool", "FileToolPath", "")
    AppConfig["IdleThresholdMinutes"] := IniRead(SettingsFile, "Report", "IdleThresholdMinutes", "60") + 0
}

; 加载热键配置
LoadHotkeyConfig() {
    global AppConfig, SettingsFile
    AppConfig["Window1Hotkey"] := IniRead(SettingsFile, "Hotkey", "Window1Hotkey", "F2")
    AppConfig["Window2Hotkey"] := IniRead(SettingsFile, "Hotkey", "Window2Hotkey", "F3")
    AppConfig["Window3Hotkey"] := IniRead(SettingsFile, "Hotkey", "Window3Hotkey", "F4")
    AppConfig["EnableWindow2"] := IniRead(SettingsFile, "Hotkey", "EnableWindow2", "0") = "1"
    AppConfig["EnableWindow3"] := IniRead(SettingsFile, "Hotkey", "EnableWindow3", "0") = "1"
}

; 加载各窗口会话数据
LoadWindowSessions() {
    global WindowSessions, SettingsFile
    for windowId in [1, 2, 3] {
        section := "Window" windowId
        WindowSessions[windowId]["CurrentDir"] := IniRead(SettingsFile, section, "CurrentDir", "")
        WindowSessions[windowId]["AgentTitleContains"] := IniRead(SettingsFile, section, "AgentTitleContains", "")
        WindowSessions[windowId]["AgentProcessName"] := IniRead(SettingsFile, section, "AgentProcessName", "")
        WindowSessions[windowId]["AgentClassName"] := IniRead(SettingsFile, section, "AgentClassName", "")
        WindowSessions[windowId]["AgentHwnd"] := IniRead(SettingsFile, section, "AgentHwnd", "")
        WindowSessions[windowId]["AgentName"] := IniRead(SettingsFile, section, "AgentName", "")
        WindowSessions[windowId]["AgentAfterCopyAction"] := IniRead(SettingsFile, section, "AgentAfterCopyAction", "3") + 0
        WindowSessions[windowId]["AppendImplementationTail"] := IniRead(SettingsFile, section, "AppendImplementationTail", "1") = "1"
        WindowSessions[windowId]["ExecuteStrategy"] := IniRead(SettingsFile, section, "ExecuteStrategy", "tweak")
    }
}

; 带重试的配置写入：settings.ini 会被 PowerShell 侧（日志/打标/通知）并发读写，
; 偶发文件占用（Error 32）重试即可恢复；重试仍失败则静默跳过——丢失一次配置保存可接受，崩溃不可接受
SafeIniWrite(value, fileName, section, key) {
    Loop 3 {
        try {
            IniWrite(value, fileName, section, key)
            return true
        } catch {
            if (A_Index < 3) {
                Sleep(120)
            }
        }
    }
    return false
}

; 保存指定窗口的会话数据
SaveWindowSession(windowId) {
    global WindowSessions, SettingsFile
    section := "Window" windowId
    SafeIniWrite(WindowSessions[windowId]["CurrentDir"], SettingsFile, section, "CurrentDir")
    SafeIniWrite(WindowSessions[windowId]["AgentTitleContains"], SettingsFile, section, "AgentTitleContains")
    SafeIniWrite(WindowSessions[windowId]["AgentProcessName"], SettingsFile, section, "AgentProcessName")
    SafeIniWrite(WindowSessions[windowId]["AgentClassName"], SettingsFile, section, "AgentClassName")
    SafeIniWrite(WindowSessions[windowId]["AgentHwnd"], SettingsFile, section, "AgentHwnd")
    SafeIniWrite(WindowSessions[windowId]["AgentName"], SettingsFile, section, "AgentName")
    SafeIniWrite(WindowSessions[windowId]["AgentAfterCopyAction"], SettingsFile, section, "AgentAfterCopyAction")
    SafeIniWrite(WindowSessions[windowId]["AppendImplementationTail"] ? "1" : "0", SettingsFile, section, "AppendImplementationTail")
    SafeIniWrite(WindowSessions[windowId]["ExecuteStrategy"], SettingsFile, section, "ExecuteStrategy")
}

; 保存窗口位置到配置文件，并同步更新 AppConfig
SaveWindowPositionToConfig(x, y) {
    global SettingsFile, AppConfig
    SafeIniWrite(x, SettingsFile, "Window", "PosX")
    SafeIniWrite(y, SettingsFile, "Window", "PosY")
    AppConfig["WindowPosX"] := x
    AppConfig["WindowPosY"] := y
}

; 保存 2 号窗口启用状态
SaveEnableWindow2(enabled) {
    global SettingsFile
    SafeIniWrite(enabled ? "1" : "0", SettingsFile, "Hotkey", "EnableWindow2")
}

; 保存 3 号窗口启用状态
SaveEnableWindow3(enabled) {
    global SettingsFile
    SafeIniWrite(enabled ? "1" : "0", SettingsFile, "Hotkey", "EnableWindow3")
}

; 确保 INI 文件使用 UTF-16 LE 带 BOM 格式，避免中文乱码
EnsureIniUtf16Bom(filePath) {
    ; 读取文件前几个字节判断是否有 UTF-16 LE BOM (FF FE)
    try {
        raw := FileRead(filePath, "RAW")
        if (raw.Length >= 2 && raw[1] = 0xFF && raw[2] = 0xFE) {
            return  ; 已经是 UTF-16 LE BOM
        }
    } catch {
        return
    }

    ; 读取当前内容（按系统默认编码），重新写入为 UTF-16 LE 带 BOM
    try {
        text := FileRead(filePath)
        FileDelete(filePath)
        FileAppend(text, filePath, "UTF-16")
    } catch {
        ; 忽略转换失败
    }
}
