#Requires AutoHotkey v2.0

; CostWindow.ahk
; 需求成本窗口：托盘入口「需求成本」→ 12 列排行；双击一行 → 检查器（左成本树，右指标 + 按天）。
; 纯展示：数据全部来自 ThemeCost（只读服务），本文件不算统计、不写任何文件。
; 口径见 约定.md 第一章（统计单元 / 根统计单元）；「自身」与「合计」的区别见 StatsSchema。
;
; 与经验总结窗口的分工：那边按"访问"、显示自身口径；这边按"需求"、显示含子主题。
; 两个窗口互不修改对方的取数与列。

global CostGui := ""
global CostListView := ""
global CostStatusText := ""
global CostPathFilterEdit := ""
global CostPathFilterValue := ""
global CostRows := []
global CostVisibleRows := []
global CostSortKey := "lastActive"
global CostSortDesc := true

global CostDetailGui := ""
global CostDetailTree := ""
global CostDetailSelectedText := ""
global CostDetailNodeByItem := Map()
global CostDetailCurrentNode := 0
global CostMetricRows := []          ; 12 行：{label, value, note}，固定骨架只换值
global CostDaysRows := []            ; 14 行：{date, bar, value}
global CostDaysEmptyText := ""

; 右侧指标区：行位与标签（口径一律 aggregate；仅「自身」取 time）
global CostMetricSpec := [
    {label: "合计", y: 32},
    {label: "认知", y: 52},
    {label: "AI", y: 72},
    {label: "自身", y: 92},
    {label: "轮次", y: 136},
    {label: "轮间间隔", y: 180},
    {label: "剔除", y: 200},
    {label: "字数", y: 244},
    {label: "文件", y: 264},
    {label: "跨度", y: 308},
    {label: "Agent", y: 328},
    {label: "统计时间", y: 348}
]

global CostGroupSpec := [
    {title: "量", y: 12},
    {title: "结构", y: 116},
    {title: "时间", y: 160},
    {title: "产出", y: 224},
    {title: "活动", y: 288},
    {title: "按天（该节点及其子主题）", y: 378}
]

global CostColumns := [
    {title: "需求", width: 240, key: "name", numeric: false},
    {title: "项目", width: 150, key: "project", numeric: false},
    {title: "合计", width: 96, key: "totalSec", numeric: true},
    {title: "人（认知）", width: 88, key: "cognitionSec", numeric: true},
    {title: "AI", width: 84, key: "aiSec", numeric: true},
    {title: "轮次 合计·讨/执/建", width: 140, key: "rounds", numeric: true},
    {title: "字数 人/AI", width: 130, key: "humanChars", numeric: true},
    {title: "文件", width: 55, key: "files", numeric: true},
    {title: "子主题", width: 60, key: "children", numeric: true},
    {title: "跨度", width: 88, key: "spanDays", numeric: true},
    {title: "最后活动", width: 110, key: "lastActive", numeric: false},
    {title: "访问", width: 60, key: "visits", numeric: true}
]


ShowCostWindow(*) {
    global CostGui

    if (CostGui) {
        CostGui.Show()
        WinActivate("ahk_id " CostGui.Hwnd)
        RefreshCostRows()
        return
    }

    CreateCostGui()
    RefreshCostRows()
}


CreateCostGui() {
    global CostGui, CostListView, CostStatusText, CostPathFilterEdit, CostColumns

    CostGui := Gui("+Resize +MinSize1200x520", "需求成本")
    CostGui.SetFont("s9", "Microsoft YaHei UI")
    CostGui.OnEvent("Close", CostGuiClose)
    CostGui.OnEvent("Size", CostGuiSize)

    CostGui.Add("Text", "xm ym w62 h18", "路径筛选：")
    CostPathFilterEdit := CostGui.Add("Edit", "x+4 ym w240 h22")
    CostPathFilterEdit.OnEvent("Change", CostOnFilterChange)
    refreshButton := CostGui.Add("Button", "x+8 ym-1 w60 h24", "刷新")
    refreshButton.OnEvent("Click", CostRefreshClick)

    titles := []
    for column in CostColumns {
        titles.Push(column.title)
    }

    CostListView := CostGui.Add("ListView", "xm y+8 w1470 h600 Grid -Multi", titles)
    index := 1
    for column in CostColumns {
        CostListView.ModifyCol(index, column.width)
        index += 1
    }
    CostListView.OnEvent("ColClick", CostOnColClick)
    CostListView.OnEvent("DoubleClick", CostOnDoubleClick)

    CostStatusText := CostGui.Add("Text", "xm y+6 w1000 h18", "")

    width := 1500
    height := 700
    x := Integer((A_ScreenWidth - width) / 2)
    y := Integer((A_ScreenHeight - height) / 2)
    CostGui.Show(Format("w{} h{} x{} y{}", width, height, x, y))
}


CostGuiClose(*) {
    global CostGui
    if (CostGui) {
        CostGui.Hide()
    }
}


CostGuiSize(gui, minMax, width, height) {
    global CostListView, CostStatusText

    if (minMax = -1) {
        return
    }
    CostListView.Move(10, 44, width - 30, height - 96)
    CostStatusText.Move(10, height - 40, width - 30, 20)
}


; ============================================================
; 列表
; ============================================================

RefreshCostRows(*) {
    global CostRows
    CostRows := ThemeCost.LoadRows()
    RenderCostList()
}


CostRefreshClick(*) {
    RefreshCostRows()
}


CostOnFilterChange(ctrl, *) {
    global CostPathFilterValue
    CostPathFilterValue := Trim(ctrl.Value)
    RenderCostList()
}


CostOnColClick(ctrl, col, *) {
    global CostColumns, CostSortKey, CostSortDesc

    if (col < 1 || col > CostColumns.Length) {
        return
    }
    column := CostColumns[col]
    if (CostSortKey = column.key) {
        CostSortDesc := !CostSortDesc
    } else {
        CostSortKey := column.key
        CostSortDesc := column.numeric
    }
    RenderCostList()
}


CostOnDoubleClick(ctrl, row, *) {
    global CostVisibleRows

    if (row < 1 || row > CostVisibleRows.Length) {
        return
    }
    ShowCostDetail(CostVisibleRows[row])
}


RenderCostList() {
    global CostListView, CostStatusText, CostRows, CostVisibleRows
    global CostPathFilterValue, CostSortKey, CostSortDesc

    filtered := []
    for row in CostRows {
        if (CostPathFilterValue != "" && !InStr(row["path"], CostPathFilterValue)) {
            continue
        }
        filtered.Push(row)
    }

    CostVisibleRows := ThemeCost.SortRows(filtered, CostSortKey, CostSortDesc)

    CostListView.Delete()
    for row in CostVisibleRows {
        CostListView.Add("",
            row["name"],
            row["project"],
            FormatCostDuration(row["totalSec"]),
            FormatCostDuration(row["cognitionSec"]),
            FormatCostDuration(row["aiSec"]),
            FormatCostRounds(row),
            FormatCostChars(row),
            row["files"],
            row["children"],
            FormatCostSpan(row["spanDays"]),
            FormatCostActive(row["lastActive"]),
            row["visits"])
    }

    order := CostSortDesc ? "降序" : "升序"
    CostStatusText.Text := "共 " CostVisibleRows.Length " 个需求 · 按「" CostColumnTitle(CostSortKey) "」" order " · 数据为各主题上次统计时间"
}


CostColumnTitle(key) {
    global CostColumns
    for column in CostColumns {
        if (column.key = key) {
            return SubStr(column.title, 1, InStr(column.title, " ") ? InStr(column.title, " ") - 1 : StrLen(column.title))
        }
    }
    return key
}


; ============================================================
; 格式化
; ============================================================

FormatCostDuration(seconds) {
    totalMinutes := Floor(seconds / 60)
    if (totalMinutes <= 0) {
        return seconds > 0 ? "<1 分" : "0 分"
    }
    hours := Floor(totalMinutes / 60)
    minutes := Mod(totalMinutes, 60)
    if (hours = 0) {
        return minutes " 分"
    }
    if (minutes = 0) {
        return hours " 时"
    }
    return hours " 时 " minutes " 分"
}


FormatCostRounds(row) {
    if (row["rounds"] <= 0) {
        return "—"
    }
    return row["rounds"] " · " row["roundD"] "/" row["roundE"] "/" row["roundR"]
}


FormatCostChars(row) {
    return FormatStatCountValue(row["humanChars"]) " / " FormatStatCountValue(row["aiChars"])
}


FormatCostSpan(days) {
    if (days <= 0) {
        return "—"
    }
    if (days < 0.1) {
        return "<0.1 天"
    }
    return Format("{:.1f} 天", days)
}


FormatCostActive(text) {
    if (text = "") {
        return "—"
    }
    return SubStr(text, 6, 11)
}


; ============================================================
; 检查器弹窗
; ============================================================

ShowCostDetail(row) {
    global CostGui, CostDetailGui, CostDetailTree, CostDetailNodeByItem, CostDetailCurrentNode
    global CostDetailSelectedText, CostMetricRows, CostDaysRows, CostDaysEmptyText
    global CostMetricSpec, CostGroupSpec

    root := ThemeCost.BuildTree(row["path"])
    if (!IsObject(root)) {
        ShowFeedback("该需求没有可用的统计数据", true)
        return
    }

    if (CostDetailGui) {
        CostDetailGui.Destroy()
        CostDetailGui := ""
    }

    ownerOption := IsObject(CostGui) ? "+Owner" CostGui.Hwnd " " : ""
    CostDetailGui := Gui(ownerOption "+ToolWindow", row["name"] " — 成本")
    CostDetailGui.SetFont("s9", "Microsoft YaHei UI")
    CostDetailGui.OnEvent("Close", CostDetailClose)

    CostDetailTree := CostDetailGui.Add("TreeView", "xm ym w380 h620")
    CostDetailTree.OnEvent("Click", CostDetailTreeClick)

    ; 分组标题：灰、小一号、加粗
    for group in CostGroupSpec {
        CostDetailGui.SetFont("s8 c808080 Bold", "Microsoft YaHei UI")
        CostDetailGui.Add("Text", "x405 y" group.y " w660 h16", group.title)
    }

    ; 指标行：标签灰常规 / 数值黑加粗 / 说明灰小字
    CostMetricRows := []
    for spec in CostMetricSpec {
        CostDetailGui.SetFont("s9 c606060", "Microsoft YaHei UI")
        labelCtrl := CostDetailGui.Add("Text", "x405 y" spec.y " w76 h18", spec.label)
        CostDetailGui.SetFont("s9 c000000 Bold", "Microsoft YaHei UI")
        valueCtrl := CostDetailGui.Add("Text", "x485 y" spec.y " w190 h18", "")
        CostDetailGui.SetFont("s8 c909090", "Microsoft YaHei UI")
        noteCtrl := CostDetailGui.Add("Text", "x680 y" spec.y " w380 h18", "")
        CostMetricRows.Push(Map("label", labelCtrl, "value", valueCtrl, "note", noteCtrl))
    }

    ; 按天：日期 / 条 / 数值，14 行固定骨架
    CostDaysRows := []
    Loop 14 {
        rowY := 398 + (A_Index - 1) * 15
        barY := rowY + 2
        CostDetailGui.SetFont("s8 c606060", "Microsoft YaHei UI")
        dateCtrl := CostDetailGui.Add("Text", "x405 y" rowY " w58 h14", "")
        barCtrl := CostDetailGui.Add("Text", "x466 y" barY " w2 h10 Background1F6FEB", "")
        CostDetailGui.SetFont("s8 c404040", "Microsoft YaHei UI")
        valueCtrl := CostDetailGui.Add("Text", "x740 y" rowY " w120 h14", "")
        dateCtrl.Visible := false
        barCtrl.Visible := false
        valueCtrl.Visible := false
        CostDaysRows.Push(Map("date", dateCtrl, "bar", barCtrl, "value", valueCtrl, "barX", 466, "barY", barY))
    }
    CostDetailGui.SetFont("s8 c909090", "Microsoft YaHei UI")
    CostDaysEmptyText := CostDetailGui.Add("Text", "x405 y398 w600 h16", "")
    CostDaysEmptyText.Visible := false

    CostDetailGui.SetFont("s9", "Microsoft YaHei UI")
    openButton := CostDetailGui.Add("Button", "x400 y630 w90 h26", "打开目录")
    openButton.OnEvent("Click", CostDetailOpenDir)
    copyButton := CostDetailGui.Add("Button", "x+8 yp w90 h26", "复制路径")
    copyButton.OnEvent("Click", CostDetailCopyPath)
    statsButton := CostDetailGui.Add("Button", "x+8 yp w110 h26", "打开统计文件")
    statsButton.OnEvent("Click", CostDetailOpenStats)
    CostDetailSelectedText := CostDetailGui.Add("Text", "x+16 yp+5 w330 h20", "")

    CostDetailNodeByItem := Map()

    rootItem := CostDetailTree.Add(FormatCostNodeText(root), 0)
    CostDetailNodeByItem[rootItem] := root
    firstLevelItems := []
    for child in root["children"] {
        firstLevelItems.Push(AddCostDetailNode(child, rootItem))
    }
    CostDetailTree.Modify(rootItem, "Expand")
    for item in firstLevelItems {
        CostDetailTree.Modify(item, "Expand")
    }

    CostDetailGui.Show("w1090 h680")
    CostShowDetailNode(root)
}


AddCostDetailNode(node, parentItem) {
    global CostDetailTree, CostDetailNodeByItem

    item := CostDetailTree.Add(FormatCostNodeText(node), parentItem)
    CostDetailNodeByItem[item] := node
    for child in node["children"] {
        AddCostDetailNode(child, item)
    }
    return item
}


FormatCostNodeText(node) {
    text := node["name"]
    total := node["total"]
    text .= "    " FormatCostDuration(total)

    if (node["isRework"]) {
        text .= "  ↻"
        return text
    }
    rework := node["reworkSec"]
    if (rework > 0) {
        percent := total > 0 ? Round(rework / total * 100) : 0
        text .= "  ↻" FormatCostDuration(rework) "(" percent "%)"
    }
    return text
}


CostDetailTreeClick(ctrl, item, *) {
    global CostDetailNodeByItem

    if (item && CostDetailNodeByItem.Has(item)) {
        CostShowDetailNode(CostDetailNodeByItem[item])
    }
}


CostShowDetailNode(node) {
    global CostDetailSelectedText, CostDetailCurrentNode

    CostDetailCurrentNode := node
    UpdateCostMetricRows(node)
    UpdateCostDaysRows(node)
    CostDetailSelectedText.Text := "当前选中：" node["name"]
}


SetCostMetric(index, valueText, noteText, visible := true) {
    global CostMetricRows

    row := CostMetricRows[index]
    row["label"].Visible := visible
    row["value"].Visible := visible
    row["note"].Visible := visible
    row["value"].Text := visible ? valueText : ""
    row["note"].Text := visible ? noteText : ""
}


UpdateCostMetricRows(node) {
    total := node["total"]
    cognition := node["cognitionSec"]
    human := node["humanSec"]
    ai := node["aiSec"]

    innerGap := cognition - human
    if (innerGap < 0) {
        innerGap := 0
    }

    SetCostMetric(1, FormatCostDuration(total), "= 认知 " FormatCostDuration(cognition) " + AI " FormatCostDuration(ai))
    SetCostMetric(2, FormatCostDuration(cognition), "= 思考 " FormatCostDuration(human) " + 阈值内间隔 " FormatCostDuration(innerGap))
    SetCostMetric(3, FormatCostDuration(ai), "")

    hasChildren := node["children"].Length > 0
    SetCostMetric(4, FormatCostDuration(node["self"]), "本目录，不含子主题", hasChildren)

    rounds := node["roundD"] + node["roundE"] + node["roundR"] + node["roundU"]
    SetCostMetric(5, rounds, "讨 " node["roundD"] " · 执 " node["roundE"] " · 建 " node["roundR"])

    SetCostMetric(6, FormatCostDuration(node["gapSec"]), "全部间隔，不计入合计")

    if (node["exclCount"] > 0) {
        SetCostMetric(7, "人 " FormatCostDuration(node["exclHumanSec"]) " / AI " FormatCostDuration(node["exclAiSec"]), node["exclCount"] " 次，不计入合计")
    } else {
        SetCostMetric(7, "—", "无剔除")
    }

    ratio := node["humanChars"] > 0 ? Format("{:.1f}", node["aiChars"] / node["humanChars"]) : "—"
    SetCostMetric(8, FormatStatCountValue(node["humanChars"]) " / " FormatStatCountValue(node["aiChars"]), "人 : AI = 1 : " ratio)
    SetCostMetric(9, node["files"], "人 " node["humanFiles"] " / AI " node["aiFiles"])

    SetCostMetric(10, FormatCostSpan(ThemeCost.SpanDays(node["createdAt"], node["lastActiveAt"])), FormatCostActive(node["createdAt"]) " → " FormatCostActive(node["lastActiveAt"]))

    agentNames := node["agents"]
    agentCount := agentNames = "" ? 0 : StrSplit(agentNames, " · ").Length
    SetCostMetric(11, (agentCount = 0 ? "—" : agentCount " 个"), TruncateCostText(agentNames, 40))
    SetCostMetric(12, FormatCostActive(node["computedAt"]), "各主题上次统计")
}


TruncateCostText(text, limit) {
    if (text = "" || StrLen(text) <= limit) {
        return text
    }
    return SubStr(text, 1, limit) "…"
}


UpdateCostDaysRows(node) {
    global CostDaysRows, CostDaysEmptyText

    for row in CostDaysRows {
        row["date"].Visible := false
        row["bar"].Visible := false
        row["value"].Visible := false
    }
    CostDaysEmptyText.Visible := false

    days := node["days"]
    if (days.Count = 0) {
        CostDaysEmptyText.Text := "该节点没有轮次明细"
        CostDaysEmptyText.Visible := true
        return
    }

    keys := []
    for day in days {
        keys.Push(day)
    }
    SortCostDayKeys(keys)

    ; 画得下就全画；画不下（超过 13 天）就把最早的那些折成一行
    totalDays := keys.Length
    dailyLimit := 13
    olderDays := 0
    olderSeconds := 0
    startIndex := 1
    if (totalDays > dailyLimit) {
        olderDays := totalDays - dailyLimit
        Loop olderDays {
            olderSeconds += days[keys[A_Index]]
        }
        startIndex := olderDays + 1
    }

    maxSeconds := 0
    index := 0
    for day in keys {
        index += 1
        if (index < startIndex) {
            continue
        }
        if (days[day] > maxSeconds) {
            maxSeconds := days[day]
        }
    }

    rowIndex := 1
    if (olderDays > 0) {
        olderRow := CostDaysRows[1]
        olderRow["date"].Text := "更早 " olderDays " 天"
        olderRow["date"].Visible := true
        olderRow["bar"].Visible := false
        olderRow["value"].Text := FormatCostDuration(olderSeconds)
        olderRow["value"].Visible := true
        rowIndex := 2
    }

    index := 0
    for day in keys {
        index += 1
        if (index < startIndex) {
            continue
        }
        seconds := days[day]
        barWidth := maxSeconds > 0 ? Round(seconds / maxSeconds * 256) : 0
        if (barWidth < 2) {
            barWidth := 2
        }
        row := CostDaysRows[rowIndex]
        row["date"].Text := SubStr(day, 6, 5)
        row["date"].Visible := true
        row["bar"].Move(row["barX"], row["barY"], barWidth, 10)
        row["bar"].Visible := true
        row["value"].Text := FormatCostDuration(seconds)
        row["value"].Visible := true
        rowIndex += 1
    }
}


SortCostDayKeys(keys) {
    count := keys.Length
    if (count < 2) {
        return
    }
    Loop count - 1 {
        position := A_Index + 1
        item := keys[position]
        cursor := position - 1
        while (cursor >= 1 && StrCompare(keys[cursor], item) > 0) {
            keys[cursor + 1] := keys[cursor]
            cursor -= 1
        }
        keys[cursor + 1] := item
    }
}


CostDetailClose(*) {
    global CostDetailGui, CostDetailTree, CostDetailNodeByItem, CostDetailCurrentNode
    global CostMetricRows, CostDaysRows, CostDaysEmptyText

    if (CostDetailGui) {
        CostDetailGui.Destroy()
        CostDetailGui := ""
    }
    CostDetailTree := ""
    CostDetailNodeByItem := Map()
    CostDetailCurrentNode := 0
    CostMetricRows := []
    CostDaysRows := []
    CostDaysEmptyText := ""
}


; ============================================================
; 底部三键：作用于当前选中节点
; ============================================================

CostDetailOpenDir(*) {
    global CostDetailCurrentNode

    if (!IsObject(CostDetailCurrentNode)) {
        return
    }
    OpenThemeDir(CostDetailCurrentNode["path"])
}


CostDetailCopyPath(*) {
    global CostDetailCurrentNode

    if (!IsObject(CostDetailCurrentNode)) {
        return
    }
    A_Clipboard := CostDetailCurrentNode["path"]
}


CostDetailOpenStats(*) {
    global CostDetailCurrentNode

    if (!IsObject(CostDetailCurrentNode)) {
        return
    }
    statsFile := CostDetailCurrentNode["path"] "\.aiprocess\统计.md"
    if (!FileExist(statsFile)) {
        ShowFeedback("该节点还没有统计文件", true)
        return
    }
    EditorOpener.Open(statsFile)
}
