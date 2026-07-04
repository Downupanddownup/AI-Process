#Requires AutoHotkey v2.0

; 归档业务逻辑：使用检查、目录移动、重名处理、索引更新

ArchiveThemes(repoPath, themeNames) {
    result := {success: 0, failed: 0, errors: []}

    for themeName in themeNames {
        themePath := repoPath "\" themeName

        if (IsThemeInUse(themePath)) {
            windowIds := GetActiveWindowIdsForTheme(themePath)
            result.failed += 1
            result.errors.Push(themeName " 正被窗口 " JoinArray(windowIds, "、") " 使用")
            continue
        }

        newPath := MoveThemeToArchive(repoPath, themeName)
        if (newPath = "") {
            result.failed += 1
            result.errors.Push(themeName " 移动失败")
            continue
        }

        UpdateThemePathInIndex(themePath, newPath)
        result.success += 1
        LogDebug("ArchiveManager: archived '" themeName "' to " newPath)
    }

    return result
}

IsThemeInUse(themePath) {
    normalized := NormalizePath(themePath)
    Loop 3 {
        currentDir := NormalizePath(GetSession(A_Index, "CurrentDir"))
        if (currentDir != "" && InStr(currentDir, normalized) = 1) {
            return true
        }
    }
    return false
}

GetActiveWindowIdsForTheme(themePath) {
    ids := []
    normalized := NormalizePath(themePath)
    Loop 3 {
        currentDir := NormalizePath(GetSession(A_Index, "CurrentDir"))
        if (currentDir != "" && InStr(currentDir, normalized) = 1) {
            ids.Push("W" A_Index)
        }
    }
    return ids
}

MoveThemeToArchive(repoPath, themeName) {
    archiveDir := GetRepoArchiveDir(repoPath)
    DirCreate(archiveDir)

    sourceDir := repoPath "\" themeName
    targetDir := archiveDir "\" themeName

    counter := 2
    while DirExist(targetDir) {
        targetDir := archiveDir "\" themeName "_" counter
        counter += 1
    }

    try {
        DirMove(sourceDir, targetDir, 1)
        return targetDir
    } catch {
        return ""
    }
}
