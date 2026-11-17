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

global RepoSelectDialog := ""
global RepoSelectRepoList := ""
global RepoSelectPathText := ""

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

    if (ThemeSelectDialog) {
        ThemeSelectDialog.Show()
        WinActivate("ahk_id " ThemeSelectDialog.Hwnd)
        RefreshThemeSelectState()
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    ThemeSelectDialog := Gui(dialogOptions, "设置主题")
    ThemeSelectDialog.BackColor := GetDialogBackColor()
    ThemeSelectDialog.MarginX := 12
    ThemeSelectDialog.MarginY := 12
    ThemeSelectDialog.SetFont("s9", "Microsoft YaHei UI")
    ThemeSelectDialog.OnEvent("Close", CloseThemeSelectDialog)
    ThemeSelectDialog.OnEvent("Escape", CloseThemeSelectDialog)

    ThemeSelectDialog.AddText("xm ym w696 h20", "当前主题：")
    ThemeSelectPathText := ThemeSelectDialog.AddText("xm y+2 w696 h20 c666666")

    ThemeSelectDialog.AddText("xm y+12 w60 h20", "选择仓库：")
    ThemeSelectRepoText := ThemeSelectDialog.AddText("x+0 yp w300 h20 cBlue", "")
    ThemeSelectRepoText.OnEvent("Click", OnRepoTextClick)
    ThemeSelectAddRepoBtn := ThemeSelectDialog.AddButton("xm y+2 w80 h24 Hidden", "新增仓库")
    ThemeSelectAddRepoBtn.OnEvent("Click", OnAddRepoFromThemeSelect)

    ThemeSelectDialog.AddText("xm y+12 w696 h20", "主题目录：")
    ThemeSelectThemeList := ThemeSelectDialog.AddListView("xm y+2 w696 h240 -Multi", ["主题名", "最近活跃"])
    ThemeSelectThemeList.ModifyCol(1, 550)
    ThemeSelectThemeList.ModifyCol(2, 100)
    ThemeSelectThemeList.OnEvent("DoubleClick", OnThemeSelectOk)

    ThemeSelectDialog.AddText("xm y+10 w696 h20", "新主题名：")
    ThemeSelectNewEdit := ThemeSelectDialog.AddEdit("xm y+2 w560 h26")

    newThemeBtn := ThemeSelectDialog.AddButton("x+8 yp w128 h26", "新建并切换")
    newThemeBtn.OnEvent("Click", OnNewThemeAndSwitch)

    okBtn := ThemeSelectDialog.AddButton("xm+264 y+14 w80 h26 Default", "确定")
    okBtn.OnEvent("Click", OnThemeSelectOk)

    cancelBtn := ThemeSelectDialog.AddButton("x+8 yp w80 h26", "取消")
    cancelBtn.OnEvent("Click", CloseThemeSelectDialog)

    RefreshThemeSelectState()
    ; 省略 x/y：系统屏幕居中，不再相对主面板定位
    ThemeSelectDialog.Show("w720 h560")
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
            ThemeSelectThemeList.Add(, t["name"], dateText)
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
    global ThemeSelectDialog, ThemeSelectThemeList, ThemeSelectCurrentRepo

    row := ThemeSelectThemeList.GetNext(0)
    if (row = 0 || ThemeSelectCurrentRepo = "") {
        return
    }

    selectedName := ThemeSelectThemeList.GetText(row, 1)
    selectedPath := ThemeSelectCurrentRepo "\" selectedName
    CloseThemeSelectDialog()
    SetCurrentDirAndOpenRequirement(selectedPath)
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
}

; ============================================================
; 三级弹窗：选择仓库
; ============================================================

ShowRepoSelectDialog(*) {
    global RepoSelectDialog, RepoSelectRepoList, RepoSelectPathText, Repositories, MainGui

    if (RepoSelectDialog) {
        RepoSelectDialog.Show()
        WinActivate("ahk_id " RepoSelectDialog.Hwnd)
        RefreshRepoSelectList()
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    RepoSelectDialog := Gui(dialogOptions, "选择仓库")
    RepoSelectDialog.BackColor := GetDialogBackColor()
    RepoSelectDialog.MarginX := 12
    RepoSelectDialog.MarginY := 12
    RepoSelectDialog.SetFont("s9", "Microsoft YaHei UI")
    RepoSelectDialog.OnEvent("Close", CloseRepoSelectDialog)
    RepoSelectDialog.OnEvent("Escape", CloseRepoSelectDialog)

    RepoSelectDialog.AddText("xm ym w876 h20", "仓库列表：")
    ; 路径行：选中仓库的完整路径（装不下时中间省略，双击复制全路径）
    RepoSelectPathText := RepoSelectDialog.AddText("xm y+2 w876 h20 c666666", "选择一行查看完整路径（双击此行复制）")
    RepoSelectPathText.OnEvent("DoubleClick", OnRepoSelectPathDoubleClick)
    RepoSelectRepoList := RepoSelectDialog.AddListView("xm y+4 w876 h400 -Multi", ["名称", "最近活跃", "路径"])
    RepoSelectRepoList.ModifyCol(1, 180)
    RepoSelectRepoList.ModifyCol(2, 100)
    RepoSelectRepoList.ModifyCol(3, 560)
    RepoSelectRepoList.OnEvent("DoubleClick", OnRepoSelectOk)
    RepoSelectRepoList.OnEvent("ItemSelect", OnRepoSelectItem)

    addBtn := RepoSelectDialog.AddButton("xm y+10 w90 h26", "新增仓库")
    addBtn.OnEvent("Click", OnAddRepoFromRepoSelect)

    okBtn := RepoSelectDialog.AddButton("x720 yp w80 h26 Default", "确定")
    okBtn.OnEvent("Click", OnRepoSelectOk)

    cancelBtn := RepoSelectDialog.AddButton("x+8 yp w80 h26", "取消")
    cancelBtn.OnEvent("Click", CloseRepoSelectDialog)

    RefreshRepoSelectList()
    ; 省略 x/y：系统屏幕居中
    RepoSelectDialog.Show("w900 h520")
}

RefreshRepoSelectList() {
    global RepoSelectRepoList, Repositories, ThemeSelectCurrentRepo

    if (!RepoSelectRepoList) {
        return
    }
    RepoSelectRepoList.Delete()

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
        RepoSelectRepoList.Add(, item["name"], dateText, item["path"])
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
    global RepoSelectRepoList, RepoSelectPathText

    if (!RepoSelectPathText) {
        return
    }
    row := RepoSelectRepoList.GetNext(0)
    if (row = 0) {
        RepoSelectPathText.Text := "选择一行查看完整路径（双击此行复制）"
        return
    }
    fullPath := RepoSelectRepoList.GetText(row, 3)
    RepoSelectPathText.Text := TruncateToWidth(fullPath, RepoSelectPathText.Hwnd)
}

OnRepoSelectItem(ctrl, item, selected) {
    if (selected && item > 0) {
        UpdateRepoSelectPathLine()
    }
}

; 双击路径行：复制选中仓库的完整路径
OnRepoSelectPathDoubleClick(*) {
    global RepoSelectRepoList

    row := RepoSelectRepoList.GetNext(0)
    if (row > 0) {
        A_Clipboard := RepoSelectRepoList.GetText(row, 3)
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
    global RepoSelectDialog, RepoSelectRepoList, ThemeSelectCurrentRepo, ThemeSelectRepoText, ThemeSelectAddRepoBtn

    row := RepoSelectRepoList.GetNext(0)
    if (row = 0) {
        return
    }

    selectedPath := RepoSelectRepoList.GetText(row, 3)
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

    if (RepoSelectDialog) {
        RepoSelectDialog.Destroy()
        RepoSelectDialog := ""
    }
    RepoSelectRepoList := ""
    RepoSelectPathText := ""
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
