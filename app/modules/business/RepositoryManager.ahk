#Requires AutoHotkey v2.0

; 仓库管理器：仓库 CRUD、持久化、查询
; 仓库持久化文件：{项目根目录}\history\repositories.json（JSONL 格式，每行一条记录）

global Repositories := []
global RepositoriesFile := ""

; ============================================================
; 初始化
; ============================================================

InitRepositoryManager() {
    global Repositories, RepositoriesFile, AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    if (projectRoot = "") {
        projectRoot := AppRoot
    }
    RepositoriesFile := projectRoot "\history\repositories.json"
    LoadRepositories()
    LogDebug("RepositoryManager: initialized, " Repositories.Length " repositories loaded")
}

; ============================================================
; 持久化（内部）
; ============================================================

LoadRepositories() {
    global Repositories, RepositoriesFile

    Repositories := []
    if (!FileExist(RepositoriesFile)) {
        return
    }

    try {
        content := FileRead(RepositoriesFile, "UTF-8")
        Loop Parse, content, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line = "") {
                continue
            }
            try {
                item := JSON.Load(line)
                repo := Map(
                    "name", item.Has("name") ? item["name"] : "",
                    "path", item.Has("path") ? item["path"] : "",
                    "addedTime", item.Has("addedTime") ? item["addedTime"] : ""
                )
                exists := false
                for r in Repositories {
                    if (NormalizePath(r["path"]) = NormalizePath(repo["path"])) {
                        exists := true
                        break
                    }
                }
                if (!exists) {
                    Repositories.Push(repo)
                }
            }
        }
    } catch {
        Repositories := []
    }
}

AppendRepositoryRecord(repo) {
    global RepositoriesFile

    DirCreate(RegExReplace(RepositoriesFile, "\\[^\\]+$"))

    JSON.EscapeUnicode := false
    line := JSON.Dump(repo) . "`n"
    FileAppend(line, RepositoriesFile, "UTF-8")
}

; ============================================================
; 仓库操作
; ============================================================

AddRepository(inputPath) {
    global Repositories

    inputPath := NormalizePath(Trim(inputPath))
    if (inputPath = "") {
        return {success: false, error: "路径不能为空"}
    }

    if (!IsStandardRepoPath(inputPath)) {
        return {success: false, error: "路径必须以 \need 或 \需求 结尾"}
    }

    if (!DirExist(inputPath)) {
        return {success: false, error: "目录不存在"}
    }

    normalizedInput := NormalizePath(inputPath)
    for repo in Repositories {
        if (NormalizePath(repo["path"]) = normalizedInput) {
            return {success: false, error: "仓库已存在"}
        }
    }

    name := ExtractRepoName(inputPath)
    repo := Map(
        "name", name,
        "path", inputPath,
        "addedTime", FormatTime(, "yyyy-MM-dd HH:mm:ss")
    )
    Repositories.Push(repo)
    AppendRepositoryRecord(repo)
    LogDebug("RepositoryManager: added repository '" name "' at " inputPath)

    return {success: true, error: ""}
}

ExtractRepoName(repoPath) {
    normalized := NormalizePath(repoPath)

    posNeed := InStr(normalized, "\need\", 0)
    posDemand := InStr(normalized, "\需求\", 0)

    if (!posNeed && !posDemand) {
        posNeed := 0
        if (SubStr(normalized, -5) = "\need") {
            posNeed := StrLen(normalized) - 5
        }
        if (SubStr(normalized, -3) = "\需求") {
            posDemand := StrLen(normalized) - 3
        }
    }

    pos := Max(posNeed, posDemand)
    if (pos > 0) {
        prefix := SubStr(normalized, 1, pos - 1)
        SplitPath(prefix, &name)
        return name
    }

    SplitPath(normalized, &fallbackName)
    return fallbackName
}

FindRepoByThemePath(themePath) {
    global Repositories

    themePath := NormalizePath(themePath)
    bestMatch := ""
    bestLen := 0

    for repo in Repositories {
        repoPath := NormalizePath(repo["path"])
        if (InStr(themePath "\", repoPath "\") = 1) {
            repoLen := StrLen(repoPath)
            if (repoLen > bestLen) {
                bestMatch := repo
                bestLen := repoLen
            }
        }
    }

    return bestMatch
}

GetRepoThemes(repoPath) {
    themes := []
    if (!DirExist(repoPath)) {
        return themes
    }

    Loop Files, repoPath "\*", "D" {
        name := A_LoopFileName
        if (name = "归档" || name = ".aiprocess") {
            continue
        }
        themes.Push(name)
    }

    return themes
}

GetRepoName(repoPath) {
    global Repositories

    normalizedInput := NormalizePath(repoPath)
    for repo in Repositories {
        if (NormalizePath(repo["path"]) = normalizedInput) {
            return repo["name"]
        }
    }

    return ExtractRepoName(repoPath)
}

; ============================================================
; 工具函数
; ============================================================

IsStandardRepoPath(path) {
    normalized := NormalizePath(path)
    normalizedLower := StrLower(normalized)
    return SubStr(normalizedLower, -5) = "\need" || SubStr(normalizedLower, -3) = "\需求"
}

GetRepoArchiveDir(repoPath) {
    return NormalizePath(repoPath) "\归档"
}

IsArchivedTheme(themePath) {
    return InStr(NormalizePath(themePath), "\归档\") ? true : false
}

ExtractRepoPath(themePath) {
    currentPath := NormalizePath(themePath)
    Loop 20 {
        if (IsStandardRepoPath(currentPath)) {
            return currentPath
        }
        SplitPath(currentPath,, &parentPath)
        if (parentPath = "" || parentPath = currentPath) {
            break
        }
        currentPath := parentPath
    }
    return ""
}

; ============================================================
; 仓库管理窗口占位（归档模块完成后替换为 ShowRepoWindow）
; ============================================================

ShowRepoWindowPlaceholder() {
    MsgBox("仓库管理功能将在归档模块中实现。", "AIProcess", "Iconi")
}
