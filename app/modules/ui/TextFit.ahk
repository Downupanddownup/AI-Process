#Requires AutoHotkey v2.0

; 控件文本量算与截断：把文本按像素装进定宽控件
; 可用宽一律取控件的物理像素——高 DPI 下控件按缩放放大，拿布局的逻辑宽度去比会误截（150% 缩放下这两套数差 1.5 倍）

; 按控件当前字体量文本的像素宽度（中英文宽度差 3 倍以上，只能按像素算，不能按字数）
MeasureTextWidth(text, sourceHwnd) {
    hdc := DllCall("GetDC", "Ptr", sourceHwnd, "Ptr")
    if (!hdc) {
        return 0
    }

    hFont := DllCall("SendMessageW", "Ptr", sourceHwnd, "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr")   ; WM_GETFONT
    previousFont := 0
    if (hFont) {
        previousFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", hFont, "Ptr")
    }

    size := Buffer(8, 0)
    DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", text, "Int", StrLen(text), "Ptr", size)
    width := NumGet(size, 0, "Int")

    if (previousFont) {
        DllCall("SelectObject", "Ptr", hdc, "Ptr", previousFont)
    }
    DllCall("ReleaseDC", "Ptr", sourceHwnd, "Ptr", hdc)
    return width
}

; 控件的可用宽（物理像素）；取不到返回 0，调用方按"装不下"处理
GetControlClientWidth(sourceHwnd) {
    if (!sourceHwnd) {
        return 0
    }
    rect := Buffer(16, 0)
    if (!DllCall("GetClientRect", "Ptr", sourceHwnd, "Ptr", rect)) {
        return 0
    }
    return NumGet(rect, 8, "Int")
}

; 装得下原样返回；装不下从中间掐，补省略号（保留头尾比只留头更容易认出是哪个名字）
TruncateToWidth(text, sourceHwnd) {
    if (text = "" || !sourceHwnd) {
        return text
    }

    maxWidth := GetControlClientWidth(sourceHwnd)
    if (maxWidth <= 0 || MeasureTextWidth(text, sourceHwnd) <= maxWidth) {
        return text
    }

    ellipsis := "..."
    length := StrLen(text) - 1
    while (length > 0) {
        headLength := Ceil(length / 2)
        tailLength := length - headLength
        tail := tailLength > 0 ? SubStr(text, -tailLength) : ""
        candidate := SubStr(text, 1, headLength) . ellipsis . tail
        if (MeasureTextWidth(candidate, sourceHwnd) <= maxWidth) {
            return candidate
        }
        length -= 1
    }
    return ellipsis
}

; 装得下原样返回；装不下从 text 尾部掐、补省略号，tail（如 "/01"）必留
; 与 TruncateToWidth 的分工：那个保头尾、不强求某个后缀活着；这个保头 + 指定后缀必活
TruncateKeepTail(text, tail, sourceHwnd) {
    if (text = "") {
        return tail
    }
    if (!sourceHwnd) {
        return text . tail
    }

    maxWidth := GetControlClientWidth(sourceHwnd)
    if (maxWidth <= 0 || MeasureTextWidth(text . tail, sourceHwnd) <= maxWidth) {
        return text . tail
    }

    ellipsis := "..."
    length := StrLen(text)
    while (length > 0) {
        candidate := SubStr(text, 1, length) . ellipsis . tail
        if (MeasureTextWidth(candidate, sourceHwnd) <= maxWidth) {
            return candidate
        }
        length -= 1
    }
    return ellipsis . tail
}
