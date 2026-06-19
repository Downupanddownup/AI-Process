#Requires AutoHotkey v2.0

; 提示词模板与管理

global ExecuteStrategies := [
    Map("key", "direct", "label", "直接", "template", "execute\direct.txt", "feedback", "执行提示词已复制"),
    Map("key", "ai_judge", "label", "AI判", "template", "execute\ai_judge.txt", "feedback", "AI判断提示词已复制"),
    Map("key", "steps_file", "label", "步文", "template", "execute\steps_file.txt", "feedback", "步骤文档提示词已复制"),
    Map("key", "steps_dir", "label", "步目", "template", "execute\steps_dir.txt", "feedback", "步骤目录提示词已复制")
]


LoadTemplate(fileName) {
    global TemplateDir
    path := TemplateDir "\" fileName
    if !FileExist(path) {
        throw Error("模板文件不存在：" path)
    }
    return FileRead(path, "UTF-8")
}



BuildExecuteStrategyOptions() {
    global ExecuteStrategies
    options := []
    for strategy in ExecuteStrategies {
        options.Push(strategy["label"])
    }
    return options
}



GetSelectedExecuteStrategy() {
    return GetSession(GetActiveWindowId(), "ExecuteStrategy")
}



GetExecuteStrategyMeta(strategyKey) {
    global ExecuteStrategies
    for strategy in ExecuteStrategies {
        if (strategy["key"] = strategyKey) {
            return strategy
        }
    }
    return ExecuteStrategies[1]
}



AppendNoModifyPromptIfNeeded(content) {
    if !GetSession(GetActiveWindowId(), "AppendNoModifyPrompt") {
        return content
    }

    extraPrompt := Trim(LoadTemplate("no_modify_prompt.txt"), "`r`n `t")
    if (extraPrompt = "") {
        return content
    }

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" extraPrompt
}



AppendOpenMdPromptIfNeeded(content) {
    global AppConfig, TemplateDir
    if (!GetSession(GetActiveWindowId(), "OpenMdWithIdea")) {
        return content
    }

    templatePath := TemplateDir "\open_md_prompt.txt"
    if (!FileExist(templatePath)) {
        return content
    }

    template := FileRead(templatePath, "UTF-8")
    template := StrReplace(template, "{{scriptPath}}", AppConfig["OpenMdScriptPath"])

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" template
}



AppendReplyImplementationTailIfNeeded(content) {
    if !GetSession(GetActiveWindowId(), "AppendImplementationTail") {
        return content
    }

    tailContent := Trim(LoadTemplate("reply_prompt_impl_tail.txt"), "`r`n `t")
    if (tailContent = "") {
        return content
    }

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n" tailContent
}



BuildContextRelationsText() {
    currentDir := GetCurrentDir()

    orderedFiles := GetOrderedContextFiles(currentDir)
    if (orderedFiles.Length = 0) {
        return "当前主题目录：" currentDir "`n`n当前目录下未找到可用于上下文重建的关键文件。"
    }

    readingNames := []
    detailLines := []
    foundRequirement := false
    foundImplementation := false

    for filePath in orderedFiles {
        fileName := ExtractFileName(filePath)
        readingNames.Push(fileName)
        detailLines.Push(fileName "：" filePath)

        if (fileName = "需求.txt") {
            foundRequirement := true
        } else if (fileName = "实施文档.md") {
            foundImplementation := true
        }
    }

    intro := "当前主题目录：" currentDir
    orderLine := "请优先按时间顺序阅读：" JoinArray(readingNames, " -> ")
    roleLines := []

    if foundRequirement {
        roleLines.Push("需求.txt：原始需求说明。")
    }
    roleLines.Push("vX.md：AI 沟通过程中的版本文档。")
    roleLines.Push("对vX的回复.txt：用户对对应版本的回复。")
    if foundImplementation {
        roleLines.Push("实施文档.md：需求沟通收敛后的最终结论文件，也是后续正式实施时最重要的执行依据。")
    }
    roleLines.Push("你的首要任务是基于以上文件完成上下文重建，不要跳过文件整理和阅读步骤。")

    return intro
        . "`n`n" . orderLine
        . "`n`n关键文件路径：`n" . JoinArray(detailLines, "`n")
        . "`n`n文件说明：`n" . JoinArray(roleLines, "`n")
}



CopyRequirementPrompt(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    content := LoadTemplate("requirement_prompt.txt")
    content := StrReplace(content, "{{filePath}}", currentDir "\需求.txt")
    content := AppendNoModifyPromptIfNeeded(content)
    content := AppendOpenMdPromptIfNeeded(content)
    A_Clipboard := content
    ShowFeedback("需求提示词已复制")
    HandleAgentWindowAfterCopy()

    MaybeAutoHide()
}



CopyReplyPrompt(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    latestVersion := GetLatestVersionNumber(currentDir)
    if (latestVersion = 0) {
        ShowFeedback("当前目录下未找到 vX.md 文件", true)
        return
    }

    currentReplyFile := currentDir "\对v" latestVersion "的回复.txt"
    nextVersionFile := "v" (latestVersion + 1) ".md"
    content := LoadTemplate("reply_prompt.txt")
    content := StrReplace(content, "{{filePath}}", currentReplyFile)
    content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
    content := AppendReplyImplementationTailIfNeeded(content)
    content := AppendNoModifyPromptIfNeeded(content)
    content := AppendOpenMdPromptIfNeeded(content)
    A_Clipboard := content
    ShowFeedback("回复提示词已复制")
    HandleAgentWindowAfterCopy()

    MaybeAutoHide()
}



CopyContextRelations(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    content := BuildContextRelationsText()
    content := AppendNoModifyPromptIfNeeded(content)
    content := AppendOpenMdPromptIfNeeded(content)
    A_Clipboard := content
    ShowFeedback("文件关系说明已复制")
    HandleAgentWindowAfterCopy()

    MaybeAutoHide()
}



CopyExecutePrompt(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    implementationPath := currentDir "\实施文档.md"
    if !FileExist(implementationPath) {
        ShowFeedback("当前目录下未找到 实施文档.md", true)
        return
    }

    selectedStrategy := GetSelectedExecuteStrategy()
    strategyMeta := GetExecuteStrategyMeta(selectedStrategy)
    content := LoadTemplate(strategyMeta["template"])
    content := StrReplace(content, "{{filePath}}", implementationPath)
    A_Clipboard := content
    ShowFeedback(strategyMeta["feedback"])
    HandleAgentWindowAfterCopy()

    MaybeAutoHide()
}

