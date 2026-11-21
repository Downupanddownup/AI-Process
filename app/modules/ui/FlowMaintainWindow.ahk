#Requires AutoHotkey v2.0

; 流程维护窗口（只读）
;
; 看配置、看预览、跑校验。不写任何文件。
; 校验结果的动作是"窗口内定位"，不打开外部编辑器——块是数据，
; 修数据要在块维护界面（05），编辑器只管改正文那一段文字。
;
; 预览固定用演示主题 app/templates/preview-topic，不随当前主题变，
; 保证同一流程永远同一份预览。

global FMWin := ""
global FMWinFlowList := ""
global FMWinComboList := ""
global FMWinPreview := ""
global FMWinDemoLabel := ""
global FMWinIssueList := ""
global FMWinHint := ""
global FMWinIssues := []
global FMWinFlowKeys := []
global FMWinCombos := []
global FMWinCurFlow := ""

; 只 include 一次，重复调用只是 Show + 刷新
ShowFlowMaintainWindow(flowKey := "") {
    global FMWin, FMWinFlowList, FMWinComboList, FMWinPreview, FMWinDemoLabel
    global FMWinIssueList, FMWinHint, FMWinIssues, FMWinFlowKeys, FMWinCombos, FMWinCurFlow

    if (FMWin) {
        FMWin.Show()
        WinActivate("ahk_id " FMWin.Hwnd)
        RefreshFMFlowList(flowKey != "" ? flowKey : FMWinCurFlow)
        return
    }

    ; 布局说明：AHK 的 "x+8" 是"上一个控件的右边缘 +8"，不是"左边 +8"。
    ; 所以"标题 → 其下控件"一律用 xp（与上一个同左边缘），
    ; 只有"跨列"时才用 x+8（相对上一列的右边缘）。
    opts := "+MinSize1100x680"
    ; 按来源绑 owner：从设置主题弹窗打开就绑它，从托盘打开就绑主面板。
    ; 子窗口永远在父窗口之上，层级自然对——不用 AlwaysOnTop（那会盖住别的程序）。
    if (IsSet(ThemeSelectDialog) && ThemeSelectDialog) {
        opts .= " +Owner" ThemeSelectDialog.Hwnd
    } else if (IsSet(MainGui) && MainGui) {
        opts .= " +Owner" MainGui.Hwnd
    }

    FMWin := Gui(opts, "流程维护")
    FMWin.BackColor := GetDialogBackColor()
    FMWin.MarginX := 12
    FMWin.MarginY := 12
    FMWin.SetFont("s9", "Microsoft YaHei UI")
    FMWin.OnEvent("Close", CloseFlowMaintainWindow)
    FMWin.OnEvent("Escape", CloseFlowMaintainWindow)

    ; 左列（x=12..232）
    FMWin.AddText("xm ym w220 h18", "流程")
    FMWinFlowList := FMWin.AddListView("xp y+2 w220 h540 -Multi", ["流程", "类型"])
    FMWinFlowList.ModifyCol(1, 140)
    FMWinFlowList.ModifyCol(2, "70 Center")
    ApplyDialogListStyle(FMWinFlowList)
    FMWinFlowList.OnEvent("ItemSelect", OnFMFlowSelect)

    ; 中列（x=240..600）：x+8 是相对左列表右边缘
    FMWin.AddText("x+8 ym w360 h18", "组合与块（选中一行看右边预览）")
    FMWinComboList := FMWin.AddListView("xp y+2 w360 h540 -Multi", ["组合", "块"])
    FMWinComboList.ModifyCol(1, 130)
    FMWinComboList.ModifyCol(2, 210)
    ApplyDialogListStyle(FMWinComboList)
    FMWinComboList.OnEvent("ItemSelect", OnFMComboSelect)

    ; 右列（x=608..1168）：x+8 是相对中列表右边缘
    FMWinDemoLabel := FMWin.AddText("x+8 ym w560 h18 cGray", "")
    FMWinPreview := FMWin.AddEdit("xp y+2 w560 h384 +ReadOnly +VScroll", "")

    ; 右列下半：校验结果
    FMWin.AddText("xp y+6 w560 h18", "校验结果（点一条定位到左边）")
    FMWinIssueList := FMWin.AddListView("xp y+2 w560 h130 -Multi", ["类型", "位置", "说明"])
    FMWinIssueList.ModifyCol(1, 120)
    FMWinIssueList.ModifyCol(2, 150)
    FMWinIssueList.ModifyCol(3, 270)
    ApplyDialogListStyle(FMWinIssueList)
    FMWinIssueList.OnEvent("ItemSelect", OnFMIssueSelect)

    ; 底部（相对校验列表下缘）
    RefreshBtn := FMWin.AddButton("xm y+8 w100 h26", "刷新预览")
    RefreshBtn.OnEvent("Click", (*) => OnFMRefresh(true))
    CheckBtn := FMWin.AddButton("x+8 yp w100 h26", "重新校验")
    CheckBtn.OnEvent("Click", OnFMCheck)
    FMWinHint := FMWin.AddText("x+12 yp+4 w700 h20 cGray", "")
    CloseBtn := FMWin.AddButton("x1060 yp w80 h26", "关闭")
    CloseBtn.OnEvent("Click", CloseFlowMaintainWindow)

    RefreshFMFlowList(flowKey)
    FMWin.Show("w1180 h700")
}

CloseFlowMaintainWindow(*) {
    global FMWin, FMWinFlowList, FMWinComboList, FMWinPreview, FMWinDemoLabel
    global FMWinIssueList, FMWinHint, FMWinIssues, FMWinFlowKeys, FMWinCombos, FMWinCurFlow

    ; 销毁 + 置空：只 Hide 的话变量会悬空，下次 Show 报 "Gui has no window"
    if (FMWin) {
        FMWin.Destroy()
        FMWin := ""
    }
    FMWinFlowList := ""
    FMWinComboList := ""
    FMWinPreview := ""
    FMWinDemoLabel := ""
    FMWinIssueList := ""
    FMWinHint := ""
    FMWinIssues := []
    FMWinFlowKeys := []
    FMWinCombos := []
    FMWinCurFlow := ""
}

; ---- 左列表 ----

RefreshFMFlowList(preferKey := "") {
    global FMWinFlowList, FMWinFlowKeys, FMWinDemoLabel

    FMWinFlowList.Delete()
    FMWinFlowKeys := []
    selectedRow := 0

    for item in FlowLibrary.ListFlows() {
        FMWinFlowKeys.Push(item["key"])
        FMWinFlowList.Add(, item["shortName"], item["readonly"] ? "内置" : "自定义")
        if (preferKey != "" && item["key"] = preferKey && selectedRow = 0) {
            selectedRow := A_Index
        }
    }

    if (FMWinFlowKeys.Length = 0) {
        return
    }
    if (selectedRow = 0) {
        selectedRow := 1
    }
    FMWinFlowList.Modify(selectedRow, "Select Focus")
    OnFMFlowSelect()
}

; ---- 中列表 ----

OnFMFlowSelect(*) {
    global FMWinFlowList, FMWinComboList, FMWinFlowKeys, FMWinCombos, FMWinCurFlow
    global FMWinDemoLabel, FMWinHint, FMWinIssues, FMWinIssueList, FMWinPreview

    row := FMWinFlowList.GetNext(0)
    if (row = 0 || row > FMWinFlowKeys.Length) {
        return
    }
    flowKey := FMWinFlowKeys[row]
    FMWinCurFlow := flowKey

    FMWinDemoLabel.Text := "预览环境：演示主题（" PreviewTopicDir() "）"
    FMWinHint.Text := ""
    ; 占位提示：让"空"与"没加载"能分开
    FMWinPreview.Value := "（未选中组合）"
    FMWinIssues := []
    FMWinIssueList.Delete()
    FMWinComboList.Delete()
    FMWinCombos := []

    try {
        flow := FlowLibrary.Get(flowKey)
    } catch as e {
        FMWinHint.Text := "流程读不出来：" e.Message
        FMWinPreview.Value := ""
        return
    }

    for comboKey in Skeleton.GetAllComboKeys() {
        parts := StrSplit(comboKey, "|")
        blockIds := []
        blockNames := ""
        try {
            recipe := flow.GetRecipe(comboKey)
            blockIds := recipe.Content
        }

        for blockId in blockIds {
            name := blockId
            try {
                blk := BlockLibrary.Get(blockId, flow.BlocksDir)
                name := blk.Name != "" ? blk.Name : blockId
            } catch {
                name := "?缺"
            }
            blockNames .= (blockNames = "" ? "" : " ") "[" name "]"
        }

        FMWinCombos.Push(Map("combo", comboKey, "blocks", blockIds, "text", blockNames))
        FMWinComboList.Add(, comboKey, blockNames)
    }

    if (FMWinCombos.Length > 0) {
        FMWinComboList.Modify(1, "Select Focus")
        OnFMComboSelect()
    }
}

OnFMComboSelect(*) {
    global FMWinComboList, FMWinCombos
    row := FMWinComboList.GetNext(0)
    if (row = 0 || row > FMWinCombos.Length) {
        return
    }
    OnFMRefresh(false)
}

; ---- 预览 ----

OnFMRefresh(manual := true) {
    global FMWin, FMWinPreview, FMWinComboList, FMWinCombos, FMWinCurFlow, FMWinHint

    if (FMWinCurFlow = "") {
        return
    }
    row := FMWinComboList.GetNext(0)
    if (row = 0 || row > FMWinCombos.Length) {
        return
    }

    comboKey := FMWinCombos[row]["combo"]
    parts := StrSplit(comboKey, "|")

    try {
        text := PromptAssembler.Build(parts[1], parts[2], BuildFMEnv(FMWinCurFlow))
        FMWinPreview.Value := text
        if (manual) {
            FMWinHint.Text := "已刷新：" comboKey "（" StrLen(text) " 字符）"
        }
    } catch as e {
        FMWinPreview.Value := "预览失败：" e.Message
        FMWinHint.Text := "预览失败"
    }
}

; ---- 校验 ----

OnFMCheck(*) {
    global FMWinIssueList, FMWinIssues, FMWinHint, FMWinCurFlow

    if (FMWinCurFlow = "") {
        return
    }
    FMWinIssueList.Delete()
    FMWinIssues := []

    try {
        report := PromptValidator.CheckFlow(FMWinCurFlow)
    } catch as e {
        FMWinHint.Text := "校验失败：" e.Message
        return
    }

    for issue in report.Issues {
        FMWinIssues.Push(issue)
        FMWinIssueList.Add(, issue.KindLabel, issue.Scope, issue.Detail)
    }
    ; 零问题时插一行「（无问题）」——否则"跑了且没问题"与"没跑"看起来一样
    if (FMWinIssues.Length = 0) {
        FMWinIssueList.Add(, "（无问题）", "", "校验通过：未发现问题")
    }
    FMWinHint.Text := report.Summary()
}

; ---- 点击定位 ----

OnFMIssueSelect(*) {
    global FMWinIssueList, FMWinIssues, FMWinComboList, FMWinCombos, FMWinCurFlow, FMWinHint

    row := FMWinIssueList.GetNext(0)
    if (row = 0 || row > FMWinIssues.Length) {
        return
    }
    issue := FMWinIssues[row]
    target := ResolveIssueTarget(issue, FMWinCurFlow)
    comboKey := target["combo"]
    blockId := target["blockId"]

    if (comboKey = "") {
        FMWinHint.Text := "该项无法定位到具体组合"
        return
    }

    for idx, item in FMWinCombos {
        if (item["combo"] = comboKey) {
            FMWinComboList.Modify(idx, "Select Focus")
            FMWinComboList.ModifyCol(1)      ; 触发重绘
            FMWinHint.Text := (blockId = "")
                ? "定位到 " comboKey
                : "定位到 " comboKey " 的块 " blockId
            return
        }
    }
    FMWinHint.Text := "该组合不在当前流程的清单里"
}

; Scope 有两种形态：组合键（含 "|"）或文件路径（…\blocks\<id>\…）
; 路径形态反查"哪个组合引用了这个块"
ResolveIssueTarget(issue, flowKey) {
    scope := issue.Scope
    if InStr(scope, "|") {
        return Map("combo", scope, "blockId", "")
    }
    if !RegExMatch(scope, "\\blocks\\([^\\]+)", &m) {
        return Map("combo", "", "blockId", "")
    }
    blockId := m[1]

    try {
        flow := FlowLibrary.Get(flowKey)
        for comboKey in Skeleton.GetAllComboKeys() {
            try {
                recipe := flow.GetRecipe(comboKey)
            } catch {
                continue
            }
            for id in recipe.Content {
                if (id = blockId) {
                    return Map("combo", comboKey, "blockId", blockId)
                }
            }
        }
    }
    return Map("combo", "", "blockId", blockId)
}

; ---- 环境 ----

; 预览固定用演示主题：不随当前主题变，同一流程永远同一份预览
PreviewTopicDir() {
    global AppRoot
    return AppRoot "\templates\preview-topic"
}

BuildFMEnv(flowKey) {
    global AppConfig
    env := Environment()
    env.TopicDir := PreviewTopicDir()
    env.WindowId := GetActiveWindowId()
    env.FlowKey := flowKey
    env.OpenMdScriptPath := AppConfig["OpenMdScriptPath"]
    env.NotificationScriptPath := AppConfig["NotificationScriptPath"]
    return env
}
