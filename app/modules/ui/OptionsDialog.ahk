#Requires AutoHotkey v2.0

; 选项弹窗

global OptionsDialog := ""
global OptionsIdeaCheckbox := ""
global OptionsMdCheckbox := ""
global OptionsNoModifyCheckbox := ""
global OptionsAutoHideCheckbox := ""
global OptionsExecuteNotificationCheckbox := ""

CreateOptionsDialog() {
    global OptionsDialog, OptionsIdeaCheckbox, OptionsMdCheckbox
    global OptionsNoModifyCheckbox, OptionsAutoHideCheckbox, OptionsExecuteNotificationCheckbox, MainGui

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        dialogOptions .= " +Owner" ownerHwnd
    }

    OptionsDialog := Gui(dialogOptions, "选项")
    OptionsDialog.BackColor := "F7F7F7"
    OptionsDialog.MarginX := 12
    OptionsDialog.MarginY := 10
    OptionsDialog.SetFont("s8", "Microsoft YaHei UI")
    OptionsDialog.OnEvent("Close", CloseOptionsDialog)
    OptionsDialog.OnEvent("Escape", CloseOptionsDialog)

    OptionsIdeaCheckbox := OptionsDialog.AddCheckbox("xm ym w220 h20", "创建后用工具打开需求文件")
    OptionsIdeaCheckbox.OnEvent("Click", OnOptionsIdeaToggle)

    OptionsMdCheckbox := OptionsDialog.AddCheckbox("xm y+4 w220 h20", "MD 文件用工具打开")
    OptionsMdCheckbox.OnEvent("Click", OnOptionsMdToggle)

    OptionsNoModifyCheckbox := OptionsDialog.AddCheckbox("xm y+4 w220 h20", "提示词追加禁止修改正式文件")
    OptionsNoModifyCheckbox.OnEvent("Click", OnOptionsNoModifyToggle)

    OptionsAutoHideCheckbox := OptionsDialog.AddCheckbox("xm y+4 w220 h20", "创建文件后自动隐藏面板")
    OptionsAutoHideCheckbox.OnEvent("Click", OnOptionsAutoHideToggle)

    OptionsExecuteNotificationCheckbox := OptionsDialog.AddCheckbox("xm y+4 w220 h20", "执行完成后显示窗口通知")
    OptionsExecuteNotificationCheckbox.OnEvent("Click", OnOptionsExecuteNotificationToggle)

    closeButton := OptionsDialog.AddButton("xm+160 y+10 w60 h24", "关闭")
    closeButton.OnEvent("Click", CloseOptionsDialog)
}

ShowOptionsDialog(*) {
    global OptionsDialog
    if (!OptionsDialog) {
        CreateOptionsDialog()
    }
    RefreshOptionsDialog()
    OptionsDialog.Show("w260 h190")
    WinActivate("ahk_id " OptionsDialog.Hwnd)
}

RefreshOptionsDialog() {
    global OptionsIdeaCheckbox, OptionsMdCheckbox
    global OptionsNoModifyCheckbox, OptionsAutoHideCheckbox, OptionsExecuteNotificationCheckbox

    windowId := GetActiveWindowId()
    OptionsIdeaCheckbox.Value := GetSession(windowId, "OpenWithIdea") ? 1 : 0
    OptionsMdCheckbox.Value := GetSession(windowId, "OpenMdWithIdea") ? 1 : 0
    OptionsNoModifyCheckbox.Value := GetSession(windowId, "AppendNoModifyPrompt") ? 1 : 0
    OptionsAutoHideCheckbox.Value := GetSession(windowId, "AutoHideAfterCreate") ? 1 : 0
    OptionsExecuteNotificationCheckbox.Value := GetSession(windowId, "ShowExecuteNotification") ? 1 : 0
}

CloseOptionsDialog(*) {
    global OptionsDialog
    if (OptionsDialog) {
        OptionsDialog.Hide()
    }
}

OnOptionsIdeaToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "OpenWithIdea", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}

OnOptionsMdToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "OpenMdWithIdea", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}

OnOptionsNoModifyToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "AppendNoModifyPrompt", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}

OnOptionsAutoHideToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "AutoHideAfterCreate", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}

OnOptionsExecuteNotificationToggle(ctrl, *) {
    SetSession(GetActiveWindowId(), "ShowExecuteNotification", ctrl.Value = 1)
    SaveWindowSession(GetActiveWindowId())
}
