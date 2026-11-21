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
global FMWinNewBtn := ""
global FMWinRenameBtn := ""
global FMWinDeleteBtn := ""
global FMWinSelectBtn := ""
global FMWinBlocksBtn := ""
global FMNewDialog := "", FMNewName := "", FMNewShort := "", FMNewKey := ""
global FMNewCopy := "", FMNewBlank := "", FMNewHint := "", FMNewOk := ""
global FMRenameDialog := "", FMRenameName := "", FMRenameShort := ""
global FMRenameHint := "", FMRenameOk := ""

; 只 include 一次，重复调用只是 Show + 刷新
ShowFlowMaintainWindow(flowKey := "") {
    global FMWin, FMWinFlowList, FMWinComboList, FMWinPreview, FMWinDemoLabel
    global FMWinIssueList, FMWinHint, FMWinIssues, FMWinFlowKeys, FMWinCombos, FMWinCurFlow
    global FMWinNewBtn, FMWinRenameBtn, FMWinDeleteBtn, FMWinSelectBtn, FMWinBlocksBtn

    if (FMWin) {
        if (GuiAlive(FMWin)) {
            FMWin.Show()
            WinActivate("ahk_id " FMWin.Hwnd)
            RefreshFMFlowList(flowKey != "" ? flowKey : FMWinCurFlow)
            return
        }
        ; owner 被销毁时，这个窗口会跟着没掉，但变量还悬着——清掉重建
        CloseFlowMaintainWindow()
    }

    ; 布局说明：AHK 的 "x+8" 是"上一个控件的右边缘 +8"，不是"左边 +8"。
    ; 所以"标题 → 其下控件"一律用 xp（与上一个同左边缘），
    ; 只有"跨列"时才用 x+8（相对上一列的右边缘）。
    opts := "+MinSize1300x700"
    ; 按来源绑 owner：从设置主题弹窗打开就绑它，从托盘打开就绑主面板。
    ; 子窗口永远在父窗口之上，层级自然对——不用 AlwaysOnTop（那会盖住别的程序）。
    ; owner 可能是已销毁的旧引用，必须判活，否则读 Hwnd 就抛错。
    if (IsSet(ThemeSelectDialog) && GuiAlive(ThemeSelectDialog)) {
        opts .= " +Owner" ThemeSelectDialog.Hwnd
    } else if (IsSet(MainGui) && GuiAlive(MainGui)) {
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
    ; 列表让出一行给「新建 / 改名 / 删除」：620 → 588，列底仍是 652
    ; 维护窗口是编辑场景：显示全称，不用面板那套固定宽简称
    FMWinFlowList := FMWin.AddListView("xp y+2 w220 h588 -Multi", ["流程", "类型"])
    FMWinFlowList.ModifyCol(1, 150)
    FMWinFlowList.ModifyCol(2, "60 Center")
    ApplyDialogListStyle(FMWinFlowList)
    FMWinFlowList.OnEvent("ItemSelect", OnFMFlowSelect)

    ; 三个按钮贴着左列对象：12 + 68 + 8 + 68 + 8 + 68 = 232，与列表同宽
    FMWinNewBtn := FMWin.AddButton("xp y+6 w68 h26", "新建")
    FMWinNewBtn.OnEvent("Click", OnFMNew)
    FMWinRenameBtn := FMWin.AddButton("x+8 yp w68 h26", "改名")
    FMWinRenameBtn.OnEvent("Click", OnFMRename)
    FMWinDeleteBtn := FMWin.AddButton("x+8 yp w68 h26", "删除")
    FMWinDeleteBtn.OnEvent("Click", OnFMDelete)
    UpdateFMWriteButtons(false, true)

    ; 中列（x=240..740）：x+8 是相对左列表右边缘
    FMWin.AddText("x+8 ym w500 h18", "组合与块（选中一行看右边预览）")
    ; 与左列对称：列表让出一行给「选块…」：620 → 588，列底仍是 652
    FMWinComboList := FMWin.AddListView("xp y+2 w500 h588 -Multi", ["组合", "块"])
    FMWinComboList.ModifyCol(1, 130)
    FMWinComboList.ModifyCol(2, 370)
    ApplyDialogListStyle(FMWinComboList)
    FMWinComboList.OnEvent("ItemSelect", OnFMComboSelect)
    FMWinComboList.OnEvent("DoubleClick", OnFMSelectBlock)

    FMWinSelectBtn := FMWin.AddButton("xp y+6 w100 h26", "选块…")
    FMWinSelectBtn.OnEvent("Click", OnFMSelectBlock)

    ; 右列（x=748..1388）：这里必须写绝对 x，因为上一个控件是「选块…」按钮，
    ; 用 x+8 会贴到按钮右边（曾经的三列错位就是这么来的）
    FMWinDemoLabel := FMWin.AddText("x748 ym w640 h18 cGray", "")
    FMWinPreview := FMWin.AddEdit("xp y+2 w640 h464 +ReadOnly +VScroll", "")

    ; 右列下半：校验结果
    FMWin.AddText("xp y+6 w640 h18", "校验结果（点一条定位到左边）")
    FMWinIssueList := FMWin.AddListView("xp y+2 w640 h130 -Multi", ["类型", "位置", "说明"])
    FMWinIssueList.ModifyCol(1, 120)
    FMWinIssueList.ModifyCol(2, 150)
    FMWinIssueList.ModifyCol(3, 350)
    ApplyDialogListStyle(FMWinIssueList)
    FMWinIssueList.OnEvent("ItemSelect", OnFMIssueSelect)

    ; 底部（相对校验列表下缘）
    RefreshBtn := FMWin.AddButton("xm y+8 w100 h26", "刷新预览")
    RefreshBtn.OnEvent("Click", (*) => OnFMRefresh(true))
    CheckBtn := FMWin.AddButton("x+8 yp w100 h26", "重新校验")
    CheckBtn.OnEvent("Click", OnFMCheck)
    FMWinBlocksBtn := FMWin.AddButton("x+8 yp w120 h26", "管理私有块")
    FMWinBlocksBtn.OnEvent("Click", OnFMPrivateBlocks)
    FMWinHint := FMWin.AddText("x+12 yp+4 w700 h20 cGray", "")
    CloseBtn := FMWin.AddButton("x1308 yp w80 h26", "关闭")
    CloseBtn.OnEvent("Click", CloseFlowMaintainWindow)

    RefreshFMFlowList(flowKey)
    FMWin.Show("w1400 h740")
}

CloseFlowMaintainWindow(*) {
    global FMWin, FMWinFlowList, FMWinComboList, FMWinPreview, FMWinDemoLabel
    global FMWinIssueList, FMWinHint, FMWinIssues, FMWinFlowKeys, FMWinCombos, FMWinCurFlow
    global FMWinNewBtn, FMWinRenameBtn, FMWinDeleteBtn, FMWinSelectBtn, FMWinBlocksBtn

    ; 销毁 + 置空：只 Hide 的话变量会悬空，下次 Show 报 "Gui has no window"。
    ; 窗口可能已被 owner 连带销毁，那时 Hwnd 读取会抛错，所以先判活。
    if (GuiAlive(FMWin)) {
        try FMWin.Destroy()
    }
    FMWin := ""
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
    FMWinNewBtn := ""
    FMWinRenameBtn := ""
    FMWinDeleteBtn := ""
    FMWinSelectBtn := ""
    FMWinBlocksBtn := ""
}

; ---- 左列表 ----

RefreshFMFlowList(preferKey := "") {
    global FMWinFlowList, FMWinFlowKeys, FMWinDemoLabel

    if (!FMWinFlowList)
        return

    FMWinFlowList.Delete()
    FMWinFlowKeys := []
    selectedRow := 0

    for item in FlowLibrary.ListFlows() {
        FMWinFlowKeys.Push(item["key"])
        FMWinFlowList.Add(, item["name"], item["readonly"] ? "内置" : "自定义")
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
        FMWinCurFlow := ""
        UpdateFMWriteButtons(false, true)
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
        UpdateFMWriteButtons(false, true)
        return
    }

    ; 内置流程只读：改名 / 删除置灰，不给入口比点了再报错好
    UpdateFMWriteButtons(true, flow.Readonly)

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
        ; 显示名与面板一致：有 label 用"动作 · label"，没有就只用动作名
        FMWinComboList.Add(, ComboDisplayName(comboKey), blockNames)
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

; ---- 选块（03）----

; 中列「选块…」或双击组合行：给该组合挑块、排序、写回
OnFMSelectBlock(*) {
    global FMWinCurFlow, FMWinCombos, FMWinComboList

    if (FMWinCurFlow = "")
        return
    row := FMWinComboList.GetNext(0)
    if (row = 0 || row > FMWinCombos.Length)
        return

    comboKey := FMWinCombos[row]["combo"]
    if (ShowFlowBlockPicker(FMWinCurFlow, comboKey)) {
        ; 保存后必须重建中列：块名文字是选流程时的快照，不重建就会一直显示旧配置
        RefreshFMFlowList(FMWinCurFlow)
        for idx, item in FMWinCombos {
            if (item["combo"] = comboKey) {
                FMWinComboList.Modify(idx, "Select Focus")
                OnFMComboSelect()
                break
            }
        }
        OnFMRefresh(true)
        SetFMHint("已保存：" ComboDisplayName(comboKey) " 的块顺序")
    }
}

; ---- 私有块（05.2）----

; 打开块维护窗口；有改动才重建中列与预览（块名会变）
OnFMPrivateBlocks(*) {
    global FMWinCurFlow, FMWinCombos, FMWinComboList

    if (FMWinCurFlow = "")
        return
    try {
        flow := FlowLibrary.Get(FMWinCurFlow)
    } catch {
        return
    }
    if (flow.Readonly)
        return

    row := FMWinComboList.GetNext(0)
    comboKey := (row > 0 && row <= FMWinCombos.Length) ? FMWinCombos[row]["combo"] : ""

    if (!ShowBlockMaintainWindow(FMWinCurFlow))
        return

    ; 块窗口是模态等待期间，维护窗口可能已被关掉（owner 连带销毁）
    if (!GuiAlive(FMWin))
        return

    RefreshFMFlowList(FMWinCurFlow)
    if (comboKey != "") {
        for idx, item in FMWinCombos {
            if (item["combo"] = comboKey) {
                FMWinComboList.Modify(idx, "Select Focus")
                OnFMComboSelect()
                break
            }
        }
    }
    OnFMRefresh(true)
    SetFMHint("私有块已更新")
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

; 组合键 → 与面板一致的显示名
; 面板规则：有 label 就显示 label（答辩/技炼/改吧/步目/实），没有就显示动作名
ComboDisplayName(comboKey) {
    parts := StrSplit(comboKey, "|")
    if (parts.Length < 2) {
        return comboKey
    }
    actKey := parts[1]
    polKey := parts[2]
    try {
        pol := Action.FromSkeleton(actKey).GetPolicy(polKey)
        if (pol && pol.Label != "") {
            return actKey " · " pol.Label
        }
    }
    return actKey
}

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

; ---- 新建 / 改名 / 删除（02）----

; 内置流程只读：改名 / 删除置灰；新建始终可用（列表为空时也能建第一个）
UpdateFMWriteButtons(hasFlow, isBuiltin) {
    global FMWinRenameBtn, FMWinDeleteBtn, FMWinBlocksBtn
    if (FMWinRenameBtn)
        FMWinRenameBtn.Enabled := hasFlow && !isBuiltin
    if (FMWinDeleteBtn)
        FMWinDeleteBtn.Enabled := hasFlow && !isBuiltin
    if (FMWinBlocksBtn)
        FMWinBlocksBtn.Enabled := hasFlow && !isBuiltin
}

SetFMHint(text) {
    global FMWinHint
    if (FMWinHint)
        FMWinHint.Text := text
}

; 删除前查三档：只读 → 默认流程 → 窗口占用。顺序从便宜到贵
FlowDeletionBlockedReason(flowKey) {
    try {
        flow := FlowLibrary.Get(flowKey)
    } catch as e {
        return e.Message
    }
    if (flow.Readonly)
        return "内置流程不可删除"
    if (flowKey = GetDefaultFlowKey())
        return "它是默认流程，删除后新主题都会指向不存在的流程"
    winId := FlowResolver.IsUsedByAnyWindow(flowKey)
    if (winId < 0)
        return "窗口 " (-winId) " 的流程配置读不出来，无法确认是否在用；先修好它再删"
    if (winId)
        return "窗口 " winId " 的当前主题正在使用该流程"
    return ""
}

; ---- 新建弹窗 ----

OnFMNew(*) {
    ShowFMNewDialog()
}

ShowFMNewDialog() {
    global FMWin, FMNewDialog, FMNewName, FMNewShort, FMNewKey
    global FMNewCopy, FMNewBlank, FMNewHint, FMNewOk

    if (FMNewDialog) {
        if (GuiAlive(FMNewDialog)) {
            FMNewDialog.Show()
            WinActivate("ahk_id " FMNewDialog.Hwnd)
            return
        }
        CloseFMNewDialog()
    }

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(FMWin))
        opts .= " +Owner" FMWin.Hwnd

    d := Gui(opts, "新建流程")
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseFMNewDialog)
    d.OnEvent("Escape", CloseFMNewDialog)

    d.AddText("xm ym w68 h20", "流程名称")
    FMNewName := d.AddEdit("x+8 yp w296 h24")
    d.AddText("xm y+10 w68 h20", "流程简称")
    FMNewShort := d.AddEdit("x+8 yp w296 h24")
    d.AddText("xm y+10 w68 h20", "流程标识")
    FMNewKey := d.AddEdit("x+8 yp w296 h24")

    d.AddText("xm y+12 w68 h20", "起点")
    ; 单选组与上面三个输入框左对齐（x88），不能用 x+8——那是"上一个控件的右边缘 +8"，
    ; 会跑到输入框右边、超出窗口（曾导致"空白流程"被裁掉）
    FMNewCopy := d.AddRadio("x88 yp w296 h20 Checked", "从内置流程复制（code）")
    FMNewBlank := d.AddRadio("x88 y+2 w296 h20", "空白流程")

    FMNewHint := d.AddText("xm y+8 w372 h34 cRed", "")
    FMNewOk := d.AddButton("x212 y+6 w80 h26 Default", "确定")
    FMNewOk.OnEvent("Click", OnFMNewOk)
    btnCancel := d.AddButton("x+8 yp w80 h26", "取消")
    btnCancel.OnEvent("Click", CloseFMNewDialog)

    FMNewName.OnEvent("Change", (*) => UpdateFMNewState())
    FMNewShort.OnEvent("Change", (*) => UpdateFMNewState())
    FMNewKey.OnEvent("Change", (*) => UpdateFMNewState())

    FMNewDialog := d
    UpdateFMNewState()
    d.Show("w396 h286")
}

CloseFMNewDialog(*) {
    global FMNewDialog, FMNewName, FMNewShort, FMNewKey
    global FMNewCopy, FMNewBlank, FMNewHint, FMNewOk

    if (GuiAlive(FMNewDialog)) {
        try FMNewDialog.Destroy()
    }
    FMNewDialog := ""
    FMNewName := ""
    FMNewShort := ""
    FMNewKey := ""
    FMNewCopy := ""
    FMNewBlank := ""
    FMNewHint := ""
    FMNewOk := ""
}

UpdateFMNewState() {
    global FMNewName, FMNewShort, FMNewKey, FMNewHint, FMNewOk

    name := Trim(FMNewName.Value)
    short := Trim(FMNewShort.Value)
    key := Trim(FMNewKey.Value)

    msg := ""
    if (name = "")
        msg := "请填流程名称"
    else if (short = "")
        msg := "请填流程简称"
    else if (key = "")
        msg := "请填流程标识"
    else
        msg := FlowEditor.ValidateKey(key)

    FMNewHint.Text := msg
    FMNewOk.Enabled := (msg = "")
}

OnFMNewOk(*) {
    global FMNewName, FMNewShort, FMNewKey, FMNewBlank, FMNewHint

    name := Trim(FMNewName.Value)
    short := Trim(FMNewShort.Value)
    key := Trim(FMNewKey.Value)

    try {
        FlowEditor.Create("code", key, name, short, FMNewBlank.Value)
    } catch as e {
        FMNewHint.Text := e.Message
        return
    }

    CloseFMNewDialog()
    RefreshFMFlowList(key)
    SetFMHint("已创建：" name)
}

; ---- 改名弹窗 ----

OnFMRename(*) {
    global FMWin, FMWinCurFlow, FMRenameDialog, FMRenameName, FMRenameShort
    global FMRenameKeyText, FMRenameHint, FMRenameOk

    if (FMWinCurFlow = "")
        return
    try {
        flow := FlowLibrary.Get(FMWinCurFlow)
    } catch as e {
        MsgBox(e.Message, "改名", "Icon! Owner" FMWin.Hwnd)
        return
    }
    if (flow.Readonly)
        return

    if (FMRenameDialog) {
        if (GuiAlive(FMRenameDialog)) {
            FMRenameDialog.Show()
            WinActivate("ahk_id " FMRenameDialog.Hwnd)
            return
        }
        CloseFMRenameDialog()
    }

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(FMWin))
        opts .= " +Owner" FMWin.Hwnd

    d := Gui(opts, "改名")
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseFMRenameDialog)
    d.OnEvent("Escape", CloseFMRenameDialog)

    d.AddText("xm ym w68 h20", "流程名称")
    FMRenameName := d.AddEdit("x+8 yp w280 h24")
    FMRenameName.Value := flow.Name
    d.AddText("xm y+10 w68 h20", "流程简称")
    FMRenameShort := d.AddEdit("x+8 yp w280 h24")
    FMRenameShort.Value := flow.ShortName
    d.AddText("xm y+10 w68 h20", "流程标识")
    FMRenameKeyText := d.AddText("x+8 yp w280 h20 cGray", flow.Key)

    FMRenameHint := d.AddText("xm y+8 w352 h30 cRed", "")
    FMRenameOk := d.AddButton("x192 y+6 w80 h26 Default", "确定")
    FMRenameOk.OnEvent("Click", OnFMRenameOk)
    btnCancel := d.AddButton("x+8 yp w80 h26", "取消")
    btnCancel.OnEvent("Click", CloseFMRenameDialog)

    FMRenameName.OnEvent("Change", (*) => UpdateFMRenameState())
    FMRenameShort.OnEvent("Change", (*) => UpdateFMRenameState())

    FMRenameDialog := d
    UpdateFMRenameState()
    d.Show("w380 h230")
}

CloseFMRenameDialog(*) {
    global FMRenameDialog, FMRenameName, FMRenameShort, FMRenameKeyText
    global FMRenameHint, FMRenameOk

    if (GuiAlive(FMRenameDialog)) {
        try FMRenameDialog.Destroy()
    }
    FMRenameDialog := ""
    FMRenameName := ""
    FMRenameShort := ""
    FMRenameKeyText := ""
    FMRenameHint := ""
    FMRenameOk := ""
}

UpdateFMRenameState() {
    global FMRenameName, FMRenameShort, FMRenameHint, FMRenameOk

    name := Trim(FMRenameName.Value)
    short := Trim(FMRenameShort.Value)

    msg := ""
    if (name = "")
        msg := "请填流程名称"
    else if (short = "")
        msg := "请填流程简称"

    FMRenameHint.Text := msg
    FMRenameOk.Enabled := (msg = "")
}

OnFMRenameOk(*) {
    global FMWinCurFlow, FMRenameName, FMRenameShort, FMRenameHint

    flowKey := FMWinCurFlow
    name := Trim(FMRenameName.Value)
    short := Trim(FMRenameShort.Value)

    try {
        FlowEditor.Rename(flowKey, name, short)
    } catch as e {
        FMRenameHint.Text := e.Message
        return
    }

    CloseFMRenameDialog()
    RefreshFMFlowList(flowKey)
    SetFMHint("已保存：" name)
}

; ---- 删除 ----

OnFMDelete(*) {
    global FMWin, FMWinCurFlow, FMWinFlowList, FMWinFlowKeys

    if (FMWinCurFlow = "")
        return
    try {
        flow := FlowLibrary.Get(FMWinCurFlow)
    } catch as e {
        MsgBox(e.Message, "删除流程", "Icon! Owner" FMWin.Hwnd)
        return
    }

    reason := FlowDeletionBlockedReason(FMWinCurFlow)
    if (reason != "") {
        MsgBox(reason, "不能删除", "Icon! Owner" FMWin.Hwnd)
        return
    }

    if (MsgBox("确定删除流程「" flow.Name "」吗？`n`n将删除整个目录：`n" flow.Dir
            . "`n`n此操作不可撤销。", "删除流程", "Icon! YesNo Default2 Owner" FMWin.Hwnd) != "Yes")
        return

    ; 删之前先记下相邻项：删完选中它，而不是跳回第一行
    row := FMWinFlowList.GetNext(0)
    nextKey := ""
    if (row < FMWinFlowKeys.Length)
        nextKey := FMWinFlowKeys[row + 1]
    else if (row > 1)
        nextKey := FMWinFlowKeys[row - 1]

    try {
        FlowEditor.Delete(FMWinCurFlow)
    } catch as e {
        MsgBox("删除失败：" e.Message, "删除流程", "Iconx Owner" FMWin.Hwnd)
        return
    }

    RefreshFMFlowList(nextKey)
    SetFMHint("已删除：" flow.Name)
}




