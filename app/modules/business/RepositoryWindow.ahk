#Requires AutoHotkey v2.0

; 仓库管理窗口：仅归档功能

global RepoWindow := ""
global RepoWindowRepoList := ""
global RepoWindowThemeList := ""
global RepoWindowArchiveBtn := ""
global RepoWindowGuideText := ""
global RepoWindowCurrentRepo := ""

ShowRepoWindow(*) {
    global RepoWindow

    if (RepoWindow) {
        RepoWindow.Show()
        WinActivate("ahk_id " RepoWindow.Hwnd)
        return
    }
    CreateRepoWindow()
}

CreateRepoWindow() {
    global RepoWindow, RepoWindowRepoList, RepoWindowThemeList
    global RepoWindowArchiveBtn, RepoWindowGuideText, RepoWindowCurrentRepo, Repositories, MainGui

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+Resize +MinSize700x460"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    RepoWindow := Gui(dialogOptions, "仓库管理")
    RepoWindow.BackColor := GetDialogBackColor()
    RepoWindow.MarginX := 12
    RepoWindow.MarginY := 12
    RepoWindow.SetFont("s9", "Microsoft YaHei UI")
    RepoWindow.OnEvent("Close", CloseRepoWindow)
    RepoWindow.OnEvent("Escape", CloseRepoWindow)
    RepoWindow.OnEvent("Size", RepoWindowSize)

    ; 左侧列：名称 | 路径（扫视比对用；完整路径看右侧路径行）
    RepoWindow.AddText("Section xm ym w280 h20", "仓库列表")
    RepoWindowRepoList := RepoWindow.AddListView("xs y+4 w280 h444", ["名称", "路径"])
    RepoWindowRepoList.ModifyCol(1, 150)
    RepoWindowRepoList.ModifyCol(2, 116)
    RepoWindowRepoList.OnEvent("ItemSelect", OnRepoWindowSelect)

    for repo in Repositories {
        RepoWindowRepoList.Add(, repo["name"], repo["path"])
    }

    ; 右侧列：路径行（选中仓库的名称+完整路径，装不下时中间省略，双击复制完整路径）+ 主题列表
    RepoWindow.AddText("Section x+24 ys w572 h20", "主题目录列表")
    RepoWindowGuideText := RepoWindow.AddText("xs y+4 w572 h20", "先在左侧选择一个仓库")
    RepoWindowGuideText.OnEvent("DoubleClick", OnRepoPathLineDoubleClick)
    RepoWindowThemeList := RepoWindow.AddListView("xs y+4 w572 h420 Checked -Multi", ["主题名", "最近活跃"])
    RepoWindowThemeList.ModifyCol(1, 460)
    RepoWindowThemeList.ModifyCol(2, 100)

    ; 底部按钮
    RepoWindowArchiveBtn := RepoWindow.AddButton("x748 y518 w140 h30", "归档选中主题")
    RepoWindowArchiveBtn.OnEvent("Click", OnRepoWindowArchive)

    RefreshRepoThemeList()
    ; 省略 x/y：由系统屏幕居中，不再相对主面板定位
    RepoWindow.Show("w900 h560")
}

OnRepoWindowSelect(ctrl, item, selected) {
    global RepoWindowCurrentRepo

    if (!selected || item <= 0) {
        return
    }
    ; 第 2 列是路径：当前仓库仍存路径，下游归档/取名调用不变
    RepoWindowCurrentRepo := ctrl.GetText(item, 2)
    RefreshRepoThemeList()
}

RefreshRepoThemeList() {
    global RepoWindowThemeList, RepoWindowGuideText, RepoWindowCurrentRepo

    RepoWindowThemeList.Delete()
    if (RepoWindowCurrentRepo = "") {
        RepoWindowThemeList.Visible := false
        UpdateRepoPathLine()
        return
    }
    RepoWindowThemeList.Visible := true
    UpdateRepoPathLine()

    themes := GetRepoThemesWithActivity(RepoWindowCurrentRepo)
    for t in themes {
        dateText := t["lastActiveAt"] != "" ? SubStr(t["lastActiveAt"], 1, 10) : ""
        RepoWindowThemeList.Add(, t["name"], dateText)
    }
    RepoWindowThemeList.ModifyCol(1, "AutoHdr")
}

; 路径行：名称 + 完整路径，左列装不下的信息在这里看全
; 装不下时中间省略（像素级量宽，TextFit）；窗口拖宽后由 RepoWindowSize 调用重排
UpdateRepoPathLine() {
    global RepoWindowGuideText, RepoWindowCurrentRepo

    if (RepoWindowCurrentRepo = "") {
        RepoWindowGuideText.Text := "先在左侧选择一个仓库"
        return
    }
    fullText := GetRepoName(RepoWindowCurrentRepo) " — " RepoWindowCurrentRepo
    RepoWindowGuideText.Text := TruncateToWidth(fullText, RepoWindowGuideText.Hwnd)
}

; 双击路径行：复制完整路径（中间省略折损了"完整"，原文在剪贴板里一字不差）
OnRepoPathLineDoubleClick(*) {
    global RepoWindowCurrentRepo

    if (RepoWindowCurrentRepo != "") {
        A_Clipboard := RepoWindowCurrentRepo
    }
}

; 拖宽跟随：左列宽度固定、高度跟随；右列宽高跟随；按钮锚定右下
RepoWindowSize(thisGui, minMax, width, height) {
    global RepoWindowRepoList, RepoWindowThemeList, RepoWindowGuideText, RepoWindowArchiveBtn

    if (minMax = -1 || !RepoWindowRepoList) {
        return
    }

    margin := 12
    topOffset := 36        ; 边距 + 标题行
    bottomReserved := 60   ; 按钮行 + 边距
    leftW := 280
    gap := 24

    listH := height - topOffset - bottomReserved
    if (listH < 160) {
        listH := 160
    }
    rightX := margin + leftW + gap
    rightW := width - rightX - margin
    if (rightW < 240) {
        rightW := 240
    }

    RepoWindowRepoList.Move(margin, topOffset, leftW, listH)
    RepoWindowGuideText.Move(rightX, topOffset, rightW, 20)
    RepoWindowThemeList.Move(rightX, topOffset + 24, rightW, listH - 24)
    RepoWindowArchiveBtn.Move(width - margin - 140, height - margin - 30)
    UpdateRepoPathLine()
}

OnRepoWindowArchive(*) {
    global RepoWindowThemeList, RepoWindowCurrentRepo, RepoWindow

    if (RepoWindowCurrentRepo = "") {
        MsgBox("请先选择一个仓库", "AIProcess", "Iconx")
        return
    }

    ; 收集勾选的主题
    selectedNames := []
    row := 0
    Loop {
        row := RepoWindowThemeList.GetNext(row, "C")
        if (row = 0) {
            break
        }
        name := RepoWindowThemeList.GetText(row)
        selectedNames.Push(name)
    }

    if (selectedNames.Length = 0) {
        MsgBox("请先勾选要归档的主题", "AIProcess", "Iconx")
        return
    }

    ; 二次确认
    repoName := GetRepoName(RepoWindowCurrentRepo)
    confirmMsg := "确定归档以下 " selectedNames.Length " 个主题吗？`n`n"
    for name in selectedNames {
        confirmMsg .= "- " name "`n"
    }
    confirmMsg .= '`n归档后将移动到 "' repoName '\归档\" 目录，且无法撤销。'

    ownerHwnd := RepoWindow ? RepoWindow.Hwnd : 0
    result := MsgBox(confirmMsg, "确认归档", "Icon? OkCancel Owner" ownerHwnd)
    if (result != "OK") {
        return
    }

    ; 执行归档
    archiveResult := ArchiveThemes(RepoWindowCurrentRepo, selectedNames)

    ; 显示结果
    notifyMsg := "归档完成：成功 " archiveResult.success " 个"
    if (archiveResult.failed > 0) {
        notifyMsg .= "，失败 " archiveResult.failed " 个`n`n"
        for err in archiveResult.errors {
            notifyMsg .= err "`n"
        }
    }
    MsgBox(notifyMsg, "AIProcess", "Iconi Owner" ownerHwnd)

    RefreshRepoThemeList()
}

CloseRepoWindow(*) {
    global RepoWindow, RepoWindowRepoList, RepoWindowThemeList
    global RepoWindowArchiveBtn, RepoWindowGuideText, RepoWindowCurrentRepo

    if (RepoWindow) {
        RepoWindow.Destroy()
        RepoWindow := ""
    }
    RepoWindowRepoList := ""
    RepoWindowThemeList := ""
    RepoWindowArchiveBtn := ""
    RepoWindowGuideText := ""
    RepoWindowCurrentRepo := ""
}
