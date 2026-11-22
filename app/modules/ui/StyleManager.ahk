#Requires AutoHotkey v2.0

; 窗口样式管理：集中管理各窗口的视觉样式

global WindowStyles := Map(
    1, Map(
        "Title", "一窗",
        "BackColor", "F5F5F5"
    ),
    2, Map(
        "Title", "二窗",
        "BackColor", "E3F2FD"
    ),
    3, Map(
        "Title", "三窗",
        "BackColor", "D0E8DA"
    )
)

; 按钮样式配置
global ButtonStyle := Map(
    "Border", true
)

; 弹窗统一底色（值即各弹窗现状，只收编不换色；接入发生在各窗口被改造时）
global DialogStyle := Map(
    "BackColor", "F7F7F7"
)

; 获取弹窗统一底色
GetDialogBackColor() {
    global DialogStyle
    return DialogStyle["BackColor"]
}

; 获取指定窗口的样式配置 Map
GetWindowStyle(windowId) {
    global WindowStyles
    if (!WindowStyles.Has(windowId)) {
        return WindowStyles[1]
    }
    return WindowStyles[windowId]
}

; 弹窗列表统一观感：网格线 + 行高（默认行高列表挤成一块，24 逻辑像素起步有呼吸感）
; 行高用空 ImageList 撑：ListView 无设置行高的消息，行高取图标高度与文本高度的较大者
; 图标宽 1px 让首列缩进不可见；不加 LVS_SHAREIMAGELISTS，控件销毁时随带销毁 ImageList，不泄漏
ApplyDialogListStyle(lvCtrl) {
    lvCtrl.Opt("+Grid")
    rowHeight := Round(24 * A_ScreenDPI / 96)
    rowIL := IL_Create(1, 1)
    DllCall("comctl32\ImageList_SetIconSize", "ptr", rowIL, "int", 1, "int", rowHeight)
    SendMessage(0x1003, 1, rowIL, lvCtrl.Hwnd)   ; LVM_SETIMAGELIST, LVSIL_SMALL
}

; 禁用表头排序：摘掉表头的 HDS_BUTTONS(0x0002)，表头变纯标题，点击不产生任何行为
; 背景：AHK ListView 点表头会按列文本内建排序（ColClick 回调拦不住，实测）；
; 行序一变，按行号取数据的预览就错位。只给"行序必须恒等于填充顺序"的列表用
DisableListHeaderSort(lvCtrl) {
    headerHwnd := SendMessage(0x101F, 0, 0, lvCtrl.Hwnd)   ; LVM_GETHEADER
    style := DllCall("GetWindowLongPtr", "ptr", headerHwnd, "int", -16, "ptr")   ; GWL_STYLE
    DllCall("SetWindowLongPtr", "ptr", headerHwnd, "int", -16, "ptr", style & ~0x2)
}

; 应用样式到主窗口
ApplyMainWindowStyle(windowId, mainGui) {
    style := GetWindowStyle(windowId)
    mainGui.Title := style["Title"]
    mainGui.BackColor := style["BackColor"]
}

; 应用按钮样式
ApplyButtonStyle(ctrl) {
    global ButtonStyle
    if (!ctrl) {
        return
    }
    if (ButtonStyle["Border"]) {
        ctrl.Opt("+Border")
    } else {
        ctrl.Opt("-Border")
    }
}
