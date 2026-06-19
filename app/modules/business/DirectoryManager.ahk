#Requires AutoHotkey v2.0

; 目录设置与管理

global DirectoryDialog := ""
global DirectoryDialogEdit := ""

SetCurrentDirAndOpenRequirement(dirPath) {
    global CurrentDir, AppConfig
    CurrentDir := NormalizePath(dirPath)

    if (MainGui) {
        UpdateCurrentPathDisplay()
        SetControlsEnabled(true)
        RefreshDirectoryStateUI()
    }

    filePath := CurrentDir "\需求.txt"
    existed := FileExist(filePath)
    if (!existed) {
        FileAppend("", filePath, "UTF-8")
    }

    if (AppConfig["OpenWithIdea"]) {
        OpenFileInIdea(filePath)
    }
}


PromptForDirectory(*) {
    global CurrentDir, DirectoryDialog, DirectoryDialogEdit, MainGui
    if DirectoryDialog {
        DirectoryDialog.Show()
        WinActivate("ahk_id " DirectoryDialog.Hwnd)
        return
    }

    defaultValue := CurrentDir != "" ? CurrentDir : ""
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
    global CurrentDir, DirectoryDialog, DirectoryDialogEdit
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

    CurrentDir := NormalizePath(rawPath)
    UpdateCurrentPathDisplay()
    SetControlsEnabled(true)
    RefreshDirectoryStateUI()
    CloseDirectoryDialog()
    ShowFeedback("当前目录已切换")
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
    global CurrentDir, CurrentPathText, CurrentDirStateMark
    if CurrentDir = "" {
        CurrentPathText.Text := "当前：未设置"
        CurrentDirStateMark.Text := ""
        return
    }

    split := StrSplit(CurrentDir, "\")
    dirName := split.Length ? split[split.Length] : CurrentDir
    CurrentPathText.Text := "当前：" dirName
    CurrentDirStateMark.Text := ""
}



IsResultIssueDir(dirPath) {
    global ResultIssueRootName
    if (dirPath = "" || !DirExist(dirPath)) {
        return false
    }

    SplitPath(dirPath, &dirName, &parentDir)
    if !RegExMatch(dirName, "^\d{2}$") {
        return false
    }

    SplitPath(parentDir, &parentName)
    return parentName = ResultIssueRootName
}



GetResultIssueRoot(themeDirPath) {
    global ResultIssueRootName
    return themeDirPath "\" ResultIssueRootName
}



GetNextIssueDirName(issueRootPath) {
    latest := 0
    Loop Files, issueRootPath "\*", "D" {
        dirName := A_LoopFileName
        if RegExMatch(dirName, "^\d{2}$") {
            version := dirName + 0
            if (version > latest) {
                latest := version
            }
        }
    }
    return Format("{:02}", latest + 1)
}


ShowFullPath(*) {
    global CurrentDir
    if CurrentDir = "" {
        ShowFeedback("请先设置当前主题目录", true)
        return
    }
    MsgBox(CurrentDir, "当前完整路径", "Iconi")
}



RefreshDirectoryStateUI() {
    global CurrentDir, SetDirectoryButton, ReturnParentButton, CreateIssueButton, NewThemeButton, CurrentDirStateMark

    if !SetDirectoryButton || !ReturnParentButton || !CreateIssueButton || !NewThemeButton || !CurrentDirStateMark {
        return
    }

    if (CurrentDir = "") {
        SetDirectoryButton.Visible := true
        ReturnParentButton.Visible := false
        CreateIssueButton.Visible := false
        NewThemeButton.Visible := false
        CurrentDirStateMark.Visible := false
        return
    }

    isIssueDir := IsResultIssueDir(CurrentDir)
    SetDirectoryButton.Visible := !isIssueDir
    ReturnParentButton.Visible := isIssueDir
    CreateIssueButton.Visible := !isIssueDir
    NewThemeButton.Visible := true
    CurrentDirStateMark.Visible := false
}


ReturnToThemeDir(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    if !IsResultIssueDir(CurrentDir) {
        ShowFeedback("当前不在问题子目录", true)
        return
    }

    CurrentDir := GetThemeRootFromIssueDir(CurrentDir)
    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    ShowFeedback("已返回主题目录")
}

GetThemeRootFromIssueDir(dirPath) {
    fileName := ""
    parentName := ""
    parentDir := ""
    themeDir := ""
    SplitPath(dirPath, &fileName, &parentDir)
    SplitPath(parentDir, &parentName, &themeDir)
    return themeDir
}
