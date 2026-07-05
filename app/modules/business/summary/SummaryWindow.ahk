#Requires AutoHotkey v2.0

; SummaryWindow.ahk
; 经验总结窗口：基于 AHK 原生 Gui 实现

global SummaryGui := ""
global SummaryListView := ""
global SummaryAgentStatusText := ""
global SummaryTotalCountText := ""
global SummaryBindButton := ""
global SummaryActivateButton := ""
global SummaryRebindButton := ""
global SummaryUnbindButton := ""
global SummaryRefreshButton := ""
global SummaryImportHistoryButton := ""
global SummaryFilterButtons := ""
global SummaryDateRangeText := ""
global SummaryReportFilter := ""
global SummaryReportFilterValue := "全部"
global SummaryCurrentFilter := "今天"
global SummaryCustomStartDate := ""
global SummaryCustomEndDate := ""
global SummaryCustomEndIsNow := true
global SummarySelectedThemePath := ""
global SummaryFilterAreaHeight := 0
global SummaryRowPathMap := Map()
global SummaryPathFilterEdit := ""
global SummaryPathFilterValue := ""
global SummaryGenerateReportBtn := ""
global SummaryOpenReportBtn := ""

; 筛选选项
FILTER_DEFINITIONS := [
    {name: "今天", reportType: "日报"},
    {name: "本周", reportType: "周报"},
    {name: "上周", reportType: "周报"},
    {name: "本月", reportType: "月报"},
    {name: "上月", reportType: "月报"},
    {name: "本季", reportType: "季报"},
    {name: "本年", reportType: "年报"}
]

ShowSummaryWindow(*) {
    global SummaryGui

    if (SummaryGui) {
        SummaryGui.Show()
        WinActivate("经验总结")
        RefreshSummaryWindow()
        return
    }

    CreateSummaryGui()
    RefreshSummaryWindow()
}

CreateSummaryGui() {
    global SummaryGui, SummaryListView, SummaryAgentStatusText, SummaryTotalCountText
    global SummaryBindButton, SummaryActivateButton, SummaryRebindButton, SummaryUnbindButton
    global SummaryRefreshButton, SummaryImportHistoryButton, SummaryFilterButtons, SummaryDateRangeText, SummaryReportFilter

    SummaryGui := Gui("+Resize +MinSize920x600", "经验总结")
    SummaryGui.SetFont("s9", "Microsoft YaHei UI")
    SummaryGui.OnEvent("Close", SummaryGuiClose)
    SummaryGui.OnEvent("Size", SummaryGuiSize)

    ; 筛选条件区
    SummaryGui.Add("Text", "xm ym w80 h18", "筛选条件：")
    SummaryFilterButtons := []
    xPos := 80
    for filterDef in FILTER_DEFINITIONS {
        btn := SummaryGui.Add("Button", "x" xPos " ym w50 h22", filterDef.name)
        btn.OnEvent("Click", SummaryFilterButtonClick)
        SummaryFilterButtons.Push(btn)
        xPos += 54
    }

    xPos += 25 ; 固定按钮与自定义之间视觉分隔

    customBtn := SummaryGui.Add("Button", "x" xPos " ym w80 h22", "自定义")
    customBtn.OnEvent("Click", SummaryCustomFilterClick)
    SummaryFilterButtons.Push(customBtn)
    xPos += 78

    ; 在自定义按钮和日期范围之间增加空隙
    xPos += 30

    SummaryDateRangeText := SummaryGui.Add("Text", "x" xPos " ym w180 h22", "")
    xPos += 184

    SummaryImportHistoryButton := SummaryGui.Add("Button", "x" xPos " ym w80 h22", "导入历史主题")
    SummaryImportHistoryButton.OnEvent("Click", SummaryImportHistoryClick)
    xPos += 84

    SummaryRefreshButton := SummaryGui.Add("Button", "x" xPos " ym w50 h22", "刷新")
    SummaryRefreshButton.OnEvent("Click", SummaryRefreshClick)

    ; 第二行：报告状态 + Agent 绑定
    SummaryGui.Add("Text", "xm y+8 w60 h18", "报告状态：")
    SummaryReportFilter := SummaryGui.Add("DropDownList", "x+4 yp w80 Choose1", ["全部", "已生成", "未生成"])
    SummaryReportFilter.OnEvent("Change", SummaryReportFilterChange)

    SummaryGui.Add("Text", "x+20 yp w80 h18", "Agent 绑定：")
    SummaryAgentStatusText := SummaryGui.Add("Text", "x+4 yp w100 h18", "未绑定")
    SummaryBindButton := SummaryGui.Add("Button", "x+4 yp w60 h24", "绑定窗口")
    SummaryBindButton.OnEvent("Click", SummaryBindAgentClick)
    SummaryActivateButton := SummaryGui.Add("Button", "x+4 yp w60 h24 Hidden", "激活窗口")
    SummaryActivateButton.OnEvent("Click", SummaryActivateAgentClick)
    SummaryRebindButton := SummaryGui.Add("Button", "x+4 yp w60 h24 Hidden", "重绑")
    SummaryRebindButton.OnEvent("Click", SummaryRebindAgentClick)
    SummaryUnbindButton := SummaryGui.Add("Button", "x+4 yp w60 h24 Hidden", "解绑")
    SummaryUnbindButton.OnEvent("Click", SummaryUnbindAgentClick)

    SummaryTotalCountText := SummaryGui.Add("Text", "x+10 yp w80 h18", "")

    ; 路径筛选
    SummaryGui.Add("Text", "xm y+8 w60 h18", "路径筛选：")
    SummaryPathFilterEdit := SummaryGui.Add("Edit", "x+4 yp w180 h22")
    SummaryPathFilterEdit.OnEvent("Change", OnPathFilterChange)

    SummaryGenerateReportBtn := SummaryGui.Add("Button", "x+8 yp w80 h22", "生成报告")
    SummaryGenerateReportBtn.OnEvent("Click", OnGenerateReportClick)

    SummaryOpenReportBtn := SummaryGui.Add("Button", "x+8 yp w80 h22", "报告窗口")
    SummaryOpenReportBtn.OnEvent("Click", OnOpenReportWindowClick)

    ; ListView
    SummaryListView := SummaryGui.Add("ListView", "xm y+8 w820 h380 Grid -Multi", ["序号", "主题名称", "归属项目", "最后访问时间", "总结状态", "目录状态"])
    SummaryListView.ModifyCol(1, 40)   ; 序号
    SummaryListView.ModifyCol(2, 180)  ; 主题名称
    SummaryListView.ModifyCol(3, 140)  ; 归属项目
    SummaryListView.ModifyCol(4, 140)  ; 最后访问时间
    SummaryListView.ModifyCol(5, 70)   ; 总结状态
    SummaryListView.ModifyCol(6, 70)   ; 目录状态
    SummaryListView.OnEvent("Click", SummaryListViewClick)
    SummaryListView.OnEvent("DoubleClick", SummaryListViewDoubleClick)
    SummaryListView.OnEvent("ItemSelect", SummaryListViewSelect)

    ; 计算窗口尺寸：固定 920×680，主屏幕居中
    width := 920
    height := 680
    x := Integer((A_ScreenWidth - width) / 2)
    y := Integer((A_ScreenHeight - height) / 2)
    SummaryGui.Show(Format("w{} h{} x{} y{}", width, height, x, y))

    ; 默认选中“今天”
    UpdateFilterButtonState()
}

; ============================================================
; 窗口事件处理
; ============================================================

SummaryGuiClose(*) {
    global SummaryGui
    if (SummaryGui) {
        SummaryGui.Hide()
    }
}

SummaryGuiSize(gui, minMax, width, height) {
    global SummaryListView

    if (minMax = -1 || !SummaryListView) {
        return
    }

    topReserved := 100     ; 筛选条件区高度 + 边距（三行）
    bottomReserved := 20   ; 底部边距
    minListHeight := 200

    newWidth := width - 40
    newHeight := height - topReserved - bottomReserved
    if (newHeight < minListHeight) {
        newHeight := minListHeight
    }

    SummaryListView.Move(10, topReserved, newWidth, newHeight)
}

; ============================================================
; 筛选条件处理
; ============================================================

SummaryFilterButtonClick(ctrl, *) {
    global SummaryCurrentFilter
    SummaryCurrentFilter := ctrl.Text
    UpdateFilterButtonState()
    RefreshSummaryWindow()
}

SummaryCustomFilterClick(*) {
    ShowCustomDateDialog()
}

SummaryRefreshClick(*) {
    RefreshSummaryWindow()
}

OnPathFilterChange(ctrl, *) {
    global SummaryPathFilterValue
    SummaryPathFilterValue := ctrl.Value
    RefreshSummaryWindow()
}

SummaryImportHistoryClick(*) {
    global AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    if (projectRoot = "") {
        projectRoot := AppRoot
    }

    defaultDir := projectRoot "\需求"
    if (!DirExist(defaultDir)) {
        defaultDir := projectRoot
    }

    ib := InputBox("选择要导入历史主题目录的根目录：", "导入历史主题", "w450 h130", defaultDir)
    if (ib.Result != "OK") {
        return
    }

    selectedDir := Trim(ib.Value)
    if (selectedDir = "" || !DirExist(selectedDir)) {
        MsgBox("目录无效", "AIProcess", "Iconx")
        return
    }

    count := ImportHistoricalThemes(selectedDir)
    MsgBox("已导入 " count " 个历史主题", "AIProcess", "Iconi")
    RefreshSummaryWindow()
}

SummaryReportFilterChange(ctrl, *) {
    global SummaryReportFilterValue
    SummaryReportFilterValue := ctrl.Text
    RefreshSummaryWindow()
}

UpdateFilterButtonState() {
    global SummaryFilterButtons, SummaryCurrentFilter
    for btn in SummaryFilterButtons {
        if (btn.Text = SummaryCurrentFilter || (SummaryCurrentFilter = "自定义" && btn.Text = "自定义")) {
            btn.Enabled := false
        } else {
            btn.Enabled := true
        }
    }
}

ShowCustomDateDialog() {
    global SummaryGui, SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow

    dialog := Gui("+Owner" SummaryGui.Hwnd " +ToolWindow", "自定义时间范围")
    dialog.SetFont("s9", "Microsoft YaHei UI")
    dialog.MarginX := 12
    dialog.MarginY := 10

    dialog.Add("Text", "xm ym", "开始日期：")
    startCtrl := dialog.Add("DateTime", "xm y+4 w140 vStartDate", "yyyy-MM-dd")

    dialog.Add("Text", "xm y+8", "结束日期：")
    endCtrl := dialog.Add("DateTime", "xm y+4 w140 vEndDate", "yyyy-MM-dd")
    nowCtrl := dialog.Add("CheckBox", "x+8 yp w60 vEndIsNow", "至今")

    ; 恢复上次选择
    try {
        if (SummaryCustomStartDate != "") {
            startCtrl.Value := SummaryCustomStartDate
        }
    }
    try {
        if (SummaryCustomEndDate != "") {
            endCtrl.Value := SummaryCustomEndDate
        }
    }
    nowCtrl.Value := SummaryCustomEndIsNow ? 1 : 0
    endCtrl.Enabled := !SummaryCustomEndIsNow

    nowCtrl.OnEvent("Click", (*) => endCtrl.Enabled := nowCtrl.Value != 1)

    okButton := dialog.Add("Button", "xm y+12 w70 h24 Default", "确定")
    okButton.OnEvent("Click", (*) => ApplyCustomDate(dialog, startCtrl, endCtrl, nowCtrl))

    cancelButton := dialog.Add("Button", "x+8 yp w70 h24", "取消")
    cancelButton.OnEvent("Click", (*) => dialog.Destroy())

    dialog.Show()
}

ApplyCustomDate(dialog, startCtrl, endCtrl, nowCtrl) {
    global SummaryCurrentFilter, SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow
    SummaryCurrentFilter := "自定义"
    SummaryCustomStartDate := startCtrl.Value
    SummaryCustomEndIsNow := nowCtrl.Value = 1
    if (!SummaryCustomEndIsNow) {
        SummaryCustomEndDate := endCtrl.Value
    }
    dialog.Destroy()
    UpdateFilterButtonState()
    RefreshSummaryWindow()
}

; ============================================================
; 数据加载与渲染
; ============================================================

RefreshSummaryWindow() {
    UpdateDateRangeText()
    RenderThemeList()
    RefreshAgentStatusUI()
}

UpdateDateRangeText() {
    global SummaryDateRangeText, SummaryCurrentFilter
    global SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow

    dateRange := GetFilterDateRange(SummaryCurrentFilter, SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow)
    if (SummaryDateRangeText) {
        SummaryDateRangeText.Text := FormatDateRangeText(dateRange)
    }
}

FormatDateRangeText(dateRange) {
    startDate := dateRange["startDate"]
    endDate := dateRange["endDate"]
    if (startDate = "" && endDate = "") {
        return ""
    }
    if (startDate = endDate) {
        return startDate
    }
    return startDate " ~ " endDate
}

RenderThemeList() {
    global SummaryListView, SummaryTotalCountText, SummaryCurrentFilter
    global SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow
    global SummaryRowPathMap, SummarySelectedThemePath, SummaryReportFilterValue

    SummaryListView.Delete()
    SummaryRowPathMap.Clear()

    dateRange := GetFilterDateRange(SummaryCurrentFilter, SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow)
    themes := LoadThemes(dateRange)

    ; 应用报告状态过滤
    filteredThemes := []
    for theme in themes {
        summaryExists := FileExist(theme.path "\.aiprocess\Summary.md") || FileExist(theme.path "\.aiprocess\Summary.json")
        if (SummaryReportFilterValue = "已生成" && !summaryExists) {
            continue
        }
        if (SummaryReportFilterValue = "未生成" && summaryExists) {
            continue
        }
        filteredThemes.Push(theme)
    }

    ; 应用路径筛选
    if (SummaryPathFilterValue != "") {
        pathFiltered := []
        for theme in filteredThemes {
            if (InStr(theme.path, SummaryPathFilterValue)) {
                pathFiltered.Push(theme)
            }
        }
        filteredThemes := pathFiltered
    }

    for index, theme in filteredThemes {
        projectName := ExtractProjectName(theme.path)
        rowIndex := SummaryListView.Add(, index, theme.name, projectName, theme.lastAccessTime, theme.summaryStatus, theme.dirStatus)
        SummaryRowPathMap[rowIndex] := theme.path
    }

    totalCount := filteredThemes.Length
    if (SummaryTotalCountText) {
        SummaryTotalCountText.Text := "共 " totalCount " 个主题"
    }

    SummarySelectedThemePath := ""
}

LoadThemes(dateRange) {
    global AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    if (projectRoot = "") {
        projectRoot := AppRoot
    }

    indexDir := projectRoot "\history\index"
    if (!DirExist(indexDir)) {
        return []
    }

    themeMap := Map()

    ; 获取需要读取的文件列表
    files := []
    Loop Files, indexDir "\*.jsonl", "F" {
        fileDate := SubStr(A_LoopFileName, 1, 10)
        if (IsDateInRange(fileDate, dateRange)) {
            files.Push(A_LoopFileFullPath)
        }
    }

    ; 读取每个文件
    for filePath in files {
        try {
            content := FileRead(filePath, "UTF-8")
            Loop Parse, content, "`n", "`r" {
                line := Trim(A_LoopField)
                if (line = "") {
                    continue
                }
                try {
                    record := JSON.Load(line)
                    path := record["path"]
                    time := record["time"]
                    themeDir := FindThemeDir(path)
                    if (themeDir = "") {
                        continue
                    }

                    if (!themeMap.Has(themeDir)) {
                        themeMap[themeDir] := time
                    } else if (time > themeMap[themeDir]) {
                        themeMap[themeDir] := time
                    }
                }
            }
        }
    }

    ; 转换为数组并排序
    themes := []
    for themeDir, lastTime in themeMap {
        SplitPath(themeDir, &themeName)
        summaryFile := themeDir "\.aiprocess\Summary.md"
        summaryStatus := FileExist(summaryFile) ? "已总结" : "未总结"
        exists := DirExist(themeDir)
        isArchived := IsArchivedTheme(themeDir)
        if (exists && isArchived) {
            dirStatus := "已归档"
        } else if (isArchived) {
            dirStatus := "已归档（目录缺失）"
        } else if (exists) {
            dirStatus := "存在"
        } else {
            dirStatus := "不存在"
        }

        themes.Push({
            path: themeDir,
            name: themeName,
            lastAccessTime: lastTime,
            summaryStatus: summaryStatus,
            dirStatus: dirStatus
        })
    }

    ; 按最后访问时间倒序
    SortThemesByTime(themes)

    return themes
}

FindThemeDir(path) {
    if (path = "" || !InStr(path, "\")) {
        return path
    }

    currentPath := path
    Loop 20 {
        if (DirExist(currentPath "\.aiprocess")) {
            return currentPath
        }
        parentPath := ""
        SplitPath(currentPath,, &parentPath)
        if (parentPath = "" || parentPath = currentPath) {
            break
        }
        currentPath := parentPath
    }

    return path
}

SortThemesByTime(themes) {
    ; 简单冒泡排序，把时间字符串转为纯数字后比较
    n := themes.Length
    Loop n - 1 {
        i := 1
        Loop n - A_Index {
            time1 := RegExReplace(themes[i].lastAccessTime, "[^\d]")
            time2 := RegExReplace(themes[i + 1].lastAccessTime, "[^\d]")
            if (time1 < time2) {
                tmp := themes[i]
                themes[i] := themes[i + 1]
                themes[i + 1] := tmp
            }
            i += 1
        }
    }
}

IsDateInRange(fileDate, dateRange) {
    if (dateRange["startDate"] = "" || dateRange["endDate"] = "") {
        return true
    }
    ; 统一转换为 yyyyMMdd 数字字符串后比较，避免 AHK 字符串比较报错
    fileDateNum := StrReplace(fileDate, "-")
    startNum := StrReplace(dateRange["startDate"], "-")
    endNum := StrReplace(dateRange["endDate"], "-")
    return fileDateNum >= startNum && fileDateNum <= endNum
}

GetFilterDateRange(filterName, customStart, customEnd, endIsNow) {
    now := A_Now
    today := FormatTime(now, "yyyy-MM-dd")

    startDate := ""
    endDate := ""

    switch filterName {
        case "今天":
            startDate := today
            endDate := today
        case "本周":
            startDate := GetWeekStart(now)
            endDate := today
        case "上周":
            weekStartTime := DateAdd(DateToTimestamp(GetWeekStart(now)), -7, "Days")
            lastWeekEnd := DateAdd(weekStartTime, 6, "Days")
            startDate := FormatTime(weekStartTime, "yyyy-MM-dd")
            endDate := FormatTime(lastWeekEnd, "yyyy-MM-dd")
        case "本月":
            startDate := SubStr(today, 1, 8) "01"
            endDate := today
        case "本季":
            todayNum := FormatTime(now, "yyyyMMdd")
            month := Integer(SubStr(todayNum, 5, 2))
            quarter := Ceil(month / 3)
            startMonth := (quarter - 1) * 3 + 1
            startDate := SubStr(todayNum, 1, 4) Format("{:02d}", startMonth) "01"
            endDate := today
        case "上月":
            thisMonthStart := SubStr(today, 1, 8) "01"
            lastMonthEndTime := DateAdd(DateToTimestamp(thisMonthStart), -1, "Days")
            lastMonthDay := Integer(FormatTime(lastMonthEndTime, "dd"))
            lastMonthStartTime := DateAdd(lastMonthEndTime, 1 - lastMonthDay, "Days")
            startDate := FormatTime(lastMonthStartTime, "yyyy-MM-dd")
            endDate := FormatTime(lastMonthEndTime, "yyyy-MM-dd")
        case "本年":
            startDate := SubStr(today, 1, 5) "01-01"
            endDate := today
        case "自定义":
            if (customStart != "") {
                startDate := FormatTime(customStart, "yyyy-MM-dd")
            }
            if (endIsNow) {
                endDate := today
            } else if (customEnd != "") {
                endDate := FormatTime(customEnd, "yyyy-MM-dd")
            }
    }

    return Map("startDate", startDate, "endDate", endDate)
}

DateToTimestamp(dateStr) {
    ; 将 yyyy-MM-dd 转换为 yyyyMMdd000000 时间戳
    return StrReplace(dateStr, "-") "000000"
}

GetWeekStart(nowTime) {
    ; 获取本周一，返回 yyyy-MM-dd
    formatted := FormatTime(nowTime, "yyyyMMdd")
    baseDate := "20000103"  ; 2000-01-03 是周一
    diff := DateDiff(formatted, baseDate, "Days")
    weekDayOffset := Mod(diff, 7)
    if (weekDayOffset < 0) {
        weekDayOffset += 7
    }
    monday := DateAdd(formatted, -weekDayOffset, "Days")
    return FormatTime(monday, "yyyy-MM-dd")
}

; ============================================================
; 列表选择事件与操作按钮
; ============================================================

SummaryListViewSelect(ctrl, item, selected) {
    global SummarySelectedThemePath
    if (selected && item > 0) {
        SummarySelectedThemePath := GetThemePathByRow(item)
    } else if (!selected) {
        SummarySelectedThemePath := ""
    }
}

SummaryListViewClick(ctrl, item) {
    global SummarySelectedThemePath
    if (item > 0) {
        SummarySelectedThemePath := GetThemePathByRow(item)
        themePath := GetThemePathByRow(item)
        ShowThemeDetailDialog(themePath)
    }
}

SummaryListViewDoubleClick(ctrl, item) {
    if (item > 0) {
        path := GetThemePathByRow(item)
        ShowThemeDetailDialog(path)
    }
}

GetThemePathByRow(rowIndex) {
    global SummaryRowPathMap
    if (SummaryRowPathMap.Has(rowIndex)) {
        return SummaryRowPathMap[rowIndex]
    }
    return ""
}

; ============================================================
; 主题详情弹窗
; ============================================================

ShowThemeDetailDialog(path) {
    global SummaryGui

    if (path = "") {
        return
    }

    SplitPath(path, &themeName)
    summaryMd := path "\.aiprocess\Summary.md"
    summaryJson := path "\.aiprocess\Summary.json"
    dirExists := DirExist(path)
    summaryExists := FileExist(summaryMd) || FileExist(summaryJson)

    dialog := Gui("+Owner" SummaryGui.Hwnd " +ToolWindow", "主题详情")
    dialog.SetFont("s9", "Microsoft YaHei UI")
    dialog.MarginX := 12
    dialog.MarginY := 10

    dialog.Add("Text", "xm ym w80 h18", "名称：")
    dialog.Add("Text", "x+4 yp w400 h18", themeName)

    dialog.Add("Text", "xm y+8 w80 h18", "路径：")
    dialog.Add("Edit", "x+4 yp w400 h22 ReadOnly", path)

    dialog.Add("Text", "xm y+8 w80 h18", "总结状态：")
    dialog.Add("Text", "x+4 yp w100 h18", summaryExists ? "已总结" : "未总结")

    dialog.Add("Text", "xm y+8 w80 h18", "目录状态：")
    dialog.Add("Text", "x+4 yp w100 h18", dirExists ? "存在" : "不存在")

    ; 操作按钮
    copyButton := dialog.Add("Button", "xm y+16 w80 h24", "复制路径")
    copyButton.OnEvent("Click", (*) => A_Clipboard := path)

    openDirButton := dialog.Add("Button", "x+8 yp w80 h24", "打开目录")
    openDirButton.OnEvent("Click", (*) => OpenThemeDir(path))
    openDirButton.Enabled := dirExists

    viewSummaryButton := dialog.Add("Button", "x+8 yp w80 h24", "查看总结")
    viewSummaryButton.OnEvent("Click", (*) => ViewThemeSummary(path))
    viewSummaryButton.Enabled := true

    generateSummaryButton := dialog.Add("Button", "x+8 yp w80 h24", "生成总结")
    generateSummaryButton.OnEvent("Click", (ctrl, *) => GenerateThemeSummary(path, ctrl))
    generateSummaryButton.Enabled := dirExists

    closeButton := dialog.Add("Button", "xm y+16 w80 h24 Default", "关闭")
    closeButton.OnEvent("Click", (*) => dialog.Destroy())

    dialog.Show()
}

; ============================================================
; Agent 绑定区
; ============================================================

RefreshAgentStatusUI() {
    global SummaryAgentStatusText
    global SummaryBindButton, SummaryActivateButton, SummaryRebindButton, SummaryUnbindButton

    status := AgentDispatcherGetStatus("SummaryAgent")

    if (!status["IsBound"]) {
        SummaryAgentStatusText.Text := "未绑定"
        SummaryBindButton.Visible := true
        SummaryActivateButton.Visible := false
        SummaryRebindButton.Visible := false
        SummaryUnbindButton.Visible := false
    } else {
        displayText := "已绑定"
        if (status["TitleContains"] != "") {
            displayText .= " " status["TitleContains"]
        }
        if (status["ProcessName"] != "") {
            displayText .= " (" status["ProcessName"] ")"
        }
        if (status["Hwnd"] != "") {
            displayText .= " HWND: " status["Hwnd"]
        }
        if (!status["IsOnline"]) {
            displayText .= " [未找到]"
        }
        SummaryAgentStatusText.Text := displayText

        SummaryBindButton.Visible := false
        SummaryActivateButton.Visible := true
        SummaryRebindButton.Visible := true
        SummaryUnbindButton.Visible := true
    }
}

SummaryBindAgentClick(*) {
    global SummaryGui
    if (SummaryGui) {
        SummaryGui.Hide()
    }
    SetTimer(DoSummaryBindAgent, -500)
}

DoSummaryBindAgent() {
    global SummaryGui
    result := AgentDispatcherBind("SummaryAgent")
    if (SummaryGui) {
        SummaryGui.Show()
        WinActivate("经验总结")
    }
    if (result["Success"]) {
        RefreshAgentStatusUI()
        MsgBox("绑定成功：" result["Title"], "AIProcess", "Iconi")
    } else {
        MsgBox("绑定失败：" result["Message"], "AIProcess", "Iconx")
    }
}

SummaryActivateAgentClick(*) {
    if (AgentDispatcherActivate("SummaryAgent")) {
        ; 激活成功，不提示
    } else {
        MsgBox("未找到绑定的 Agent 窗口", "AIProcess", "Iconx")
    }
}

SummaryRebindAgentClick(*) {
    SummaryBindAgentClick()
}

SummaryUnbindAgentClick(*) {
    AgentDispatcherUnbind("SummaryAgent")
    RefreshAgentStatusUI()
}

OpenThemeDir(themePath) {
    if (themePath = "" || !DirExist(themePath)) {
        return
    }
    Run('explorer.exe "' themePath '"')
}

ViewThemeSummary(themePath) {
    if (themePath = "") {
        MsgBox("当前主题路径为空", "AIProcess", "Iconx")
        return
    }

    if (!DirExist(themePath)) {
        MsgBox("当前主题目录不存在：" themePath, "AIProcess", "Iconx")
        return
    }

    summaryMd := themePath "\.aiprocess\Summary.md"
    summaryJson := themePath "\.aiprocess\Summary.json"

    if (FileExist(summaryMd)) {
        OpenFileInTool(summaryMd)
        return
    }

    if (FileExist(summaryJson)) {
        global AppRoot
        psScript := AppRoot "\powershell\summary\ConvertSummaryToMarkdown.ps1"
        cmd := 'powershell -ExecutionPolicy Bypass -File "' psScript '" -JsonPath "' summaryJson '"'
        try {
            RunWait(cmd, , "Hide")
        } catch Error as err {
            MsgBox("生成 Markdown 失败：" err.Message, "AIProcess", "Iconx")
            return
        }
        if (FileExist(summaryMd)) {
            OpenFileInTool(summaryMd)
        } else {
            MsgBox("Markdown 生成失败", "AIProcess", "Iconx")
        }
        return
    }

    MsgBox("当前主题尚未生成总结。", "AIProcess", "Iconi")
}

SummaryRefreshMessageHandler(wParam, lParam, msg, hwnd) {
    RefreshSummaryWindow()
    return true
}

; 注册自定义窗口消息，供结束脚本刷新列表
OnMessage(0x8000, SummaryRefreshMessageHandler)

GenerateThemeSummary(themePath, buttonCtrl := "") {
    if (themePath = "" || !DirExist(themePath)) {
        return
    }

    if (IsObject(buttonCtrl)) {
        buttonCtrl.Enabled := false
    }

    if (!GenerateSummary(themePath)) {
        if (IsObject(buttonCtrl)) {
            buttonCtrl.Enabled := true
        }
    }
}

; ============================================================
; 报告类型映射
; ============================================================

GetReportType(filterName) {
    global FILTER_DEFINITIONS
    if (filterName = "自定义") {
        return "自定义"
    }
    for def in FILTER_DEFINITIONS {
        if (def.name = filterName) {
            return def.reportType
        }
    }
    return ""
}

GetReportFileName(filterName, dateRange) {
    reportType := GetReportType(filterName)
    startDate := dateRange["startDate"]
    endDate := dateRange["endDate"]

    if (reportType = "日报") {
        return "日报_" startDate
    }
    if (reportType = "周报") {
        return "周报_" startDate "_" endDate
    }
    if (reportType = "月报") {
        return "月报_" SubStr(startDate, 1, 7)
    }
    if (reportType = "季报") {
        m := Integer(SubStr(startDate, 6, 2))
        q := Ceil(m / 3)
        return "季报_" SubStr(startDate, 1, 4) "_Q" q
    }
    if (reportType = "年报") {
        return "年报_" SubStr(startDate, 1, 4)
    }
    ; 自定义
    return "自定义_" startDate "_" endDate
}

; ============================================================
; 报告生成
; ============================================================

OnGenerateReportClick(ctrl, *) {
    global SummaryCurrentFilter, SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow, AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    filterName := SummaryCurrentFilter
    dateRange := GetFilterDateRange(filterName, SummaryCustomStartDate, SummaryCustomEndDate, SummaryCustomEndIsNow)
    fileName := GetReportFileName(filterName, dateRange)
    reportPath := projectRoot "\reports\" fileName ".md"

    DirCreate(projectRoot "\reports")

    promptPath := BuildReportPrompt(filterName, dateRange, reportPath)
    if (promptPath = "") {
        MsgBox("当前时间范围内没有匹配的主题", "AIProcess", "Iconi")
        return
    }

    shortMsg := "请根据临时文件 " promptPath " 生成报告"
    result := AgentDispatcherSend("SummaryAgent", shortMsg)
    if (!result["Success"]) {
        MsgBox("Agent 发送失败：" result["Message"], "AIProcess", "Iconx")
        FileDelete(promptPath)
        return
    }
}

OnOpenReportWindowClick(*) {
    ShowReportWindow()
}

