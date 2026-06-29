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
    if (IsObject(data) && data.Has("Error")) {
        MsgBox("收集主题数据失败：`n" data["Error"], "AIProcess", "Iconx")
        return false
    }
    if (!IsObject(data) || data.Count = 0) {
        MsgBox("收集主题数据失败", "AIProcess", "Iconx")
        return false
    }

    prompt := BuildSummaryPrompt(data)
    if (prompt = "") {
        MsgBox("构建提示词失败", "AIProcess", "Iconx")
        return false
    }

    ; 将完整 Prompt 写入临时文件，避免剪贴板内容过长被拦截
    tmpDir := themePath "\.aiprocess\_tmp"
    if (!DirExist(tmpDir)) {
        DirCreate(tmpDir)
    }
    promptFile := tmpDir "\summary_prompt_" A_Now A_MSec ".txt"
    try {
        FileAppend(prompt, promptFile, "UTF-8")
    } catch Error as err {
        MsgBox("保存提示词失败：" err.Message, "AIProcess", "Iconx")
        return false
    }

    ; 剪贴板中只放文件路径和简单说明
    shortMessage := "请查看这个文件：" promptFile "`n这是本次「经验总结」任务的完整提示词，请按其中的要求和模板生成 Summary.md。"

    result := AgentDispatcherSend("SummaryAgent", shortMessage)
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
    prompt := StrReplace(prompt, "{{tweakBreakdown}}", BuildTweakBreakdownText(data["tweakBreakdown"]))
    prompt := StrReplace(prompt, "{{fileTree}}", data["fileTree"])
    prompt := StrReplace(prompt, "{{coreFiles}}", BuildCoreFilesText(data["coreFiles"]))
    prompt := StrReplace(prompt, "{{subThemes}}", BuildSubThemesText(data["subThemes"]))
    prompt := StrReplace(prompt, "{{summaryTemplatePath}}", AppRoot "\templates\summary\summary_template.md")
    prompt := StrReplace(prompt, "{{notifyScriptPath}}", AppRoot "\powershell\summary\NotifySummaryComplete.ps1")

    return prompt
}

BuildCoreFilesText(coreFiles) {
    if (!IsObject(coreFiles)) {
        if (coreFiles = "") {
            return ""
        }
        lines := ""
        Loop Parse, coreFiles, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line != "") {
                lines .= "- " line "`n"
            }
        }
        return RTrim(lines, "`n")
    }

    lines := ""
    for path in coreFiles {
        lines .= "- " path "`n"
    }
    return RTrim(lines, "`n")
}

BuildSubThemesText(subThemes) {
    if (!IsObject(subThemes)) {
        return "无"
    }
    count := subThemes.HasProp("Length") ? subThemes.Length : subThemes.Count
    if (count = 0) {
        return "无"
    }

    text := ""
    if (subThemes.HasProp("Count")) {
        text .= BuildSubThemeItemText(subThemes)
    } else {
        for sub in subThemes {
            text .= BuildSubThemeItemText(sub)
        }
    }
    return RTrim(text, "`n")
}

BuildSubThemeItemText(sub) {
    return "- " sub["path"] "`n"
        . "  - 总耗时：" sub["totalTime"] "`n"
        . "  - 讨论耗时：" sub["discussionTime"] "`n"
        . "  - 执行耗时：" sub["executeTime"] "`n"
        . "  - 结果微调耗时：" sub["tweakTime"] "`n"
}

BuildTweakBreakdownText(tweakBreakdown) {
    if (!IsObject(tweakBreakdown)) {
        return ""
    }
    count := tweakBreakdown.HasProp("Length") ? tweakBreakdown.Length : tweakBreakdown.Count
    if (count = 0) {
        return ""
    }

    text := ""
    if (tweakBreakdown.HasProp("Count")) {
        if (tweakBreakdown.Has("name") && tweakBreakdown.Has("duration")) {
            text .= "  - " tweakBreakdown["name"] "：" tweakBreakdown["duration"] "`n"
        }
    } else {
        for item in tweakBreakdown {
            text .= "  - " item["name"] "：" item["duration"] "`n"
        }
    }
    return RTrim(text, "`n")
}
