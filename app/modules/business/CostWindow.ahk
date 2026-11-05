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
global CostSortKey := "totalSec"
global CostSortDesc := true

global CostDetailGui := ""
global CostDetailTree := ""
global CostDetailMetricsText := ""
global CostDetailDaysText := ""
global CostDetailSelectedText := ""
global CostDetailNodeByItem := Map()
global CostDetailCurrentNode := 0

global CostColumns := [
    {title: "需求", width: 240, key: "name", numeric: false},
    {title: "项目", width: 150, key: "project", numeric: false},
    {title: "合计", width: 80, key: "totalSec", numeric: true},
    {title: "人", width: 70, key: "humanSec", numeric: true},
    {title: "AI", width: 70, key: "aiSec", numeric: true},
    {title: "轮次 合计·讨/执/建", width: 140, key: "rounds", numeric: true},
    {title: "字数 人/AI", width: 130, key: "humanChars", numeric: true},
    {title: "文件", width: 55, key: "files", numeric: true},
    {title: "子主题", width: 60, key: "children", numeric: true},
    {title: "跨度", width: 80, key: "spanDays", numeric: true},
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
            FormatCostDuration(row["humanSec"]),
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
    return FormatStatDurationSec(seconds)
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
    global CostDetailMetricsText, CostDetailDaysText, CostDetailSelectedText

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

    CostDetailMetricsText := CostDetailGui.Add("Text", "x400 y10 w660 h300", "")
    CostDetailDaysText := CostDetailGui.Add("Text", "x400 y330 w660 h270", "")

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
    text .= "    " FormatStatDurationSec(total)

    if (node["isRework"]) {
        text .= "  ↻"
        return text
    }
    rework := node["reworkSec"]
    if (rework > 0) {
        percent := total > 0 ? Round(rework / total * 100) : 0
        text .= "  ↻" FormatStatDurationSec(rework) "(" percent "%)"
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
    global CostDetailMetricsText, CostDetailDaysText, CostDetailSelectedText, CostDetailCurrentNode

    CostDetailCurrentNode := node
    CostDetailMetricsText.Text := BuildCostMetricsText(node)
    CostDetailDaysText.Text := BuildCostDaysText(node)
    CostDetailSelectedText.Text := "当前选中：" node["name"]
}


BuildCostMetricsText(node) {
    text := ""
    text .= "合计 " FormatStatDurationSec(node["total"]) "    人 " FormatStatDurationSec(node["humanSec"]) "    AI " FormatStatDurationSec(node["aiSec"]) "`n"
    text .= "轮次 " (node["roundD"] + node["roundE"] + node["roundR"] + node["roundU"]) "（讨 " node["roundD"] " · 执 " node["roundE"] " · 建 " node["roundR"] "）`n"
    text .= "认知 " FormatStatDurationSec(node["cognitionSec"]) "（思考 " FormatStatDurationSec(node["humanSec"]) " · 间隔 " FormatStatDurationSec(node["gapSec"]) "）`n"
    text .= "轮间空档 " FormatStatDurationSec(node["gapSec"]) "    剔除 人 " FormatStatDurationSec(node["exclHumanSec"]) " / AI " FormatStatDurationSec(node["exclAiSec"]) "（" node["exclCount"] " 次）`n"

    ratio := node["humanChars"] > 0 ? Format("{:.1f}", node["aiChars"] / node["humanChars"]) : "—"
    text .= "产出 " FormatStatCountValue(node["humanChars"]) " / " FormatStatCountValue(node["aiChars"]) " 字（1 : " ratio "）    文件 " node["files"] "（人 " node["humanFiles"] " / AI " node["aiFiles"] "）`n"

    text .= "跨度 " FormatCostSpan(ThemeCost.SpanDays(node["createdAt"], node["lastActiveAt"])) "    " node["createdAt"] " → " node["lastActiveAt"] "`n"
    text .= "Agent " (node["agents"] = "" ? "—" : node["agents"]) "`n"
    text .= "自身 " FormatStatDurationSec(node["self"]) "    统计时间 " (node["computedAt"] = "" ? "—" : node["computedAt"]) "`n"
    return text
}


BuildCostDaysText(node) {
    days := node["days"]
    if (days.Count = 0) {
        return "按天：该节点没有轮次明细"
    }

    keys := []
    for day in days {
        keys.Push(day)
    }
    SortCostDayKeys(keys)

    startIndex := Max(1, keys.Length - 13)
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

    text := "按天（该节点及其子主题，最近 14 天）`n"
    index := 0
    for day in keys {
        index += 1
        if (index < startIndex) {
            continue
        }
        seconds := days[day]
        blocks := maxSeconds > 0 ? Round(seconds / maxSeconds * 20) : 0
        if (blocks < 1) {
            blocks := 1
        }
        bar := ""
        Loop blocks {
            bar .= "█"
        }
        text .= SubStr(day, 6, 5) "  " bar "  " FormatStatDurationSec(seconds) "`n"
    }
    return text
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

    if (CostDetailGui) {
        CostDetailGui.Destroy()
        CostDetailGui := ""
    }
    CostDetailTree := ""
    CostDetailNodeByItem := Map()
    CostDetailCurrentNode := 0
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
