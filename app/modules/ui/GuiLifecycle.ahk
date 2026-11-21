#Requires AutoHotkey v2.0

; 窗口生命周期：判断一个 Gui 是否还活着
;
; 为什么需要它：绑了 +Owner 的窗口会被父窗口连带销毁，而且没有任何回调通知；
; 销毁后 `if (gui)` 仍为真、读 `gui.Hwnd` 直接抛 "Gui has no window"。
; 所以"复用已创建过的窗口"之前必须试读一次 Hwnd，不能只判变量非空。
; 背景与三条用法见 基础信息\技术信息.md 第三节「Gui 生命周期」。

GuiAlive(g) {
    if !IsObject(g)
        return false
    try {
        return (g.Hwnd != 0)
    } catch {
        return false
    }
}
