#Requires AutoHotkey v2.0

; 仓库主题选择弹窗链：二级（设置主题）、三级（选择仓库）、四级（新增仓库）
; 依赖 RepositoryManager.ahk 提供数据操作

; ============================================================
; 弹窗全局变量
; ============================================================

global ThemeSelectDialog := ""
global ThemeSelectPathText := ""
global ThemeSelectRepoText := ""
global ThemeSelectAddRepoBtn := ""
global ThemeSelectThemeList := ""
global ThemeSelectNewEdit := ""
global ThemeSelectCurrentRepo := ""

; 切流程弹窗
global FlowSwitchDialog := ""
global FlowSwitchList := ""

global RepoSelectDialog := ""
global RepoSelectRepoList := ""
global RepoSelectPathText := ""
; 列表第 3 列只放中间省略后的显示串，完整路径按行号存这里（复制/打开/确定都用全路径）
global RepoSelectFullPaths := []

; 可拖拽调整尺寸：Size 事件按客户区差量锚定控件，需持有底部控件引用、当前客户区尺寸和弹性列宽
global ThemeSelectClientW := 0
global ThemeSelectClientH := 0
global ThemeSelectCol1W := 640
global ThemeSelectNewLabel := ""
global ThemeSelectNewThemeBtn := ""
global ThemeSelectOpenDirBtn := ""
global ThemeSelectCopyPathBtn := ""
global ThemeSelectOkBtn := ""
global ThemeSelectCancelBtn := ""

global RepoSelectClientW := 0
global RepoSelectClientH := 0
global RepoSelectCol3W := 780
global RepoSelectAddBtn := ""
global RepoSelectOpenDirBtn := ""
global RepoSelectCopyPathBtn := ""
global RepoSelectOkBtn := ""
global RepoSelectCancelBtn := ""

global RepoAddDialog := ""
global RepoAddEdit := ""
global RepoAddErrorText := ""

; ============================================================
; 二级弹窗：设置主题
; ============================================================

ShowThemeSelectDialog(*) {
    global ThemeSelectDialog, ThemeSelectPathText, ThemeSelectRepoText
    global ThemeSelectAddRepoBtn, ThemeSelectThemeList, ThemeSelectNewEdit
    global ThemeSelectCurrentRepo, MainGui
    global ThemeSelectClientW, ThemeSelectClientH
    global ThemeSelectNewLabel, ThemeSelectNewThemeBtn, ThemeSelectOpenDirBtn
    global ThemeSelectCopyPathBtn, ThemeSelectOkBtn, ThemeSelectCancelBtn

    if (ThemeSelectDialog) {
        ThemeSelectDialog.Show()
        WinActivate("ahk_id " ThemeSelectDialog.Hwnd)
        RefreshThemeSelectState()
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow +Resize"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    ThemeSelectDialog := Gui(dialogOptions, "设置主题")
    ThemeSelectDialog.BackColor := GetDialogBackColor()
    ThemeSelectDialog.MarginX := 12
    ThemeSelectDialog.MarginY := 12
    ThemeSelectDialog.SetFont("s9", "Microsoft YaHei UI")
    ThemeSelectDialog.MinSize := "720x560"
    ThemeSelectDialog.OnEvent("Close", CloseThemeSelectDialog)
    ThemeSelectDialog.OnEvent("Escape", CloseThemeSelectDialog)
    ThemeSelectDialog.OnEvent("Size", OnThemeSelectSize)

    ThemeSelectDialog.AddText("xm ym w936 h20", "当前主题：")
    ThemeSelectPathText := ThemeSelectDialog.AddText("xm y+2 w936 h20 c666666")

    ; 切换当前主题的流程：只读当前值，改只在流程维护里做
    ThemeSelectFlowBtn := ThemeSelectDialog.AddButton("xm y+4 w120 h24", "切换流程…")
    ThemeSelectFlowBtn.OnEvent("Click", ShowFlowSwitchDialog)

    ThemeSelectDialog.AddText("xm y+8 w60 h20", "选择仓库：")
    ThemeSelectRepoText := ThemeSelectDialog.AddText("x+0 yp w300 h20 cBlue", "")
    ThemeSelectRepoText.OnEvent("Click", OnRepoTextClick)
    ThemeSelectAddRepoBtn := ThemeSelectDialog.AddButton("xm y+2 w80 h24 Hidden", "新增仓库")
    ThemeSelectAddRepoBtn.OnEvent("Click", OnAddRepoFromThemeSelect)

    ThemeSelectDialog.AddText("xm y+12 w936 h20", "主题目录：")
    ThemeSelectThemeList := ThemeSelectDialog.AddListView("xm y+2 w936 h380 -Multi", ["主题名", "流程", "最近活跃"])
    ThemeSelectThemeList.ModifyCol(1, 640)
    ThemeSelectThemeList.ModifyCol(2, "140 Center")
    ThemeSelectThemeList.ModifyCol(3, "100 Center")
    ApplyDialogListStyle(ThemeSelectThemeList)
    ThemeSelectThemeList.OnEvent("DoubleClick", OnThemeSelectOk)

    ThemeSelectNewLabel := ThemeSelectDialog.AddText("xm y+10 w936 h20", "新主题名：")
    ThemeSelectNewEdit := ThemeSelectDialog.AddEdit("xm y+2 w800 h26")

    ThemeSelectNewThemeBtn := ThemeSelectDialog.AddButton("x+8 yp w128 h26", "新建并切换")
    ThemeSelectNewThemeBtn.OnEvent("Click", OnNewThemeAndSwitch)

    ThemeSelectOpenDirBtn := ThemeSelectDialog.AddButton("xm y+14 w80 h26", "打开目录")
    ThemeSelectOpenDirBtn.OnEvent("Click", OnThemeSelectOpenDir)
    ThemeSelectCopyPathBtn := ThemeSelectDialog.AddButton("x+8 yp w80 h26", "复制路径")
    ThemeSelectCopyPathBtn.OnEvent("Click", OnThemeSelectCopyPath)

    ThemeSelectOkBtn := ThemeSelectDialog.AddButton("x780 yp w80 h26 Default", "确定")
    ThemeSelectOkBtn.OnEvent("Click", OnThemeSelectOk)

    ThemeSelectCancelBtn := ThemeSelectDialog.AddButton("x+8 yp w80 h26", "取消")
    ThemeSelectCancelBtn.OnEvent("Click", CloseThemeSelectDialog)

    ThemeSelectClientW := 960
    ThemeSelectClientH := 700
    RefreshThemeSelectState()
    ; 省略 x/y：系统屏幕居中，不再相对主面板定位
    ThemeSelectDialog.Show("w960 h700")
}

; ============================================================
; 切流程弹窗：改当前主题用哪套流程
; ============================================================

; 只改"当前主题"的流程，不动别的主题
ShowFlowSwitchDialog(*) {
    global FlowSwitchDialog, FlowSwitchList, ThemeSelectDialog

    currentDir := GetCurrentDir()
    if (currentDir = "") {
        ShowFeedback("请先设置当前主题目录", true)
        return
    }

    ownerHwnd := ThemeSelectDialog ? ThemeSelectDialog.Hwnd : 0
    if (FlowSwitchDialog) {
        FlowSwitchDialog.Show()
        WinActivate("ahk_id " FlowSwitchDialog.Hwnd)
        RefreshFlowSwitchList()
        return
    }

    opts := "+AlwaysOnTop +ToolWindow"
    if (ownerHwnd) {
        opts .= " +Owner" ownerHwnd
    }
    FlowSwitchDialog := Gui(opts, "切换流程")
    FlowSwitchDialog.BackColor := GetDialogBackColor()
    FlowSwitchDialog.MarginX := 12
    FlowSwitchDialog.MarginY := 12
    FlowSwitchDialog.SetFont("s9", "Microsoft YaHei UI")
    FlowSwitchDialog.OnEvent("Close", CloseFlowSwitchDialog)
    FlowSwitchDialog.OnEvent("Escape", CloseFlowSwitchDialog)

    FlowSwitchDialog.AddText("xm ym w536 h20", "当前主题：")
    ; 路径可能很长：给三行高度并显式 Wrap，否则换行后第二行会被 h20 裁掉
    FlowSwitchDialog.AddText("xm y+2 w536 h48 c666666 +Wrap", currentDir)
    FlowSwitchDialog.AddText("xm y+10 w536 h20", "选择流程：")
    FlowSwitchList := FlowSwitchDialog.AddListView("xm y+2 w536 h240 -Multi", ["流程", "全称", "标识"])
    FlowSwitchList.ModifyCol(1, 120)
    FlowSwitchList.ModifyCol(2, 296)
    FlowSwitchList.ModifyCol(3, 100)
    ApplyDialogListStyle(FlowSwitchList)
    FlowSwitchList.OnEvent("DoubleClick", OnFlowSwitchOk)

    ; 流程维护窗口（03）
    MaintainBtn := FlowSwitchDialog.AddButton("xm y+10 w120 h26", "维护流程…")
    MaintainBtn.OnEvent("Click", OnOpenFlowMaintain)

    OkBtn := FlowSwitchDialog.AddButton("x348 yp w90 h26 Default", "确定")
    OkBtn.OnEvent("Click", OnFlowSwitchOk)
    CancelBtn := FlowSwitchDialog.AddButton("x+8 yp w90 h26", "取消")
    CancelBtn.OnEvent("Click", CloseFlowSwitchDialog)

    RefreshFlowSwitchList()
    FlowSwitchDialog.Show()
}

RefreshFlowSwitchList() {
    global FlowSwitchList

    FlowSwitchList.Delete()
    currentKey := FlowResolver.Resolve(GetCurrentDir())["flowKey"]
    selectedRow := 0

    for key in FlowLibrary.ListKeys() {
        try {
            f := FlowLibrary.Get(key)
            shortName := f.ShortName
            fullName := f.Name
        } catch {
            shortName := key
            fullName := key
        }
        FlowSwitchList.Add(, shortName, fullName, key)
        if (key = currentKey && selectedRow = 0) {
            selectedRow := A_Index
        }
    }

    if (selectedRow > 0) {
        FlowSwitchList.Modify(selectedRow, "Select Focus")
    }
}

CloseFlowSwitchDialog(*) {
    global FlowSwitchDialog, FlowSwitchList
    ; 必须 Destroy + 置空：Gui.Close 事件处理器执行完后窗口仍会被销毁，
    ; 只 Hide 不置空的话，变量指向已销毁的 Gui，下次 Show() 报 "Gui has no window"。
    ; 同 CloseThemeSelectDialog 的做法。
    if (FlowSwitchDialog) {
        FlowSwitchDialog.Destroy()
        FlowSwitchDialog := ""
    }
    FlowSwitchList := ""
}

; 从切流程弹窗进流程维护：带着当前选中的流程
OnOpenFlowMaintain(*) {
    global FlowSwitchList

    flowKey := ""
    row := FlowSwitchList ? FlowSwitchList.GetNext(0) : 0
    if (row > 0) {
        flowKey := FlowSwitchList.GetText(row, 3)
    }
    ShowFlowMaintainWindow(flowKey)
}

OnFlowSwitchOk(*) {
    global FlowSwitchList, FlowSwitchDialog, ThemeSelectDialog

    row := FlowSwitchList.GetNext(0)
    if (row = 0) {
        return
    }
    pickedKey := FlowSwitchList.GetText(row, 3)

    currentDir := GetCurrentDir()
    cur := FlowResolver.Resolve(currentDir)
    curKey := cur["flowKey"]

    ; 切到同一个：不写、不记日志
    if (pickedKey != curKey) {
        FlowResolver.Write(currentDir, pickedKey)
        LogActivity("流程切换", curKey " → " pickedKey,
            Map("from", curKey, "to", pickedKey,
                "window", GetActiveWindowId(), "topicDir", currentDir))
    }

    CloseFlowSwitchDialog()
    ; 面板与主题列表同步刷新
    UpdateCurrentPathDisplay()
    if (ThemeSelectDialog) {
        RefreshThemeSelectState()
    }
}

; 尺寸变化时按客户区差量锚定：列表和输入框双向拉伸、首列吃掉横向增量、底部控件吸附下缘/右缘
OnThemeSelectSize(guiObj, minMax, w, h) {
    global ThemeSelectClientW, ThemeSelectClientH, ThemeSelectCol1W
    global ThemeSelectPathText, ThemeSelectThemeList, ThemeSelectNewLabel, ThemeSelectNewEdit
    global ThemeSelectNewThemeBtn, ThemeSelectOpenDirBtn, ThemeSelectCopyPathBtn
    global ThemeSelectOkBtn, ThemeSelectCancelBtn

    if (minMax = -1 || ThemeSelectClientW = 0) {
        return
    }
    dw := w - ThemeSelectClientW
    dh := h - ThemeSelectClientH
    if (dw = 0 && dh = 0) {
        return
    }
    ThemeSelectClientW := w
    ThemeSelectClientH := h

    ThemeSelectPathText.GetPos(, , &pathW, )
    ThemeSelectPathText.Move(, , pathW + dw)

    ThemeSelectThemeList.GetPos(, , &listW, &listH)
    ThemeSelectThemeList.Move(, , listW + dw, listH + dh)
    ThemeSelectCol1W += dw
    ThemeSelectThemeList.ModifyCol(1, ThemeSelectCol1W)

    ThemeSelectNewLabel.GetPos(, &labelY, , )
    ThemeSelectNewLabel.Move(, labelY + dh)
    ThemeSelectNewEdit.GetPos(&editX, &editY, &editW, )
    ThemeSelectNewEdit.Move(editX, editY + dh, editW + dw)
    ThemeSelectNewThemeBtn.GetPos(&newBtnX, &newBtnY, , )
    ThemeSelectNewThemeBtn.Move(newBtnX + dw, newBtnY + dh)

    ThemeSelectOpenDirBtn.GetPos(, &openY, , )
    ThemeSelectOpenDirBtn.Move(, openY + dh)
    ThemeSelectCopyPathBtn.GetPos(, &copyY, , )
    ThemeSelectCopyPathBtn.Move(, copyY + dh)
    ThemeSelectOkBtn.GetPos(&okX, &okY, , )
    ThemeSelectOkBtn.Move(okX + dw, okY + dh)
    ThemeSelectCancelBtn.GetPos(&cancelX, &cancelY, , )
    ThemeSelectCancelBtn.Move(cancelX + dw, cancelY + dh)
}

RefreshThemeSelectState() {
    global ThemeSelectPathText, ThemeSelectRepoText, ThemeSelectAddRepoBtn
    global ThemeSelectThemeList, ThemeSelectNewEdit, ThemeSelectCurrentRepo

    currentDir := GetCurrentDir()
    ThemeSelectPathText.Text := currentDir != "" ? TruncateToWidth(currentDir, ThemeSelectPathText.Hwnd) : "未设置"

    ; 确定默认仓库（仅在首次打开或选中无效时推导，避免覆盖用户选择）
    if (ThemeSelectCurrentRepo = "") {
        if (currentDir != "") {
            repo := FindRepoByThemePath(currentDir)
            if (repo != "") {
                ThemeSelectCurrentRepo := repo["path"]
            }
        }
        if (ThemeSelectCurrentRepo = "" && Repositories.Length > 0) {
            ThemeSelectCurrentRepo := Repositories[1]["path"]
        }
    }

    ; 设置仓库显示状态
    if (ThemeSelectCurrentRepo != "") {
        ThemeSelectRepoText.Text := GetRepoName(ThemeSelectCurrentRepo) " ▾"
        ThemeSelectRepoText.SetFont("cBlue")
        ThemeSelectAddRepoBtn.Visible := false
    } else {
        ThemeSelectRepoText.Text := "当前没有仓库"
        ThemeSelectRepoText.SetFont("c777777")
        ThemeSelectAddRepoBtn.Visible := true
    }

    ThemeSelectThemeList.Delete()
    if (ThemeSelectCurrentRepo != "") {
        themes := GetRepoThemesWithActivity(ThemeSelectCurrentRepo)
        selectedRow := 0
        for t in themes {
            dateText := t["lastActiveAt"] != "" ? SubStr(t["lastActiveAt"], 1, 10) : ""
            ThemeSelectThemeList.Add(, t["name"], t["flowShort"], dateText)
            if (selectedRow = 0 && currentDir != "" && t["name"] = ExtractFileName(currentDir)) {
                selectedRow := A_Index
            }
        }
        if (selectedRow > 0) {
            ThemeSelectThemeList.Modify(selectedRow, "Select Focus")
        }
    }

    ThemeSelectNewEdit.Value := ""
}

OnRepoTextClick(*) {
    ShowRepoSelectDialog()
}

OnAddRepoFromThemeSelect(*) {
    ShowRepoAddDialog()
}

OnThemeSelectOk(*) {
    global ThemeSelectDialog

    selectedPath := GetSelectedThemePath()
    if (selectedPath = "") {
        return
    }

    CloseThemeSelectDialog()
    SetCurrentDirAndOpenRequirement(selectedPath)
}

; 主题列表选中行的完整路径（无选中/无仓库返回空串）
GetSelectedThemePath() {
    global ThemeSelectThemeList, ThemeSelectCurrentRepo

    row := ThemeSelectThemeList.GetNext(0)
    if (row = 0 || ThemeSelectCurrentRepo = "") {
        return ""
    }
    return ThemeSelectCurrentRepo "\" ThemeSelectThemeList.GetText(row, 1)
}

OnThemeSelectOpenDir(*) {
    path := GetSelectedThemePath()
    if (path != "") {
        OpenThemeDir(path)
    }
}

OnThemeSelectCopyPath(*) {
    path := GetSelectedThemePath()
    if (path != "") {
        A_Clipboard := path
    }
}

OnNewThemeAndSwitch(*) {
    global ThemeSelectDialog, ThemeSelectNewEdit, ThemeSelectCurrentRepo

    newName := Trim(ThemeSelectNewEdit.Value)
    if (newName = "") {
        return
    }
    if (ThemeSelectCurrentRepo = "") {
        MsgBox("请先选择或添加仓库", "AIProcess", "Iconx")
        return
    }
    if (!IsValidDirName(newName)) {
        MsgBox("目录名包含非法字符", "AIProcess", "Iconx")
        return
    }

    newPath := ThemeSelectCurrentRepo "\" newName
    if (DirExist(newPath)) {
        MsgBox("目录已存在：" newName, "AIProcess", "Iconx")
        return
    }

    DirCreate(newPath)
    CloseThemeSelectDialog()
    SetCurrentDirAndOpenRequirement(newPath)
}

CloseThemeSelectDialog(*) {
    global ThemeSelectDialog, ThemeSelectPathText, ThemeSelectRepoText
    global ThemeSelectAddRepoBtn, ThemeSelectThemeList, ThemeSelectNewEdit
    global ThemeSelectCurrentRepo
    global ThemeSelectClientW, ThemeSelectClientH, ThemeSelectCol1W
    global ThemeSelectNewLabel, ThemeSelectNewThemeBtn, ThemeSelectOpenDirBtn
    global ThemeSelectCopyPathBtn, ThemeSelectOkBtn, ThemeSelectCancelBtn

    if (ThemeSelectDialog) {
        ThemeSelectDialog.Destroy()
        ThemeSelectDialog := ""
    }
    ThemeSelectPathText := ""
    ThemeSelectRepoText := ""
    ThemeSelectAddRepoBtn := ""
    ThemeSelectThemeList := ""
    ThemeSelectNewEdit := ""
    ThemeSelectCurrentRepo := ""
    ThemeSelectClientW := 0
    ThemeSelectClientH := 0
    ThemeSelectCol1W := 640
    ThemeSelectNewLabel := ""
    ThemeSelectNewThemeBtn := ""
    ThemeSelectOpenDirBtn := ""
    ThemeSelectCopyPathBtn := ""
    ThemeSelectOkBtn := ""
    ThemeSelectCancelBtn := ""
}

; ============================================================
; 三级弹窗：选择仓库
; ============================================================

ShowRepoSelectDialog(*) {
    global RepoSelectDialog, RepoSelectRepoList, RepoSelectPathText, Repositories, MainGui
    global RepoSelectClientW, RepoSelectClientH
    global RepoSelectAddBtn, RepoSelectOpenDirBtn, RepoSelectCopyPathBtn
    global RepoSelectOkBtn, RepoSelectCancelBtn

    if (RepoSelectDialog) {
        RepoSelectDialog.Show()
        WinActivate("ahk_id " RepoSelectDialog.Hwnd)
        RefreshRepoSelectList()
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow +Resize"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    RepoSelectDialog := Gui(dialogOptions, "选择仓库")
    RepoSelectDialog.BackColor := GetDialogBackColor()
    RepoSelectDialog.MarginX := 12
    RepoSelectDialog.MarginY := 12
    RepoSelectDialog.SetFont("s9", "Microsoft YaHei UI")
    RepoSelectDialog.MinSize := "900x520"
    RepoSelectDialog.OnEvent("Close", CloseRepoSelectDialog)
    RepoSelectDialog.OnEvent("Escape", CloseRepoSelectDialog)
    RepoSelectDialog.OnEvent("Size", OnRepoSelectSize)

    RepoSelectDialog.AddText("xm ym w1076 h20", "仓库列表：")
    ; 路径行：选中仓库的完整路径（装不下时中间省略，双击复制全路径）
    RepoSelectPathText := RepoSelectDialog.AddText("xm y+2 w1076 h20 c666666", "选择一行查看完整路径（双击此行复制）")
    RepoSelectPathText.OnEvent("DoubleClick", OnRepoSelectPathDoubleClick)
    RepoSelectRepoList := RepoSelectDialog.AddListView("xm y+4 w1076 h560 -Multi", ["名称", "最近活跃", "路径"])
    RepoSelectRepoList.ModifyCol(1, 180)
    RepoSelectRepoList.ModifyCol(2, "100 Center")
    RepoSelectRepoList.ModifyCol(3, 780)
    ApplyDialogListStyle(RepoSelectRepoList)
    RepoSelectRepoList.OnEvent("DoubleClick", OnRepoSelectOk)
    RepoSelectRepoList.OnEvent("ItemSelect", OnRepoSelectItem)

    RepoSelectAddBtn := RepoSelectDialog.AddButton("xm y+10 w90 h26", "新增仓库")
    RepoSelectAddBtn.OnEvent("Click", OnAddRepoFromRepoSelect)

    RepoSelectOpenDirBtn := RepoSelectDialog.AddButton("x+8 yp w80 h26", "打开目录")
    RepoSelectOpenDirBtn.OnEvent("Click", OnRepoSelectOpenDir)
    RepoSelectCopyPathBtn := RepoSelectDialog.AddButton("x+8 yp w80 h26", "复制路径")
    RepoSelectCopyPathBtn.OnEvent("Click", OnRepoSelectCopyPath)

    RepoSelectOkBtn := RepoSelectDialog.AddButton("x920 yp w80 h26 Default", "确定")
    RepoSelectOkBtn.OnEvent("Click", OnRepoSelectOk)

    RepoSelectCancelBtn := RepoSelectDialog.AddButton("x+8 yp w80 h26", "取消")
    RepoSelectCancelBtn.OnEvent("Click", CloseRepoSelectDialog)

    RepoSelectClientW := 1100
    RepoSelectClientH := 680
    RefreshRepoSelectList()
    ; 省略 x/y：系统屏幕居中
    RepoSelectDialog.Show("w1100 h680")
}

; 尺寸变化时按客户区差量锚定：列表双向拉伸、路径列吃掉横向增量并按新列宽重截显示串、底部控件吸附下缘/右缘
OnRepoSelectSize(guiObj, minMax, w, h) {
    global RepoSelectClientW, RepoSelectClientH, RepoSelectCol3W
    global RepoSelectRepoList, RepoSelectFullPaths, RepoSelectPathText
    global RepoSelectAddBtn, RepoSelectOpenDirBtn, RepoSelectCopyPathBtn
    global RepoSelectOkBtn, RepoSelectCancelBtn

    if (minMax = -1 || RepoSelectClientW = 0) {
        return
    }
    dw := w - RepoSelectClientW
    dh := h - RepoSelectClientH
    if (dw = 0 && dh = 0) {
        return
    }
    RepoSelectClientW := w
    RepoSelectClientH := h

    RepoSelectPathText.GetPos(, , &pathW, )
    RepoSelectPathText.Move(, , pathW + dw)

    RepoSelectRepoList.GetPos(, , &listW, &listH)
    RepoSelectRepoList.Move(, , listW + dw, listH + dh)
    RepoSelectCol3W += dw
    RepoSelectRepoList.ModifyCol(3, RepoSelectCol3W)

    if (dw != 0 && RepoSelectFullPaths.Length > 0) {
        ; 列宽变了，显示串按新宽重截（ModifyCol 是逻辑单位，量宽是物理像素，乘 DPI 换算）
        pathColWidth := Round(RepoSelectCol3W * A_ScreenDPI / 96) - 12
        Loop RepoSelectRepoList.GetCount() {
            row := A_Index
            RepoSelectRepoList.Modify(row, "Col3", TruncateToPixelWidth(RepoSelectFullPaths[row], pathColWidth, RepoSelectRepoList.Hwnd))
        }
    }

    RepoSelectAddBtn.GetPos(, &addY, , )
    RepoSelectAddBtn.Move(, addY + dh)
    RepoSelectOpenDirBtn.GetPos(, &openY, , )
    RepoSelectOpenDirBtn.Move(, openY + dh)
    RepoSelectCopyPathBtn.GetPos(, &copyY, , )
    RepoSelectCopyPathBtn.Move(, copyY + dh)
    RepoSelectOkBtn.GetPos(&okX, &okY, , )
    RepoSelectOkBtn.Move(okX + dw, okY + dh)
    RepoSelectCancelBtn.GetPos(&cancelX, &cancelY, , )
    RepoSelectCancelBtn.Move(cancelX + dw, cancelY + dh)
}

RefreshRepoSelectList() {
    global RepoSelectRepoList, RepoSelectFullPaths, Repositories, ThemeSelectCurrentRepo

    if (!RepoSelectRepoList) {
        return
    }
    RepoSelectRepoList.Delete()
    RepoSelectFullPaths := []

    ; LVM_GETCOLUMNWIDTH 读回物理像素（ModifyCol 是逻辑单位），TruncateToPixelWidth 量的也是物理像素；12px 是单元格内边距
    pathColWidth := SendMessage(0x101D, 2, 0, RepoSelectRepoList.Hwnd) - 12

    ; 仓库活跃时间 = 该仓库主题活跃的最大值（GetRepoThemesWithActivity 已倒序，首项即最新）
    withTime := []
    withoutTime := []
    for repo in Repositories {
        lastActiveAt := ""
        themes := GetRepoThemesWithActivity(repo["path"])
        if (themes.Length > 0) {
            lastActiveAt := themes[1]["lastActiveAt"]
        }
        item := Map("name", repo["name"], "path", repo["path"], "lastActiveAt", lastActiveAt)
        if (lastActiveAt != "") {
            withTime.Push(item)
        } else {
            withoutTime.Push(item)
        }
    }

    sorted := []
    for item in withTime {
        InsertByActivityDesc(sorted, item)
    }
    for item in withoutTime {
        sorted.Push(item)
    }

    selectedRow := 0
    for item in sorted {
        dateText := item["lastActiveAt"] != "" ? SubStr(item["lastActiveAt"], 1, 10) : ""
        RepoSelectFullPaths.Push(item["path"])
        displayPath := TruncateToPixelWidth(item["path"], pathColWidth, RepoSelectRepoList.Hwnd)
        RepoSelectRepoList.Add(, item["name"], dateText, displayPath)
        if (selectedRow = 0 && ThemeSelectCurrentRepo != ""
            && NormalizePath(item["path"]) = NormalizePath(ThemeSelectCurrentRepo)) {
            selectedRow := A_Index
        }
    }
    if (selectedRow > 0) {
        RepoSelectRepoList.Modify(selectedRow, "Select Focus")
    }
    UpdateRepoSelectPathLine()
}

; 路径行：显示选中仓库的完整路径（列里截断的在这里看全）
UpdateRepoSelectPathLine() {
    global RepoSelectRepoList, RepoSelectFullPaths, RepoSelectPathText

    if (!RepoSelectPathText) {
        return
    }
    row := RepoSelectRepoList.GetNext(0)
    if (row = 0) {
        RepoSelectPathText.Text := "选择一行查看完整路径（双击此行复制）"
        return
    }
    RepoSelectPathText.Text := TruncateToWidth(RepoSelectFullPaths[row], RepoSelectPathText.Hwnd)
}

OnRepoSelectItem(ctrl, item, selected) {
    if (selected && item > 0) {
        UpdateRepoSelectPathLine()
    }
}

; 双击路径行：复制选中仓库的完整路径
OnRepoSelectPathDoubleClick(*) {
    OnRepoSelectCopyPath()
}

OnRepoSelectOpenDir(*) {
    global RepoSelectRepoList, RepoSelectFullPaths

    row := RepoSelectRepoList.GetNext(0)
    if (row = 0) {
        return
    }
    OpenThemeDir(RepoSelectFullPaths[row])
}

OnRepoSelectCopyPath(*) {
    global RepoSelectRepoList, RepoSelectFullPaths

    row := RepoSelectRepoList.GetNext(0)
    if (row > 0) {
        A_Clipboard := RepoSelectFullPaths[row]
    }
}

; 活跃倒序插入排序（"YYYY-MM-DD HH:MM:SS" 定长字典序）
; AHK v2 关系运算符不接受字符串（实测抛"Expected a Number"），必须用 StrCompare
InsertByActivityDesc(sortedList, item) {
    idx := 1
    while (idx <= sortedList.Length && StrCompare(sortedList[idx]["lastActiveAt"], item["lastActiveAt"], true) >= 0) {
        idx++
    }
    sortedList.InsertAt(idx, item)
}

OnRepoSelectOk(*) {
    global RepoSelectDialog, RepoSelectRepoList, RepoSelectFullPaths, ThemeSelectCurrentRepo, ThemeSelectRepoText, ThemeSelectAddRepoBtn

    row := RepoSelectRepoList.GetNext(0)
    if (row = 0) {
        return
    }

    selectedPath := RepoSelectFullPaths[row]
    ThemeSelectCurrentRepo := selectedPath
    if (ThemeSelectRepoText) {
        ThemeSelectRepoText.Text := GetRepoName(selectedPath) " ▾"
        ThemeSelectRepoText.SetFont("cBlue")
    }
    if (ThemeSelectAddRepoBtn) {
        ThemeSelectAddRepoBtn.Visible := false
    }

    CloseRepoSelectDialog()
    RefreshThemeSelectState()
}

OnAddRepoFromRepoSelect(*) {
    ShowRepoAddDialog()
}

CloseRepoSelectDialog(*) {
    global RepoSelectDialog, RepoSelectRepoList, RepoSelectPathText
    global RepoSelectClientW, RepoSelectClientH, RepoSelectCol3W, RepoSelectFullPaths
    global RepoSelectAddBtn, RepoSelectOpenDirBtn, RepoSelectCopyPathBtn
    global RepoSelectOkBtn, RepoSelectCancelBtn

    if (RepoSelectDialog) {
        RepoSelectDialog.Destroy()
        RepoSelectDialog := ""
    }
    RepoSelectRepoList := ""
    RepoSelectPathText := ""
    RepoSelectFullPaths := []
    RepoSelectClientW := 0
    RepoSelectClientH := 0
    RepoSelectCol3W := 780
    RepoSelectAddBtn := ""
    RepoSelectOpenDirBtn := ""
    RepoSelectCopyPathBtn := ""
    RepoSelectOkBtn := ""
    RepoSelectCancelBtn := ""
}

; ============================================================
; 四级弹窗：新增仓库
; ============================================================

ShowRepoAddDialog(*) {
    global RepoAddDialog, RepoAddEdit, RepoAddErrorText, MainGui

    if (RepoAddDialog) {
        RepoAddEdit.Value := ""
        RepoAddErrorText.Text := ""
        RepoAddErrorText.Visible := false
        RepoAddDialog.Show()
        WinActivate("ahk_id " RepoAddDialog.Hwnd)
        RepoAddEdit.Focus()
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    RepoAddDialog := Gui(dialogOptions, "新增仓库")
    RepoAddDialog.BackColor := GetDialogBackColor()
    RepoAddDialog.MarginX := 12
    RepoAddDialog.MarginY := 12
    RepoAddDialog.SetFont("s9", "Microsoft YaHei UI")
    RepoAddDialog.OnEvent("Close", CloseRepoAddDialog)
    RepoAddDialog.OnEvent("Escape", CloseRepoAddDialog)

    RepoAddDialog.AddText("xm ym w616 h20", "请输入仓库路径：")
    RepoAddEdit := RepoAddDialog.AddEdit("xm y+6 w510 h26")
    browseBtn := RepoAddDialog.AddButton("x+8 yp w90 h26", "浏览…")
    browseBtn.OnEvent("Click", OnRepoAddBrowse)
    RepoAddErrorText := RepoAddDialog.AddText("xm y+4 w616 h20 cRed Hidden", "")

    RepoAddDialog.AddText("xm y+4 w616 h20 c777777", DomainConventions.RepoRootRuleHint)

    okBtn := RepoAddDialog.AddButton("xm+214 y+10 w90 h26 Default", "确认")
    okBtn.OnEvent("Click", OnRepoAddConfirm)

    cancelBtn := RepoAddDialog.AddButton("x+8 yp w90 h26", "取消")
    cancelBtn.OnEvent("Click", CloseRepoAddDialog)

    ; 省略 x/y：系统屏幕居中
    RepoAddDialog.Show("w640 h240")
    RepoAddEdit.Focus()
}

; 浏览选目录：只填输入框，确认时仍走 AddRepository 的既有校验
OnRepoAddBrowse(*) {
    global RepoAddEdit

    selected := DirSelect(, 3, "选择仓库根目录")
    if (selected != "") {
        RepoAddEdit.Value := selected
    }
}

OnRepoAddConfirm(*) {
    global RepoAddDialog, RepoAddEdit, RepoAddErrorText

    rawPath := Trim(RepoAddEdit.Value)
    result := AddRepository(rawPath)
    if (result.success) {
        newRepoPath := NormalizePath(rawPath)
        CloseRepoAddDialog()
        if (RepoSelectDialog) {
            RefreshRepoSelectList()
        } else {
            ThemeSelectCurrentRepo := newRepoPath
            ThemeSelectRepoText.Text := GetRepoName(newRepoPath) " ▾"
            ThemeSelectRepoText.SetFont("cBlue")
            ThemeSelectAddRepoBtn.Visible := false
            RefreshThemeSelectState()
        }
    } else {
        RepoAddErrorText.Text := result.error
        RepoAddErrorText.Visible := true
    }
}

CloseRepoAddDialog(*) {
    global RepoAddDialog, RepoAddEdit, RepoAddErrorText

    if (RepoAddDialog) {
        RepoAddDialog.Destroy()
        RepoAddDialog := ""
    }
    RepoAddEdit := ""
    RepoAddErrorText := ""
}
