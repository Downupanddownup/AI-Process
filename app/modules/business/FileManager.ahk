#Requires AutoHotkey v2.0

; 文件创建与管理


OpenFileInIdea(filePath) {
    global AppConfig
    try {
        Run('"' AppConfig["IdeaCommand"] '" "' filePath '"')
    } catch Error {
        ShowFeedback("IDEA 打开失败，请检查 settings.ini 中的 IdeaCommand", true)
    }
}



EnsureCurrentDirectory() {
    if GetCurrentDir() = "" {
        ShowFeedback("请先设置当前主题目录", true)
        return false
    }
    return true
}



GetLatestVersionNumber(dirPath) {
    latest := 0
    Loop Files, dirPath "\v*.md", "F" {
        if RegExMatch(A_LoopFileName, "^v(\d+)\.md$", &match) {
            version := match[1] + 0
            if (version > latest) {
                latest := version
            }
        }
    }
    return latest
}


GetOrderedContextFiles(dirPath) {
    orderedFiles := []
    requirementPath := dirPath "\需求.txt"
    implementationPath := dirPath "\实施文档.md"

    if FileExist(requirementPath) {
        orderedFiles.Push(requirementPath)
    }

    versions := []
    Loop Files, dirPath "\v*.md", "F" {
        if RegExMatch(A_LoopFileName, "^v(\d+)\.md$", &match) {
            version := match[1] + 0
            versions.Push(Map(
                "version", version,
                "path", A_LoopFileFullPath,
                "replyPath", dirPath "\对v" version "的回复.txt"
            ))
        }
    }

    if (versions.Length > 1) {
        loopCount := versions.Length - 1
        Loop loopCount {
            changed := false
            index := 1
            while (index <= versions.Length - A_Index) {
                if (versions[index]["version"] > versions[index + 1]["version"]) {
                    temp := versions[index]
                    versions[index] := versions[index + 1]
                    versions[index + 1] := temp
                    changed := true
                }
                index += 1
            }
            if !changed {
                break
            }
        }
    }

    for item in versions {
        orderedFiles.Push(item["path"])
        if FileExist(item["replyPath"]) {
            orderedFiles.Push(item["replyPath"])
        }
    }

    if FileExist(implementationPath) {
        orderedFiles.Push(implementationPath)
    }

    return orderedFiles
}



CreateRequirementFile(*) {
    global AppConfig
    if !EnsureCurrentDirectory() {
        return
    }

    filePath := GetCurrentDir() "\需求.txt"
    existed := FileExist(filePath)
    if !existed {
        FileAppend("", filePath, "UTF-8")
        ShowFeedback("已创建：需求.txt")
    } else {
        ShowFeedback("文件已存在：需求.txt", true)
    }

    if AppConfig["OpenWithIdea"] {
        OpenFileInIdea(filePath)
    }

    MaybeAutoHide()
}



CreateReplyFile(*) {
    global AppConfig
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    latestVersion := GetLatestVersionNumber(currentDir)
    if (latestVersion = 0) {
        ShowFeedback("当前目录下未找到 vX.md 文件", true)
        return
    }

    replyPath := currentDir "\对v" latestVersion "的回复.txt"
    existed := FileExist(replyPath)
    if !existed {
        FileAppend("", replyPath, "UTF-8")
        ShowFeedback("已创建：" ExtractFileName(replyPath))
    } else {
        ShowFeedback("文件已存在：" ExtractFileName(replyPath), true)
    }

    if AppConfig["OpenWithIdea"] {
        OpenFileInIdea(replyPath)
    }

    MaybeAutoHide()
}

