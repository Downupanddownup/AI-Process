#Requires AutoHotkey v2.0

; HistoricalThemeImporter.ahk
; 经验总结历史主题导入器：将历史主题目录批量追加到索引中

ImportHistoricalThemes(rootDir) {
    rootDir := NormalizePath(rootDir)
    if (rootDir = "" || !DirExist(rootDir)) {
        MsgBox("目录无效", "AIProcess", "Iconx")
        return 0
    }

    candidates := FindThemeCandidateDirs(rootDir)
    if (candidates.Length = 0) {
        return 0
    }

    importedCount := 0
    indexCache := Map()

    for path in candidates {
        try {
            createTime := FileGetTime(path, "C")
        } catch {
            continue
        }

        dateStr := FormatTime(createTime, "yyyy-MM-dd")
        if (!indexCache.Has(dateStr)) {
            indexCache[dateStr] := ReadIndexFileContent(dateStr)
        }
        fileContent := indexCache[dateStr]

        normalizedPath := NormalizePath(path)
        if (IsPathInIndexContent(normalizedPath, fileContent)) {
            continue
        }

        if (AppendThemeIndexRecord(normalizedPath, "历史导入", createTime)) {
            importedCount += 1
            indexCache[dateStr] := ReadIndexFileContent(dateStr)
        }
    }

    return importedCount
}

FindThemeCandidateDirs(rootDir) {
    result := []

    Loop Files, rootDir "\*", "DR" {
        dirPath := A_LoopFileFullPath
        if (!FileExist(dirPath "\需求.txt")) {
            continue
        }
        if (IsResultIssueDir(dirPath)) {
            continue
        }
        result.Push(dirPath)
    }

    return result
}

ReadIndexFileContent(dateStr) {
    global AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    if (projectRoot = "") {
        projectRoot := AppRoot
    }

    indexFile := projectRoot "\history\index\" dateStr ".jsonl"
    if (!FileExist(indexFile)) {
        return ""
    }

    try {
        return FileRead(indexFile, "UTF-8")
    } catch {
        return ""
    }
}

IsPathInIndexContent(normalizedPath, content) {
    if (content = "") {
        return false
    }

    Loop Parse, content, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "") {
            continue
        }
        try {
            record := JSON.Load(line)
            recordPath := record["path"]
            if (NormalizePath(recordPath) = normalizedPath) {
                return true
            }
        } catch {
            continue
        }
    }

    return false
}
