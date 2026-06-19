#Requires AutoHotkey v2.0

; 主面板 GUI

global CurrentPathText := ""
global CurrentPathHwnd := 0
global CurrentDirStateMark := ""
global OpenWithIdeaCheckbox := ""
global OpenMdWithIdeaCheckbox := ""
global NoModifyPromptCheckbox := ""
global ReplyImplementationTailCheckbox := ""
global SetDirectoryButton := ""
global ReturnParentButton := ""
global CreateIssueButton := ""
global NewThemeButton := ""
global AutoHideCheckbox := ""
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
    global MainGui, CurrentPathText, CurrentPathHwnd, CurrentDirStateMark, OpenWithIdeaCheckbox, OpenMdWithIdeaCheckbox, NoModifyPromptCheckbox, ReplyImplementationTailCheckbox, AutoHideCheckbox, BindAgentWindowButton, UnbindAgentWindowButton, AppConfig
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

    NewThemeButton := MainGui.AddButton("xm y+6 w54 h22", "新主题")
    NewThemeButton.OnEvent("Click", CreateNewTheme)

    CreateIssueButton := MainGui.AddButton("x+6 yp w54 h22", "建问题")
    CreateIssueButton.OnEvent("Click", CreateAndEnterIssueDir)

    OpenWithIdeaCheckbox := MainGui.AddCheckbox("xm y+6", "IDEA开")
    OpenWithIdeaCheckbox.Value := AppConfig["OpenWithIdea"] ? 1 : 0
    OpenWithIdeaCheckbox.OnEvent("Click", ToggleIdeaOpen)

    NoModifyPromptCheckbox := MainGui.AddCheckbox("x+4 yp", "禁改正式")
    NoModifyPromptCheckbox.Value := AppConfig["AppendNoModifyPrompt"] ? 1 : 0
    NoModifyPromptCheckbox.OnEvent("Click", ToggleNoModifyPrompt)

    AutoHideCheckbox := MainGui.AddCheckbox("x+4 yp", "自隐藏")
    AutoHideCheckbox.Value := AppConfig["AutoHideAfterCreate"] ? 1 : 0
    AutoHideCheckbox.OnEvent("Click", ToggleAutoHide)

    OpenMdWithIdeaCheckbox := MainGui.AddCheckbox("xm y+8 h" actionButtonHeight, "MD开")
    OpenMdWithIdeaCheckbox.Value := AppConfig["OpenMdWithIdea"] ? 1 : 0
    OpenMdWithIdeaCheckbox.OnEvent("Click", ToggleOpenMdWithIdea)

    BindAgentWindowButton := MainGui.AddButton("x+4 yp w" actionButtonWidth " h" actionButtonHeight, "绑窗口")
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

    CopyRelationsButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "复关系")
    CopyRelationsButton.OnEvent("Click", CopyContextRelations)

    CopyExecuteButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复执行")
    CopyExecuteButton.OnEvent("Click", CopyExecutePrompt)

    executeStrategyOptions := BuildExecuteStrategyOptions()
    ExecuteStrategyDropdown := MainGui.AddDropDownList("x+" actionGap " yp w44", executeStrategyOptions)
    ExecuteStrategyDropdown.Choose(2)

    SetControlsEnabled(false)
    RefreshDirectoryStateUI()
}



ShowMainWindow(*) {
    global MainGui, AppConfig

    if !MainGui {
        return
    }

    RefreshMainWindow()

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
    global MainGui
    if (!MainGui) {
        return
    }

    windowId := GetActiveWindowId()
    title := windowId = 1 ? "一窗" : "二窗"
    MainGui.Title := title

    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    UpdateBindButtonState()
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
    global NewThemeButton, AutoHideCheckbox, OpenMdWithIdeaCheckbox, BindAgentWindowButton, UnbindAgentWindowButton
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
    AutoHideCheckbox.Enabled := enabled
    OpenMdWithIdeaCheckbox.Enabled := enabled
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
    global AutoHideCheckbox
    if (AutoHideCheckbox && AutoHideCheckbox.Value = 1) {
        HideToTray()
    }
}

ToggleIdeaOpen(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["OpenWithIdea"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Editor", "OpenWithIdea")
    ShowFeedback(checked ? "已开启 IDEA 打开" : "已关闭 IDEA 打开")
}



ToggleNoModifyPrompt(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["AppendNoModifyPrompt"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Prompt", "AppendNoModifyPrompt")
    ShowFeedback(checked ? "已开启禁改正式" : "已关闭禁改正式")
}



ToggleAutoHide(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["AutoHideAfterCreate"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Behavior", "AutoHideAfterCreate")
    ShowFeedback(checked ? "已开启自动隐藏" : "已关闭自动隐藏")
}



ToggleOpenMdWithIdea(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["OpenMdWithIdea"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Editor", "OpenMdWithIdea")
    ShowFeedback(checked ? "已开启MD开" : "已关闭MD开")
}

ShowFeedback(message, isError := false) {
    if isError {
        MsgBox(message, "AIProcess", "Iconx T3")
        return
    }
    ; 成功提示不再显示 ToolTip
}
