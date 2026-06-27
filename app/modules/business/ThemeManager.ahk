#Requires AutoHotkey v2.0

; 主题与问题目录管理

global NewThemeDialog := ""
global NewThemeDialogEdit := ""
global NewThemeDialogErrorText := ""

global ResultIssueRootName := "结果微调"
global ResultIssueStateMark := "↳"


CreateNewTheme(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    if IsResultIssueDir(currentDir) {
        parentDir := ""
        SplitPath(currentDir,, &parentDir)
        issueRoot := parentDir
        DirCreate(issueRoot)
        nextIssueDirName := GetNextIssueDirName(issueRoot)
        newDir := issueRoot "\" nextIssueDirName
        DirCreate(newDir)
        SwitchToNewTheme(newDir)
        return
    }

    ShowNewThemeDialog()
}




ShowNewThemeDialog() {
    global MainGui, NewThemeDialog, NewThemeDialogEdit, NewThemeDialogErrorText

    if NewThemeDialog {
        NewThemeDialogEdit.Value := ""
        NewThemeDialogErrorText.Text := ""
        NewThemeDialogErrorText.Visible := false
        NewThemeDialog.Show()
        WinActivate("ahk_id " NewThemeDialog.Hwnd)
        NewThemeDialogEdit.Focus()
        return
    }

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        dialogOptions .= " +Owner" ownerHwnd
    }

    NewThemeDialog := Gui(dialogOptions, "新建主题")
    NewThemeDialog.BackColor := "F7F7F7"
    NewThemeDialog.MarginX := 12
    NewThemeDialog.MarginY := 10
    NewThemeDialog.SetFont("s8", "Microsoft YaHei UI")
    NewThemeDialog.OnEvent("Close", CloseNewThemeDialog)
    NewThemeDialog.OnEvent("Escape", CloseNewThemeDialog)

    NewThemeDialog.AddText("xm ym w336 h18", "新主题目录名称")
    NewThemeDialogEdit := NewThemeDialog.AddEdit("xm y+6 w336 h24", "")
    NewThemeDialogErrorText := NewThemeDialog.AddText("xm y+4 w336 h18 cRed Hidden", "")

    okButton := NewThemeDialog.AddButton("xm y+8 w72 h24 Default", "确定")
    okButton.OnEvent("Click", SubmitNewThemeDialog)

    cancelButton := NewThemeDialog.AddButton("x+8 yp w72 h24", "取消")
    cancelButton.OnEvent("Click", CloseNewThemeDialog)

    ShowNewThemeDialogAtCenter()
    NewThemeDialogEdit.Focus()
}



ShowNewThemeDialogAtCenter() {
    global NewThemeDialog, MainGui
    if !NewThemeDialog {
        return
    }

    width := 360
    height := 130
    if MainGui {
        WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
        x := mainX + Floor((mainW - width) / 2)
        y := mainY + Floor((mainH - height) / 2)
        NewThemeDialog.Show("w" width " h" height " x" x " y" y)
        return
    }

    NewThemeDialog.Show("w" width " h" height)
}



SubmitNewThemeDialog(*) {
    global NewThemeDialog, NewThemeDialogEdit, NewThemeDialogErrorText
    if !NewThemeDialog {
        return
    }

    themeName := Trim(NewThemeDialogEdit.Value)
    if (themeName = "") {
        ShowNewThemeDialogError("目录名不能为空")
        return
    }
    if !IsValidDirName(themeName) {
        ShowNewThemeDialogError("目录名包含非法字符")
        return
    }

    currentDir := GetCurrentDir()
    parentDir := ""
    SplitPath(currentDir,, &parentDir)
    newDir := parentDir "\" themeName
    if DirExist(newDir) {
        ShowNewThemeDialogError("目录已存在：" themeName)
        return
    }

    DirCreate(newDir)
    CloseNewThemeDialog()
    SwitchToNewTheme(newDir)
}



CloseNewThemeDialog(*) {
    global NewThemeDialog, NewThemeDialogEdit, NewThemeDialogErrorText
    if !NewThemeDialog {
        return
    }
    NewThemeDialog.Destroy()
    NewThemeDialog := ""
    NewThemeDialogEdit := ""
    NewThemeDialogErrorText := ""
}


CreateAndEnterIssueDir(*) {
    global ResultIssueRootName
    if !EnsureCurrentDirectory() {
        return
    }

    currentDir := GetCurrentDir()
    if IsResultIssueDir(currentDir) {
        ShowFeedback("请先返回主题目录", true)
        return
    }

    issueRoot := GetResultIssueRoot(currentDir)
    DirCreate(issueRoot)
    nextIssueDirName := GetNextIssueDirName(issueRoot)
    nextIssueDirPath := issueRoot "\" nextIssueDirName
    DirCreate(nextIssueDirPath)

    SetCurrentDir(nextIssueDirPath)
    SaveWindowSession(GetActiveWindowId())
    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    ShowFeedback("已进入问题目录：" nextIssueDirName)

    LogActivity("建问题", "")
    CreateRequirementFile()
}

ShowNewThemeDialogError(message) {
    global NewThemeDialogErrorText
    if !NewThemeDialogErrorText {
        return
    }
    NewThemeDialogErrorText.Text := message
    NewThemeDialogErrorText.Visible := true
}



SwitchToNewTheme(newDir) {
    SetCurrentDir(newDir)
    SaveWindowSession(GetActiveWindowId())
    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    LogThemeIndex(newDir, "新主题")
    CreateRequirementFile()
}

IsValidDirName(name) {
    if (name = "" || name = "." || name = "..") {
        return false
    }
    illegal := "\/:*?<>|"
    Loop Parse, illegal {
        if InStr(name, A_LoopField) {
            return false
        }
    }
    if InStr(name, Chr(34)) {
        return false
    }
    return true
}

