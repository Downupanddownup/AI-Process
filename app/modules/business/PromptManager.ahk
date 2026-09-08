#Requires AutoHotkey v2.0

; 提示词模板与管理

global ExecuteStrategies := [
    Map("key", "tweak", "label", "改吧", "template", "execute\tweak.txt", "feedback", "改吧提示词已复制"),
    Map("key", "steps_dir", "label", "步目", "template", "execute\steps_dir.txt", "feedback", "步目提示词已复制")
]


LoadTemplate(fileName) {
    global TemplateDir
    path := TemplateDir "\" fileName
    if !FileExist(path) {
        LogError("模板文件不存在：" path)
        throw Error("模板文件不存在：" path)
    }
    return FileRead(path, "UTF-8")
}

EnsureTemplateExists(fileName) {
    global TemplateDir
    path := TemplateDir "\" fileName
    if !FileExist(path) {
        LogError("模板文件不存在：" path)
        throw Error("模板文件不存在：" path)
    }
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
    global AppConfig
    if (!GetSession(GetActiveWindowId(), "OpenMdWithIdea")) {
        return content
    }

    template := LoadTemplate("open_md_prompt.txt")
    template := StrReplace(template, "{{scriptPath}}", AppConfig["OpenMdScriptPath"])
    template := StrReplace(template, "{{windowId}}", GetActiveWindowId())

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" template
}



AppendQuestionRulesIfNeeded(content) {
    if !GetSession(GetActiveWindowId(), "AppendQuestionRules") {
        return content
    }

    rulesContent := Trim(LoadTemplate("question_rules.txt"), "`r`n `t")
    if (rulesContent = "") {
        return content
    }

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" rulesContent
}



AppendQuestionTemplateIfNeeded(content) {
    global TemplateDir
    if !GetSession(GetActiveWindowId(), "AppendQuestionTemplate") {
        return content
    }

    EnsureTemplateExists("question_format.txt")

    hint := "如需提问，请参照提问模板：" TemplateDir "\question_format.txt"
    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" hint
}



AppendExecuteNotificationIfNeeded(content) {
    global AppConfig
    windowId := GetActiveWindowId()

    ; 其它策略：无条件追加（日志补全：完成时刻必须落日志）；
    ; "显示通知"开关关闭时以 -Silent 调用：日志照写、不弹窗
    template := LoadTemplate("execute_notification_prompt.txt")
    template := StrReplace(template, "{{scriptPath}}", AppConfig["NotificationScriptPath"])
    template := StrReplace(template, "{{windowId}}", windowId)
    silentArg := GetSession(windowId, "ShowExecuteNotification") ? "" : " -Silent"
    template := StrReplace(template, "{{silentArg}}", silentArg)

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" template
}



AppendContextRelationTailIfNeeded(content) {
    global AppConfig
    windowId := GetActiveWindowId()

    template := LoadTemplate("context_relation_tail.txt")
    template := StrReplace(template, "{{scriptPath}}", AppConfig["NotificationScriptPath"])
    template := StrReplace(template, "{{windowId}}", windowId)
    silentArg := GetSession(windowId, "ShowExecuteNotification") ? "" : " -Silent"
    template := StrReplace(template, "{{silentArg}}", silentArg)

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" template
}



BuildContextRelationsText() {
    currentDir := GetCurrentDir()

    allFiles := GetAllFilesRecursive(currentDir)
    if (allFiles.Length = 0) {
        return "当前主题目录：" currentDir "`n`n当前目录下未找到任何文件。"
    }

    universalGuide := LoadTemplate("context_relation.txt")

    fileTree := ""
    for path in allFiles {
        fileTree .= path "`n"
    }

    return "当前主题目录：" currentDir
        . "`n`n## 通用解读提示`n" . universalGuide
        . "`n`n## 当前目录完整文件清单`n" . fileTree
}



CopyRequirementPrompt(*) {
    try {
        if !EnsureCurrentDirectory() {
            return
        }

        currentDir := GetCurrentDir()
        content := LoadTemplate("requirement_prompt.txt")
        content := StrReplace(content, "{{filePath}}", currentDir "\需求.txt")
        content := AppendNoModifyPromptIfNeeded(content)
        content := AppendQuestionRulesIfNeeded(content)
        content := AppendQuestionTemplateIfNeeded(content)
        content := AppendOpenMdPromptIfNeeded(content)
        A_Clipboard := content
        LogActivity("复需求", content, Map("target", "v1.md", "source", "需求.txt"))
        ShowFeedback("需求提示词已复制")
        HandleAgentWindowAfterCopy()

        MaybeAutoHide()
    } catch Error as err {
        LogError("复需求提示词复制失败：" err.Message)
        ShowFeedback("提示词复制失败：" err.Message, true)
    }
}



CopyReplyPrompt(*) {
    try {
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
        implChecked := GetSession(GetActiveWindowId(), "AppendImplementationTail")

        if (implChecked) {
            content := LoadTemplate("reply_prompt_impl_tail.txt")
            content := StrReplace(content, "{{filePath}}", currentReplyFile)
        } else {
            content := LoadTemplate("reply_prompt.txt")
            content := StrReplace(content, "{{filePath}}", currentReplyFile)
            content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
        }

        content := AppendNoModifyPromptIfNeeded(content)
        if (!implChecked) {
            content := AppendQuestionTemplateIfNeeded(content)
        }
        content := AppendOpenMdPromptIfNeeded(content)

        properties := Map()
        properties["source"] := "对v" latestVersion "的回复.txt"
        if (implChecked) {
            properties["实"] := true
            properties["target"] := "实施文档.md"
        } else {
            properties["target"] := nextVersionFile
        }

        A_Clipboard := content
        LogActivity("复回复", content, properties)
        ShowFeedback("回复提示词已复制")
        HandleAgentWindowAfterCopy()

        MaybeAutoHide()
    } catch Error as err {
        LogError("复回复提示词复制失败：" err.Message)
        ShowFeedback("提示词复制失败：" err.Message, true)
    }
}



CopyContextRelations(*) {
    try {
        if !EnsureCurrentDirectory() {
            return
        }

        content := BuildContextRelationsText()
        content := AppendNoModifyPromptIfNeeded(content)
        content := AppendContextRelationTailIfNeeded(content)
        A_Clipboard := content
        LogActivity("复关系", content, Map("target", "上下文重建"))
        ShowFeedback("文件关系说明已复制")
        HandleAgentWindowAfterCopy()

        MaybeAutoHide()
    } catch Error as err {
        LogError("文件关系说明复制失败：" err.Message)
        ShowFeedback("文件关系说明复制失败：" err.Message, true)
    }
}



CopyExecutePrompt(*) {
    global AppConfig, TemplateDir
    try {
        if !EnsureCurrentDirectory() {
            return
        }

        currentDir := GetCurrentDir()
        selectedStrategy := GetSelectedExecuteStrategy()
        strategyMeta := GetExecuteStrategyMeta(selectedStrategy)

        if (selectedStrategy = "tweak") {
            ; "改吧"策略：结果文档由 AI 按模板撰写，文件名沿用同一规则（有实施文档.md→已实施.md，否则 v(N+1).md）
            if FileExist(currentDir "\实施文档.md") {
                resultName := "已实施.md"
            } else {
                resultName := "v" (GetLatestVersionNumber(currentDir) + 1) ".md"
            }
            content := LoadTemplate(strategyMeta["template"])
            content := StrReplace(content, "{{resultFilePath}}", currentDir "\" resultName)
            EnsureTemplateExists("execute\result_doc.md")
            content := StrReplace(content, "{{resultTemplatePath}}", TemplateDir "\execute\result_doc.md")
            content := StrReplace(content, "{{openMdScriptPath}}", AppConfig["OpenMdScriptPath"])
            content := StrReplace(content, "{{windowId}}", GetActiveWindowId())
        } else {
            ; 原有 4 种策略：必须存在实施文档.md
            implementationPath := currentDir "\实施文档.md"
            if !FileExist(implementationPath) {
                ShowFeedback("当前目录下未找到 实施文档.md", true)
                return
            }
            content := LoadTemplate(strategyMeta["template"])
            content := StrReplace(content, "{{filePath}}", implementationPath)
        }

        if (selectedStrategy != "tweak") {
            content := AppendExecuteNotificationIfNeeded(content)
        }

        properties := Map("执行策略", strategyMeta["label"])
        if (selectedStrategy = "tweak") {
            ; 改吧会产出结果 md：target 复用上面已算出的 resultName
            properties["target"] := resultName
        }

        A_Clipboard := content
        LogActivity("复执行", content, properties)
        ShowFeedback(strategyMeta["feedback"])
        HandleAgentWindowAfterCopy()

        MaybeAutoHide()
    } catch Error as err {
        LogError("执行提示词复制失败：" err.Message)
        ShowFeedback("执行提示词复制失败：" err.Message, true)
    }
}
