#Requires AutoHotkey v2.0

; 主面板 GUI

global CurrentPathText := ""
global CurrentPathHwnd := 0
global CurrentDirStateMark := ""
global ReplyImplementationTailCheckbox := ""
global SetDirectoryButton := ""
global ReturnParentButton := ""
global CreateIssueButton := ""
global NewThemeButton := ""
global BindAgentWindowButton := ""
global UnbindAgentWindowButton := ""
global AgentNameText := ""
global AgentNameTextHwnd := 0
global CreateRequirementButton := ""
global CopyRequirementPromptButton := ""
global QualityCheckButton := ""
global CreateReplyButton := ""
global CopyReplyPromptButton := ""
global CopyRelationsButton := ""
global CopyExecuteButton := ""
global ExecuteStrategyDropdown := ""
global MainGui := ""
global HoverTooltipVisible := false

CreateMainGui() {
    global MainGui, CurrentPathText, CurrentPathHwnd, CurrentDirStateMark, ReplyImplementationTailCheckbox, BindAgentWindowButton, UnbindAgentWindowButton, AppConfig
    global AgentNameText, AgentNameTextHwnd
    global SetDirectoryButton, ReturnParentButton, CreateIssueButton, NewThemeButton
    global CreateRequirementButton, CopyRequirementPromptButton, QualityCheckButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyExecuteButton, ExecuteStrategyDropdown
    actionButtonWidth := 60
    actionButtonHeight := 24
    actionGap := 6

    guiOptions := "+Resize -MaximizeBox +MinimizeBox"
    if AppConfig["AlwaysOnTop"] {
        guiOptions .= " +AlwaysOnTop"
    }

    MainGui := Gui(guiOptions, "一窗")
    MainGui.BackColor := GetWindowStyle(GetActiveWindowId())["BackColor"]
    MainGui.MarginX := 8
    MainGui.MarginY := 8
    MainGui.SetFont("s8", "Microsoft YaHei UI")
    MainGui.OnEvent("Close", HandleClose)
    MainGui.OnEvent("Escape", HideToTray)
    RegisterWindowPositionTracking(MainGui.Hwnd)

    CurrentPathText := MainGui.AddText("xm ym+2 w126 h18 +0x200", "当前：未设置")
    CurrentPathText.OnEvent("Click", ShowThemeSelectDialog)
    CurrentPathHwnd := CurrentPathText.Hwnd
    CurrentDirStateMark := MainGui.AddText("x+0 yp w0 h18 Hidden", "")

    SetDirectoryButton := MainGui.AddButton("x148 ym w54 h22", "设目录")
    SetDirectoryButton.OnEvent("Click", PromptForDirectory)
    ApplyButtonStyle(SetDirectoryButton)
    ReturnParentButton := MainGui.AddButton("x148 ym w54 h22 Hidden", "返")
    ReturnParentButton.OnEvent("Click", ReturnToThemeDir)
    ApplyButtonStyle(ReturnParentButton)


    NewThemeButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "新主题")
    NewThemeButton.OnEvent("Click", CreateNewTheme)
    ApplyButtonStyle(NewThemeButton)

    CreateIssueButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "建问题")
    CreateIssueButton.OnEvent("Click", CreateAndEnterIssueDir)
    ApplyButtonStyle(CreateIssueButton)

    BindAgentWindowButton := MainGui.AddButton("xm y+8 w" actionButtonWidth " h" actionButtonHeight, "绑窗口")
    BindAgentWindowButton.OnEvent("Click", OnBindAgentWindowButtonClick)
    ApplyButtonStyle(BindAgentWindowButton)

    UnbindAgentWindowButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "解绑")
    UnbindAgentWindowButton.OnEvent("Click", OnUnbindAgentWindowButtonClick)
    ApplyButtonStyle(UnbindAgentWindowButton)

    AgentNameText := MainGui.AddText("x+" actionGap " yp+4 w62 h18", "")
    AgentNameTextHwnd := AgentNameText.Hwnd

    CreateRequirementButton := MainGui.AddButton("xm y+8 w" actionButtonWidth " h" actionButtonHeight, "建需求")
    CreateRequirementButton.OnEvent("Click", AgentActions.CreateRequirement)
    ApplyButtonStyle(CreateRequirementButton)

    CopyRequirementPromptButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复需求")
    CopyRequirementPromptButton.OnEvent("Click", AgentActions.CopyRequirement)
    ApplyButtonStyle(CopyRequirementPromptButton)

    QualityCheckButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "质检码")
    QualityCheckButton.OnEvent("Click", AgentActions.QualityCheck)
    ApplyButtonStyle(QualityCheckButton)

    CreateReplyButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "建回复")
    CreateReplyButton.OnEvent("Click", AgentActions.CreateReply)
    ApplyButtonStyle(CreateReplyButton)

    CopyReplyPromptButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复回复")
    CopyReplyPromptButton.OnEvent("Click", AgentActions.CopyReply)
    ApplyButtonStyle(CopyReplyPromptButton)

    ReplyImplementationTailCheckbox := MainGui.AddCheckbox("x+" actionGap " yp+4 w28 h18 Checked", "实")
    ReplyImplementationTailCheckbox.OnEvent("Click", OnImplementationTailToggle)

    CopyRelationsButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "复关系")
    CopyRelationsButton.OnEvent("Click", AgentActions.CopyRelations)
    ApplyButtonStyle(CopyRelationsButton)

    CopyExecuteButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复执行")
    CopyExecuteButton.OnEvent("Click", AgentActions.CopyExecute)
    ApplyButtonStyle(CopyExecuteButton)

    executeStrategyOptions := ExecuteStrategyRegistry.BuildOptions()
    ExecuteStrategyDropdown := MainGui.AddDropDownList("x+" actionGap " yp w60", executeStrategyOptions)
    ExecuteStrategyDropdown.OnEvent("Change", OnExecuteStrategyChange)
    windowId := GetActiveWindowId()
    strategyKey := GetSession(windowId, "ExecuteStrategy")
    initialIndex := 1
    for index, strategy in ExecuteStrategyRegistry.Strategies {
        if (strategy["key"] = strategyKey) {
            initialIndex := index
            break
        }
    }
    ExecuteStrategyDropdown.Choose(initialIndex)

    SetControlsEnabled(false)
    RefreshDirectoryStateUI()
}



ShowMainWindow(*) {
    global MainGui, AppConfig

    LogDebug("ShowMainWindow called")

    if !MainGui {
        LogDebug("ShowMainWindow: MainGui is null")
        return
    }

    RefreshMainWindow()

    if (GetCurrentDir() != "") {
        SetControlsEnabled(true)
    }

    width := AppConfig["WindowWidth"]
    height := AppConfig["WindowHeight"]
    screenWidth := A_ScreenWidth
    screenHeight := A_ScreenHeight
    pos := GetSavedWindowPosition()
    if (pos.Length >= 2) {
        savedX := pos[1]
        savedY := pos[2]
        LogDebug("ShowMainWindow: using saved position x=" savedX " y=" savedY)
        MainGui.Show("w" width " h" height " x" savedX " y" savedY)
    } else {
        LogDebug("ShowMainWindow: using center position")
        x := Max(0, Floor((screenWidth - width) / 2))
        y := Max(0, Floor((screenHeight - height) / 2))
        MainGui.Show("w" width " h" height " x" x " y" y)
    }
    if AppConfig["AlwaysOnTop"] {
        WinSetAlwaysOnTop(1, "ahk_id " MainGui.Hwnd)
    }
    WinActivate("ahk_id " MainGui.Hwnd)
}

SwitchToWindow(windowId) {
    LogDebug("SwitchToWindow called windowId=" windowId)
    SetActiveWindowId(windowId)
    RefreshMainWindow()
    ShowMainWindow()
    OpenPendingMarkdownIfAny(windowId)
}

ToggleWindow(windowId) {
    LogDebug("ToggleWindow called windowId=" windowId)
    if (ShouldHideOnToggle(windowId)) {
        LogDebug("ToggleWindow: hiding")
        HideToTray()
        return
    }
    LogDebug("ToggleWindow: switching")
    SwitchToWindow(windowId)
}

ShouldHideOnToggle(windowId) {
    global MainGui
    if (!MainGui) {
        LogDebug("ShouldHideOnToggle: MainGui is null")
        return false
    }
    if (GetActiveWindowId() != windowId) {
        LogDebug("ShouldHideOnToggle: activeWindowId mismatch, current=" GetActiveWindowId() " requested=" windowId)
        return false
    }
    isActive := WinActive("ahk_id " MainGui.Hwnd)
    LogDebug("ShouldHideOnToggle: isActive=" isActive)
    return isActive
}

OpenPendingMarkdownIfAny(windowId) {
    global SettingsFile
    key := "Window" windowId "PendingMd"
    pendingPath := IniRead(SettingsFile, "PendingMd", key, "")
    if (pendingPath = "") {
        return
    }
    if (!FileExist(pendingPath)) {
        SafeIniWrite("", SettingsFile, "PendingMd", key)
        return
    }
    EditorOpener.Open(pendingPath)
    SafeIniWrite("", SettingsFile, "PendingMd", key)
}

RefreshMainWindow() {
    global MainGui, ReplyImplementationTailCheckbox, ExecuteStrategyDropdown

    if (!MainGui) {
        return
    }

    windowId := GetActiveWindowId()
    ApplyMainWindowStyle(windowId, MainGui)

    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    UpdateBindButtonState()

    ; 同步"实" checkbox
    if (ReplyImplementationTailCheckbox) {
        ReplyImplementationTailCheckbox.Value := GetSession(windowId, "AppendImplementationTail") ? 1 : 0
    }

    ; 同步执行策略下拉框
    if (ExecuteStrategyDropdown) {
        strategyKey := GetSession(windowId, "ExecuteStrategy")
        for index, strategy in ExecuteStrategyRegistry.Strategies {
            if (strategy["key"] = strategyKey) {
                ExecuteStrategyDropdown.Choose(index)
                break
            }
        }
    }
}



HideToTray(*) {
    global MainGui
    LogDebug("HideToTray called")
    SaveWindowPosition()
    MainGui.Hide()
}



ToggleMainWindow(*) {
    global MainGui
    ShowMainWindow()
}



HandleClose(*) {
    global AppConfig
    LogDebug("HandleClose called")
    SaveWindowPosition()
    if AppConfig["CloseToTray"] {
        HideToTray()
        return
    }
    ExitApplication()
}


SetControlsEnabled(enabled) {
    global CreateRequirementButton, CopyRequirementPromptButton, QualityCheckButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyExecuteButton, ExecuteStrategyDropdown, ReplyImplementationTailCheckbox, CreateIssueButton, ReturnParentButton
    global NewThemeButton, BindAgentWindowButton, UnbindAgentWindowButton
    CreateRequirementButton.Enabled := enabled
    CopyRequirementPromptButton.Enabled := enabled
    QualityCheckButton.Enabled := enabled
    CreateReplyButton.Enabled := enabled
    CopyReplyPromptButton.Enabled := enabled
    ReplyImplementationTailCheckbox.Enabled := enabled
    CopyRelationsButton.Enabled := enabled
    CopyExecuteButton.Enabled := enabled
    ExecuteStrategyDropdown.Enabled := enabled
    CreateIssueButton.Enabled := enabled
    ReturnParentButton.Enabled := enabled
    NewThemeButton.Enabled := enabled
    BindAgentWindowButton.Enabled := enabled
    UnbindAgentWindowButton.Enabled := enabled
}



OnMouseMove(wParam, lParam, msg, hwnd) {
    global CurrentPathHwnd, AgentNameTextHwnd, HoverTooltipVisible

    ; 悬停显示全名：一个控件一段文案，显隐统一走下面一处
    tooltipText := ""
    if (hwnd = CurrentPathHwnd) {
        tooltipText := GetCurrentDir()
    } else if (hwnd = AgentNameTextHwnd) {
        tooltipText := GetSession(GetActiveWindowId(), "AgentName")
    }

    if (tooltipText != "") {
        ToolTip(tooltipText)
        HoverTooltipVisible := true
        return
    }

    if HoverTooltipVisible {
        ToolTip()
        HoverTooltipVisible := false
    }
}



; 按控件当前字体量文本的像素宽度（中英文宽度差 3 倍以上，只能按像素算，不能按字数）
MeasureTextWidth(text, sourceHwnd) {
    hdc := DllCall("GetDC", "Ptr", sourceHwnd, "Ptr")
    if (!hdc) {
        return 0
    }

    hFont := DllCall("SendMessageW", "Ptr", sourceHwnd, "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr")   ; WM_GETFONT
    previousFont := 0
    if (hFont) {
        previousFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
    }

    size := Buffer(8, 0)
    DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", text, "Int", StrLen(text), "Ptr", size)
    width := NumGet(size, 0, "Int")

    if (previousFont) {
        DllCall("SelectObject", "Ptr", hdc, "Ptr", previousFont)
    }
    DllCall("ReleaseDC", "Ptr", sourceHwnd, "Ptr", hdc)
    return width
}



; 装得下原样返回；装不下从中间掐，补省略号（保留头尾比只留头更容易认出是哪个名字）
; 可用宽度取 GetClientRect 的物理像素：高 DPI 下控件按缩放放大，拿布局的逻辑宽度去比会误截
TruncateToWidth(text, sourceHwnd) {
    if (text = "" || !sourceHwnd) {
        return text
    }

    rect := Buffer(16, 0)
    if (!DllCall("GetClientRect", "Ptr", sourceHwnd, "Ptr", rect)) {
        return text
    }
    maxWidth := NumGet(rect, 8, "Int")
    if (maxWidth <= 0 || MeasureTextWidth(text, sourceHwnd) <= maxWidth) {
        return text
    }

    ellipsis := "..."
    length := StrLen(text) - 1
    while (length > 0) {
        headLength := Ceil(length / 2)
        tailLength := length - headLength
        tail := tailLength > 0 ? SubStr(text, -tailLength) : ""
        candidate := SubStr(text, 1, headLength) . ellipsis . tail
        if (MeasureTextWidth(candidate, sourceHwnd) <= maxWidth) {
            return candidate
        }
        length -= 1
    }
    return ellipsis
}



OnWindowSize(wParam, lParam, msg, hwnd) {
    global MainGui, AppConfig
    if !MainGui || hwnd != MainGui.Hwnd {
        return
    }

    if (wParam = 1 && AppConfig["MinimizeToTray"]) {
        SetTimer(HideToTray, -10)
    }
}



; 恒备业务行为：创建类行为（建需求/建回复）成功后自动隐藏主面板
; 注意：行为提前返回（无 vN、无实施文档等守卫失败）时由基类 Run 跳过本调用，不隐藏
AutoHidePanel() {
    HideToTray()
}

OnImplementationTailToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "AppendImplementationTail", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}

OnExecuteStrategyChange(ctrl, *) {
    selectedIndex := ctrl.Value
    if (selectedIndex >= 1 && selectedIndex <= ExecuteStrategyRegistry.Strategies.Length) {
        SetSession(GetActiveWindowId(), "ExecuteStrategy", ExecuteStrategyRegistry.Strategies[selectedIndex]["key"])
        SaveWindowSession(GetActiveWindowId())
    }
}

ShowFeedback(message, isError := false) {
    if isError {
        ownerHwnd := MainGui ? MainGui.Hwnd : 0
        MsgBox(message, "AIProcess", "Iconx T3 Owner" ownerHwnd)
        return
    }
    ; 成功提示不再显示 ToolTip
}
