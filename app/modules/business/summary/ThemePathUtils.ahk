#Requires AutoHotkey v2.0

; 从主题路径中提取归属项目名
; 规则：经仓库单源（注册表 → 路径推导），兜底取父级目录名
ExtractProjectName(path) {
    ; 优先通过仓库管理器查找
    repo := FindRepoByThemePath(path)
    if (repo != "") {
        return repo["name"]
    }

    ; 未注册时按仓库根规则推导
    repoPath := ExtractRepoPath(path)
    if (repoPath != "") {
        return ExtractRepoName(repoPath)
    }

    ; 兜底：取主题目录的父级
    SplitPath(path,, &parentDir)
    SplitPath(parentDir, &fallbackName)
    return fallbackName
}
