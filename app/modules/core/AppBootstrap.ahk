#Requires AutoHotkey v2.0

; 单实例、启动参数、进程间通信

global AppMutexName := "AIProcess_SingleInstance_Mutex_7a3f9e2b"
global AppMutex := 0
global StartedFromContextMenu := false

EnsureSingleInstance() {
    global AppMutex
    AppMutex := DllCall("CreateMutex", "Ptr", 0, "Int", 1, "Str", AppMutexName, "Ptr")
    return DllCall("GetLastError") != 183
}

ActivateExistingInstance() {
    global MainGui
    if (MainGui) {
        ShowMainWindow()
    }
}

HasSetDirArg() {
    argString := DllCall("GetCommandLine", "Str")
    return InStr(argString, "/setdir")
}

GetSetDirArg() {
    argString := DllCall("GetCommandLine", "Str")
    pos := InStr(argString, "/setdir")
    if (pos = 0) {
        return ""
    }

    rest := SubStr(argString, pos + StrLen("/setdir"))
    rest := Trim(rest)

    if (SubStr(rest, 1, 1) = "`"") {
        rest := SubStr(rest, 2)
    }
    if (SubStr(rest, -1) = "`"") {
        rest := SubStr(rest, 1, -1)
    }

    return Trim(rest)
}

SendSetDirToExistingInstance(dirPath) {
    tempFile := A_Temp "\AIProcess_SetDir.tmp"
    try {
        FileDelete(tempFile)
    } catch {
        ; 忽略
    }
    FileAppend(dirPath, tempFile, "UTF-8")

    DetectHiddenWindows(true)
    try {
        hwnd := WinGetID("一窗")
        if (hwnd) {
            SendMessage(0x4000, 0, 0, , "ahk_id " hwnd)
        }
    } catch Error {
        ; 没有运行的 AIProcess 实例或窗口不可访问，忽略
    }
    DetectHiddenWindows(false)
}

OnSetDirMessage(wParam, lParam, msg, hwnd) {
    dirPath := ReadSetDirTempFile()
    if (dirPath != "") {
        SetActiveWindowId(1)
        SetCurrentDirAndOpenRequirement(dirPath)
        RefreshMainWindow()
    }
    return 0
}

ReadSetDirTempFile() {
    tempFile := A_Temp "\AIProcess_SetDir.tmp"
    if (!FileExist(tempFile)) {
        return ""
    }
    dirPath := FileRead(tempFile, "UTF-8")
    try {
        FileDelete(tempFile)
    } catch {
        ; 忽略
    }
    return Trim(dirPath)
}
