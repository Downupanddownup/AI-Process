#Requires AutoHotkey v2.0

; 窗口位置管理模块：缓存窗口位置，提供读取/保存接口

global CachedWindowX := ""
global CachedWindowY := ""
global MIN_VALID_WINDOW_COORD := -1000

; 注册 WM_MOVE 消息监听
RegisterWindowPositionTracking(hwnd) {
    OnMessage(0x0003, OnWmMove)
}

; WM_MOVE 消息处理：实时缓存主窗口位置
OnWmMove(wParam, lParam, msg, hwnd) {
    global MainGui, CachedWindowX, CachedWindowY
    if (!MainGui || hwnd != MainGui.Hwnd) {
        return
    }
    try {
        WinGetPos(&x, &y, , , "ahk_id " hwnd)
        ; 过滤隐藏窗口的异常坐标（如 -32000）
        if (x > MIN_VALID_WINDOW_COORD && y > MIN_VALID_WINDOW_COORD) {
            CachedWindowX := x
            CachedWindowY := y
        }
    } catch {
        ; 忽略位置获取失败
    }
}

; 保存当前缓存的位置到配置
SaveWindowPosition() {
    global CachedWindowX, CachedWindowY
    if (CachedWindowX = "" || CachedWindowY = "") {
        return
    }
    SaveWindowPositionToConfig(CachedWindowX, CachedWindowY)
}

; 获取应使用的窗口位置：优先内存缓存，其次配置文件
; 返回数组 [x, y]，无效时返回空数组
GetSavedWindowPosition() {
    global CachedWindowX, CachedWindowY, AppConfig
    x := CachedWindowX != "" ? CachedWindowX : AppConfig["WindowPosX"]
    y := CachedWindowY != "" ? CachedWindowY : AppConfig["WindowPosY"]
    if (x != "" && y != "" && x > MIN_VALID_WINDOW_COORD && y > MIN_VALID_WINDOW_COORD) {
        return [x, y]
    }
    return []
}

; 校验窗口坐标是否落在当前任一显示器工作区内
; 空坐标视为无效，由调用方走默认居中逻辑
IsWindowPositionValid(x, y) {
    if (x = "" || y = "") {
        return false
    }
    try {
        monitorCount := MonitorGetCount()
        Loop monitorCount {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            if (x >= left && x < right && y >= top && y < bottom) {
                return true
            }
        }
    } catch {
        ; 获取显示器信息失败时，保守视为无效，走兜底居中
        return false
    }
    return false
}

; 清空保存的窗口位置，让下次启动使用默认居中
ClearSavedWindowPosition() {
    SaveWindowPositionToConfig("", "")
}
