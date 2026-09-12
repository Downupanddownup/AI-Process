#Requires AutoHotkey v2.0

; 通用工具：生成 GUID（叶子，无项目依赖）
; 什么时候用它：需要"绝不重复"的标识时。别用时间戳——Windows 计时器一拍约 17.5ms，
; 连续两次取 A_Now . A_MSec 会拿到完全相同的值（实测 40/40 相同），拿它当唯一名必然撞。

NewGuid() {
    buf := Buffer(16, 0)
    if (DllCall("ole32\CoCreateGuid", "ptr", buf) != 0)
        throw Error("CoCreateGuid 调用失败")
    hex := ""
    Loop 16
        hex .= Format("{:02x}", NumGet(buf, A_Index - 1, "UChar"))
    return SubStr(hex, 1, 8) "-" SubStr(hex, 9, 4) "-" SubStr(hex, 13, 4) "-" SubStr(hex, 17, 4) "-" SubStr(hex, 21, 12)
}
