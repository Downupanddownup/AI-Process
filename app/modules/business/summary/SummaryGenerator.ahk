#Requires AutoHotkey v2.0

; SummaryGenerator.ahk
; 经验总结生成编排层：校验、构建 Prompt、发送 Agent

GenerateSummary(themePath) {
    if (themePath = "" || !DirExist(themePath)) {
        MsgBox("主题目录无效", "AIProcess", "Iconx")
        return false
    }

    summaryFile := themePath "\.aiprocess\Summary.json"
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
    shortMessage := "请查看这个文件：" promptFile "`n这是本次「经验总结」任务的完整提示词，请按其中的要求和模板生成 Summary.json。"

    result := AgentDispatcherSend("SummaryAgent", shortMessage)
    if (!result["Success"]) {
        MsgBox("发送失败：" result["Message"], "AIProcess", "Iconx")
        return false
    }

    return true
}

BuildSummaryPrompt(data) {
    global AppRoot

    themePath := data["themePath"]
    themeName := data["themeName"]
    tmpDir := themePath "\.aiprocess\_tmp"

    ; 复制稳定规则文件到主题临时目录，方便 Agent 一次性读取
    guideSrc := AppRoot "\templates\summary\summary_input_guide.md"
    templateSrc := AppRoot "\templates\summary\summary_template.json"
    rulesSrc := AppRoot "\templates\summary\summary_rules.md"

    guideDst := tmpDir "\summary_input_guide.md"
    templateDst := tmpDir "\summary_template.json"
    rulesDst := tmpDir "\summary_rules.md"

    if (!FileExist(guideSrc) || !FileExist(templateSrc) || !FileExist(rulesSrc)) {
        MsgBox("缺少经验总结规则模板文件，请检查 app/templates/summary/ 目录。", "AIProcess", "Iconx")
        return ""
    }

    try {
        FileCopy(guideSrc, guideDst, true)
        FileCopy(templateSrc, templateDst, true)
        FileCopy(rulesSrc, rulesDst, true)
    } catch Error as err {
        MsgBox("复制规则模板文件失败：" err.Message, "AIProcess", "Iconx")
        return ""
    }

    inputFile := tmpDir "\summary_input.json"
    notifyScript := AppRoot "\powershell\summary\NotifySummaryComplete.ps1"

    prompt := "你是 AI Process 的「经验总结」助手。本次任务是基于主题素材生成结构化总结 JSON。`n`n"
    prompt .= "请按以下顺序读取文件，然后生成 Summary.json：`n"
    prompt .= "1. 素材说明：" guideDst "`n"
    prompt .= "2. 输出模板：" templateDst "`n"
    prompt .= "3. 生成规则：" rulesDst "`n"
    prompt .= "4. 主题素材：" inputFile "`n`n"
    prompt .= "要求：`n"
    prompt .= "- 严格按输出模板生成 JSON，不要增删字段。`n"
    prompt .= "- 严格按生成规则进行分类、摘要、分析和自检。`n"
    prompt .= "- 生成完成后，将 Summary.json 保存到：" themePath "\.aiprocess\Summary.json`n"
    prompt .= Format("- 保存后执行：powershell -ExecutionPolicy Bypass -File `"{1:s}`" -ThemePath `"{2:s}`" -Status `"done`"`n`n", notifyScript, themePath)
    prompt .= "主题名称：" themeName "`n"
    prompt .= "主题路径：" themePath "`n"

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
