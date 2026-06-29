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
