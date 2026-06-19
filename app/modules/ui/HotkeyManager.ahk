#Requires AutoHotkey v2.0

; 热键管理


RegisterGlobalHotkey() {
    global AppConfig
    try {
        Hotkey(AppConfig["Hotkey"], ToggleMainWindow)
    } catch Error as err {
        MsgBox("全局快捷键注册失败：" AppConfig["Hotkey"] "`n" err.Message, "AIProcess", "Iconx")
    }
}

