#Requires AutoHotkey v2.0

; 选块弹窗：给一个「动作 · 策略」挑块并排序
;
; 左：候选（本流程私有 + 全局，同名只留私有），带勾选与筛选
; 右：选中区，顺序即拼装顺序
; 勾选只是"意图"，点「同步到选中区」才写进右侧；确定时自动再同步一次。
;
; ListView 的坑（见 基础信息\技术信息.md）：勾选框要手动开 LVS_EX_CHECKBOXES 且必须先开样式再添行；
; 这个 AHK 版本没有 ItemCheck 事件，所以不做实时同步，用显式按钮。

global FBPWin := ""
global FBPFlowKey := ""
global FBPComboKey := ""
global FBPCandidates := []          ; [{id,name,kind,purpose,scope}]
global FBPVisible := []            ; 当前筛选后可见的候选（与左列行一一对应）
global FBPChecked := Map()         ; id → true，用户的勾选意图（跨筛选保留）
global FBPSelected := []           ; 选中区，顺序即拼写顺序
global FBPResult := false

global FBPKeyEdit := ""
global FBPKindCombo := ""
global FBPScopeCombo := ""
global FBPCountText := ""
global FBPLeftList := ""
global FBPRightList := ""
global FBPSyncBtn := ""
global FBPUpBtn := ""
global FBPDownBtn := ""
global FBPRemoveBtn := ""
global FBPStatus := ""

LVM_GETITEMSTATE := 0x102C
LVM_SETEXTENDEDLISTVIEWSTYLE := 0x1036
LVIS_STATEIMAGEMASK := 0x2000
LVS_EX_CHECKBOXES := 0x4

; 打开选块弹窗；保存成功返回 true，取消/关闭返回 false
ShowFlowBlockPicker(flowKey, comboKey) {
    global FBPWin, FBPFlowKey, FBPComboKey, FBPCandidates, FBPSelected
    global FBPChecked, FBPResult

    if (FBPWin) {
        if (GuiAlive(FBPWin)) {
            FBPWin.Show()
            WinActivate("ahk_id " FBPWin.Hwnd)
            return false
        }
        CloseFlowBlockPicker()
    }

    FBPFlowKey := flowKey
    FBPComboKey := comboKey
    FBPResult := false
    FBPCandidates := BuildFBPCandidates(flowKey)
    FBPSelected := LoadFBPCurrent(flowKey, comboKey)

    ; 勾选意图：选中区里、且候选里存在的块，初始为勾选
    FBPChecked := Map()
    for id in FBPSelected {
        if IsFBPCandidate(id)
            FBPChecked[id] := true
    }

    BuildFlowBlockPicker()
    FBPWin.Show("w872 h564")
    WinWaitClose("ahk_id " FBPWin.Hwnd)
    return FBPResult
}

BuildFlowBlockPicker() {
    global FBPWin, FBPKeyEdit, FBPKindCombo, FBPScopeCombo, FBPCountText
    global FBPLeftList, FBPRightList, FBPSyncBtn, FBPUpBtn, FBPDownBtn, FBPRemoveBtn
    global FBPStatus, FMWin, FBPFlowKey, FBPComboKey

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(FMWin))
        opts .= " +Owner" FMWin.Hwnd

    d := Gui(opts, "选块")
    FBPWin := d
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseFlowBlockPicker)
    d.OnEvent("Escape", CloseFlowBlockPicker)

    ; 顶部：筛选
    d.AddText("xm ym w48 h22", "关键字")
    FBPKeyEdit := d.AddEdit("x+8 yp w200 h22")
    d.AddText("x+16 yp w40 h22", "类别")
    FBPKindCombo := d.AddComboBox("x+8 yp w130 h22")
    d.AddText("x+16 yp w40 h22", "归属")
    FBPScopeCombo := d.AddComboBox("x+8 yp w100 h22")
    FBPScopeCombo.Add(["全部", "公共", "私有"])
    FBPScopeCombo.Value := 1
    FBPCountText := d.AddText("x+16 yp w120 h22 cGray", "")

    ; 左列：候选（先开复选框样式，再添行；顺序反了会丢勾选框）
    FBPLeftList := d.AddListView("xm y+8 w520 h440 -Multi", ["名称", "类别", "归属", "说明"])
    SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, LVS_EX_CHECKBOXES, LVS_EX_CHECKBOXES, FBPLeftList.Hwnd)
    FBPLeftList.ModifyCol(1, 170)
    FBPLeftList.ModifyCol(2, 90)
    FBPLeftList.ModifyCol(3, 60)
    FBPLeftList.ModifyCol(4, 196)
    ApplyDialogListStyle(FBPLeftList)
    FBPLeftList.OnEvent("DoubleClick", OnFBPToggleRow)

    FBPSyncBtn := d.AddButton("xm y+6 w140 h26", "同步到选中区 →")
    FBPSyncBtn.OnEvent("Click", OnFBPSync)

    ; 右列：选中区（顺序）
    d.AddText("x540 y44 w320 h18", "选中区（顺序即拼装顺序）")
    FBPRightList := d.AddListView("x540 y+2 w320 h418 -Multi", ["序号", "名称"])
    FBPRightList.ModifyCol(1, 40)
    FBPRightList.ModifyCol(2, 276)
    ApplyDialogListStyle(FBPRightList)
    FBPRightList.OnEvent("Click", OnFBPRightClick)
    FBPRightList.OnEvent("ItemSelect", OnFBPRightClick)

    FBPUpBtn := d.AddButton("x540 y+6 w90 h26", "上移")
    FBPUpBtn.OnEvent("Click", OnFBPUp)
    FBPDownBtn := d.AddButton("x+8 yp w90 h26", "下移")
    FBPDownBtn.OnEvent("Click", OnFBPDown)
    FBPRemoveBtn := d.AddButton("x+8 yp w90 h26", "移除")
    FBPRemoveBtn.OnEvent("Click", OnFBPRemove)

    ; 底部
    FBPStatus := d.AddText("xm y+10 w660 h20 cGray", "")
    btnOk := d.AddButton("x688 y526 w80 h26 Default", "确定")
    btnOk.OnEvent("Click", OnFBPOk)
    btnCancel := d.AddButton("x+8 yp w80 h26", "取消")
    btnCancel.OnEvent("Click", CloseFlowBlockPicker)

    FBPKeyEdit.OnEvent("Change", (*) => OnFBPFilterChanged())
    FBPKindCombo.OnEvent("Change", (*) => OnFBPFilterChanged())
    FBPScopeCombo.OnEvent("Change", (*) => OnFBPFilterChanged())

    FillFBPKindCombo()
    RefreshFBPLeft()
    RefreshFBPRight()

    SetFBPStatus("将写入：" ComboDisplayName(FBPComboKey) "（勾选后点同步）")
}

CloseFlowBlockPicker(*) {
    global FBPWin, FBPKeyEdit, FBPKindCombo, FBPScopeCombo, FBPCountText
    global FBPLeftList, FBPRightList, FBPSyncBtn, FBPUpBtn, FBPDownBtn, FBPRemoveBtn
    global FBPStatus, FBPVisible, FBPCandidates

    if (GuiAlive(FBPWin)) {
        try FBPWin.Destroy()
    }
    FBPWin := ""
    FBPKeyEdit := ""
    FBPKindCombo := ""
    FBPScopeCombo := ""
    FBPCountText := ""
    FBPLeftList := ""
    FBPRightList := ""
    FBPSyncBtn := ""
    FBPUpBtn := ""
    FBPDownBtn := ""
    FBPRemoveBtn := ""
    FBPStatus := ""
    FBPVisible := []
    FBPCandidates := []
}

; ---- 数据 ----

BuildFBPCandidates(flowKey) {
    cands := []
    seen := Map()

    flow := FlowLibrary.Get(flowKey)
    for id in flow.ListBlockIds() {
        cands.Push(LoadFBPCandidate(id, flow.BlocksDir, "私有"))
        seen[id] := true
    }
    for id in BlockLibrary.ListIds(BlockLibrary.DataRoot "\blocks") {
        if seen.Has(id)
            continue
        cands.Push(LoadFBPCandidate(id, "", "公共"))
        seen[id] := true
    }
    return cands
}

LoadFBPCandidate(id, blocksDir, scope) {
    try {
        blk := BlockLibrary.Get(id, blocksDir)
        return Map("id", id,
                   "name", blk.Name != "" ? blk.Name : id,
                   "kind", blk.Kind != "" ? blk.Kind : "?",
                   "purpose", blk.Purpose,
                   "scope", scope)
    } catch {
        return Map("id", id, "name", id, "kind", "?", "purpose", "", "scope", scope)
    }
}

; 当前组合已有的 content
LoadFBPCurrent(flowKey, comboKey) {
    ids := []
    try {
        flow := FlowLibrary.Get(flowKey)
        recipe := flow.GetRecipe(comboKey)
        for id in recipe.Content
            ids.Push(id)
    }
    return ids
}

FindFBPCandidate(id) {
    global FBPCandidates
    for c in FBPCandidates {
        if (c["id"] = id)
            return c
    }
    return ""
}

IsFBPCandidate(id) {
    return FindFBPCandidate(id) != ""
}

; ---- 左列 ----

FillFBPKindCombo() {
    global FBPCandidates, FBPKindCombo

    kinds := []
    for c in FBPCandidates {
        if c["kind"] = "" || c["kind"] = "?"
            continue
        if !HasFBPValue(kinds, c["kind"])
            kinds.Push(c["kind"])
    }
    FBPKindCombo.Delete()
    FBPKindCombo.Add(["全部"])
    for k in kinds
        FBPKindCombo.Add([k])
    FBPKindCombo.Value := 1
}

OnFBPFilterChanged() {
    ; 重建前先把当前可见行的勾选收进意图表，否则筛选会丢状态
    CaptureFBPChecks()
    RefreshFBPLeft()
}

RefreshFBPLeft() {
    global FBPLeftList, FBPCandidates, FBPVisible, FBPChecked, FBPCountText
    global FBPKeyEdit, FBPKindCombo, FBPScopeCombo

    kw := Trim(FBPKeyEdit.Value)
    kindSel := FBPKindCombo.Text
    scopeSel := FBPScopeCombo.Text

    FBPLeftList.Delete()
    FBPVisible := []
    for c in FBPCandidates {
        if (kw != "" && !(InStr(c["name"], kw, false) || InStr(c["purpose"], kw, false) || InStr(c["kind"], kw, false)))
            continue
        if (kindSel != "" && kindSel != "全部" && c["kind"] != kindSel)
            continue
        if (scopeSel != "" && scopeSel != "全部" && c["scope"] != scopeSel)
            continue

        FBPVisible.Push(c)
        FBPLeftList.Add(, c["name"], c["kind"], c["scope"], c["purpose"])
        if FBPChecked.Has(c["id"])
            FBPLeftList.Modify(A_Index, "Check")
    }

    FBPCountText.Text := "候选 " FBPVisible.Length " 个"
}

; 读左列可见行的勾选，写回意图表（被筛掉的行保留原意图）
CaptureFBPChecks() {
    global FBPVisible, FBPChecked, FBPLeftList

    for idx, c in FBPVisible {
        if (GetFBPCheckState(idx) = 2)
            FBPChecked[c["id"]] := true
        else if FBPChecked.Has(c["id"])
            FBPChecked.Delete(c["id"])
    }
}

GetFBPCheckState(row) {
    global FBPLeftList
    s := SendMessage(LVM_GETITEMSTATE, row - 1, LVIS_STATEIMAGEMASK, FBPLeftList.Hwnd)
    return (s >> 12) & 0xF
}

OnFBPToggleRow(*) {
    global FBPLeftList
    row := FBPLeftList.GetNext(0)
    if (row = 0)
        return
    if (GetFBPCheckState(row) = 2)
        FBPLeftList.Modify(row, "-Check")
    else
        FBPLeftList.Modify(row, "Check")
}

; ---- 同步 ----

OnFBPSync(*) {
    SyncFBPSelection()
}

SyncFBPSelection() {
    global FBPSelected, FBPChecked, FBPCandidates

    CaptureFBPChecks()

    newSel := []
    ; ① 选中区原有顺序：仍勾选的保留原位；命中 ?缺 的也保留
    for id in FBPSelected {
        if IsFBPCandidate(id) {
            if FBPChecked.Has(id)
                newSel.Push(id)
        } else {
            newSel.Push(id)
        }
    }
    ; ② 新勾选的追加到末尾
    for c in FBPCandidates {
        id := c["id"]
        if FBPChecked.Has(id) && !HasFBPValue(newSel, id)
            newSel.Push(id)
    }

    FBPSelected := newSel
    RefreshFBPRight()
    SetFBPStatus("已同步：" FBPSelected.Length " 个块")
}

; ---- 右列 ----

RefreshFBPRight() {
    global FBPRightList, FBPSelected, FBPUpBtn, FBPDownBtn, FBPRemoveBtn

    FBPRightList.Delete()
    for idx, id in FBPSelected {
        c := FindFBPCandidate(id)
        name := (c = "") ? id "（?缺）" : c["name"]
        FBPRightList.Add(, idx, name)
    }

    if (FBPSelected.Length > 0)
        FBPRightList.Modify(1, "Select Focus")
    UpdateFBPRightButtons()
}

UpdateFBPRightButtons() {
    global FBPRightList, FBPSelected, FBPUpBtn, FBPDownBtn, FBPRemoveBtn

    row := FBPRightList.GetNext(0)
    FBPUpBtn.Enabled := (row > 1)
    FBPDownBtn.Enabled := (row > 0 && row < FBPSelected.Length)
    FBPRemoveBtn.Enabled := (row > 0)
}

OnFBPRightClick(*) {
    UpdateFBPRightButtons()
}

OnFBPUp(*) {
    global FBPRightList, FBPSelected

    row := FBPRightList.GetNext(0)
    if (row <= 1)
        return
    SwapFBPSelected(row, row - 1)
    RefreshFBPRight()
    FBPRightList.Modify(row - 1, "Select Focus")
    UpdateFBPRightButtons()
}

OnFBPDown(*) {
    global FBPRightList, FBPSelected

    row := FBPRightList.GetNext(0)
    if (row = 0 || row >= FBPSelected.Length)
        return
    SwapFBPSelected(row, row + 1)
    RefreshFBPRight()
    FBPRightList.Modify(row + 1, "Select Focus")
    UpdateFBPRightButtons()
}

OnFBPRemove(*) {
    global FBPRightList, FBPSelected, FBPChecked

    row := FBPRightList.GetNext(0)
    if (row = 0)
        return
    id := FBPSelected[row]
    FBPSelected.RemoveAt(row)
    if FBPChecked.Has(id)
        FBPChecked.Delete(id)
    RefreshFBPRight()
    RefreshFBPLeft()
    SetFBPStatus("已移除：" id)
}

SwapFBPSelected(a, b) {
    global FBPSelected
    tmp := FBPSelected[a]
    FBPSelected[a] := FBPSelected[b]
    FBPSelected[b] := tmp
}

; ---- 确定 ----

OnFBPOk(*) {
    global FBPFlowKey, FBPComboKey, FBPSelected, FBPResult, FBPStatus

    ; 勾了没点同步也不能丢：先同步一次
    SyncFBPSelection()

    try {
        FlowEditor.SetRecipe(FBPFlowKey, FBPComboKey, FBPSelected)
    } catch as e {
        SetFBPStatus("保存失败：" e.Message)
        return
    }

    FBPResult := true
    CloseFlowBlockPicker()
}

; ---- 小工具 ----

SetFBPStatus(text) {
    global FBPStatus
    if (FBPStatus)
        FBPStatus.Text := text
}

HasFBPValue(arr, value) {
    for item in arr {
        if (item = value)
            return true
    }
    return false
}

