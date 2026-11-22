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
global BMIdText := ""
global BMKindText := ""
global BMScopeText := ""
global BMPurposeView := ""
global BMBodyView := ""
global BMRefText := ""

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

global BMRefDlg := ""
global BMRefList := ""
global BMRefIds := []

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
    global BMNameText, BMIdText, BMKindText, BMScopeText, BMPurposeView, BMBodyView, BMRefText
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
    BMPrivateList := d.AddListView("xm y+2 w700 h240 -Multi", ["名称", "标识", "说明", "分类", "正文"])
    BMPrivateList.ModifyCol(1, 140)
    BMPrivateList.ModifyCol(2, 160)
    BMPrivateList.ModifyCol(3, 220)
    BMPrivateList.ModifyCol(4, 90)
    BMPrivateList.ModifyCol(5, 70)
    ApplyDialogListStyle(BMPrivateList)
    ; 行序必须恒等于填充顺序（按行号取 BMPrivateIds）：点表头内建排序会脱钩
    DisableListHeaderSort(BMPrivateList)
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
    BMGlobalList := d.AddListView("xm y+2 w700 h200 -Multi", ["名称", "标识", "说明", "分类", "归属"])
    BMGlobalList.ModifyCol(1, 140)
    BMGlobalList.ModifyCol(2, 160)
    BMGlobalList.ModifyCol(3, 220)
    BMGlobalList.ModifyCol(4, 90)
    BMGlobalList.ModifyCol(5, 70)
    ApplyDialogListStyle(BMGlobalList)
    DisableListHeaderSort(BMGlobalList)
    BMGlobalList.OnEvent("ItemSelect", (*) => OnBMSelect("global"))

    d.AddText("xm y+4 w700 h18 cGray", "只读 · 要改就新建流程，它会复制一份私有副本")

    ; ---- 右：预览（全部只读） ----
    d.AddText("x724 y12 w444 h18", "预览（只读）")

    d.AddText("x724 y36 w50 h20", "名称")
    BMNameText := d.AddText("x+8 yp w386 h20", "")

    ; 标识用只读 Edit 而不是 Text：Text 选不中、复制不了，而"拿 id 去目录里找人"正是它的用途
    d.AddText("x724 y62 w50 h20", "标识")
    BMIdText := d.AddEdit("x+8 yp w386 h22 +ReadOnly", "")

    d.AddText("x724 y92 w50 h20", "分类")
    BMKindText := d.AddText("x+8 yp w160 h20", "")
    d.AddText("x+16 yp w50 h20", "归属")
    BMScopeText := d.AddText("x+8 yp w120 h20", "")

    d.AddText("x724 y118 w444 h18", "说明")
    BMPurposeView := d.AddEdit("x724 y140 w444 h52 +ReadOnly +Multi +VScroll", "")

    d.AddText("x724 y200 w444 h18", "正文")
    BMBodyView := d.AddEdit("x724 y222 w444 h280 +ReadOnly +Multi +VScroll", "")

    ; 正文里的 {{ref:…}} 译文：正文是数据，一个字不动，翻译放在框外
    d.AddText("x724 y510 w444 h18", "本文引用")
    BMRefText := d.AddEdit("x724 y532 w444 h30 +ReadOnly +Multi +VScroll", "")

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
    global BMNameText, BMIdText, BMKindText, BMScopeText, BMPurposeView, BMBodyView, BMRefText
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
    BMIdText := ""
    BMKindText := ""
    BMScopeText := ""
    BMPurposeView := ""
    BMBodyView := ""
    BMRefText := ""
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

        BMPrivateList.Add(, name, id, purpose, kind, bodyState)
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
        BMGlobalList.Add(, name, id, purpose, kind, "公共")
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
    global BMNameText, BMIdText, BMKindText, BMScopeText, BMPurposeView, BMBodyView, BMRefText, BMFlowKey

    BMSelectedKind := kind
    BMSelectedId := id

    if (id = "") {
        BMNameText.Text := ""
        BMIdText.Value := ""
        BMKindText.Text := ""
        BMScopeText.Text := ""
        BMPurposeView.Value := ""
        BMBodyView.Value := ""
        BMRefText.Value := ""
        return
    }

    flow := FlowLibrary.Get(BMFlowKey)
    if (kind = "private")
        blk := BlockLibrary.Get(id, flow.BlocksDir)
    else
        blk := BlockLibrary.Get(id, "")

    BMNameText.Text := blk.Name != "" ? blk.Name : id
    BMIdText.Value := id
    BMKindText.Text := blk.Kind
    BMScopeText.Text := (kind = "private") ? "私有" : "公共"
    BMPurposeView.Value := blk.Purpose
    BMBodyView.Value := blk.Body
    ; 正文里的 {{ref:…}} 就地翻成人话：引用按当前流程解析（全局块也一样）
    BMRefText.Value := PromptLabels.RefsInBody(blk.Body, BMFlowKey)
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
    global BMPrivateList, BMPrivateIds, BMChanged, BMFlowKey, BMWin

    row := BMPrivateList.GetNext(0)
    if (row = 0 || row > BMPrivateIds.Length)
        return
    id := BMPrivateIds[row]
    name := BMPrivateList.GetText(row, 1)

    ; 确认框必须绑到块窗口，否则它会被窗口盖住（层级低、看起来"点了没反应"）
    ownerHwnd := GuiAlive(BMWin) ? BMWin.Hwnd : 0
    opts := "Icon! YesNo Default2"
    if (ownerHwnd)
        opts .= " Owner" ownerHwnd

    if (MsgBox("确定删除块「" name "」吗？`n`n目录：" id "`n此操作不可撤销。",
            "删除块", opts) != "Yes")
        return

    neighbor := ""
    if (row < BMPrivateIds.Length)
        neighbor := BMPrivateIds[row + 1]
    else if (row > 1)
        neighbor := BMPrivateIds[row - 1]

    try {
        BlockEditor.Delete(BMFlowKey, id)
    } catch as e {
        ; 被引用时不能用状态行打发：确认过却什么都没发生，等于坏交互
        ownerHwnd := GuiAlive(BMWin) ? BMWin.Hwnd : 0
        opts := "Icon!"
        if (ownerHwnd)
            opts .= " Owner" ownerHwnd
        MsgBox(e.Message, "不能删除", opts)
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
    btnInsertRef := d.AddButton("x+8 yp w90 h22", "插入引用")
    btnInsertRef.OnEvent("Click", OnBMInsertRef)
    BMBodyEdit := d.AddEdit("xm y+26 w600 h240 +Multi +VScroll")

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
    global BMRefDlg, BMRefList, BMRefIds

    if (GuiAlive(BMRefDlg)) {
        try BMRefDlg.Destroy()
    }
    BMRefDlg := ""
    BMRefList := ""
    BMRefIds := []

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
        ; 引用校验必须在写正文之前：否则文件已经被写脏了再报错
        err := BlockEditor.ValidateRefs(BMFlowKey, body)
        if (err != "") {
            BMDlgHint.Text := err
            return
        }

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

; ---- 插入引用（03）----

; 弹窗：只列可引用的两层（本流程私有 + 全局）；骨架私有不可引用，不出现在候选里
ShowBMRefPicker() {
    global BMDlg, BMRefDlg, BMRefList, BMRefIds, BMFlowKey

    if (GuiAlive(BMRefDlg)) {
        BMRefDlg.Show()
        WinActivate("ahk_id " BMRefDlg.Hwnd)
        return
    }

    opts := "+AlwaysOnTop +ToolWindow"
    if (GuiAlive(BMDlg))
        opts .= " +Owner" BMDlg.Hwnd

    d := Gui(opts, "选择参考文档")
    BMRefDlg := d
    d.BackColor := GetDialogBackColor()
    d.MarginX := 12
    d.MarginY := 12
    d.SetFont("s9", "Microsoft YaHei UI")
    d.OnEvent("Close", CloseBMRefPicker)
    d.OnEvent("Escape", CloseBMRefPicker)

    BMRefList := d.AddListView("xm ym w560 h260 -Multi", ["名称", "标识", "用途", "来源"])
    BMRefList.ModifyCol(1, 130)
    BMRefList.ModifyCol(2, 150)
    BMRefList.ModifyCol(3, 190)
    BMRefList.ModifyCol(4, 90)
    ApplyDialogListStyle(BMRefList)
    ; 按行号取 BMRefIds：点表头会打乱行序，必须关掉内建排序
    DisableListHeaderSort(BMRefList)
    BMRefList.OnEvent("DoubleClick", OnBMRefPickerOk)

    BMRefIds := []
    for doc in ReferenceLibrary.ListFlow(BMFlowKey) {
        BMRefList.Add(, doc.Name != "" ? doc.Name : doc.Id, doc.Id, doc.Purpose, "本流程私有")
        BMRefIds.Push(doc.Id)
    }
    for doc in ReferenceLibrary.ListGlobal() {
        BMRefList.Add(, doc.Name != "" ? doc.Name : doc.Id, doc.Id, doc.Purpose, "全局")
        BMRefIds.Push(doc.Id)
    }
    if (BMRefIds.Length > 0)
        BMRefList.Modify(1, "Select Focus")

    btnOk := d.AddButton("x432 y+10 w80 h26 Default", "插入")
    btnOk.OnEvent("Click", OnBMRefPickerOk)
    btnCancel := d.AddButton("x+8 yp w80 h26", "取消")
    btnCancel.OnEvent("Click", CloseBMRefPicker)

    d.Show("w600 h360")
}

CloseBMRefPicker(*) {
    global BMRefDlg, BMRefList, BMRefIds

    if (GuiAlive(BMRefDlg)) {
        try BMRefDlg.Destroy()
    }
    BMRefDlg := ""
    BMRefList := ""
    BMRefIds := []
}

OnBMInsertRef(*) {
    ShowBMRefPicker()
}

OnBMRefPickerOk(*) {
    global BMRefList, BMRefIds

    row := BMRefList.GetNext(0)
    if (row = 0 || row > BMRefIds.Length)
        return

    id := BMRefIds[row]
    CloseBMRefPicker()
    InsertBMRefText("{{ref:" id "}}")
}

; 在光标处插入；前后补空格边界；取不到光标就落文末
InsertBMRefText(piece) {
    global BMBodyEdit

    EM_GETSEL := 0x00B0, EM_SETSEL := 0x00B1, EM_REPLACESEL := 0x00C2

    current := BMBodyEdit.Value
    sel := SendMessage(EM_GETSEL, 0, 0, BMBodyEdit.Hwnd)
    start := sel & 0xFFFF
    end := (sel >> 16) & 0xFFFF
    if (start > end) {
        tmp := start
        start := end
        end := tmp
    }
    if (start < 0 || start > StrLen(current)) {
        start := StrLen(current)
        end := start
    }

    if (start > 0 && !InStr(" `t`r`n", SubStr(current, start, 1)))
        piece := " " piece
    if (end < StrLen(current) && !InStr(" `t`r`n", SubStr(current, end + 1, 1)))
        piece := piece " "

    SendMessage(EM_SETSEL, start, end, BMBodyEdit.Hwnd)
    SendMessage(EM_REPLACESEL, true, StrPtr(piece), BMBodyEdit.Hwnd)
    BMBodyEdit.Focus()
}