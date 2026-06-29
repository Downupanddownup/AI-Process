#Requires AutoHotkey v2.0

; SummaryDataCollector.ahk
; 经验总结数据收集层：调用 PowerShell 脚本获取主题结构化数据

CollectSummaryData(themePath) {
    global AppRoot

    if (themePath = "" || !DirExist(themePath)) {
        return ""
    }

    ; 确保临时目录存在
    tmpDir := themePath "\.aiprocess\_tmp"
    if (!DirExist(tmpDir)) {
        DirCreate(tmpDir)
    }

    timestamp := A_Now . A_MSec
    outputFile := tmpDir "\summary_data_" timestamp ".json"

    psScript := AppRoot "\powershell\summary\PrepareSummaryData.ps1"
    cmd := 'powershell -ExecutionPolicy Bypass -File "' psScript '" -ThemePath "' themePath '" -OutputFile "' outputFile '"'

    try {
        RunWait(cmd, , "Hide")
    } catch Error as err {
        return ""
    }

    if (!FileExist(outputFile)) {
        return ""
    }

    try {
        content := FileRead(outputFile, "UTF-8")
        ; 去除可能的 BOM
        if (SubStr(content, 1, 1) = "`uFEFF") {
            content := SubStr(content, 2)
        }
        data := JSON.Load(content)
        FileDelete(outputFile)
        return data
    } catch Error as err {
        try {
            FileDelete(outputFile)
        } catch {
            ; 忽略删除失败
        }
        return ""
    }
}
