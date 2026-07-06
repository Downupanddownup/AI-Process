#Requires AutoHotkey v2.0

; SummaryDataCollector.ahk
; 经验总结数据收集层：调用 PowerShell 脚本获取主题结构化数据

CollectSummaryData(themePath) {
    global AppRoot

    if (themePath = "" || !DirExist(themePath)) {
        return Map("Error", "主题目录无效")
    }

    ; 确保临时目录存在
    tmpDir := themePath "\.aiprocess\_tmp"
    if (!DirExist(tmpDir)) {
        DirCreate(tmpDir)
    }

    outputFile := tmpDir "\summary_input.json"
    errFile := tmpDir "\summary_input_err.txt"

    psScript := AppRoot "\powershell\summary\PrepareSummaryInput.ps1"
    cmd := 'powershell -ExecutionPolicy Bypass -File "' psScript '" -ThemePath "' themePath '" -OutputFile "' outputFile '" -ErrorFile "' errFile '"'

    try {
        RunWait(cmd, , "Hide")
    } catch Error as err {
        return Map("Error", "启动 PowerShell 失败：" err.Message)
    }

    if (!FileExist(outputFile)) {
        errMsg := ""
        if (FileExist(errFile)) {
            try {
                errMsg := FileRead(errFile, "UTF-8")
            } catch {
                errMsg := ""
            }
            try {
                FileDelete(errFile)
            } catch {
                ; 忽略删除失败
            }
        }
        if (errMsg = "") {
            errMsg := "未生成数据文件，原因未知"
        }
        return Map("Error", errMsg)
    }

    ; 清理错误文件
    try {
        FileDelete(errFile)
    } catch {
        ; 忽略
    }

    try {
        content := FileRead(outputFile, "UTF-8")
        ; 去除可能的 BOM
        if (SubStr(content, 1, 1) = "`uFEFF") {
            content := SubStr(content, 2)
        }
        data := JSON.Load(content)
        return data
    } catch Error as err {
        return Map("Error", "解析数据失败：" err.Message)
    }
}
