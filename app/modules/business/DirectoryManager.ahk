#Requires AutoHotkey v2.0

; 目录设置与管理

global DirectoryDialog := ""
global DirectoryDialogEdit := ""

SetCurrentDirAndOpenRequirement(dirPath) {
    ; 自动仓库关联：标准路径且在仓库列表中不存在 → 自动添加
    if (IsStandardRepoPath(dirPath)) {
        repo := FindRepoByThemePath(dirPath)
        if (repo = "") {
            repoPath := ExtractRepoPath(dirPath)
            if (repoPath != "") {
                AddRepository(repoPath)
            }
        }
    }

    SetCurrentDir(NormalizePath(dirPath))
    SaveWindowSession(GetActiveWindowId())
    LogThemeIndex(GetCurrentDir(), "右键")

    if (MainGui) {
        UpdateCurrentPathDisplay()
        SetControlsEnabled(true)
        RefreshDirectoryStateUI()
    }

    filePath := GetCurrentDir() "\需求.txt"
    existed := FileExist(filePath)
    if (!existed) {
        FileAppend("", filePath, "UTF-8")
    }

    EditorOpener.Open(filePath)
}


PromptForDirectory(*) {
    global DirectoryDialog, DirectoryDialogEdit, MainGui
    if DirectoryDialog {
        DirectoryDialog.Show()
        WinActivate("ahk_id " DirectoryDialog.Hwnd)
        return
    }

    defaultValue := GetCurrentDir() != "" ? GetCurrentDir() : ""
    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        dialogOptions .= " +Owner" ownerHwnd
    }

    DirectoryDialog := Gui(dialogOptions, "设置目录")
    DirectoryDialog.BackColor := "F7F7F7"
    DirectoryDialog.MarginX := 12
    DirectoryDialog.MarginY := 10
    DirectoryDialog.SetFont("s8", "Microsoft YaHei UI")
    DirectoryDialog.OnEvent("Close", CloseDirectoryDialog)
    DirectoryDialog.OnEvent("Escape", CloseDirectoryDialog)

    DirectoryDialog.AddText("xm ym w336 h18", "当前主题目录")
    DirectoryDialogEdit := DirectoryDialog.AddEdit("xm y+6 w336 h24", defaultValue)

    okButton := DirectoryDialog.AddButton("xm y+10 w72 h24 Default", "确定")
    okButton.OnEvent("Click", SubmitDirectoryDialog)

    cancelButton := DirectoryDialog.AddButton("x+8 yp w72 h24", "取消")
    cancelButton.OnEvent("Click", CloseDirectoryDialog)

    ShowDirectoryDialog()
    DirectoryDialogEdit.Focus()
}



ShowDirectoryDialog() {
    global DirectoryDialog, MainGui
    if !DirectoryDialog {
        return
    }

    width := 360
    height := 104
    if MainGui {
        WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
        x := mainX + Floor((mainW - width) / 2)
        y := mainY + Floor((mainH - height) / 2)
        DirectoryDialog.Show("w" width " h" height " x" x " y" y)
        return
    }

    DirectoryDialog.Show("w" width " h" height)
}



SubmitDirectoryDialog(*) {
    global DirectoryDialog, DirectoryDialogEdit
    if !DirectoryDialog {
        return
    }

    rawPath := Trim(DirectoryDialogEdit.Value)
    if rawPath = "" {
        ShowFeedback("请先输入目录路径", true)
        return
    }

    if !DirExist(rawPath) {
        ShowFeedback("路径不是有效目录", true)
        return
    }

    SetCurrentDir(NormalizePath(rawPath))
    SaveWindowSession(GetActiveWindowId())
    UpdateCurrentPathDisplay()
    SetControlsEnabled(true)
    RefreshDirectoryStateUI()
    CloseDirectoryDialog()
    ShowFeedback("当前目录已切换")
    LogThemeIndex(GetCurrentDir(), "面板")
}



CloseDirectoryDialog(*) {
    global DirectoryDialog, DirectoryDialogEdit
    if !DirectoryDialog {
        return
    }

    DirectoryDialog.Destroy()
    DirectoryDialog := ""
    DirectoryDialogEdit := ""
}



UpdateCurrentPathDisplay() {
    global CurrentPathText, CurrentDirStateMark, CurrentPathHwnd
    currentDir := GetCurrentDir()
    if currentDir = "" {
        CurrentPathText.Text := "未设置"
        CurrentDirStateMark.Text := ""
        return
    }

    dirName := ExtractFileName(currentDir)
    if (dirName = "") {
        dirName := currentDir
    }

    label := dirName
    keepTail := ""
    if DomainConventions.IsResultIssueDir(currentDir) {
        themeName := ExtractFileName(DomainConventions.GetThemeRootFromIssueDir(currentDir))
        if (themeName != "") {
            label := themeName
            keepTail := "/" dirName
        }
    }

    CurrentPathText.Text := TruncateKeepTail(label, keepTail, CurrentPathHwnd)
    CurrentDirStateMark.Text := ""
}


ShowFullPath(*) {
    currentDir := GetCurrentDir()
    if currentDir = "" {
        ShowFeedback("请先设置当前主题目录", true)
        return
    }
    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    MsgBox(currentDir, "当前完整路径", "Iconi Owner" ownerHwnd)
}



RefreshDirectoryStateUI() {
    global SetDirectoryButton, ReturnParentButton, CreateIssueButton, NewThemeButton, CurrentDirStateMark

    if !SetDirectoryButton || !ReturnParentButton || !CreateIssueButton || !NewThemeButton || !CurrentDirStateMark {
        return
    }

    currentDir := GetCurrentDir()
    if (currentDir = "") {
        SetDirectoryButton.Visible := true
        ReturnParentButton.Visible := false
        CreateIssueButton.Visible := false
        NewThemeButton.Visible := false
        CurrentDirStateMark.Visible := false
        return
    }

    isIssueDir := DomainConventions.IsResultIssueDir(currentDir)
    SetDirectoryButton.Visible := !isIssueDir
    ReturnParentButton.Visible := isIssueDir
    CreateIssueButton.Visible := !isIssueDir
    NewThemeButton.Visible := true
    CurrentDirStateMark.Visible := false
}


ReturnToThemeDir(*) {
    if !ActionGuard.EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    if !DomainConventions.IsResultIssueDir(currentDir) {
        ShowFeedback("当前不在问题子目录", true)
        return
    }

    SetCurrentDir(DomainConventions.GetThemeRootFromIssueDir(currentDir))
    SaveWindowSession(GetActiveWindowId())
    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    ShowFeedback("已返回主题目录")
}
