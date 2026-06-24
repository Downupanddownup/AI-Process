#Requires AutoHotkey v2.0

; 热键管理

RegisterGlobalHotkey() {
    global AppConfig

    ; 1 号窗口热键永远注册
    try {
        Hotkey(AppConfig["Window1Hotkey"], ToggleWindow1)
    } catch Error as err {
        ownerHwnd := MainGui ? MainGui.Hwnd : 0
        MsgBox("1 号窗口热键注册失败：" AppConfig["Window1Hotkey"] "`n" err.Message, "AIProcess", "Iconx Owner" ownerHwnd)
    }

    ; 2 号窗口热键仅在启用且不冲突时注册
    if (AppConfig["EnableWindow2"]) {
        if (AppConfig["Window1Hotkey"] != AppConfig["Window2Hotkey"]) {
            try {
                Hotkey(AppConfig["Window2Hotkey"], ToggleWindow2)
            } catch Error as err {
                ownerHwnd := MainGui ? MainGui.Hwnd : 0
                MsgBox("2 号窗口热键注册失败：" AppConfig["Window2Hotkey"] "`n" err.Message, "AIProcess", "Iconx Owner" ownerHwnd)
            }
        }
    }
}

ToggleWindow1(*) {
    SwitchToWindow(1)
}

ToggleWindow2(*) {
    SwitchToWindow(2)
}
