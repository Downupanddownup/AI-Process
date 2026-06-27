#Requires AutoHotkey v2.0

; 操作日志管理
; AHK 侧入口：调用 PowerShell 脚本 WriteActivityLog.ps1 写入 .aiprocess/log.jsonl

LogActivity(action, content, properties := "") {
    global AppRoot
    try {
        if (properties = "") {
            properties := Map()
        }

        currentDir := GetCurrentDir()
        if (currentDir = "") {
            return
        }

        ; 确保临时目录存在
        tmpDir := currentDir "\.aiprocess\_tmp"
        DirCreate(tmpDir)

        timestamp := A_Now . A_MSec

        ; 把 content 写入临时文件
        contentFile := tmpDir "\content_" timestamp ".txt"
        FileAppend(content, contentFile, "UTF-8")

        ; 把 properties 序列化为 JSON 字符串并写入临时文件
        JSON.EscapeUnicode := false
        propertiesJson := JSON.Dump(properties)
        propertiesFile := tmpDir "\properties_" timestamp ".json"
        FileAppend(propertiesJson, propertiesFile, "UTF-8")

        windowId := GetActiveWindowId()
        psScript := AppRoot "\powershell\activity\WriteActivityLog.ps1"

        ; 构造 PowerShell 命令
        cmd := 'powershell -ExecutionPolicy Bypass -File "' psScript '"'
            . ' -WindowId "' windowId '"'
            . ' -Action "' action '"'
            . ' -PropertiesFile "' propertiesFile '"'
            . ' -ContentFile "' contentFile '"'

        ; 调试：把命令写入日志
        FileAppend(cmd "`n", A_Temp "\AIProcess_LogActivity_Cmd.txt", "UTF-8")

        Run(cmd, , "Hide")
    } catch {
        ; 写入失败静默忽略，不影响主流程
    }
}
