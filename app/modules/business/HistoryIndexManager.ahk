#Requires AutoHotkey v2.0

; 历史目录索引管理
; 记录每次进入主题目录的动作，写入 history/index/YYYY-MM-DD.jsonl

LogThemeIndex(themePath, source) {
    ; 结果微调子目录（如 主题/结果微调/01）不是独立主题，不写入索引
    if (IsResultIssueDir(themePath)) {
        return
    }

    global AppRoot
    try {
        ; 提取主题名
        SplitPath(themePath, &themeName)

        ; 构造数据对象
        data := Map(
            "time", FormatTime(, "yyyy-MM-dd HH:mm:ss"),
            "window", "W" GetActiveWindowId(),
            "theme", themeName,
            "source", source,
            "path", themePath
        )

        ; 生成 JSON 行，直接输出中文
        JSON.EscapeUnicode := false
        jsonLine := JSON.Dump(data) . "`n"

        ; AppRoot 指向 app/，项目根目录需要向上退一级
        projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
        if (projectRoot = "") {
            projectRoot := AppRoot
        }

        ; 确保目录存在
        indexDir := projectRoot "\history\index"
        DirCreate(indexDir)

        ; 按日期分片写入
        date := FormatTime(, "yyyy-MM-dd")
        indexFile := indexDir "\" date ".jsonl"
        FileAppend(jsonLine, indexFile, "UTF-8")
    } catch {
        ; 写入失败静默忽略，不影响主流程
    }
}

AppendThemeIndexRecord(path, source, recordTime) {
    global AppRoot

    try {
        SplitPath(path, &themeName)

        data := Map(
            "time", FormatTime(recordTime, "yyyy-MM-dd HH:mm:ss"),
            "window", "W" GetActiveWindowId(),
            "theme", themeName,
            "source", source,
            "path", path
        )

        JSON.EscapeUnicode := false
        jsonLine := JSON.Dump(data) . "`n"

        projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
        if (projectRoot = "") {
            projectRoot := AppRoot
        }

        indexDir := projectRoot "\history\index"
        DirCreate(indexDir)

        dateStr := FormatTime(recordTime, "yyyy-MM-dd")
        indexFile := indexDir "\" dateStr ".jsonl"
        FileAppend(jsonLine, indexFile, "UTF-8")

        return true
    } catch {
        return false
    }
}

UpdateThemePathInIndex(oldPath, newPath) {
    global AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    if (projectRoot = "") {
        projectRoot := AppRoot
    }

    indexDir := projectRoot "\history\index"
    if (!DirExist(indexDir)) {
        return 0
    }

    LogDebug("UpdateThemePathInIndex: scanning " indexDir " for oldPath=" oldPath " newPath=" newPath)

    updatedCount := 0
    fileCount := 0
    lineChecked := 0

    Loop Files, indexDir "\*.jsonl", "F" {
        filePath := A_LoopFileFullPath
        fileCount += 1
        try {
            content := FileRead(filePath, "UTF-8")
        } catch {
            LogDebug("UpdateThemePathInIndex: FAILED to read " filePath)
            continue
        }

        newContent := ""
        fileChanged := false
        Loop Parse, content, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line = "") {
                continue
            }

            record := ""
            try {
                record := JSON.Load(line)
            } catch {
                LogDebug("UpdateThemePathInIndex: JSON parse FAILED for: " SubStr(line, 1, 80))
                newContent .= line "`n"
                continue
            }

            lineChecked += 1
            recordPath := record.Has("path") ? record["path"] : ""

            if (lineChecked = 1 || InStr(recordPath, "测试V3") || InStr(line, "测试V3")) {
                LogDebug("UpdateThemePathInIndex: line=" lineChecked " recordPath=[" recordPath "]")
            }

            if (recordPath != "" && IsPathPrefix(oldPath, recordPath)) {
                record["path"] := StrReplace(recordPath, oldPath, newPath)
                JSON.EscapeUnicode := false
                line := JSON.Dump(record)
                updatedCount += 1
                fileChanged := true
                LogDebug("UpdateThemePathInIndex: UPDATED to " record["path"])
            }

            newContent .= line "`n"
        }

        if (fileChanged) {
            FileDelete(filePath)
            FileAppend(newContent, filePath, "UTF-8")
        }
    }

    LogDebug("UpdateThemePathInIndex: scanned " fileCount " files, " lineChecked " lines, updated " updatedCount)
    return updatedCount
}
