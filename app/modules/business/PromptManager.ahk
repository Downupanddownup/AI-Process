#Requires AutoHotkey v2.0

; 提示词模板与管理

global ExecuteStrategies := [
    ; Map("key", "direct", "label", "直接", "template", "execute\direct.txt", "feedback", "执行提示词已复制"),
    Map("key", "ai_judge", "label", "AI判", "template", "execute\ai_judge.txt", "feedback", "AI判断提示词已复制"),
    ; Map("key", "steps_file", "label", "步文", "template", "execute\steps_file.txt", "feedback", "步骤文档提示词已复制"),
    Map("key", "steps_dir", "label", "步目", "template", "execute\steps_dir.txt", "feedback", "步骤目录提示词已复制"),
    Map("key", "tweak", "label", "改吧", "template", "execute\tweak.txt", "feedback", "改吧提示词已复制")
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

    templatePath := TemplateDir "\question_format.txt"
    if !FileExist(templatePath) {
        return content
    }

    hint := "如需提问，请参照提问模板：" templatePath
    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" hint
}



AppendExecuteNotificationIfNeeded(content) {
    global AppConfig, TemplateDir
    windowId := GetActiveWindowId()

    templatePath := TemplateDir "\execute_notification_prompt.txt"
    if (!FileExist(templatePath)) {
        return content
    }

    ; 改吧：无条件追加，指向 WriteExecResultDoc（结果文档+打开由其处理；通知由脚本按开关控制）
    if (GetSelectedExecuteStrategy() = "tweak") {
        template := FileRead(templatePath, "UTF-8")
        template := StrReplace(template, "{{scriptPath}}", AppConfig["ExecResultScriptPath"])
        template := StrReplace(template, "{{windowId}}", windowId)
        template := StrReplace(template, "{{silentArg}}", "")
        baseContent := RTrim(content, "`r`n")
        return baseContent "`r`n`r`n" template
    }

    ; 其它策略：无条件追加（日志补全：完成时刻必须落日志）；
    ; "显示通知"开关关闭时以 -Silent 调用：日志照写、不弹窗
    template := FileRead(templatePath, "UTF-8")
    template := StrReplace(template, "{{scriptPath}}", AppConfig["NotificationScriptPath"])
    template := StrReplace(template, "{{windowId}}", windowId)
    silentArg := GetSession(windowId, "ShowExecuteNotification") ? "" : " -Silent"
    template := StrReplace(template, "{{silentArg}}", silentArg)

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" template
}



AppendContextRelationTailIfNeeded(content) {
    global AppConfig, TemplateDir
    windowId := GetActiveWindowId()

    templatePath := TemplateDir "\context_relation_tail.txt"
    if !FileExist(templatePath) {
        return content
    }

    template := FileRead(templatePath, "UTF-8")
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
    content := AppendQuestionTemplateIfNeeded(content)
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
}



CopyContextRelations(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    content := BuildContextRelationsText()
    content := AppendNoModifyPromptIfNeeded(content)
    content := AppendOpenMdPromptIfNeeded(content)
    content := AppendContextRelationTailIfNeeded(content)
    A_Clipboard := content
    LogActivity("复关系", content, Map("target", "上下文重建"))
    ShowFeedback("文件关系说明已复制")
    HandleAgentWindowAfterCopy()

    MaybeAutoHide()
}



CopyExecutePrompt(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    selectedStrategy := GetSelectedExecuteStrategy()
    strategyMeta := GetExecuteStrategyMeta(selectedStrategy)

    if (selectedStrategy = "tweak") {
        ; "改吧"策略：不需要实施文档.md
        content := LoadTemplate(strategyMeta["template"])
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

    content := AppendExecuteNotificationIfNeeded(content)

    properties := Map("执行策略", strategyMeta["label"])
    if (selectedStrategy = "tweak") {
        ; 改吧会产出结果 md：按 WriteExecResultDoc 同一命名规则预填 target
        if FileExist(currentDir "\实施文档.md") {
            properties["target"] := "已实施.md"
        } else {
            properties["target"] := "v" (GetLatestVersionNumber(currentDir) + 1) ".md"
        }
    }

    A_Clipboard := content
    LogActivity("复执行", content, properties)
    ShowFeedback(strategyMeta["feedback"])
    HandleAgentWindowAfterCopy()

    MaybeAutoHide()
}
