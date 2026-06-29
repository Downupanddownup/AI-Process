#Requires AutoHotkey v2.0

; SummaryGenerator.ahk
; 经验总结生成编排层：校验、构建 Prompt、发送 Agent

GenerateSummary(themePath) {
    if (themePath = "" || !DirExist(themePath)) {
        MsgBox("主题目录无效", "AIProcess", "Iconx")
        return false
    }

    summaryFile := themePath "\.aiprocess\Summary.md"
    if (FileExist(summaryFile)) {
        MsgBox("总结已存在，如需重新生成请删除后重试。", "AIProcess", "Iconi")
        return false
    }

    status := AgentDispatcherGetStatus("SummaryAgent")
    if (!status["IsBound"]) {
        MsgBox("未绑定经验总结 Agent，请先绑定。", "AIProcess", "Iconx")
        return false
    }

    data := CollectSummaryData(themePath)
    if (!IsObject(data) || data.Count = 0) {
        MsgBox("收集主题数据失败", "AIProcess", "Iconx")
        return false
    }

    prompt := BuildSummaryPrompt(data)
    if (prompt = "") {
        MsgBox("构建提示词失败", "AIProcess", "Iconx")
        return false
    }

    result := AgentDispatcherSend("SummaryAgent", prompt)
    if (!result["Success"]) {
        MsgBox("发送失败：" result["Message"], "AIProcess", "Iconx")
        return false
    }

    return true
}

BuildSummaryPrompt(data) {
    global AppRoot

    templatePath := AppRoot "\templates\summary\summary_prompt.txt"
    if (!FileExist(templatePath)) {
        return ""
    }

    try {
        prompt := FileRead(templatePath, "UTF-8")
    } catch Error as err {
        return ""
    }

    prompt := StrReplace(prompt, "{{themePath}}", data["themePath"])
    prompt := StrReplace(prompt, "{{themeName}}", data["themeName"])
    prompt := StrReplace(prompt, "{{fileCount}}", String(data["fileCount"]))
    prompt := StrReplace(prompt, "{{charCount}}", String(data["charCount"]))
    prompt := StrReplace(prompt, "{{lastModifiedFile}}", data["lastModifiedFile"])
    prompt := StrReplace(prompt, "{{lastModifiedTime}}", data["lastModifiedTime"])
    prompt := StrReplace(prompt, "{{totalTime}}", data["totalTime"])
    prompt := StrReplace(prompt, "{{discussionTime}}", data["discussionTime"])
    prompt := StrReplace(prompt, "{{executeTime}}", data["executeTime"])
    prompt := StrReplace(prompt, "{{tweakTime}}", data["tweakTime"])
    prompt := StrReplace(prompt, "{{fileTree}}", data["fileTree"])
    prompt := StrReplace(prompt, "{{coreFiles}}", BuildCoreFilesText(data["coreFiles"]))
    prompt := StrReplace(prompt, "{{logEntries}}", data["logEntries"])
    prompt := StrReplace(prompt, "{{subThemes}}", BuildSubThemesText(data["subThemes"]))
    prompt := StrReplace(prompt, "{{summaryTemplatePath}}", AppRoot "\templates\summary\summary_template.md")
    prompt := StrReplace(prompt, "{{notifyScriptPath}}", AppRoot "\powershell\summary\NotifySummaryComplete.ps1")

    return prompt
}

BuildCoreFilesText(coreFiles) {
    if (!IsObject(coreFiles)) {
        return ""
    }
    lines := ""
    for path in coreFiles {
        lines .= "- " path "`n"
    }
    return RTrim(lines, "`n")
}

BuildSubThemesText(subThemes) {
    if (!IsObject(subThemes) || subThemes.Length = 0) {
        return "无"
    }

    text := ""
    for sub in subThemes {
        text .= "- " sub["path"] "`n"
        text .= "  - 总耗时：" sub["totalTime"] "`n"
        text .= "  - 讨论耗时：" sub["discussionTime"] "`n"
        text .= "  - 执行耗时：" sub["executeTime"] "`n"
        text .= "  - 结果微调耗时：" sub["tweakTime"] "`n"
    }
    return RTrim(text, "`n")
}
