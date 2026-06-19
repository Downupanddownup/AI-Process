#Requires AutoHotkey v2.0

; 配置弹窗

global ConfigDialog := ""
global ConfigDialogListView := ""

ShowConfigDialog(*) {
    global ConfigDialog, ConfigDialogListView, AppConfig, MainGui

    if (ConfigDialog) {
        ConfigDialog.Show()
        WinActivate("ahk_id " ConfigDialog.Hwnd)
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        dialogOptions .= " +Owner" ownerHwnd
    }

    ConfigDialog := Gui(dialogOptions, "配置")
    ConfigDialog.BackColor := "F7F7F7"
    ConfigDialog.MarginX := 12
    ConfigDialog.MarginY := 10
    ConfigDialog.SetFont("s8", "Microsoft YaHei UI")
    ConfigDialog.OnEvent("Close", CloseConfigDialog)
    ConfigDialog.OnEvent("Escape", CloseConfigDialog)

    ConfigDialog.AddText("xm ym w240 h18", "窗口列表")

    ConfigDialogListView := ConfigDialog.AddListView("xm y+6 w240 h80 Checked", ["窗口", "热键"])
    ConfigDialogListView.Add("Check", "1 号窗", AppConfig["Window1Hotkey"])
    if (AppConfig["EnableWindow2"]) {
        ConfigDialogListView.Add("Check", "2 号窗", AppConfig["Window2Hotkey"])
    } else {
        ConfigDialogListView.Add("", "2 号窗", AppConfig["Window2Hotkey"])
    }
    ConfigDialogListView.OnEvent("ItemCheck", OnConfigDialogItemCheck)

    ConfigDialog.AddText("xm y+10 w240 h18 cGray", "修改后需退出重启")

    exitButton := ConfigDialog.AddButton("xm y+10 w80 h24", "退出程序")
    exitButton.OnEvent("Click", OnConfigDialogExit)

    cancelButton := ConfigDialog.AddButton("x+8 yp w80 h24", "取消")
    cancelButton.OnEvent("Click", CloseConfigDialog)

    ConfigDialog.Show()
}

OnConfigDialogItemCheck(ctrl, itemIndex, checked) {
    global AppConfig
    if (itemIndex = 1) {
        if (!checked) {
            ; 1 号窗口永远启用，不允许取消
            ctrl.Modify(1, "Check")
        }
        return
    }
    if (itemIndex = 2) {
        AppConfig["EnableWindow2"] := checked
        SaveEnableWindow2(checked)
    }
}

OnConfigDialogExit(*) {
    ExitApplication()
}

CloseConfigDialog(*) {
    global ConfigDialog, ConfigDialogListView
    if (ConfigDialog) {
        ConfigDialog.Destroy()
        ConfigDialog := ""
        ConfigDialogListView := ""
    }
}
