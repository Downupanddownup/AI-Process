#Requires AutoHotkey v2.0

; 私有块维护窗口：本流程的私有块增删改 + 全局块只读
;
; 编辑只发生在一个地方：新增 / 编辑弹窗（元数据 + 正文一起写）。
; 右侧面板只做预览，全部只读——不拆成"在这里改一半、在那里改一半"。
;
; 写盘全部经 BlockEditor（它自己管只读拦截、引用反查、块缓存）。

global BMWin := ""
global BMFlowKey := ""
global BMPrivateList := ""
global BMGlobalList := ""
global BMPrivateIds := []
global BMGlobalIds := []
global BMStatus := ""
global BMChanged := false

global BMBtnEdit := "", BMBtnDelete := "", BMBtnOpen := ""

global BMNameText := ""
global BMKindText := ""
global BMScopeText := ""
global BMPurposeView := ""
global BMBodyView := ""

global BMSelectedKind := ""
global BMSelectedId := ""
global BMSuppress := false

global BMDlg := ""
global BMIdEdit := ""
global BMNameEdit := ""
global BMPurposeEdit := ""
global BMKindCombo := ""
global BMBodyEdit := ""
global BMDlgHint := ""
global BMDlgOk := ""
global BMDlgMode := ""
global BMDlgEditId := ""

; 打开块维护窗口；有改动返回 true
ShowBlockMaintainWindow(flowKey) {
    global BMWin, BMFlowKey, BMChanged

    if (BMWin) {
        if (GuiAlive(BMWin)) {
            BMWin.Show()
            WinActivate("ahk_id " BMWin.Hwnd)
            return false
        }
        CloseBMWindow()
    }

    BMFlowKey := flowKey
    BMChanged := false
    BuildBMWindow(flowKey)
    BMWin.Show("w1180 h620")
    WinWaitClose("ahk_id " BMWin.Hwnd)
    return BMChanged
}

BuildBMWindow(flowKey) {
    global BMWin, BMPrivateList, BMGlobalList, BMStatus, BMPrivateIds, BMGlobalIds
    global FMWin, BMChanged, BMFlowKey
    global BMBtnEdit, BMBtnDelete, BMBtnOpen
    global BMNameText, BMKindText, BMScopeText, BMPurposeView, BMBodyView
    global BMSelectedKind, BMSelectedId

    flow := FlowLibrary.Get(flowKey)
    BMFlowKey := flowKey
    BMSelectedKind := ""
    BMSelectedId := ""

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(FMWin))
        opts .= " +Owner" FMWin.Hwnd

    d := Gui(opts, "私有块维护")
    BMWin := d
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseBMWindow)
    d.OnEvent("Escape", CloseBMWindow)

    ; ---- 左：两个列表 ----
    d.AddText("xm ym w700 h18", "私有块：" flow.Name "（只属于这套流程）")
    BMPrivateList := d.AddListView("xm y+2 w700 h240 -Multi", ["名称", "说明", "分类", "正文"])
    BMPrivateList.ModifyCol(1, 160)
    BMPrivateList.ModifyCol(2, 300)
    BMPrivateList.ModifyCol(3, 110)
    BMPrivateList.ModifyCol(4, 70)
    ApplyDialogListStyle(BMPrivateList)
    BMPrivateList.OnEvent("ItemSelect", (*) => OnBMSelect("private"))

    btnNew := d.AddButton("xm y+6 w90 h26", "新增")
    btnNew.OnEvent("Click", OnBMNew)
    BMBtnEdit := d.AddButton("x+8 yp w90 h26", "编辑")
    BMBtnEdit.OnEvent("Click", OnBMEdit)
    BMBtnDelete := d.AddButton("x+8 yp w90 h26", "删除")
    BMBtnDelete.OnEvent("Click", OnBMDelete)
    BMBtnOpen := d.AddButton("x+8 yp w90 h26", "打开正文")
    BMBtnOpen.OnEvent("Click", OnBMOpenBody)

    d.AddText("xm y+12 w700 h18", "全局块（只读）")
    BMGlobalList := d.AddListView("xm y+2 w700 h200 -Multi", ["名称", "说明", "分类", "归属"])
    BMGlobalList.ModifyCol(1, 160)
    BMGlobalList.ModifyCol(2, 300)
    BMGlobalList.ModifyCol(3, 110)
    BMGlobalList.ModifyCol(4, 70)
    ApplyDialogListStyle(BMGlobalList)
    BMGlobalList.OnEvent("ItemSelect", (*) => OnBMSelect("global"))

    d.AddText("xm y+4 w700 h18 cGray", "只读 · 要改就新建流程，它会复制一份私有副本")

    ; ---- 右：预览（全部只读） ----
    d.AddText("x724 y12 w444 h18", "预览（只读）")

    d.AddText("x724 y36 w50 h20", "名称")
    BMNameText := d.AddText("x+8 yp w386 h20", "")
    d.AddText("x724 y60 w50 h20", "分类")
    BMKindText := d.AddText("x+8 yp w160 h20", "")
    d.AddText("x+16 yp w50 h20", "归属")
    BMScopeText := d.AddText("x+8 yp w120 h20", "")

    d.AddText("x724 y88 w444 h18", "说明")
    BMPurposeView := d.AddEdit("x724 y+2 w444 h60 +ReadOnly +Multi +VScroll", "")

    d.AddText("x724 y176 w444 h18", "正文")
    BMBodyView := d.AddEdit("x724 y+2 w444 h340 +ReadOnly +Multi +VScroll", "")

    ; ---- 底部 ----
    BMStatus := d.AddText("x12 y568 w700 h20 cGray", "")
    btnRefresh := d.AddButton("x976 y568 w90 h26", "刷新")
    btnRefresh.OnEvent("Click", OnBMRefresh)
    btnClose := d.AddButton("x1074 y568 w90 h26", "关闭")
    btnClose.OnEvent("Click", CloseBMWindow)

    RefreshBMPrivate()
    RefreshBMGlobal()
    if (BMPrivateIds.Length > 0)
        LoadBMDetail("private", BMPrivateIds[1])
}

CloseBMWindow(*) {
    global BMWin, BMPrivateList, BMGlobalList, BMStatus, BMPrivateIds, BMGlobalIds
    global BMDlg, BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo, BMBodyEdit
    global BMDlgHint, BMDlgOk, BMDlgMode, BMDlgEditId
    global BMNameText, BMKindText, BMScopeText, BMPurposeView, BMBodyView
    global BMSelectedKind, BMSelectedId

    if (GuiAlive(BMWin)) {
        try BMWin.Destroy()
    }
    BMWin := ""
    BMPrivateList := ""
    BMGlobalList := ""
    BMStatus := ""
    BMPrivateIds := []
    BMGlobalIds := []

    if (GuiAlive(BMDlg)) {
        try BMDlg.Destroy()
    }
    BMDlg := ""
    BMIdEdit := ""
    BMNameEdit := ""
    BMPurposeEdit := ""
    BMKindCombo := ""
    BMBodyEdit := ""
    BMDlgHint := ""
    BMDlgOk := ""
    BMDlgMode := ""
    BMDlgEditId := ""

    BMNameText := ""
    BMKindText := ""
    BMScopeText := ""
    BMPurposeView := ""
    BMBodyView := ""
    BMSelectedKind := ""
    BMSelectedId := ""
}

; ---- 列表 ----

RefreshBMPrivate(preferId := "") {
    global BMPrivateList, BMPrivateIds, BMFlowKey, BMSuppress

    flow := FlowLibrary.Get(BMFlowKey)
    BMPrivateList.Delete()
    BMPrivateIds := []
    selectRow := 0

    for id in flow.ListBlockIds() {
        name := id
        kind := "?"
        purpose := ""
        try {
            blk := BlockLibrary.Get(id, flow.BlocksDir)
            name := blk.Name != "" ? blk.Name : id
            kind := blk.Kind
            purpose := blk.Purpose
        }

        bodyPath := flow.BlocksDir "\" id "\body.txt"
        bodyState := (FileExist(bodyPath) && FileGetSize(bodyPath) > 0) ? "已写" : "未写正文"

        BMPrivateList.Add(, name, purpose, kind, bodyState)
        BMPrivateIds.Push(id)
        if (preferId != "" && id = preferId && selectRow = 0)
            selectRow := A_Index
    }

    if (BMPrivateIds.Length > 0) {
        if (selectRow = 0)
            selectRow := 1
        BMSuppress := true
        BMPrivateList.Modify(selectRow, "Select Focus")
        BMSuppress := false
    }
    UpdateBMButtons()
}

RefreshBMGlobal() {
    global BMGlobalList, BMGlobalIds

    BMGlobalList.Delete()
    BMGlobalIds := []
    globalDir := BlockLibrary.DataRoot "\blocks"
    for id in BlockLibrary.ListIds(globalDir) {
        name := id
        kind := "?"
        purpose := ""
        try {
            blk := BlockLibrary.Get(id, "")
            name := blk.Name != "" ? blk.Name : id
            kind := blk.Kind
            purpose := blk.Purpose
        }
        BMGlobalList.Add(, name, purpose, kind, "公共")
        BMGlobalIds.Push(id)
    }
}

UpdateBMButtons(*) {
    global BMPrivateList, BMPrivateIds, BMBtnEdit, BMBtnDelete, BMBtnOpen

    row := BMPrivateList.GetNext(0)
    has := (row > 0 && row <= BMPrivateIds.Length)
    if (BMBtnEdit)
        BMBtnEdit.Enabled := has
    if (BMBtnDelete)
        BMBtnDelete.Enabled := has
    if (BMBtnOpen)
        BMBtnOpen.Enabled := has
}

; ---- 选中 → 右侧预览 ----

OnBMSelect(kind) {
    global BMPrivateList, BMPrivateIds, BMGlobalList, BMGlobalIds, BMSuppress

    if (BMSuppress)
        return

    id := ""
    if (kind = "private") {
        row := BMPrivateList.GetNext(0)
        if (row > 0 && row <= BMPrivateIds.Length)
            id := BMPrivateIds[row]
    } else {
        row := BMGlobalList.GetNext(0)
        if (row > 0 && row <= BMGlobalIds.Length)
            id := BMGlobalIds[row]
    }

    if (id = "")
        return
    LoadBMDetail(kind, id)
}

LoadBMDetail(kind, id) {
    global BMSelectedKind, BMSelectedId
    global BMNameText, BMKindText, BMScopeText, BMPurposeView, BMBodyView, BMFlowKey

    BMSelectedKind := kind
    BMSelectedId := id

    if (id = "") {
        BMNameText.Text := ""
        BMKindText.Text := ""
        BMScopeText.Text := ""
        BMPurposeView.Value := ""
        BMBodyView.Value := ""
        return
    }

    flow := FlowLibrary.Get(BMFlowKey)
    if (kind = "private")
        blk := BlockLibrary.Get(id, flow.BlocksDir)
    else
        blk := BlockLibrary.Get(id, "")

    BMNameText.Text := blk.Name != "" ? blk.Name : id
    BMKindText.Text := blk.Kind
    BMScopeText.Text := (kind = "private") ? "私有" : "公共"
    BMPurposeView.Value := blk.Purpose
    BMBodyView.Value := blk.Body
}

; ---- 三个动作 ----

OnBMNew(*) {
    ShowBMDialog("new")
}

OnBMEdit(*) {
    global BMPrivateList, BMPrivateIds
    row := BMPrivateList.GetNext(0)
    if (row = 0 || row > BMPrivateIds.Length)
        return
    ShowBMDialog("edit", BMPrivateIds[row])
}

OnBMDelete(*) {
    global BMPrivateList, BMPrivateIds, BMChanged, BMFlowKey, BMPrivateList

    row := BMPrivateList.GetNext(0)
    if (row = 0 || row > BMPrivateIds.Length)
        return
    id := BMPrivateIds[row]
    name := BMPrivateList.GetText(row, 1)

    if (MsgBox("确定删除块「" name "」吗？`n`n目录：" id "`n此操作不可撤销。",
            "删除块", "Icon! YesNo Default2") != "Yes")
        return

    neighbor := ""
    if (row < BMPrivateIds.Length)
        neighbor := BMPrivateIds[row + 1]
    else if (row > 1)
        neighbor := BMPrivateIds[row - 1]

    try {
        BlockEditor.Delete(BMFlowKey, id)
    } catch as e {
        SetBMStatus(e.Message)
        return
    }

    BMChanged := true
    RefreshBMPrivate(neighbor)
    LoadBMDetail("private", neighbor)
    SetBMStatus("已删除：" name)
}

OnBMOpenBody(*) {
    global BMPrivateList, BMPrivateIds
    row := BMPrivateList.GetNext(0)
    if (row = 0 || row > BMPrivateIds.Length)
        return
    OpenBMBlockBody(BMPrivateIds[row])
}

OnBMRefresh(*) {
    global BMPrivateList, BMPrivateIds
    row := BMPrivateList.GetNext(0)
    keep := (row > 0 && row <= BMPrivateIds.Length) ? BMPrivateIds[row] : ""
    RefreshBMPrivate(keep)
    RefreshBMGlobal()
    LoadBMDetail("private", keep)
    SetBMStatus("已刷新")
}

OpenBMBlockBody(blockId) {
    global BMFlowKey

    if (GetCurrentToolPath() = "") {
        SetBMStatus("未配置文件处理工具，请到「托盘 → 配置」里设置")
        return
    }
    flow := FlowLibrary.Get(BMFlowKey)
    EditorOpener.Open(flow.BlocksDir "\" blockId "\body.txt")
}

SetBMStatus(text) {
    global BMStatus
    if (BMStatus)
        BMStatus.Text := text
}

; ---- 新增 / 编辑弹窗（唯一编辑入口：元数据 + 正文） ----

ShowBMDialog(mode, blockId := "") {
    global BMWin, BMDlg, BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo, BMBodyEdit
    global BMDlgHint, BMDlgOk, BMDlgMode, BMDlgEditId, BMFlowKey

    if (GuiAlive(BMDlg)) {
        BMDlg.Show()
        WinActivate("ahk_id " BMDlg.Hwnd)
        return
    }

    BMDlgMode := mode
    BMDlgEditId := blockId

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(BMWin))
        opts .= " +Owner" BMWin.Hwnd

    d := Gui(opts, mode = "new" ? "新增私有块" : "编辑私有块")
    BMDlg := d
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseBMDialog)
    d.OnEvent("Escape", CloseBMDialog)

    d.AddText("xm ym w60 h20", "标识")
    BMIdEdit := d.AddEdit("x+8 yp w536 h24")
    d.AddText("xm y+8 w60 h20", "名称")
    BMNameEdit := d.AddEdit("x+8 yp w536 h24")
    d.AddText("xm y+8 w60 h20", "说明")
    BMPurposeEdit := d.AddEdit("x+8 y+2 w536 h60 +Multi +VScroll")

    d.AddText("xm y+8 w60 h20", "分类")
    ; h 是下拉展开高度，不是控件高度
    BMKindCombo := d.AddComboBox("x+8 yp w300 h200")
    BMKindCombo.Add(BlockEditor.KindValues)
    BMKindCombo.Value := 1

    d.AddText("xm y+8 w60 h20", "正文")
    BMBodyEdit := d.AddEdit("x+8 y+2 w536 h240 +Multi +VScroll")

    BMDlgHint := d.AddText("xm y+8 w600 h20 cRed", "")
    BMDlgOk := d.AddButton("x452 y+6 w80 h26 Default", "确定")
    BMDlgOk.OnEvent("Click", OnBMDialogOk)
    btnCancel := d.AddButton("x+8 yp w80 h26", "取消")
    btnCancel.OnEvent("Click", CloseBMDialog)

    if (mode = "edit") {
        flow := FlowLibrary.Get(BMFlowKey)
        blk := BlockLibrary.Get(blockId, flow.BlocksDir)
        BMIdEdit.Value := blockId
        BMIdEdit.Enabled := false
        BMNameEdit.Value := blk.Name
        BMPurposeEdit.Value := blk.Purpose
        SetBMKindValue(blk.Kind)
        BMBodyEdit.Value := blk.Body
    }

    BMIdEdit.OnEvent("Change", (*) => UpdateBMDialogState())
    BMNameEdit.OnEvent("Change", (*) => UpdateBMDialogState())
    BMPurposeEdit.OnEvent("Change", (*) => UpdateBMDialogState())

    UpdateBMDialogState()
    d.Show("w640 h560")
}

SetBMKindValue(kind) {
    global BMKindCombo
    for idx, value in BlockEditor.KindValues {
        if (value = kind) {
            BMKindCombo.Value := idx
            return
        }
    }
    BMKindCombo.Text := kind
}

CloseBMDialog(*) {
    global BMDlg, BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo, BMBodyEdit
    global BMDlgHint, BMDlgOk, BMDlgMode, BMDlgEditId

    if (GuiAlive(BMDlg)) {
        try BMDlg.Destroy()
    }
    BMDlg := ""
    BMIdEdit := ""
    BMNameEdit := ""
    BMPurposeEdit := ""
    BMKindCombo := ""
    BMBodyEdit := ""
    BMDlgHint := ""
    BMDlgOk := ""
    BMDlgMode := ""
    BMDlgEditId := ""
}

UpdateBMDialogState() {
    global BMIdEdit, BMNameEdit, BMPurposeEdit, BMDlgHint, BMDlgOk
    global BMDlgMode, BMDlgEditId, BMFlowKey

    msg := ""
    id := Trim(BMIdEdit.Value)
    if (BMDlgMode = "new") {
        err := BlockEditor.ValidateId(BMFlowKey, id)
        if (err != "")
            msg := err
    }
    if (msg = "" && Trim(BMNameEdit.Value) = "")
        msg := "请填块名称"
    if (msg = "" && Trim(BMPurposeEdit.Value) = "")
        msg := "请填块说明"

    BMDlgHint.Text := msg
    BMDlgOk.Enabled := (msg = "")
}

OnBMDialogOk(*) {
    global BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo, BMBodyEdit, BMDlgHint
    global BMDlgMode, BMFlowKey, BMChanged

    id := Trim(BMIdEdit.Value)
    name := Trim(BMNameEdit.Value)
    purpose := Trim(BMPurposeEdit.Value)
    kind := Trim(BMKindCombo.Text)
    body := BMBodyEdit.Value

    mode := BMDlgMode
    created := false

    try {
        if (mode = "new") {
            BlockEditor.Create(BMFlowKey, id, name, purpose, kind)
            created := true
        } else {
            BlockEditor.UpdateMeta(BMFlowKey, id, name, purpose, kind)
        }
        BlockEditor.UpdateBody(BMFlowKey, id, body)
    } catch as e {
        ; 新建失败：把刚建出来的半个块删掉，不留残骸
        if (created) {
            try BlockEditor.Delete(BMFlowKey, id)
        }
        BMDlgHint.Text := e.Message
        return
    }

    BMChanged := true
    CloseBMDialog()
    RefreshBMPrivate(id)
    LoadBMDetail("private", id)
    SetBMStatus(mode = "new" ? "已新增：" name : "已保存：" name)
    if (mode = "new" && Trim(body) = "")
        SetBMStatus("已新增：" name "（正文为空，记得补）")
}
