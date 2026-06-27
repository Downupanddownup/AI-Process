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


SortIntegers(arr) {
    if (arr.Length <= 1) {
        return
    }
    loopCount := arr.Length - 1
    Loop loopCount {
        changed := false
        i := 1
        while (i <= arr.Length - A_Index) {
            if (arr[i] > arr[i + 1]) {
                tmp := arr[i]
                arr[i] := arr[i + 1]
                arr[i + 1] := tmp
                changed := true
            }
            i += 1
        }
        if !changed {
            break
        }
    }
}


SortByConvention(fullPaths) {
    requirementFile := ""
    vMap := Map()
    replyMap := Map()
    implDocFile := ""
    otherFiles := []

    for path in fullPaths {
        name := ExtractFileName(path)
        if (name = "需求.txt") {
            requirementFile := path
        } else if RegExMatch(name, "^v(\d+)\.md$", &m) {
            vMap[Integer(m[1])] := path
        } else if RegExMatch(name, "^对v(\d+)的回复\.txt$", &m) {
            replyMap[Integer(m[1])] := path
        } else if (name = "实施文档.md") {
            implDocFile := path
        } else {
            otherFiles.Push(path)
        }
    }

    allVersions := []
    for ver in vMap {
        allVersions.Push(ver)
    }
    for ver in replyMap {
        if !vMap.Has(ver) {
            allVersions.Push(ver)
        }
    }
    SortIntegers(allVersions)

    result := []
    if (requirementFile != "") {
        result.Push(requirementFile)
    }
    for ver in allVersions {
        if vMap.Has(ver) {
            result.Push(vMap[ver])
        }
        if replyMap.Has(ver) {
            result.Push(replyMap[ver])
        }
    }
    if (implDocFile != "") {
        result.Push(implDocFile)
    }
    for path in otherFiles {
        result.Push(path)
    }
    return result
}


SortSubdirsByConvention(fullPaths) {
    stepsDir := ""
    tweakDir := ""
    otherDirs := []

    for path in fullPaths {
        name := ExtractFileName(path)
        if (name = "实施步骤") {
            stepsDir := path
        } else if (name = "结果微调") {
            tweakDir := path
        } else {
            otherDirs.Push(path)
        }
    }

    result := []
    if (stepsDir != "") {
        result.Push(stepsDir)
    }
    if (tweakDir != "") {
        result.Push(tweakDir)
    }
    for path in otherDirs {
        result.Push(path)
    }
    return result
}


GetAllFilesRecursive(dirPath) {
    result := []
    files := []
    subdirs := []

    Loop Files, dirPath "\*", "FD" {
        if InStr(A_LoopFileAttrib, "D") {
            subdirs.Push(A_LoopFileFullPath)
        } else {
            files.Push(A_LoopFileFullPath)
        }
    }

    sortedFiles := SortByConvention(files)
    sortedSubdirs := SortSubdirsByConvention(subdirs)

    for filePath in sortedFiles {
        result.Push(filePath)
    }
    for dir in sortedSubdirs {
        subResult := GetAllFilesRecursive(dir)
        for subPath in subResult {
            result.Push(subPath)
        }
    }

    return result
}





CreateRequirementFile(*) {
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

    LogActivity("建需求", "")

    if GetSession(GetActiveWindowId(), "OpenWithIdea") {
        OpenFileInIdea(filePath)
    }

    MaybeAutoHide()
}



CreateReplyFile(*) {
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

    LogActivity("建回复", "")

    if GetSession(GetActiveWindowId(), "OpenWithIdea") {
        OpenFileInIdea(replyPath)
    }

    MaybeAutoHide()
}

