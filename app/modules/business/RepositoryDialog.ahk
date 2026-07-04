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
global ThemeSelectListBox := ""
global ThemeSelectNewEdit := ""
global ThemeSelectCurrentRepo := ""

global RepoSelectDialog := ""
global RepoSelectListBox := ""

global RepoAddDialog := ""
global RepoAddEdit := ""
global RepoAddErrorText := ""

; ============================================================
; 二级弹窗：设置主题
; ============================================================

ShowThemeSelectDialog(*) {
    global ThemeSelectDialog, ThemeSelectPathText, ThemeSelectRepoText
    global ThemeSelectAddRepoBtn, ThemeSelectListBox, ThemeSelectNewEdit
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
    ThemeSelectDialog.BackColor := "F7F7F7"
    ThemeSelectDialog.MarginX := 12
    ThemeSelectDialog.MarginY := 10
    ThemeSelectDialog.SetFont("s8", "Microsoft YaHei UI")
    ThemeSelectDialog.OnEvent("Close", CloseThemeSelectDialog)
    ThemeSelectDialog.OnEvent("Escape", CloseThemeSelectDialog)

    ThemeSelectDialog.AddText("xm ym w400 h18", "当前主题：")
    ThemeSelectPathText := ThemeSelectDialog.AddText("xm y+2 w400 h18 c666666")

    ThemeSelectDialog.AddText("xm y+12 w60 h18", "选择仓库：")
    ThemeSelectRepoText := ThemeSelectDialog.AddText("x+0 yp w300 h18 cBlue", "")
    ThemeSelectRepoText.OnEvent("Click", OnRepoTextClick)
    ThemeSelectAddRepoBtn := ThemeSelectDialog.AddButton("xm y+2 w80 h22 Hidden", "新增仓库")
    ThemeSelectAddRepoBtn.OnEvent("Click", OnAddRepoFromThemeSelect)

    ThemeSelectDialog.AddText("xm y+12 w400 h18", "主题目录：")
    ThemeSelectListBox := ThemeSelectDialog.AddListBox("xm y+2 w400 h160")

    ThemeSelectDialog.AddText("xm y+8 w400 h18", "新主题名：")
    ThemeSelectNewEdit := ThemeSelectDialog.AddEdit("xm y+2 w320 h24")

    newThemeBtn := ThemeSelectDialog.AddButton("x+8 yp w72 h24", "新建并切换")
    newThemeBtn.OnEvent("Click", OnNewThemeAndSwitch)

    okBtn := ThemeSelectDialog.AddButton("xm+130 y+12 w72 h24 Default", "确定")
    okBtn.OnEvent("Click", OnThemeSelectOk)

    cancelBtn := ThemeSelectDialog.AddButton("x+8 yp w72 h24", "取消")
    cancelBtn.OnEvent("Click", CloseThemeSelectDialog)

    RefreshThemeSelectState()
    ShowThemeSelectAtCenter()
}

RefreshThemeSelectState() {
    global ThemeSelectPathText, ThemeSelectRepoText, ThemeSelectAddRepoBtn
    global ThemeSelectListBox, ThemeSelectNewEdit, ThemeSelectCurrentRepo

    currentDir := GetCurrentDir()
    ThemeSelectPathText.Text := currentDir != "" ? currentDir : "未设置"

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

    ThemeSelectListBox.Delete()
    if (ThemeSelectCurrentRepo != "") {
        themes := GetRepoThemes(ThemeSelectCurrentRepo)
        selectedIndex := 0
        idx := 1
        for name in themes {
            ThemeSelectListBox.Add([name])
            if (currentDir != "" && name = ExtractFileName(currentDir)) {
                selectedIndex := idx
            }
            idx += 1
        }
        if (selectedIndex > 0) {
            ThemeSelectListBox.Choose(selectedIndex)
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
    global ThemeSelectDialog, ThemeSelectListBox, ThemeSelectCurrentRepo

    selectedName := ThemeSelectListBox.Text
    if (selectedName = "") {
        return
    }
    if (ThemeSelectCurrentRepo = "") {
        return
    }

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
    global ThemeSelectAddRepoBtn, ThemeSelectListBox, ThemeSelectNewEdit
    global ThemeSelectCurrentRepo

    if (ThemeSelectDialog) {
        ThemeSelectDialog.Destroy()
        ThemeSelectDialog := ""
    }
    ThemeSelectPathText := ""
    ThemeSelectRepoText := ""
    ThemeSelectAddRepoBtn := ""
    ThemeSelectListBox := ""
    ThemeSelectNewEdit := ""
    ThemeSelectCurrentRepo := ""
}

ShowThemeSelectAtCenter() {
    global ThemeSelectDialog, MainGui

    width := 436
    height := 420
    if (MainGui) {
        WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
        x := mainX + Floor((mainW - width) / 2)
        y := mainY + Floor((mainH - height) / 2)
        ThemeSelectDialog.Show("w" width " h" height " x" x " y" y)
        return
    }
    ThemeSelectDialog.Show("w" width " h" height)
}

; ============================================================
; 三级弹窗：选择仓库
; ============================================================

ShowRepoSelectDialog(*) {
    global RepoSelectDialog, RepoSelectListBox, Repositories, MainGui

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
    RepoSelectDialog.BackColor := "F7F7F7"
    RepoSelectDialog.MarginX := 12
    RepoSelectDialog.MarginY := 10
    RepoSelectDialog.SetFont("s8", "Microsoft YaHei UI")
    RepoSelectDialog.OnEvent("Close", CloseRepoSelectDialog)
    RepoSelectDialog.OnEvent("Escape", CloseRepoSelectDialog)

    RepoSelectDialog.AddText("xm ym w480 h18", "仓库列表：")
    RepoSelectListBox := RepoSelectDialog.AddListBox("xm y+2 w480 h200")

    addBtn := RepoSelectDialog.AddButton("xm y+8 w80 h24", "新增仓库")
    addBtn.OnEvent("Click", OnAddRepoFromRepoSelect)

    okBtn := RepoSelectDialog.AddButton("x+200 yp w72 h24 Default", "确定")
    okBtn.OnEvent("Click", OnRepoSelectOk)

    cancelBtn := RepoSelectDialog.AddButton("x+8 yp w72 h24", "取消")
    cancelBtn.OnEvent("Click", CloseRepoSelectDialog)

    RefreshRepoSelectList()
    ShowRepoSelectAtCenter()
}

RefreshRepoSelectList() {
    global RepoSelectListBox, Repositories

    if (!RepoSelectListBox) {
        return
    }
    RepoSelectListBox.Delete()
    for repo in Repositories {
        RepoSelectListBox.Add([repo["path"]])
    }
}

OnRepoSelectOk(*) {
    global RepoSelectDialog, RepoSelectListBox, ThemeSelectCurrentRepo, ThemeSelectRepoText, ThemeSelectAddRepoBtn

    selectedPath := RepoSelectListBox.Text
    if (selectedPath = "") {
        return
    }

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
    global RepoSelectDialog, RepoSelectListBox

    if (RepoSelectDialog) {
        RepoSelectDialog.Destroy()
        RepoSelectDialog := ""
    }
    RepoSelectListBox := ""
}

ShowRepoSelectAtCenter() {
    global RepoSelectDialog, MainGui

    width := 516
    height := 320
    if (MainGui) {
        WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
        x := mainX + Floor((mainW - width) / 2)
        y := mainY + Floor((mainH - height) / 2)
        RepoSelectDialog.Show("w" width " h" height " x" x " y" y)
        return
    }
    RepoSelectDialog.Show("w" width " h" height)
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
    RepoAddDialog.BackColor := "F7F7F7"
    RepoAddDialog.MarginX := 12
    RepoAddDialog.MarginY := 10
    RepoAddDialog.SetFont("s8", "Microsoft YaHei UI")
    RepoAddDialog.OnEvent("Close", CloseRepoAddDialog)
    RepoAddDialog.OnEvent("Escape", CloseRepoAddDialog)

    RepoAddDialog.AddText("xm ym w380 h18", "请输入仓库路径：")
    RepoAddEdit := RepoAddDialog.AddEdit("xm y+6 w380 h24")
    RepoAddErrorText := RepoAddDialog.AddText("xm y+4 w380 h18 cRed Hidden", "")

    RepoAddDialog.AddText("xm y+4 w380 h18 c777777", "路径必须以 \need 或 \需求 结尾。")

    okBtn := RepoAddDialog.AddButton("xm+120 y+8 w72 h24 Default", "确认")
    okBtn.OnEvent("Click", OnRepoAddConfirm)

    cancelBtn := RepoAddDialog.AddButton("x+8 yp w72 h24", "取消")
    cancelBtn.OnEvent("Click", CloseRepoAddDialog)

    ShowRepoAddAtCenter()
    RepoAddEdit.Focus()
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

ShowRepoAddAtCenter() {
    global RepoAddDialog, MainGui

    width := 416
    height := 190
    if (MainGui) {
        WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
        x := mainX + Floor((mainW - width) / 2)
        y := mainY + Floor((mainH - height) / 2)
        RepoAddDialog.Show("w" width " h" height " x" x " y" y)
        return
    }
    RepoAddDialog.Show("w" width " h" height)
}
