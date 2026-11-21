#Requires AutoHotkey v2.0

; 私有块维护窗口：本流程的私有块增删改 + 全局块只读
;
; 只做界面：写盘全部经 BlockEditor（它自己管只读拦截、引用反查、块缓存）。
; 正文不在这里编辑，交给外部编辑器；改完点「刷新」重读元数据与正文长度。

global BMWin := ""
global BMFlowKey := ""
global BMPrivateList := ""
global BMGlobalList := ""
global BMPrivateIds := []
global BMStatus := ""
global BMChanged := false
global BMBtnEdit := "", BMBtnDelete := "", BMBtnOpen := ""

global BMDlg := ""
global BMIdEdit := ""
global BMNameEdit := ""
global BMPurposeEdit := ""
global BMKindCombo := ""
global BMDlgHint := ""
global BMDlgOk := ""
global BMDlgMode := ""      ; "new" / "edit"
global BMDlgEditId := ""

; 打开块维护窗口；有改动返回 true
ShowBlockMaintainWindow(flowKey) {
    global BMWin, BMFlowKey, BMChanged, BMPrivateList, BMGlobalList, BMStatus

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
    BMWin.Show("w900 h620")
    WinWaitClose("ahk_id " BMWin.Hwnd)
    return BMChanged
}

BuildBMWindow(flowKey) {
    global BMWin, BMPrivateList, BMGlobalList, BMStatus, BMPrivateIds, FMWin, BMChanged, BMFlowKey

    flow := FlowLibrary.Get(flowKey)
    BMFlowKey := flowKey

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

    d.AddText("xm ym w860 h18", "私有块：" flow.Name "（只属于这套流程）")
    BMPrivateList := d.AddListView("xm y+2 w860 h240 -Multi", ["名称", "说明", "分类", "正文"])
    BMPrivateList.ModifyCol(1, 180)
    BMPrivateList.ModifyCol(2, 330)
    BMPrivateList.ModifyCol(3, 100)
    BMPrivateList.ModifyCol(4, 80)
    ApplyDialogListStyle(BMPrivateList)
    BMPrivateList.OnEvent("ItemSelect", UpdateBMButtons)

    btnNew := d.AddButton("xm y+6 w90 h26", "新增")
    btnNew.OnEvent("Click", OnBMNew)
    global BMBtnEdit, BMBtnDelete, BMBtnOpen
    BMBtnEdit := d.AddButton("x+8 yp w90 h26", "编辑")
    BMBtnEdit.OnEvent("Click", OnBMEdit)
    BMBtnDelete := d.AddButton("x+8 yp w90 h26", "删除")
    BMBtnDelete.OnEvent("Click", OnBMDelete)
    BMBtnOpen := d.AddButton("x+8 yp w90 h26", "打开正文")
    BMBtnOpen.OnEvent("Click", OnBMOpenBody)

    d.AddText("xm y+12 w860 h18", "全局块（只读）")
    BMGlobalList := d.AddListView("xm y+2 w860 h200 -Multi", ["名称", "说明", "分类", "归属"])
    BMGlobalList.ModifyCol(1, 180)
    BMGlobalList.ModifyCol(2, 330)
    BMGlobalList.ModifyCol(3, 100)
    BMGlobalList.ModifyCol(4, 80)
    ApplyDialogListStyle(BMGlobalList)

    d.AddText("xm y+4 w860 h18 cGray", "只读 · 要改就新建流程，它会复制一份私有副本")

    BMStatus := d.AddText("x12 y568 w560 h20 cGray", "")
    btnRefresh := d.AddButton("x688 y568 w90 h26", "刷新")
    btnRefresh.OnEvent("Click", OnBMRefresh)
    btnClose := d.AddButton("x+8 yp w90 h26", "关闭")
    btnClose.OnEvent("Click", CloseBMWindow)

    RefreshBMPrivate()
    RefreshBMGlobal()
}

CloseBMWindow(*) {
    global BMWin, BMPrivateList, BMGlobalList, BMStatus, BMPrivateIds
    global BMDlg, BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo
    global BMDlgHint, BMDlgOk, BMDlgMode, BMDlgEditId

    if (GuiAlive(BMWin)) {
        try BMWin.Destroy()
    }
    BMWin := ""
    BMPrivateList := ""
    BMGlobalList := ""
    BMStatus := ""
    BMPrivateIds := []

    if (GuiAlive(BMDlg)) {
        try BMDlg.Destroy()
    }
    BMDlg := ""
    BMIdEdit := ""
    BMNameEdit := ""
    BMPurposeEdit := ""
    BMKindCombo := ""
    BMDlgHint := ""
    BMDlgOk := ""
    BMDlgMode := ""
    BMDlgEditId := ""
}

; ---- 列表 ----

RefreshBMPrivate(preferId := "") {
    global BMPrivateList, BMPrivateIds, BMFlowKey

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
        BMPrivateList.Modify(selectRow, "Select Focus")
    }
    UpdateBMButtons()
}

RefreshBMGlobal() {
    global BMGlobalList

    BMGlobalList.Delete()
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
    }
}

UpdateBMButtons(*) {
    global BMPrivateList, BMPrivateIds, BMStatus
    ; 按钮是局部变量，这里只按选中状态改可用性
    row := BMPrivateList.GetNext(0)
    has := (row > 0 && row <= BMPrivateIds.Length)

    ; 通过 Gui 的控件集合按标题找按钮太重；用全局登记更直接
    global BMBtnEdit, BMBtnDelete, BMBtnOpen
    if (IsSet(BMBtnEdit) && BMBtnEdit)
        BMBtnEdit.Enabled := has
    if (IsSet(BMBtnDelete) && BMBtnDelete)
        BMBtnDelete.Enabled := has
    if (IsSet(BMBtnOpen) && BMBtnOpen)
        BMBtnOpen.Enabled := has
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
    global BMPrivateList, BMPrivateIds, BMChanged, BMFlowKey

    row := BMPrivateList.GetNext(0)
    if (row = 0 || row > BMPrivateIds.Length)
        return
    id := BMPrivateIds[row]
    name := BMPrivateList.GetText(row, 1)

    if (MsgBox("确定删除块「" name "」吗？`n`n目录：" id "`n此操作不可撤销。",
            "删除块", "Icon! YesNo Default2") != "Yes")
        return

    ; 删之前记下相邻项
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
    SetBMStatus("已删除：" name)
}

OnBMOpenBody(*) {
    global BMPrivateList, BMPrivateIds, BMFlowKey
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

; ---- 新增 / 编辑弹窗 ----

ShowBMDialog(mode, blockId := "") {
    global BMWin, BMDlg, BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo
    global BMDlgHint, BMDlgOk, BMDlgMode, BMDlgEditId, BMFlowKey, BMChanged

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
    BMIdEdit := d.AddEdit("x+8 yp w300 h24")
    d.AddText("xm y+8 w60 h20", "名称")
    BMNameEdit := d.AddEdit("x+8 yp w300 h24")
    d.AddText("xm y+8 w60 h20", "说明")
    BMPurposeEdit := d.AddEdit("x+8 yp w300 h40 +Multi")
    d.AddText("xm y+8 w60 h20", "分类")
    BMKindCombo := d.AddComboBox("x+8 yp w300 h24")
    BMKindCombo.Add(BlockEditor.KindValues)
    BMKindCombo.Value := 1

    BMDlgHint := d.AddText("xm y+8 w372 h34 cRed", "")
    BMDlgOk := d.AddButton("x212 y+6 w80 h26 Default", "确定")
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
        BMKindCombo.Value := blk.Kind
    }

    BMIdEdit.OnEvent("Change", (*) => UpdateBMDialogState())
    BMNameEdit.OnEvent("Change", (*) => UpdateBMDialogState())
    BMPurposeEdit.OnEvent("Change", (*) => UpdateBMDialogState())

    UpdateBMDialogState()
    d.Show("w400 h300")
}

CloseBMDialog(*) {
    global BMDlg, BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo
    global BMDlgHint, BMDlgOk, BMDlgMode, BMDlgEditId

    if (GuiAlive(BMDlg)) {
        try BMDlg.Destroy()
    }
    BMDlg := ""
    BMIdEdit := ""
    BMNameEdit := ""
    BMPurposeEdit := ""
    BMKindCombo := ""
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
    global BMIdEdit, BMNameEdit, BMPurposeEdit, BMKindCombo, BMDlgHint
    global BMDlgMode, BMDlgEditId, BMFlowKey, BMChanged

    id := Trim(BMIdEdit.Value)
    name := Trim(BMNameEdit.Value)
    purpose := Trim(BMPurposeEdit.Value)
    kind := BMKindCombo.Text

    try {
        if (BMDlgMode = "new")
            BlockEditor.Create(BMFlowKey, id, name, purpose, kind)
        else
            BlockEditor.UpdateMeta(BMFlowKey, id, name, purpose, kind)
    } catch as e {
        BMDlgHint.Text := e.Message
        return
    }

    BMChanged := true
    mode := BMDlgMode          ; CloseBMDialog 会把 BMDlgMode 清空，先记下来
    CloseBMDialog()

    if (mode = "new") {
        RefreshBMPrivate(id)
        SetBMStatus("已新增：" name)
        OpenBMBlockBody(id)
    } else {
        RefreshBMPrivate(id)
        SetBMStatus("已保存：" name)
    }
}

