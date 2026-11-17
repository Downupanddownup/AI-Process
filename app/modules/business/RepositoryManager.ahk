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
                itemPath := item.Has("path") ? item["path"] : ""
                if (itemPath = "") {
                    continue
                }
                repo := Map(
                    "name", ExtractRepoName(itemPath),
                    "path", itemPath,
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
        return {success: false, error: DomainConventions.RepoRootRuleHint}
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

; 自动注册：任意目录向上推导仓库根，未注册则注册
EnsureRepoRegistered(dirPath) {
    if (dirPath = "") {
        return
    }
    if (FindRepoByThemePath(dirPath) != "") {
        return
    }
    repoPath := ExtractRepoPath(dirPath)
    if (repoPath != "" && DirExist(repoPath)) {
        AddRepository(repoPath)
    }
}

ExtractRepoName(repoPath) {
    normalized := NormalizePath(repoPath) "\"

    posNeed := InStr(normalized, "\" DomainConventions.RepoSuffixNeed "\", 0)
    posDemand := InStr(normalized, "\" DomainConventions.RepoSuffixDemand "\", 0)

    pos := Max(posNeed, posDemand)
    if (pos > 0) {
        prefix := SubStr(normalized, 1, pos - 1)
        SplitPath(prefix, &name)
        return name
    }

    SplitPath(NormalizePath(repoPath), &fallbackName)
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
        if (name = DomainConventions.ArchiveDir || name = DomainConventions.DataDir) {
            continue
        }
        themes.Push(name)
    }

    return themes
}

; 带活跃时间的主题查询：供仓库管理窗口识别列使用
; 返回 [{name, lastActiveAt}, ...]，按活跃倒序，无数据的排尾（保持目录扫描原序）
; 不改旧 GetRepoThemes 的返回结构——设置主题弹窗仍在消费它
GetRepoThemesWithActivity(repoPath) {
    withTime := []
    withoutTime := []

    for name in GetRepoThemes(repoPath) {
        stats := ThemeCost.ReadStats(repoPath "\" name)
        lastActiveAt := ThemeCost.GetText(stats, "aggregate", "lastActiveAt")
        item := Map("name", name, "lastActiveAt", lastActiveAt)
        if (lastActiveAt != "") {
            withTime.Push(item)
        } else {
            withoutTime.Push(item)
        }
    }

    ; "YYYY-MM-DD HH:MM:SS" 定长可按字典序比较；插入排序（主题数量级小）
    ; 注意：AHK v2 的关系运算符不接受字符串，必须用 StrCompare（实测 >= 抛"Expected a Number"）
    sorted := []
    for item in withTime {
        idx := 1
        while (idx <= sorted.Length && StrCompare(sorted[idx]["lastActiveAt"], item["lastActiveAt"], true) >= 0) {
            idx++
        }
        sorted.InsertAt(idx, item)
    }
    for item in withoutTime {
        sorted.Push(item)
    }

    return sorted
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
    return DomainConventions.IsRepoRootDir(path)
}

GetRepoArchiveDir(repoPath) {
    return NormalizePath(repoPath) "\" DomainConventions.ArchiveDir
}

IsArchivedTheme(themePath) {
    return InStr(NormalizePath(themePath), "\" DomainConventions.ArchiveDir "\") ? true : false
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
