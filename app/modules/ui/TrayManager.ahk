#Requires AutoHotkey v2.0

; 托盘菜单

CreateTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("显示", ShowMainWindow)
    A_TrayMenu.Add("退出", ExitApplication)
    A_TrayMenu.Default := "显示"
    TraySetIcon(AppConfig["IconSource"], AppConfig["IconIndex"])
}

ExitApplication(*) {
    ExitApp()
}
