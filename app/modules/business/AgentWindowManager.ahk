#Requires AutoHotkey v2.0

; Agent 窗口绑定与管理

global AgentWindowDialog := ""
global AgentWindowDialogTitleText := ""
global AgentWindowDialogProcessText := ""
global AgentWindowDialogClassText := ""
global AgentWindowDialogStatusText := ""
global AgentWindowDialogActionDropdown := ""

OnBindAgentWindowButtonClick(*) {
    if (IsAgentWindowBound()) {
        ShowAgentWindowDialog()
    } else {
        StartBindAgentWindow()
    }
}



StartBindAgentWindow() {
    global MainGui
    if (MainGui) {
        MainGui.Hide()
    }
    SetTimer(DoBindAgentWindow, -500)
}



DoBindAgentWindow() {
    BindAgentWindow()
    ShowMainWindow()
}



BindAgentWindow(*) {
    global AppConfig, BindAgentWindowButton

    hwnd := WinGetID("A")
    if (!hwnd) {
        FlashBindButtonError("无窗口")
        return
    }

    title := WinGetTitle(hwnd)
    ; 去掉标题开头和结尾的特殊字符，避免 Windows Terminal 图标变化导致匹配失败
    title := RegExReplace(title, "^[^\p{L}\p{N}]+")
    title := RegExReplace(title, "[^\p{L}\p{N}]+$")

    proc := WinGetProcessName(hwnd)
    class := WinGetClass(hwnd)

    if (class = "Progman" || class = "WorkerW" || class = "Shell_TrayWnd") {
        FlashBindButtonError("无效窗口")
        return
    }
    if (InStr(title, "AIProcess") != 0 || proc = "AutoHotkey.exe" || proc = "AutoHotkey64.exe") {
        FlashBindButtonError("不能绑定自身")
        return
    }
    if (title = "" || proc = "" || class = "") {
        FlashBindButtonError("绑定失败")
        return
    }

    AppConfig["AgentWindowTitleContains"] := title
    AppConfig["AgentWindowProcessName"] := proc
    AppConfig["AgentWindowClassName"] := class
    SaveAgentWindowConfig()
    UpdateBindButtonState()
}



IsAgentWindowBound() {
    global AppConfig
    return AppConfig["AgentWindowProcessName"] != "" && AppConfig["AgentWindowClassName"] != ""
}



UpdateBindButtonState() {
    global BindAgentWindowButton, UnbindAgentWindowButton
    if (!BindAgentWindowButton || !UnbindAgentWindowButton) {
        return
    }
    if (IsAgentWindowBound()) {
        BindAgentWindowButton.Text := "已绑定"
        UnbindAgentWindowButton.Visible := true
    } else {
        BindAgentWindowButton.Text := "绑窗口"
        UnbindAgentWindowButton.Visible := false
    }
}



FlashBindButtonError(message) {
    global BindAgentWindowButton
    if (!BindAgentWindowButton) {
        return
    }
    originalText := BindAgentWindowButton.Text
    BindAgentWindowButton.Text := message
    SetTimer(() => BindAgentWindowButton.Text := originalText, -1000)
}



SaveAgentWindowConfig() {
    global AppConfig, SettingsFile
    IniWrite(AppConfig["AgentWindowTitleContains"], SettingsFile, "AgentWindow", "TitleContains")
    IniWrite(AppConfig["AgentWindowProcessName"], SettingsFile, "AgentWindow", "ProcessName")
    IniWrite(AppConfig["AgentWindowClassName"], SettingsFile, "AgentWindow", "ClassName")
    IniWrite(AppConfig["AgentWindowAfterCopyAction"], SettingsFile, "AgentWindow", "AfterCopyAction")
}



ShowAgentWindowDialog() {
    global AgentWindowDialog, AppConfig
    global AgentWindowDialogTitleText, AgentWindowDialogProcessText
    global AgentWindowDialogClassText, AgentWindowDialogStatusText
    global AgentWindowDialogActionDropdown

    if (AgentWindowDialog) {
        RefreshAgentWindowDialog()
        AgentWindowDialog.Show()
        WinActivate("ahk_id " AgentWindowDialog.Hwnd)
        return
    }

    AgentWindowDialog := Gui("+AlwaysOnTop +ToolWindow", "Agent 窗口管理")
    AgentWindowDialog.BackColor := "F7F7F7"
    AgentWindowDialog.MarginX := 12
    AgentWindowDialog.MarginY := 10
    AgentWindowDialog.SetFont("s8", "Microsoft YaHei UI")
    AgentWindowDialog.OnEvent("Close", CloseAgentWindowDialog)
    AgentWindowDialog.OnEvent("Escape", CloseAgentWindowDialog)

    AgentWindowDialog.AddText("xm ym w300 h18", "当前绑定")
    AgentWindowDialogTitleText := AgentWindowDialog.AddText("xm y+4 w300 h18", "窗口标题：未绑定")
    AgentWindowDialogProcessText := AgentWindowDialog.AddText("xm y+4 w300 h18", "进程：未绑定")
    AgentWindowDialogClassText := AgentWindowDialog.AddText("xm y+4 w300 h18", "类名：未绑定")
    AgentWindowDialogStatusText := AgentWindowDialog.AddText("xm y+4 w300 h18", "状态：未绑定")

    unbindButton := AgentWindowDialog.AddButton("xm y+10 w80 h24", "解绑")
    unbindButton.OnEvent("Click", AgentDialogUnbind)

    testButton := AgentWindowDialog.AddButton("x+8 yp w80 h24", "测试激活")
    testButton.OnEvent("Click", AgentDialogTestActivate)

    AgentWindowDialog.AddText("xm y+14 w300 h18", "复制提示词后")
    AgentWindowDialogActionDropdown := AgentWindowDialog.AddDropDownList("xm y+4 w120", ["不操作", "仅激活", "激活并粘贴", "激活粘贴并发送"])
    AgentWindowDialogActionDropdown.OnEvent("Change", AgentDialogActionChanged)

    RefreshAgentWindowDialog()
    AgentWindowDialog.Show()
}



RefreshAgentWindowDialog() {
    global AppConfig
    global AgentWindowDialogTitleText, AgentWindowDialogProcessText
    global AgentWindowDialogClassText, AgentWindowDialogStatusText
    global AgentWindowDialogActionDropdown

    if (!IsAgentWindowBound()) {
        AgentWindowDialogTitleText.Text := "窗口标题：未绑定"
        AgentWindowDialogProcessText.Text := "进程：未绑定"
        AgentWindowDialogClassText.Text := "类名：未绑定"
        AgentWindowDialogStatusText.Text := "状态：未绑定"
        AgentWindowDialogActionDropdown.Choose(1)
        return
    }

    title := AppConfig["AgentWindowTitleContains"]
    proc := AppConfig["AgentWindowProcessName"]
    class := AppConfig["AgentWindowClassName"]

    AgentWindowDialogTitleText.Text := "窗口标题：" TruncateMiddle(title, 40)
    AgentWindowDialogProcessText.Text := "进程：" proc
    AgentWindowDialogClassText.Text := "类名：" class

    hwnd := FindBoundAgentWindow()
    if (hwnd) {
        AgentWindowDialogStatusText.Text := "状态：在线"
    } else {
        AgentWindowDialogStatusText.Text := "状态：未找到"
    }

    action := AppConfig["AgentWindowAfterCopyAction"]
    if (action >= 1 && action <= 4) {
        AgentWindowDialogActionDropdown.Choose(action)
    } else {
        AgentWindowDialogActionDropdown.Choose(3)
    }
}



CloseAgentWindowDialog(*) {
    global AgentWindowDialog
    if (AgentWindowDialog) {
        AgentWindowDialog.Hide()
    }
}



AgentDialogUnbind(*) {
    UnbindAgentWindow()
}



AgentDialogTestActivate(*) {
    hwnd := FindBoundAgentWindow()
    if (hwnd) {
        WinActivate(hwnd)
    } else {
        ShowFeedback("未找到绑定窗口", true)
    }
}



AgentDialogActionChanged(ctrl, *) {
    global AppConfig
    AppConfig["AgentWindowAfterCopyAction"] := ctrl.Value
    SaveAgentWindowConfig()
}



FindBoundAgentWindow() {
    global AppConfig
    titleContains := AppConfig["AgentWindowTitleContains"]
    procName := AppConfig["AgentWindowProcessName"]
    className := AppConfig["AgentWindowClassName"]

    if (procName = "" || className = "") {
        return 0
    }

    logFile := A_Temp "\AIProcess_WindowSearch.log"
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    logText := "[" timestamp "] FindBoundAgentWindow called`n"
    logText .= "  TitleContains: " titleContains "`n"
    logText .= "  ProcessName: " procName "`n"
    logText .= "  ClassName: " className "`n"

    DetectHiddenWindows(true)
    logText .= "  DetectHiddenWindows: true`n"

    hwnd := 0
    ids := WinGetList("ahk_exe " procName " ahk_class " className)
    logText .= "  Found windows: " ids.Length "`n"

    for id in ids {
        title := WinGetTitle(id)
        visible := DllCall("IsWindowVisible", "Ptr", id)
        iconic := DllCall("IsIconic", "Ptr", id)
        logText .= "    HWND=" id ", Title=`"" title "`", Visible=" visible ", Iconic=" iconic "`n"

        if (hwnd = 0) {
            if (titleContains = "" || InStr(title, titleContains) || title = "") {
                hwnd := id
            }
        }
    }

    logText .= "  Selected HWND: " hwnd "`n`n"

    try {
        FileAppend(logText, logFile, "UTF-8")
    } catch {
        ; 忽略日志写入失败
    }

    DetectHiddenWindows(false)
    return hwnd
}



HandleAgentWindowAfterCopy() {
    global AppConfig
    action := AppConfig["AgentWindowAfterCopyAction"]
    if (action <= 1 || action = "") {
        return
    }

    if (!IsAgentWindowBound()) {
        ShowFeedback("未绑定 Agent 窗口", true)
        return
    }

    hwnd := FindBoundAgentWindow()
    if (!hwnd) {
        ShowFeedback("未找到绑定的 Agent 窗口", true)
        return
    }

    WinActivate(hwnd)

    if (action >= 3) {
        Send "^v"
        Sleep 150
    }

    if (action >= 4) {
        Send "{Enter}"
    }
}


UnbindAgentWindow() {
    global AppConfig, AgentWindowDialog
    AppConfig["AgentWindowTitleContains"] := ""
    AppConfig["AgentWindowProcessName"] := ""
    AppConfig["AgentWindowClassName"] := ""
    SaveAgentWindowConfig()
    UpdateBindButtonState()
    if (AgentWindowDialog) {
        RefreshAgentWindowDialog()
    }
}



OnUnbindAgentWindowButtonClick(*) {
    UnbindAgentWindow()
}

