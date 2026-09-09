#Requires AutoHotkey v2.0

; 行为执行前提守卫：必须已设置当前主题目录（= 原 FileManager.EnsureCurrentDirectory，逐行等价）

class ActionGuard {

    static EnsureCurrentDirectory() {
        if GetCurrentDir() = "" {
            ShowFeedback("请先设置当前主题目录", true)
            return false
        }
        return true
    }
}
