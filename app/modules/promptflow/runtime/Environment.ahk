#Requires AutoHotkey v2.0

; 运行环境：一个窗口在一次动作中的稳定事实
; 只装"这次运行是谁"，不装业务计算——版本链、目录扫描由规则直接调内核能力

class Environment {

    ; 哪个窗口：1/2/3
    WindowId := ""

    ; 该窗口当前主题目录
    TopicDir := ""

    ; 打开 Markdown 的脚本路径
    OpenMdScriptPath := ""

    ; 显示完成通知的脚本路径
    NotificationScriptPath := ""

    ; 从 Map 构造（便于测试与调用方填充）
    static FromMap(m) {
        e := Environment()
        e.WindowId := m.Has("WindowId") ? m["WindowId"] : ""
        e.TopicDir := m.Has("TopicDir") ? m["TopicDir"] : ""
        e.OpenMdScriptPath := m.Has("OpenMdScriptPath") ? m["OpenMdScriptPath"] : ""
        e.NotificationScriptPath := m.Has("NotificationScriptPath") ? m["NotificationScriptPath"] : ""
        return e
    }
}
