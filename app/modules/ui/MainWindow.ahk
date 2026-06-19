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
global CreateRequirementButton := ""
global CopyRequirementPromptButton := ""
global CreateReplyButton := ""
global CopyReplyPromptButton := ""
global CopyRelationsButton := ""
global CopyExecuteButton := ""
global ExecuteStrategyDropdown := ""
global MainGui := ""
global HoverTooltipVisible := false

CreateMainGui() {
    global MainGui, CurrentPathText, CurrentPathHwnd, CurrentDirStateMark, ReplyImplementationTailCheckbox, BindAgentWindowButton, UnbindAgentWindowButton, AppConfig
    global SetDirectoryButton, ReturnParentButton, CreateIssueButton, NewThemeButton
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyExecuteButton, ExecuteStrategyDropdown, ExecuteStrategies
    actionButtonWidth := 60
    actionButtonHeight := 24
    actionGap := 6

    guiOptions := "+Resize -MaximizeBox +MinimizeBox"
    if AppConfig["AlwaysOnTop"] {
        guiOptions .= " +AlwaysOnTop"
    }

    MainGui := Gui(guiOptions, "一窗")
    MainGui.BackColor := "F7F7F7"
    MainGui.MarginX := 8
    MainGui.MarginY := 8
    MainGui.SetFont("s8", "Microsoft YaHei UI")
    MainGui.OnEvent("Close", HandleClose)
    MainGui.OnEvent("Escape", HideToTray)

    CurrentPathText := MainGui.AddText("xm ym+2 w126 h18 +0x200", "当前：未设置")
    CurrentPathText.OnEvent("Click", ShowFullPath)
    CurrentPathHwnd := CurrentPathText.Hwnd
    CurrentDirStateMark := MainGui.AddText("x+0 yp w0 h18 Hidden", "")

    SetDirectoryButton := MainGui.AddButton("x148 ym w54 h22", "设目录")
    SetDirectoryButton.OnEvent("Click", PromptForDirectory)
    ReturnParentButton := MainGui.AddButton("x148 ym w54 h22 Hidden", "返")
    ReturnParentButton.OnEvent("Click", ReturnToThemeDir)

    OptionsButton := MainGui.AddButton("xm y+6 w54 h22", "选项")
    OptionsButton.OnEvent("Click", ShowOptionsDialog)

    NewThemeButton := MainGui.AddButton("x+6 yp w54 h22", "新主题")
    NewThemeButton.OnEvent("Click", CreateNewTheme)

    CreateIssueButton := MainGui.AddButton("x+6 yp w54 h22", "建问题")
    CreateIssueButton.OnEvent("Click", CreateAndEnterIssueDir)

    BindAgentWindowButton := MainGui.AddButton("xm y+8 w" actionButtonWidth " h" actionButtonHeight, "绑窗口")
    BindAgentWindowButton.OnEvent("Click", OnBindAgentWindowButtonClick)

    UnbindAgentWindowButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "解绑")
    UnbindAgentWindowButton.OnEvent("Click", OnUnbindAgentWindowButtonClick)

    CreateRequirementButton := MainGui.AddButton("xm y+8 w" actionButtonWidth " h" actionButtonHeight, "建需求")
    CreateRequirementButton.OnEvent("Click", CreateRequirementFile)

    CopyRequirementPromptButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复需求")
    CopyRequirementPromptButton.OnEvent("Click", CopyRequirementPrompt)

    CreateReplyButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "建回复")
    CreateReplyButton.OnEvent("Click", CreateReplyFile)

    CopyReplyPromptButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复回复")
    CopyReplyPromptButton.OnEvent("Click", CopyReplyPrompt)

    ReplyImplementationTailCheckbox := MainGui.AddCheckbox("x+" actionGap " yp+4 w28 h18 Checked", "实")
    ReplyImplementationTailCheckbox.OnEvent("Click", OnImplementationTailToggle)

    CopyRelationsButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "复关系")
    CopyRelationsButton.OnEvent("Click", CopyContextRelations)

    CopyExecuteButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复执行")
    CopyExecuteButton.OnEvent("Click", CopyExecutePrompt)

    executeStrategyOptions := BuildExecuteStrategyOptions()
    ExecuteStrategyDropdown := MainGui.AddDropDownList("x+" actionGap " yp w60", executeStrategyOptions)
    ExecuteStrategyDropdown.OnEvent("Change", OnExecuteStrategyChange)
    windowId := GetActiveWindowId()
    strategyKey := GetSession(windowId, "ExecuteStrategy")
    initialIndex := 1
    for index, strategy in ExecuteStrategies {
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

    if !MainGui {
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
    x := Max(0, Floor((screenWidth - width) / 2))
    y := Max(0, Floor((screenHeight - height) / 2))
    MainGui.Show("w" width " h" height " x" x " y" y)
    if AppConfig["AlwaysOnTop"] {
        WinSetAlwaysOnTop(1, "ahk_id " MainGui.Hwnd)
    }
    WinActivate("ahk_id " MainGui.Hwnd)
}

SwitchToWindow(windowId) {
    SetActiveWindowId(windowId)
    RefreshMainWindow()
    ShowMainWindow()
}

RefreshMainWindow() {
    global MainGui, ReplyImplementationTailCheckbox, ExecuteStrategyDropdown, ExecuteStrategies

    if (!MainGui) {
        return
    }

    windowId := GetActiveWindowId()
    title := windowId = 1 ? "一窗" : "二窗"
    MainGui.Title := title

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
        for index, strategy in ExecuteStrategies {
            if (strategy["key"] = strategyKey) {
                ExecuteStrategyDropdown.Choose(index)
                break
            }
        }
    }
}



HideToTray(*) {
    global MainGui
    MainGui.Hide()
}



ToggleMainWindow(*) {
    global MainGui
    ShowMainWindow()
}



HandleClose(*) {
    global AppConfig
    if AppConfig["CloseToTray"] {
        HideToTray()
        return
    }
    ExitApplication()
}


SetControlsEnabled(enabled) {
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyExecuteButton, ExecuteStrategyDropdown, ReplyImplementationTailCheckbox, CreateIssueButton, ReturnParentButton
    global NewThemeButton, BindAgentWindowButton, UnbindAgentWindowButton
    CreateRequirementButton.Enabled := enabled
    CopyRequirementPromptButton.Enabled := enabled
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
    global CurrentPathHwnd, HoverTooltipVisible

    currentDir := GetCurrentDir()
    if (hwnd = CurrentPathHwnd && currentDir != "") {
        ToolTip(currentDir)
        HoverTooltipVisible := true
        return
    }

    if HoverTooltipVisible {
        ToolTip()
        HoverTooltipVisible := false
    }
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



MaybeAutoHide() {
    if (GetSession(GetActiveWindowId(), "AutoHideAfterCreate")) {
        HideToTray()
    }
}

OnImplementationTailToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "AppendImplementationTail", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}

OnExecuteStrategyChange(ctrl, *) {
    global ExecuteStrategies
    selectedIndex := ctrl.Value
    if (selectedIndex >= 1 && selectedIndex <= ExecuteStrategies.Length) {
        SetSession(GetActiveWindowId(), "ExecuteStrategy", ExecuteStrategies[selectedIndex]["key"])
        SaveWindowSession(GetActiveWindowId())
    }
}

ShowFeedback(message, isError := false) {
    if isError {
        MsgBox(message, "AIProcess", "Iconx T3")
        return
    }
    ; 成功提示不再显示 ToolTip
}
