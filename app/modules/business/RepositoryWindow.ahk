#Requires AutoHotkey v2.0

; 仓库管理窗口：仅归档功能

global RepoWindow := ""
global RepoWindowRepoList := ""
global RepoWindowThemeList := ""
global RepoWindowArchiveBtn := ""
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
    global RepoWindowArchiveBtn, RepoWindowCurrentRepo, Repositories, MainGui

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+Resize"
    if (ownerHwnd) {
        dialogOptions .= " +Owner" ownerHwnd
    }

    RepoWindow := Gui(dialogOptions, "仓库管理")
    RepoWindow.BackColor := "F7F7F7"
    RepoWindow.MarginX := 10
    RepoWindow.MarginY := 10
    RepoWindow.SetFont("s8", "Microsoft YaHei UI")
    RepoWindow.OnEvent("Close", CloseRepoWindow)
    RepoWindow.OnEvent("Escape", CloseRepoWindow)

    ; 左侧列
    RepoWindow.AddText("Section xm ym w220 h18", "仓库列表")
    RepoWindowRepoList := RepoWindow.AddListBox("xs y+4 w220 h320")
    RepoWindowRepoList.OnEvent("Change", OnRepoWindowSelect)

    for repo in Repositories {
        RepoWindowRepoList.Add([repo["path"]])
    }

    ; 右侧列
    RepoWindow.AddText("Section x+24 ys w460 h18", "主题目录列表")
    RepoWindowThemeList := RepoWindow.AddListView("xs y+4 w460 h320 Checked -Multi", ["主题名"])
    RepoWindowThemeList.ModifyCol(1, 450)

    ; 底部按钮
    RepoWindowArchiveBtn := RepoWindow.AddButton("xm+280 y+10 w120 h24", "归档选中主题")
    RepoWindowArchiveBtn.OnEvent("Click", OnRepoWindowArchive)

    width := 716
    height := 420
    x := ""
    y := ""
    if (MainGui) {
        try {
            WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
            x := mainX + Floor((mainW - width) / 2)
            y := mainY + Floor((mainH - height) / 2)
        }
    }
    if (x != "") {
        RepoWindow.Show("w" width " h" height " x" x " y" y)
    } else {
        RepoWindow.Show("w" width " h" height)
    }
}

OnRepoWindowSelect(*) {
    global RepoWindowRepoList, RepoWindowCurrentRepo

    RepoWindowCurrentRepo := RepoWindowRepoList.Text
    RefreshRepoThemeList()
}

RefreshRepoThemeList() {
    global RepoWindowThemeList, RepoWindowCurrentRepo

    RepoWindowThemeList.Delete()
    if (RepoWindowCurrentRepo = "") {
        return
    }

    themes := GetRepoThemes(RepoWindowCurrentRepo)
    for name in themes {
        RepoWindowThemeList.Add(, name)
    }
    RepoWindowThemeList.ModifyCol(1, "AutoHdr")
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
    global RepoWindowArchiveBtn, RepoWindowCurrentRepo

    if (RepoWindow) {
        RepoWindow.Destroy()
        RepoWindow := ""
    }
    RepoWindowRepoList := ""
    RepoWindowThemeList := ""
    RepoWindowArchiveBtn := ""
    RepoWindowCurrentRepo := ""
}
