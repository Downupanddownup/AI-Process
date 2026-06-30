#Requires AutoHotkey v2.0

; ReportGenerator.ahk
; 报告生成数据收集：查索引 → 分组排序 → 拼 prompt → 写入临时文件

BuildReportPrompt(filterName, dateRange, reportPath) {
    global AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    reportType := GetReportType(filterName)
    dateRangeText := FormatDateRangeText(dateRange)

    themes := LoadThemes(dateRange)
    if (themes.Length = 0) {
        return ""
    }

    ; 按归属项目分组
    projectGroups := Map()
    for theme in themes {
        projectName := ExtractProjectName(theme.path)
        if (!projectGroups.Has(projectName)) {
            projectGroups[projectName] := []
        }
        projectGroups[projectName].Push(theme)
    }

    ; 组内按时间升序
    for projectName, group in projectGroups {
        SortThemesByTimeAsc(group)
    }

    ; 项目按最近活动时间降序（活跃项目排前面）
    sortedProjects := []
    for projectName, group in projectGroups {
        latestTime := group[group.Length].lastAccessTime
        sortedProjects.Push({name: projectName, themes: group, latestTime: latestTime})
    }
    SortProjectsByTimeDesc(sortedProjects)

    ; 统计主题数
    totalCount := 0
    for project in sortedProjects {
        totalCount += project.themes.Length
    }

    ; 拼主题列表文本（精简格式）
    themeList := ""
    themeIndex := 1
    for project in sortedProjects {
        themeList .= "### " project.name "`n"
        for theme in project.themes {
            duration := CalculateThemeDuration(theme.path)
            summaryPath := theme.path "\.aiprocess\Summary.md"
            implDocPath := theme.path "\实施文档.md"

            if (FileExist(summaryPath)) {
                themeList .= Format("{}. {} → 执行时长：{} → Summary: {}`n", themeIndex, theme.path, duration, summaryPath)
            } else {
                entry := Format("{}. {} → 执行时长：{} → Summary: 无", themeIndex, theme.path, duration)
                if (FileExist(implDocPath)) {
                    entry .= "，有 实施文档.md"
                }
                themeList .= entry "`n"
            }
            themeIndex += 1
        }
        themeList .= "`n"
    }

    ; 读提示词模板
    templatePath := AppRoot "\templates\report\report_prompt.txt"
    if (!FileExist(templatePath)) {
        return ""
    }
    try {
        prompt := FileRead(templatePath, "UTF-8")
    } catch Error as err {
        return ""
    }

    ; 替换占位符
    prompt := StrReplace(prompt, "{{reportType}}", reportType)
    prompt := StrReplace(prompt, "{{totalCount}}", String(totalCount))
    prompt := StrReplace(prompt, "{{projectCount}}", String(sortedProjects.Length))
    prompt := StrReplace(prompt, "{{dateRange}}", dateRangeText)
    prompt := StrReplace(prompt, "{{reportPath}}", reportPath)
    prompt := StrReplace(prompt, "{{themeList}}", themeList)
    prompt := StrReplace(prompt, "{{reportTemplatePath}}", AppRoot "\templates\report\report_template.md")
    prompt := StrReplace(prompt, "{{reportCompletePs1}}", projectRoot "\app\powershell\report\ReportComplete.ps1")

    ; 清理旧临时文件 + 写入新文件
    tmpDir := AppRoot "\_tmp"
    DirCreate(tmpDir)
    Loop Files, tmpDir "\report_prompt_*.txt", "F" {
        FileDelete(A_LoopFileFullPath)
    }
    tmpPath := tmpDir "\report_prompt_" A_Now ".txt"
    FileAppend(prompt, tmpPath, "UTF-8")

    return tmpPath
}

SortThemesByTimeAsc(themes) {
    n := themes.Length
    Loop n - 1 {
        i := 1
        Loop n - A_Index {
            t1 := RegExReplace(themes[i].lastAccessTime, "[^\d]")
            t2 := RegExReplace(themes[i + 1].lastAccessTime, "[^\d]")
            if (t1 > t2) {
                tmp := themes[i]
                themes[i] := themes[i + 1]
                themes[i + 1] := tmp
            }
            i += 1
        }
    }
}

SortProjectsByTimeDesc(projects) {
    n := projects.Length
    Loop n - 1 {
        i := 1
        Loop n - A_Index {
            t1 := RegExReplace(projects[i].latestTime, "[^\d]")
            t2 := RegExReplace(projects[i + 1].latestTime, "[^\d]")
            if (t1 < t2) {
                tmp := projects[i]
                projects[i] := projects[i + 1]
                projects[i + 1] := tmp
            }
            i += 1
        }
    }
}
