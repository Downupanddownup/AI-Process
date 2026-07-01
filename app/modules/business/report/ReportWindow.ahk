#Requires AutoHotkey v2.0

; ReportWindow.ahk
; 独立报告管理窗口

global ReportGui := ""
global ReportListView := ""
global ReportTotalText := ""
global btnOpen := ""
global btnDir := ""
global btnDel := ""

ShowReportWindow() {
    global ReportGui, ReportListView, ReportTotalText, btnOpen, btnDir, btnDel

    if (ReportGui) {
        ReportGui.Show()
        WinActivate("报告管理")
        RefreshReportList()
        return
    }

    ReportGui := Gui("+Resize +MinSize480x320", "报告管理")
    ReportGui.SetFont("s9", "Microsoft YaHei UI")
    ReportGui.OnEvent("Close", (*) => ReportGui.Hide())
    ReportGui.OnEvent("Size", ReportGuiSize)

    ReportTotalText := ReportGui.Add("Text", "xm ym w120 h22", "")
    refreshBtn := ReportGui.Add("Button", "x+8 yp w50 h22", "刷新")
    refreshBtn.OnEvent("Click", (*) => RefreshReportList())

    ReportListView := ReportGui.Add("ListView", "xm y+8 w440 h280 Grid -Multi +LV0x4000", ["序号", "报告类型", "时间范围", "生成时间"])
    ReportListView.ModifyCol(1, 40)
    ReportListView.ModifyCol(2, 70)
    ReportListView.ModifyCol(3, 180)
    ReportListView.ModifyCol(4, 120)
    ReportListView.OnEvent("DoubleClick", OnReportDoubleClick)

    btnOpen := ReportGui.Add("Button", "xm y+8 w70 h24", "打开")
    btnOpen.OnEvent("Click", OnReportOpenClick)
    btnDir := ReportGui.Add("Button", "x+4 yp w80 h24", "打开目录")
    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    btnDir.OnEvent("Click", (*) => Run("explorer.exe `"" projectRoot "\reports`""))
    btnDel := ReportGui.Add("Button", "x+4 yp w60 h24", "删除")
    btnDel.OnEvent("Click", OnReportDeleteClick)

    x := Integer((A_ScreenWidth - 480) / 2)
    y := Integer((A_ScreenHeight - 400) / 2)
    ReportGui.Show(Format("w480 h400 x{} y{}", x, y))

    RefreshReportList()
    OnMessage(0x8002, ReportRefreshHandler)
}

ReportGuiSize(gui, minMax, width, height) {
    global ReportListView, btnOpen, btnDir, btnDel
    if (minMax = -1 || !ReportListView)
        return
    ReportListView.Move(10, 40, width - 20, height - 85)
    btnY := height - 35
    btnOpen.Move(10, btnY, 70, 24)
    btnDir.Move(84, btnY, 80, 24)
    btnDel.Move(168, btnY, 60, 24)
}

RefreshReportList() {
    global ReportListView, ReportTotalText, AppRoot

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")
    ReportListView.Delete()

    reportsDir := projectRoot "\reports"
    if (!DirExist(reportsDir)) {
        ReportTotalText.Text := "共 0 份"
        return
    }

    files := []
    Loop Files, reportsDir "\*.md", "F" {
        files.Push({path: A_LoopFileFullPath, name: A_LoopFileName, time: A_LoopFileTimeModified})
    }

    SortReportsByTimeDesc(files)

    for index, file in files {
        info := ParseReportFileName(file.name)
        ReportListView.Add(, index, info.type, info.dateRange, FormatTime(file.time, "MM-dd HH:mm"))
    }

    ReportTotalText.Text := "共 " files.Length " 份"
}

ParseReportFileName(fileName) {
    baseName := SubStr(fileName, 1, -3)
    usPos := InStr(baseName, "_")
    if (usPos = 0) {
        return {type: baseName, dateRange: ""}
    }
    rptType := SubStr(baseName, 1, usPos - 1)
    datePart := SubStr(baseName, usPos + 1)
    dateRange := StrReplace(datePart, "_", " ~ ")
    return {type: rptType, dateRange: dateRange}
}

SortReportsByTimeDesc(files) {
    n := files.Length
    Loop n - 1 {
        i := 1
        Loop n - A_Index {
            if (files[i].time < files[i + 1].time) {
                tmp := files[i]
                files[i] := files[i + 1]
                files[i + 1] := tmp
            }
            i += 1
        }
    }
}

OnReportDoubleClick(ctrl, item) {
    if (item > 0) {
        OpenReportByRow(item)
    }
}

OnReportOpenClick(*) {
    row := GetSelectedReportRow()
    if (row <= 0) {
        MsgBox("请先选择一份报告。", "提示", "Iconi")
        return
    }
    OpenReportByRow(row)
}

OnReportDeleteClick(*) {
    global ReportListView
    row := GetSelectedReportRow()
    if (row <= 0) {
        MsgBox("请先选择一份报告。", "提示", "Iconi")
        return
    }
    path := GetReportPathByRow(row)
    SplitPath(path, &fileName)
    msg := "确认删除 '" fileName "' ？`n此操作不可恢复。"
    result := MsgBox(msg, "确认删除", "YesNo Icon!")
    if (result != "Yes")
        return
    FileDelete(path)
    RefreshReportList()
}

GetSelectedReportRow() {
    global ReportListView
    return ReportListView.GetNext(0, "F")
}

OpenReportByRow(row) {
    path := GetReportPathByRow(row)
    if (path != "") {
        OpenFileInIdea(path)
    }
}

GetReportPathByRow(row) {
    global ReportListView, AppRoot
    local path

    projectRoot := RegExReplace(AppRoot, "\\[^\\]+$")

    try {
        reportType := ReportListView.GetText(row, 2)
        dateRange := ReportListView.GetText(row, 3)

        fileName := reportType "_" StrReplace(dateRange, " ~ ", "_") ".md"
        path := projectRoot "\reports\" fileName
    }

    if (IsSet(path) && FileExist(path)) {
        return path
    }

    ; 如果文件名拼出来的路径不存在，尝试扫描匹配
    Loop Files, projectRoot "\reports\*.md", "F" {
        if (A_Index = row) {
            return A_LoopFileFullPath
        }
    }
    return ""
}

ReportRefreshHandler(wParam, lParam, msg, hwnd) {
    RefreshReportList()
    return true
}
