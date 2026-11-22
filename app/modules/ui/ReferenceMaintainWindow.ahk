#Requires AutoHotkey v2.0

; 参考文档维护窗口：三层列表（本流程私有 / 骨架私有 / 全局）+ 详情 + 增删改
;
; 可写性只由 flow.Readonly 决定：自定义流程私有可写，内置流程整窗只读。
; 骨架私有与全局永远只读，且骨架私有不可被流程引用——列表里标明，避免误以为能改。
;
; 写盘全部经 ReferenceEditor（它自己管只读拦截、引用反查、参考文档缓存）。

global RMWin := ""
global RMFlowKey := ""
global RMPrivateList := ""
global RMSkelList := ""
global RMGlobalList := ""
global RMPrivateIds := []
global RMSkelIds := []
global RMGlobalIds := []
global RMStatus := ""
global RMChanged := false

global RMBtnNew := "", RMBtnEdit := "", RMBtnDelete := "", RMBtnOpen := ""

global RMNameText := ""
global RMIdText := ""
global RMScopeText := ""
global RMPurposeView := ""
global RMBodyView := ""
global RMUsedText := ""

global RMSelectedKind := ""
global RMSelectedId := ""
global RMSuppress := false

global RMDlg := ""
global RMIdEdit := ""
global RMNameEdit := ""
global RMPurposeEdit := ""
global RMBodyEdit := ""
global RMDlgHint := ""
global RMDlgOk := ""
global RMDlgMode := ""
global RMDlgEditId := ""

; 打开参考文档维护窗口；有改动返回 true
ShowReferenceMaintainWindow(flowKey) {
    global RMWin, RMFlowKey, RMChanged

    if (RMWin) {
        if (GuiAlive(RMWin)) {
            RMWin.Show()
            WinActivate("ahk_id " RMWin.Hwnd)
            return false
        }
        CloseRMWindow()
    }

    RMFlowKey := flowKey
    RMChanged := false
    BuildRMWindow(flowKey)
    RMWin.Show("w1180 h620")
    WinWaitClose("ahk_id " RMWin.Hwnd)
    return RMChanged
}

BuildRMWindow(flowKey) {
    global RMWin, RMFlowKey, RMPrivateList, RMSkelList, RMGlobalList, RMStatus
    global RMPrivateIds, RMSkelIds, RMGlobalIds, RMSelectedKind, RMSelectedId
    global RMBtnNew, RMBtnEdit, RMBtnDelete, RMBtnOpen
    global RMNameText, RMIdText, RMScopeText, RMPurposeView, RMBodyView, RMUsedText
    global FMWin

    flow := FlowLibrary.Get(flowKey)
    RMFlowKey := flowKey
    RMSelectedKind := ""
    RMSelectedId := ""

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(FMWin))
        opts .= " +Owner" FMWin.Hwnd

    d := Gui(opts, "参考文档维护")
    RMWin := d
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseRMWindow)
    d.OnEvent("Escape", CloseRMWindow)

    ; ---- 左：三个列表 ----
    d.AddText("x12 y12 w700 h18", "本流程私有：" flow.Name (flow.Readonly ? "（内置流程，只读）" : "（可写）"))
    RMPrivateList := d.AddListView("x12 y32 w700 h150 -Multi", ["名称", "标识", "说明", "正文"])
    RMPrivateList.ModifyCol(1, 140)
    RMPrivateList.ModifyCol(2, 160)
    RMPrivateList.ModifyCol(3, 300)
    RMPrivateList.ModifyCol(4, 80)
    ApplyDialogListStyle(RMPrivateList)
    ; 行序必须恒等于填充顺序（按行号取 RMPrivateIds）：点表头内建排序会脱钩
    DisableListHeaderSort(RMPrivateList)
    RMPrivateList.OnEvent("ItemSelect", (*) => OnRMSelect("flow"))

    d.AddText("x12 y186 w700 h18", "")
    RMBtnNew := d.AddButton("x12 y190 w90 h26", "新增")
    RMBtnNew.OnEvent("Click", OnRMNew)
    RMBtnEdit := d.AddButton("x110 y190 w90 h26", "编辑")
    RMBtnEdit.OnEvent("Click", OnRMEdit)
    RMBtnDelete := d.AddButton("x208 y190 w90 h26", "删除")
    RMBtnDelete.OnEvent("Click", OnRMDelete)
    RMBtnOpen := d.AddButton("x306 y190 w90 h26", "打开正文")
    RMBtnOpen.OnEvent("Click", OnRMOpenBody)

    d.AddText("x12 y226 w700 h18", "骨架私有（只读 · 不可引用）")
    RMSkelList := d.AddListView("x12 y246 w700 h80 -Multi", ["名称", "标识", "说明"])
    RMSkelList.ModifyCol(1, 140)
    RMSkelList.ModifyCol(2, 160)
    RMSkelList.ModifyCol(3, 400)
    ApplyDialogListStyle(RMSkelList)
    DisableListHeaderSort(RMSkelList)
    RMSkelList.OnEvent("ItemSelect", (*) => OnRMSelect("skeleton"))

    d.AddText("x12 y332 w700 h18", "全局（只读，任何流程可引用）")
    RMGlobalList := d.AddListView("x12 y352 w700 h150 -Multi", ["名称", "标识", "说明"])
    RMGlobalList.ModifyCol(1, 140)
    RMGlobalList.ModifyCol(2, 160)
    RMGlobalList.ModifyCol(3, 400)
    ApplyDialogListStyle(RMGlobalList)
    DisableListHeaderSort(RMGlobalList)
    RMGlobalList.OnEvent("ItemSelect", (*) => OnRMSelect("global"))

    d.AddText("x12 y510 w700 h18 cGray", "只读的层改不了：要改全局，就新建流程并在它的 references 下放一份私有副本")

    ; ---- 右：详情 ----
    d.AddText("x724 y12 w444 h18", "详情")

    d.AddText("x724 y36 w50 h20", "名称")
    RMNameText := d.AddText("x778 y36 w390 h20", "")

    ; 标识只展示：不用只读 Edit——那种控件值改不了，但边框与光标跟输入框一样，看着像能改
    d.AddText("x724 y62 w50 h20", "标识")
    RMIdText := d.AddText("x778 y62 w390 h20", "")

    d.AddText("x724 y92 w50 h20", "归属")
    RMScopeText := d.AddText("x778 y92 w390 h20", "")

    d.AddText("x724 y118 w444 h18", "用途")
    RMPurposeView := d.AddEdit("x724 y140 w444 h50 +ReadOnly +Multi +VScroll", "")

    d.AddText("x724 y196 w444 h18", "正文（只读预览 · 用「打开正文」改）")
    RMBodyView := d.AddEdit("x724 y216 w444 h240 +ReadOnly +Multi +VScroll", "")

    ; 高度按 3 行给：一个文档被两个块引用时不再被切
    d.AddText("x724 y464 w444 h18", "被谁引用（本流程的块）")
    RMUsedText := d.AddEdit("x724 y484 w444 h56 +ReadOnly +Multi +VScroll", "")

    ; ---- 底部 ----
    RMStatus := d.AddText("x12 y576 w900 h20 cGray", "")
    btnRefresh := d.AddButton("x976 y572 w90 h26", "刷新")
    btnRefresh.OnEvent("Click", OnRMRefresh)
    btnClose := d.AddButton("x1074 y572 w90 h26", "关闭")
    btnClose.OnEvent("Click", CloseRMWindow)

    RefreshRMPrivate()
    RefreshRMSkeleton()
    RefreshRMGlobal()
    UpdateRMButtons()

    if (RMPrivateIds.Length > 0)
        LoadRMDetail("flow", RMPrivateIds[1])
}

CloseRMWindow(*) {
    global RMWin, RMPrivateList, RMSkelList, RMGlobalList, RMStatus
    global RMPrivateIds, RMSkelIds, RMGlobalIds, RMSelectedKind, RMSelectedId
    global RMDlg, RMIdEdit, RMNameEdit, RMPurposeEdit, RMBodyEdit
    global RMDlgHint, RMDlgOk, RMDlgMode, RMDlgEditId
    global RMNameText, RMIdText, RMScopeText, RMPurposeView, RMBodyView, RMUsedText

    if (GuiAlive(RMWin)) {
        try RMWin.Destroy()
    }
    RMWin := ""
    RMPrivateList := ""
    RMSkelList := ""
    RMGlobalList := ""
    RMStatus := ""
    RMPrivateIds := []
    RMSkelIds := []
    RMGlobalIds := []

    if (GuiAlive(RMDlg)) {
        try RMDlg.Destroy()
    }
    RMDlg := ""
    RMIdEdit := ""
    RMNameEdit := ""
    RMPurposeEdit := ""
    RMBodyEdit := ""
    RMDlgHint := ""
    RMDlgOk := ""
    RMDlgMode := ""
    RMDlgEditId := ""

    RMNameText := ""
    RMIdText := ""
    RMScopeText := ""
    RMPurposeView := ""
    RMBodyView := ""
    RMUsedText := ""
    RMSelectedKind := ""
    RMSelectedId := ""
}

; ---- 列表 ----

RefreshRMPrivate(preferId := "") {
    global RMPrivateList, RMPrivateIds, RMFlowKey, RMSuppress

    flow := FlowLibrary.Get(RMFlowKey)
    RMPrivateList.Delete()
    RMPrivateIds := []
    selectRow := 0

    for doc in ReferenceLibrary.ListFlow(RMFlowKey) {
        bodyState := (FileExist(doc.BodyPath) && FileGetSize(doc.BodyPath) > 0) ? "已写" : "未写正文"
        RMPrivateList.Add(, doc.Name != "" ? doc.Name : doc.Id, doc.Id, doc.Purpose, bodyState)
        RMPrivateIds.Push(doc.Id)
        if (preferId != "" && doc.Id = preferId && selectRow = 0)
            selectRow := A_Index
    }

    if (RMPrivateIds.Length > 0) {
        if (selectRow = 0)
            selectRow := 1
        RMSuppress := true
        RMPrivateList.Modify(selectRow, "Select Focus")
        RMSuppress := false
    }
    UpdateRMButtons()
}

RefreshRMSkeleton() {
    global RMSkelList, RMSkelIds

    RMSkelList.Delete()
    RMSkelIds := []
    for doc in ReferenceLibrary.ListSkeleton() {
        RMSkelList.Add(, doc.Name != "" ? doc.Name : doc.Id, doc.Id, doc.Purpose)
        RMSkelIds.Push(doc.Id)
    }
}

RefreshRMGlobal() {
    global RMGlobalList, RMGlobalIds

    RMGlobalList.Delete()
    RMGlobalIds := []
    for doc in ReferenceLibrary.ListGlobal() {
        RMGlobalList.Add(, doc.Name != "" ? doc.Name : doc.Id, doc.Id, doc.Purpose)
        RMGlobalIds.Push(doc.Id)
    }
}

UpdateRMButtons(*) {
    global RMBtnNew, RMBtnEdit, RMBtnDelete, RMBtnOpen, RMPrivateList, RMPrivateIds, RMFlowKey

    flow := FlowLibrary.Get(RMFlowKey)
    writable := !flow.Readonly
    row := RMPrivateList.GetNext(0)
    has := (row > 0 && row <= RMPrivateIds.Length)

    if (RMBtnNew)
        RMBtnNew.Enabled := writable
    if (RMBtnEdit)
        RMBtnEdit.Enabled := writable && has
    if (RMBtnDelete)
        RMBtnDelete.Enabled := writable && has
    if (RMBtnOpen)
        RMBtnOpen.Enabled := writable && has
}

; ---- 选中 → 详情 ----

OnRMSelect(kind) {
    global RMPrivateList, RMPrivateIds, RMSkelList, RMSkelIds, RMGlobalList, RMGlobalIds, RMSuppress

    if (RMSuppress)
        return

    id := ""
    if (kind = "flow") {
        row := RMPrivateList.GetNext(0)
        if (row > 0 && row <= RMPrivateIds.Length)
            id := RMPrivateIds[row]
    } else if (kind = "skeleton") {
        row := RMSkelList.GetNext(0)
        if (row > 0 && row <= RMSkelIds.Length)
            id := RMSkelIds[row]
    } else {
        row := RMGlobalList.GetNext(0)
        if (row > 0 && row <= RMGlobalIds.Length)
            id := RMGlobalIds[row]
    }

    if (id = "")
        return
    LoadRMDetail(kind, id)
}

; 按层精确加载：不走 Get(id, flowKey) 的三层回退，否则同名时会显示错那一层
LoadRMDetail(kind, id) {
    global RMFlowKey, RMSelectedKind, RMSelectedId
    global RMNameText, RMIdText, RMScopeText, RMPurposeView, RMBodyView, RMUsedText

    RMSelectedKind := kind
    RMSelectedId := id

    doc := ""
    try {
        if (kind = "flow") {
            flow := FlowLibrary.Get(RMFlowKey)
            doc := ReferenceDoc.Load(flow.ReferencesDir "\" id, "flow", RMFlowKey)
        } else if (kind = "skeleton") {
            doc := ReferenceDoc.Load(ReferenceLibrary.DataRoot "\skeleton\references\" id, "skeleton")
        } else {
            doc := ReferenceDoc.Load(ReferenceLibrary.DataRoot "\references\" id, "global")
        }
    } catch as e {
        RMNameText.Text := "（读不出来）"
        RMIdText.Text := ""
        RMScopeText.Text := ""
        RMPurposeView.Value := ""
        RMBodyView.Value := ""
        RMUsedText.Value := ""
        SetRMStatus(e.Message)
        return
    }

    RMNameText.Text := doc.Name != "" ? doc.Name : id
    RMIdText.Text := id
    RMScopeText.Text := kind = "flow" ? "本流程私有" : (kind = "skeleton" ? "骨架私有（不可引用）" : "全局")
    RMPurposeView.Value := doc.Purpose

    body := ""
    if FileExist(doc.BodyPath)
        body := FileRead(doc.BodyPath, "UTF-8")
    RMBodyView.Value := body

    ; 只吐 ID 的地方给名称：块维护改了名，这里跟着变
    flow := FlowLibrary.Get(RMFlowKey)
    used := ReferenceEditor.UsedByBlocks(RMFlowKey, id)
    labels := []
    for blockId in used
        labels.Push(PromptLabels.Block(blockId, flow.BlocksDir))
    RMUsedText.Value := labels.Length > 0 ? PromptLabels.Join(labels) : "（无）"
}

; ---- 动作 ----

OnRMNew(*) {
    global RMFlowKey
    flow := FlowLibrary.Get(RMFlowKey)
    if (flow.Readonly) {
        SetRMStatus("内置流程只读，不能新增参考文档")
        return
    }
    ShowRMDialog("new")
}

OnRMEdit(*) {
    global RMPrivateList, RMPrivateIds
    row := RMPrivateList.GetNext(0)
    if (row = 0 || row > RMPrivateIds.Length)
        return
    ShowRMDialog("edit", RMPrivateIds[row])
}

OnRMDelete(*) {
    global RMPrivateList, RMPrivateIds, RMChanged, RMFlowKey, RMWin

    row := RMPrivateList.GetNext(0)
    if (row = 0 || row > RMPrivateIds.Length)
        return
    id := RMPrivateIds[row]
    name := RMPrivateList.GetText(row, 1)

    ; 先查引用：被引用时删不掉，别先问"确定删除吗"再报错（白问一次）。
    ; 领域层的 ReferenceEditor.Delete 仍自带同一道闸，那是数据完整性的兜底，不承担展示
    flow := FlowLibrary.Get(RMFlowKey)
    used := ReferenceEditor.UsedByBlocks(RMFlowKey, id)
    if (used.Length > 0) {
        labels := []
        for blockId in used
            labels.Push(PromptLabels.Block(blockId, flow.BlocksDir))
        ownerHwnd := GuiAlive(RMWin) ? RMWin.Hwnd : 0
        opts := "Icon!"
        if (ownerHwnd)
            opts .= " Owner" ownerHwnd
        MsgBox("仍被这些块引用，先把引用改掉再删：`n`n" PromptLabels.Join(labels), "不能删除", opts)
        SetRMStatus("不能删除：" name " 仍被引用")
        return
    }

    ownerHwnd := GuiAlive(RMWin) ? RMWin.Hwnd : 0
    opts := "Icon! YesNo Default2"
    if (ownerHwnd)
        opts .= " Owner" ownerHwnd

    if (MsgBox("确定删除参考文档「" name "」吗？`n`n目录：" id "`n此操作不可撤销。",
            "删除参考文档", opts) != "Yes")
        return

    neighbor := ""
    if (row < RMPrivateIds.Length)
        neighbor := RMPrivateIds[row + 1]
    else if (row > 1)
        neighbor := RMPrivateIds[row - 1]

    try {
        ReferenceEditor.Delete(RMFlowKey, id)
    } catch as e {
        ; 被引用时不能用状态行打发：确认过却什么都没发生，等于坏交互
        ownerHwnd := GuiAlive(RMWin) ? RMWin.Hwnd : 0
        opts := "Icon!"
        if (ownerHwnd)
            opts .= " Owner" ownerHwnd
        MsgBox(e.Message, "不能删除", opts)
        SetRMStatus(e.Message)
        return
    }

    RMChanged := true
    RefreshRMPrivate(neighbor)
    LoadRMDetail("flow", neighbor)
    SetRMStatus("已删除：" name)
}

OnRMOpenBody(*) {
    global RMPrivateList, RMPrivateIds, RMFlowKey

    row := RMPrivateList.GetNext(0)
    if (row = 0 || row > RMPrivateIds.Length)
        return

    if (GetCurrentToolPath() = "") {
        SetRMStatus("未配置文件处理工具，请到「托盘 → 配置」里设置")
        return
    }
    flow := FlowLibrary.Get(RMFlowKey)
    EditorOpener.Open(flow.ReferencesDir "\" RMPrivateIds[row] "\body.md")
}

OnRMRefresh(*) {
    global RMPrivateList, RMPrivateIds, RMChanged

    row := RMPrivateList.GetNext(0)
    keep := (row > 0 && row <= RMPrivateIds.Length) ? RMPrivateIds[row] : ""

    ; 正文可能刚被外部编辑器改过，先让缓存失效
    ReferenceLibrary.ClearCache()
    RefreshRMPrivate(keep)
    RefreshRMSkeleton()
    RefreshRMGlobal()
    LoadRMDetail("flow", keep)
    SetRMStatus("已刷新")
}

SetRMStatus(text) {
    global RMStatus
    if (RMStatus)
        RMStatus.Text := text
}

; ---- 新增 / 编辑弹窗（唯一编辑入口） ----

ShowRMDialog(mode, refId := "") {
    global RMWin, RMDlg, RMIdEdit, RMNameEdit, RMPurposeEdit, RMBodyEdit
    global RMDlgHint, RMDlgOk, RMDlgMode, RMDlgEditId, RMFlowKey

    if (GuiAlive(RMDlg)) {
        RMDlg.Show()
        WinActivate("ahk_id " RMDlg.Hwnd)
        return
    }

    RMDlgMode := mode
    RMDlgEditId := refId

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(RMWin))
        opts .= " +Owner" RMWin.Hwnd

    d := Gui(opts, mode = "new" ? "新增参考文档" : "编辑参考文档")
    RMDlg := d
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseRMDialog)
    d.OnEvent("Escape", CloseRMDialog)

    d.AddText("xm ym w60 h20", "标识")
    RMIdEdit := d.AddEdit("x+8 yp w536 h24")
    d.AddText("xm y+8 w60 h20", "名称")
    RMNameEdit := d.AddEdit("x+8 yp w536 h24")
    d.AddText("xm y+8 w60 h20", "用途")
    RMPurposeEdit := d.AddEdit("x+8 y+2 w536 h60 +Multi +VScroll")

    d.AddText("xm y+8 w60 h20", "正文")
    RMBodyEdit := d.AddEdit("x+8 y+2 w536 h300 +Multi +VScroll")

    RMDlgHint := d.AddText("xm y+8 w600 h20 cRed", "")
    RMDlgOk := d.AddButton("x452 y+6 w80 h26 Default", "确定")
    RMDlgOk.OnEvent("Click", OnRMDialogOk)
    btnCancel := d.AddButton("x+8 yp w80 h26", "取消")
    btnCancel.OnEvent("Click", CloseRMDialog)

    if (mode = "edit") {
        flow := FlowLibrary.Get(RMFlowKey)
        doc := ReferenceDoc.Load(flow.ReferencesDir "\" refId, "flow", RMFlowKey)
        RMIdEdit.Value := refId
        RMIdEdit.Enabled := false
        RMNameEdit.Value := doc.Name
        RMPurposeEdit.Value := doc.Purpose
        RMBodyEdit.Value := FileExist(doc.BodyPath) ? FileRead(doc.BodyPath, "UTF-8") : ""
    }

    RMIdEdit.OnEvent("Change", (*) => UpdateRMDialogState())
    RMNameEdit.OnEvent("Change", (*) => UpdateRMDialogState())
    RMPurposeEdit.OnEvent("Change", (*) => UpdateRMDialogState())

    UpdateRMDialogState()
    d.Show("w640 h600")
}

CloseRMDialog(*) {
    global RMDlg, RMIdEdit, RMNameEdit, RMPurposeEdit, RMBodyEdit
    global RMDlgHint, RMDlgOk, RMDlgMode, RMDlgEditId

    if (GuiAlive(RMDlg)) {
        try RMDlg.Destroy()
    }
    RMDlg := ""
    RMIdEdit := ""
    RMNameEdit := ""
    RMPurposeEdit := ""
    RMBodyEdit := ""
    RMDlgHint := ""
    RMDlgOk := ""
    RMDlgMode := ""
    RMDlgEditId := ""
}

UpdateRMDialogState() {
    global RMIdEdit, RMNameEdit, RMPurposeEdit, RMDlgHint, RMDlgOk, RMDlgMode, RMFlowKey

    msg := ""
    if (msg = "" && RMDlgMode = "new") {
        err := ReferenceEditor.ValidateId(RMFlowKey, Trim(RMIdEdit.Value))
        if (err != "")
            msg := err
    }
    if (msg = "" && Trim(RMNameEdit.Value) = "")
        msg := "请填参考文档名称"
    if (msg = "" && Trim(RMPurposeEdit.Value) = "")
        msg := "请填用途"

    RMDlgHint.Text := msg
    RMDlgOk.Enabled := (msg = "")
}

OnRMDialogOk(*) {
    global RMIdEdit, RMNameEdit, RMPurposeEdit, RMBodyEdit, RMDlgHint
    global RMDlgMode, RMDlgEditId, RMFlowKey, RMChanged

    id := Trim(RMIdEdit.Value)
    name := Trim(RMNameEdit.Value)
    purpose := Trim(RMPurposeEdit.Value)
    body := RMBodyEdit.Value

    mode := RMDlgMode
    created := false

    try {
        if (mode = "new") {
            ReferenceEditor.Create(RMFlowKey, id, name, purpose)
            created := true
        } else {
            ReferenceEditor.UpdateMeta(RMFlowKey, id, name, purpose)
        }
        ReferenceEditor.UpdateBody(RMFlowKey, id, body)
    } catch as e {
        ; 新建失败：把刚建出来的半个目录删掉，不留残骸
        if (created) {
            try ReferenceEditor.Delete(RMFlowKey, id)
        }
        RMDlgHint.Text := e.Message
        return
    }

    RMChanged := true
    CloseRMDialog()
    RefreshRMPrivate(id)
    LoadRMDetail("flow", id)
    SetRMStatus(mode = "new" ? "已新增：" name : "已保存：" name)
    if (mode = "new" && Trim(body) = "")
        SetRMStatus("已新增：" name "（正文为空，记得补）")
}
