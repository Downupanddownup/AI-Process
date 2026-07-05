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

    ; 文件处理工具区域（顶部，即时生效，无需重启）
    ConfigDialog.AddText("xm ym w240 h18", "文件处理工具")
    global ConfigDialogFileToolLabel := ConfigDialog.AddText("xm y+2 w240 h14 cGray", "当前：" GetDefaultToolName())
    manageBtn := ConfigDialog.AddButton("xm y+6 w100 h24", "管理...")
    manageBtn.OnEvent("Click", (*) => (ShowFileToolDialog(ConfigDialog.Hwnd), RefreshConfigFileToolLabel()))

    ; 分隔线
    ConfigDialog.AddText("xm y+12 w240 h2 +0x7")

    ; 窗口列表区域（底部，修改后需重启）
    ConfigDialog.AddText("xm y+6 w240 h18", "窗口列表")

    ConfigDialogListView := ConfigDialog.AddListView("xm y+6 w240 h110 Checked", ["窗口", "热键"])
    ConfigDialogListView.Add("Check", "1 号窗", AppConfig["Window1Hotkey"])
    if (AppConfig["EnableWindow2"]) {
        ConfigDialogListView.Add("Check", "2 号窗", AppConfig["Window2Hotkey"])
    } else {
        ConfigDialogListView.Add("", "2 号窗", AppConfig["Window2Hotkey"])
    }
    if (AppConfig["EnableWindow3"]) {
        ConfigDialogListView.Add("Check", "3 号窗", AppConfig["Window3Hotkey"])
    } else {
        ConfigDialogListView.Add("", "3 号窗", AppConfig["Window3Hotkey"])
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
    if (itemIndex = 3) {
        AppConfig["EnableWindow3"] := checked
        SaveEnableWindow3(checked)
    }
}

OnConfigDialogExit(*) {
    ExitApplication()
}

CloseConfigDialog(*) {
    global ConfigDialog, ConfigDialogListView, ConfigDialogFileToolLabel
    global g_FileToolDialog, g_FileToolListView
    if (g_FileToolDialog) {
        g_FileToolDialog.Destroy()
        g_FileToolDialog := ""
        g_FileToolListView := ""
    }
    if (ConfigDialog) {
        ConfigDialog.Destroy()
        ConfigDialog := ""
        ConfigDialogListView := ""
        ConfigDialogFileToolLabel := ""
    }
}

RefreshConfigFileToolLabel() {
    global ConfigDialogFileToolLabel
    if (ConfigDialogFileToolLabel) {
        ConfigDialogFileToolLabel.Text := "当前：" GetDefaultToolName()
    }
}
