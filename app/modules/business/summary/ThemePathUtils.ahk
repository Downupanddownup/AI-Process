#Requires AutoHotkey v2.0

; 从主题路径中提取归属项目名
; 规则：找 \需求\ 或 \need\，取上一级；兜底取父级目录名
ExtractProjectName(path) {
    pathNoDrive := RegExReplace(path, "^[A-Z]:\\", "")

    pos := InStr(pathNoDrive, "\需求\")
    if (!pos) {
        pos := InStr(pathNoDrive, "\need\")
    }

    if (pos) {
        prefix := SubStr(pathNoDrive, 1, pos - 1)
        SplitPath(prefix, &projectName)
        return projectName
    }

    ; 兜底：取主题目录的父级
    SplitPath(path,, &parentDir)
    SplitPath(parentDir, &fallbackName)
    return fallbackName
}
