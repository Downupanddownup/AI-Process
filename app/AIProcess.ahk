#Requires AutoHotkey v2.0
#SingleInstance Force

Persistent

global AppRoot := A_ScriptDir
global ConfigDir := AppRoot "\config"
global TemplateDir := AppRoot "\templates"
global SettingsFile := ConfigDir "\settings.ini"

global AppConfig := Map()
global CurrentDir := ""
global CurrentPathText := ""
global CurrentPathHwnd := 0
global CurrentDirStateMark := ""
global DirectoryDialog := ""
global DirectoryDialogEdit := ""
global NewThemeDialog := ""
global NewThemeDialogEdit := ""
global NewThemeDialogErrorText := ""
global OpenWithIdeaCheckbox := ""
global NoModifyPromptCheckbox := ""
global ReplyImplementationTailCheckbox := ""
global SetDirectoryButton := ""
global ReturnParentButton := ""
global CreateIssueButton := ""
global NewThemeButton := ""
global AutoHideCheckbox := ""
global CreateRequirementButton := ""
global CopyRequirementPromptButton := ""
global CreateReplyButton := ""
global CopyReplyPromptButton := ""
global CopyRelationsButton := ""
global CopyExecuteButton := ""
global ExecuteStrategyDropdown := ""
global MainGui := ""
global HoverTooltipVisible := false
global ResultIssueRootName := "结果微调"
global ResultIssueStateMark := "↳"
global ExecuteStrategies := [
    Map("key", "direct", "label", "直接", "template", "execute\direct.txt", "feedback", "执行提示词已复制"),
    Map("key", "ai_judge", "label", "AI判", "template", "execute\ai_judge.txt", "feedback", "AI判断提示词已复制"),
    Map("key", "steps_file", "label", "步文", "template", "execute\steps_file.txt", "feedback", "步骤文档提示词已复制"),
    Map("key", "steps_dir", "label", "步目", "template", "execute\steps_dir.txt", "feedback", "步骤目录提示词已复制")
]

EnsureDefaultFiles()
LoadConfig()
CreateTray()
CreateMainGui()
RegisterGlobalHotkey()
if AppConfig["StartVisible"] {
    ShowMainWindow()
}

OnMessage(0x200, OnMouseMove)
OnMessage(0x05, OnWindowSize)

return

EnsureDefaultFiles() {
    global ConfigDir, TemplateDir, SettingsFile
    DirCreate(ConfigDir)
    DirCreate(TemplateDir)
    executeTemplateDir := TemplateDir "\execute"
    DirCreate(executeTemplateDir)

    if !FileExist(SettingsFile) {
        IniWrite("F2", SettingsFile, "App", "Hotkey")
        IniWrite("210", SettingsFile, "Window", "Width")
        IniWrite("185", SettingsFile, "Window", "Height")
        IniWrite("1", SettingsFile, "Behavior", "AlwaysOnTop")
        IniWrite("1", SettingsFile, "Behavior", "StartVisible")
        IniWrite("1", SettingsFile, "Behavior", "CloseToTray")
        IniWrite("1", SettingsFile, "Behavior", "MinimizeToTray")
        IniWrite("0", SettingsFile, "Behavior", "AutoHideAfterCreate")
        IniWrite("1", SettingsFile, "Editor", "OpenWithIdea")
        IniWrite("1", SettingsFile, "Prompt", "AppendNoModifyPrompt")
        IniWrite("idea64.exe", SettingsFile, "Editor", "IdeaCommand")
    }

    if (IniRead(SettingsFile, "Prompt", "AppendNoModifyPrompt", "") = "") {
        IniWrite("1", SettingsFile, "Prompt", "AppendNoModifyPrompt")
    }

    if (IniRead(SettingsFile, "Behavior", "AutoHideAfterCreate", "") = "") {
        IniWrite("0", SettingsFile, "Behavior", "AutoHideAfterCreate")
    }

    requirementTemplate := TemplateDir "\requirement_prompt.txt"
    if !FileExist(requirementTemplate) {
        FileAppend(
        "这是一个需求文件，请你查看这个文件：{{filePath}}。如果你有新的想法或问题，请创建 v1.md；如果没有新的问题，请创建 实施文档.md。"
        , requirementTemplate, "UTF-8")
    }

    replyTemplate := TemplateDir "\reply_prompt.txt"
    if !FileExist(replyTemplate) {
        FileAppend(
        "这是一个回复文件，请你查看这个文件：{{filePath}}。如果你还有新的想法或问题，请创建 {{nextVersionFile}}。"
        , replyTemplate, "UTF-8")
    }

    replyImplementationTailTemplate := TemplateDir "\reply_prompt_impl_tail.txt"
    if !FileExist(replyImplementationTailTemplate) {
        FileAppend(
        "如果没有新的问题，请创建 实施文档.md。"
        , replyImplementationTailTemplate, "UTF-8")
    }

    relationTemplate := TemplateDir "\context_relation.txt"
    if !FileExist(relationTemplate) {
        FileAppend(
        "当前目录中的 需求.txt 是原始需求说明；vX.md 是 AI 沟通过程中的版本文档；对vX的回复.txt 是用户对对应版本的回复；实施文档.md 是整个需求沟通收敛后的最终结论文件，也是后续正式实施时最重要的执行依据。这些文件按时间顺序构成完整沟通过程。新会话接管时，应优先阅读这些文件并完成上下文重建。"
        , relationTemplate, "UTF-8")
    }

    executeDirectTemplate := executeTemplateDir "\direct.txt"
    if !FileExist(executeDirectTemplate) {
        FileAppend(
        "请你根据当前的实施文档：{{filePath}}，修改正式代码和文件，完成整个方案的落地。"
        , executeDirectTemplate, "UTF-8")
    }

    executeAiJudgeTemplate := executeTemplateDir "\ai_judge.txt"
    if !FileExist(executeAiJudgeTemplate) {
        FileAppend(
        "请你查看当前的实施文档：{{filePath}}。`n`n请先判断该方案的内容复杂度，是否需要拆解为多个实施步骤：`n- 如果不需要拆解，请直接修改正式代码和文件，完成整个方案的落地。`n- 如果需要拆解，请在当前目录下按照合理的执行顺序创建多个步骤 md 文件（格式如 01-xxx.md、02-xxx.md 等），确保所有步骤合起来覆盖实施文档的全部内容。步骤文档写完后请先停下来，告诉我已经写好，等待我验收。不要进入步骤目录模式，也不要在未获得我确认前直接修改正式代码。"
        , executeAiJudgeTemplate, "UTF-8")
    }

    executeStepsFileTemplate := executeTemplateDir "\steps_file.txt"
    if !FileExist(executeStepsFileTemplate) {
        FileAppend(
        "请你查看当前的实施文档：{{filePath}}。`n`n请不要直接修改正式代码。请在当前目录下按照合理的执行顺序创建多个步骤 md 文件（格式如 01-xxx.md、02-xxx.md 等），确保所有步骤合起来覆盖实施文档的全部内容。步骤文档写完后请先停下来，告诉我已经写好，等待我验收。"
        , executeStepsFileTemplate, "UTF-8")
    }

    executeStepsDirTemplate := executeTemplateDir "\steps_dir.txt"
    if !FileExist(executeStepsDirTemplate) {
        FileAppend(
        "请你查看当前的实施文档：{{filePath}}。`n`n请不要直接修改正式代码。请在当前目录下按照合理的执行顺序创建多个步骤目录，目录名格式如 01-xxx、02-xxx 等，并在每个目录中创建一个与目录同名的 md 文档（例如 01-xxx\\01-xxx.md）。确保所有步骤目录和文档合起来覆盖实施文档的全部内容。写完后请先停下来，告诉我已经写好，等待我验收。"
        , executeStepsDirTemplate, "UTF-8")
    }

    noModifyTemplate := TemplateDir "\no_modify_prompt.txt"
    if !FileExist(noModifyTemplate) {
        FileAppend(
        "补充约束：当前阶段不要修改正式代码，不要修改已有正式文件。你可以按当前要求创建新的 vX.md 或 实施文档.md；如果你认为需要进入正式修改阶段，请先明确说明并等待确认。"
        , noModifyTemplate, "UTF-8")
    }
}

LoadConfig() {
    global AppConfig, SettingsFile
    AppConfig := Map()
    AppConfig["Hotkey"] := IniRead(SettingsFile, "App", "Hotkey", "F2")
    AppConfig["WindowWidth"] := IniRead(SettingsFile, "Window", "Width", "210") + 0
    AppConfig["WindowHeight"] := IniRead(SettingsFile, "Window", "Height", "150") + 0
    if (AppConfig["WindowHeight"] < 180) {
        AppConfig["WindowHeight"] := 180
    }
    AppConfig["AlwaysOnTop"] := IniRead(SettingsFile, "Behavior", "AlwaysOnTop", "1") = "1"
    AppConfig["StartVisible"] := IniRead(SettingsFile, "Behavior", "StartVisible", "1") = "1"
    AppConfig["CloseToTray"] := IniRead(SettingsFile, "Behavior", "CloseToTray", "1") = "1"
    AppConfig["MinimizeToTray"] := IniRead(SettingsFile, "Behavior", "MinimizeToTray", "1") = "1"
    AppConfig["AutoHideAfterCreate"] := IniRead(SettingsFile, "Behavior", "AutoHideAfterCreate", "0") = "1"
    AppConfig["OpenWithIdea"] := IniRead(SettingsFile, "Editor", "OpenWithIdea", "1") = "1"
    AppConfig["AppendNoModifyPrompt"] := IniRead(SettingsFile, "Prompt", "AppendNoModifyPrompt", "1") = "1"
    AppConfig["IdeaCommand"] := IniRead(SettingsFile, "Editor", "IdeaCommand", "idea64.exe")
}

CreateTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("显示", ShowMainWindow)
    A_TrayMenu.Add("退出", ExitApplication)
    A_TrayMenu.Default := "显示"
    TraySetIcon("shell32.dll", 44)
}

CreateMainGui() {
    global MainGui, CurrentPathText, CurrentPathHwnd, CurrentDirStateMark, OpenWithIdeaCheckbox, NoModifyPromptCheckbox, ReplyImplementationTailCheckbox, AutoHideCheckbox, AppConfig
    global SetDirectoryButton, ReturnParentButton, CreateIssueButton, NewThemeButton
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyExecuteButton, ExecuteStrategyDropdown, ExecuteStrategies
    actionButtonWidth := 60
    actionButtonHeight := 24
    actionGap := 6

    guiOptions := "+Resize -MaximizeBox +MinimizeBox"
    if AppConfig["AlwaysOnTop"] {
        guiOptions .= " +AlwaysOnTop"
    }

    MainGui := Gui(guiOptions, "AIProcess 快捷面板")
    MainGui.BackColor := "F7F7F7"
    MainGui.MarginX := 8
    MainGui.MarginY := 8
    MainGui.SetFont("s8", "Microsoft YaHei UI")
    MainGui.OnEvent("Close", HandleClose)
    MainGui.OnEvent("Escape", HideToTray)

    CurrentPathText := MainGui.AddText("xm ym+2 w126 h18 +0x200", "当前：未设置")
    CurrentPathText.OnEvent("Click", ShowFullPath)
    CurrentPathHwnd := CurrentPathText.Hwnd
    CurrentDirStateMark := MainGui.AddText("x+0 yp w0 h18 Hidden", "")

    SetDirectoryButton := MainGui.AddButton("x148 ym w54 h22", "设目录")
    SetDirectoryButton.OnEvent("Click", PromptForDirectory)
    ReturnParentButton := MainGui.AddButton("x148 ym w54 h22 Hidden", "返")
    ReturnParentButton.OnEvent("Click", ReturnToThemeDir)

    NewThemeButton := MainGui.AddButton("xm y+6 w54 h22", "新主题")
    NewThemeButton.OnEvent("Click", CreateNewTheme)

    CreateIssueButton := MainGui.AddButton("x+6 yp w54 h22", "建问题")
    CreateIssueButton.OnEvent("Click", CreateAndEnterIssueDir)

    OpenWithIdeaCheckbox := MainGui.AddCheckbox("xm y+6", "IDEA开")
    OpenWithIdeaCheckbox.Value := AppConfig["OpenWithIdea"] ? 1 : 0
    OpenWithIdeaCheckbox.OnEvent("Click", ToggleIdeaOpen)

    NoModifyPromptCheckbox := MainGui.AddCheckbox("x+4 yp", "禁改正式")
    NoModifyPromptCheckbox.Value := AppConfig["AppendNoModifyPrompt"] ? 1 : 0
    NoModifyPromptCheckbox.OnEvent("Click", ToggleNoModifyPrompt)

    AutoHideCheckbox := MainGui.AddCheckbox("x+4 yp", "自隐藏")
    AutoHideCheckbox.Value := AppConfig["AutoHideAfterCreate"] ? 1 : 0
    AutoHideCheckbox.OnEvent("Click", ToggleAutoHide)

    CreateRequirementButton := MainGui.AddButton("xm y+8 w" actionButtonWidth " h" actionButtonHeight, "建需求")
    CreateRequirementButton.OnEvent("Click", CreateRequirementFile)

    CopyRequirementPromptButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复需求")
    CopyRequirementPromptButton.OnEvent("Click", CopyRequirementPrompt)

    CreateReplyButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "建回复")
    CreateReplyButton.OnEvent("Click", CreateReplyFile)

    CopyReplyPromptButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复回复")
    CopyReplyPromptButton.OnEvent("Click", CopyReplyPrompt)

    ReplyImplementationTailCheckbox := MainGui.AddCheckbox("x+" actionGap " yp+4 w28 h18 Checked", "实")

    CopyRelationsButton := MainGui.AddButton("xm y+6 w" actionButtonWidth " h" actionButtonHeight, "复关系")
    CopyRelationsButton.OnEvent("Click", CopyContextRelations)

    CopyExecuteButton := MainGui.AddButton("x+" actionGap " yp w" actionButtonWidth " h" actionButtonHeight, "复执行")
    CopyExecuteButton.OnEvent("Click", CopyExecutePrompt)

    executeStrategyOptions := BuildExecuteStrategyOptions()
    ExecuteStrategyDropdown := MainGui.AddDropDownList("x+" actionGap " yp w44", executeStrategyOptions)
    ExecuteStrategyDropdown.Choose(2)

    SetControlsEnabled(false)
    RefreshDirectoryStateUI()
}

RegisterGlobalHotkey() {
    global AppConfig
    try {
        Hotkey(AppConfig["Hotkey"], ToggleMainWindow)
    } catch Error as err {
        MsgBox("全局快捷键注册失败：" AppConfig["Hotkey"] "`n" err.Message, "AIProcess", "Iconx")
    }
}

HandleClose(*) {
    global AppConfig
    if AppConfig["CloseToTray"] {
        HideToTray()
        return
    }
    ExitApplication()
}

ShowMainWindow(*) {
    global MainGui, AppConfig
    width := AppConfig["WindowWidth"]
    height := AppConfig["WindowHeight"]

    if !MainGui {
        return
    }

    screenWidth := A_ScreenWidth
    screenHeight := A_ScreenHeight
    x := Max(0, Floor((screenWidth - width) / 2))
    y := Max(0, Floor((screenHeight - height) / 2))
    MainGui.Show("w" width " h" height " x" x " y" y)
    if AppConfig["AlwaysOnTop"] {
        WinSetAlwaysOnTop(1, "ahk_id " MainGui.Hwnd)
    }
    WinActivate("ahk_id " MainGui.Hwnd)
}

ToggleMainWindow(*) {
    global MainGui
    ShowMainWindow()
}

HideToTray(*) {
    global MainGui
    MainGui.Hide()
    ToolTip("AIProcess 已隐藏到托盘")
    SetTimer(() => ToolTip(), -1200)
}

MaybeAutoHide() {
    global AutoHideCheckbox
    if (AutoHideCheckbox && AutoHideCheckbox.Value = 1) {
        HideToTray()
    }
}

ExitApplication(*) {
    ExitApp()
}

OnWindowSize(wParam, lParam, msg, hwnd) {
    global MainGui, AppConfig
    if !MainGui || hwnd != MainGui.Hwnd {
        return
    }

    if (wParam = 1 && AppConfig["MinimizeToTray"]) {
        SetTimer(HideToTray, -10)
    }
}

OnMouseMove(wParam, lParam, msg, hwnd) {
    global CurrentDir, CurrentPathHwnd, HoverTooltipVisible

    if (hwnd = CurrentPathHwnd && CurrentDir != "") {
        ToolTip(CurrentDir)
        HoverTooltipVisible := true
        return
    }

    if HoverTooltipVisible {
        ToolTip()
        HoverTooltipVisible := false
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

SetControlsEnabled(enabled) {
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyExecuteButton, ExecuteStrategyDropdown, ReplyImplementationTailCheckbox, CreateIssueButton, ReturnParentButton
    global NewThemeButton, AutoHideCheckbox
    CreateRequirementButton.Enabled := enabled
    CopyRequirementPromptButton.Enabled := enabled
    CreateReplyButton.Enabled := enabled
    CopyReplyPromptButton.Enabled := enabled
    ReplyImplementationTailCheckbox.Enabled := enabled
    CopyRelationsButton.Enabled := enabled
    CopyExecuteButton.Enabled := enabled
    ExecuteStrategyDropdown.Enabled := enabled
    CreateIssueButton.Enabled := enabled
    ReturnParentButton.Enabled := enabled
    NewThemeButton.Enabled := enabled
    AutoHideCheckbox.Enabled := enabled
}

ToggleIdeaOpen(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["OpenWithIdea"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Editor", "OpenWithIdea")
    ShowFeedback(checked ? "已开启 IDEA 打开" : "已关闭 IDEA 打开")
}

ToggleNoModifyPrompt(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["AppendNoModifyPrompt"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Prompt", "AppendNoModifyPrompt")
    ShowFeedback(checked ? "已开启禁改正式" : "已关闭禁改正式")
}

ToggleAutoHide(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["AutoHideAfterCreate"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Behavior", "AutoHideAfterCreate")
    ShowFeedback(checked ? "已开启自动隐藏" : "已关闭自动隐藏")
}

CreateRequirementFile(*) {
    global CurrentDir, AppConfig
    if !EnsureCurrentDirectory() {
        return
    }

    filePath := CurrentDir "\需求.txt"
    existed := FileExist(filePath)
    if !existed {
        FileAppend("", filePath, "UTF-8")
        ShowFeedback("已创建：需求.txt")
    } else {
        ShowFeedback("文件已存在：需求.txt", true)
    }

    if AppConfig["OpenWithIdea"] {
        OpenFileInIdea(filePath)
    }

    MaybeAutoHide()
}

CreateReplyFile(*) {
    global CurrentDir, AppConfig
    if !EnsureCurrentDirectory() {
        return
    }

    latestVersion := GetLatestVersionNumber(CurrentDir)
    if (latestVersion = 0) {
        ShowFeedback("当前目录下未找到 vX.md 文件", true)
        return
    }

    replyPath := CurrentDir "\对v" latestVersion "的回复.txt"
    existed := FileExist(replyPath)
    if !existed {
        FileAppend("", replyPath, "UTF-8")
        ShowFeedback("已创建：" ExtractFileName(replyPath))
    } else {
        ShowFeedback("文件已存在：" ExtractFileName(replyPath), true)
    }

    if AppConfig["OpenWithIdea"] {
        OpenFileInIdea(replyPath)
    }

    MaybeAutoHide()
}

CopyRequirementPrompt(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    content := LoadTemplate("requirement_prompt.txt")
    content := StrReplace(content, "{{filePath}}", CurrentDir "\需求.txt")
    content := AppendNoModifyPromptIfNeeded(content)
    A_Clipboard := content
    ShowFeedback("需求提示词已复制")

    MaybeAutoHide()
}

CopyReplyPrompt(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    latestVersion := GetLatestVersionNumber(CurrentDir)
    if (latestVersion = 0) {
        ShowFeedback("当前目录下未找到 vX.md 文件", true)
        return
    }

    currentReplyFile := CurrentDir "\对v" latestVersion "的回复.txt"
    nextVersionFile := "v" (latestVersion + 1) ".md"
    content := LoadTemplate("reply_prompt.txt")
    content := StrReplace(content, "{{filePath}}", currentReplyFile)
    content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
    content := AppendReplyImplementationTailIfNeeded(content)
    content := AppendNoModifyPromptIfNeeded(content)
    A_Clipboard := content
    ShowFeedback("回复提示词已复制")

    MaybeAutoHide()
}

CopyContextRelations(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    content := BuildContextRelationsText()
    content := AppendNoModifyPromptIfNeeded(content)
    A_Clipboard := content
    ShowFeedback("文件关系说明已复制")

    MaybeAutoHide()
}

CopyExecutePrompt(*) {
    global CurrentDir, ExecuteStrategyDropdown
    if !EnsureCurrentDirectory() {
        return
    }

    implementationPath := CurrentDir "\实施文档.md"
    if !FileExist(implementationPath) {
        ShowFeedback("当前目录下未找到 实施文档.md", true)
        return
    }

    selectedStrategy := GetSelectedExecuteStrategy()
    strategyMeta := GetExecuteStrategyMeta(selectedStrategy)
    content := LoadTemplate(strategyMeta["template"])
    content := StrReplace(content, "{{filePath}}", implementationPath)
    A_Clipboard := content
    ShowFeedback(strategyMeta["feedback"])

    MaybeAutoHide()
}

EnsureCurrentDirectory() {
    global CurrentDir
    if CurrentDir = "" {
        ShowFeedback("请先设置当前主题目录", true)
        return false
    }
    return true
}

OpenFileInIdea(filePath) {
    global AppConfig
    try {
        Run('"' AppConfig["IdeaCommand"] '" "' filePath '"')
    } catch Error {
        ShowFeedback("IDEA 打开失败，请检查 settings.ini 中的 IdeaCommand", true)
    }
}

ShowFeedback(message, isError := false) {
    if isError {
        MsgBox(message, "AIProcess", "Iconx T3")
        return
    }
    ToolTip(message)
    SetTimer(() => ToolTip(), -1200)
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

LoadTemplate(fileName) {
    global TemplateDir
    path := TemplateDir "\" fileName
    if !FileExist(path) {
        throw Error("模板文件不存在：" path)
    }
    return FileRead(path, "UTF-8")
}

BuildExecuteStrategyOptions() {
    global ExecuteStrategies
    options := []
    for strategy in ExecuteStrategies {
        options.Push(strategy["label"])
    }
    return options
}

GetSelectedExecuteStrategy() {
    global ExecuteStrategyDropdown, ExecuteStrategies
    selectedIndex := ExecuteStrategyDropdown.Value
    if (selectedIndex < 1 || selectedIndex > ExecuteStrategies.Length) {
        return ExecuteStrategies[1]["key"]
    }
    return ExecuteStrategies[selectedIndex]["key"]
}

GetExecuteStrategyMeta(strategyKey) {
    global ExecuteStrategies
    for strategy in ExecuteStrategies {
        if (strategy["key"] = strategyKey) {
            return strategy
        }
    }
    return ExecuteStrategies[1]
}

CreateAndEnterIssueDir(*) {
    global CurrentDir, ResultIssueRootName
    if !EnsureCurrentDirectory() {
        return
    }

    if IsResultIssueDir(CurrentDir) {
        ShowFeedback("请先返回主题目录", true)
        return
    }

    issueRoot := GetResultIssueRoot(CurrentDir)
    DirCreate(issueRoot)
    nextIssueDirName := GetNextIssueDirName(issueRoot)
    nextIssueDirPath := issueRoot "\" nextIssueDirName
    DirCreate(nextIssueDirPath)

    CurrentDir := nextIssueDirPath
    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    ShowFeedback("已进入问题目录：" nextIssueDirName)

    CreateRequirementFile()
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

SubmitNewThemeDialog(*) {
    global CurrentDir, NewThemeDialog, NewThemeDialogEdit, NewThemeDialogErrorText
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

    parentDir := ""
    SplitPath(CurrentDir,, &parentDir)
    newDir := parentDir "\" themeName
    if DirExist(newDir) {
        ShowNewThemeDialogError("目录已存在：" themeName)
        return
    }

    DirCreate(newDir)
    CloseNewThemeDialog()
    SwitchToNewTheme(newDir)
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
    global CurrentDir
    CurrentDir := newDir
    UpdateCurrentPathDisplay()
    RefreshDirectoryStateUI()
    CreateRequirementFile()
}

CreateNewTheme(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    if IsResultIssueDir(CurrentDir) {
        parentDir := ""
        SplitPath(CurrentDir,, &parentDir)
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

GetThemeRootFromIssueDir(dirPath) {
    fileName := ""
    parentName := ""
    parentDir := ""
    themeDir := ""
    SplitPath(dirPath, &fileName, &parentDir)
    SplitPath(parentDir, &parentName, &themeDir)
    return themeDir
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

AppendNoModifyPromptIfNeeded(content) {
    global AppConfig
    if !AppConfig["AppendNoModifyPrompt"] {
        return content
    }

    extraPrompt := Trim(LoadTemplate("no_modify_prompt.txt"), "`r`n `t")
    if (extraPrompt = "") {
        return content
    }

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n`r`n" extraPrompt
}

AppendReplyImplementationTailIfNeeded(content) {
    global ReplyImplementationTailCheckbox
    if !ReplyImplementationTailCheckbox || ReplyImplementationTailCheckbox.Value != 1 {
        return content
    }

    tailContent := Trim(LoadTemplate("reply_prompt_impl_tail.txt"), "`r`n `t")
    if (tailContent = "") {
        return content
    }

    baseContent := RTrim(content, "`r`n")
    return baseContent "`r`n" tailContent
}

BuildContextRelationsText() {
    global CurrentDir

    orderedFiles := GetOrderedContextFiles(CurrentDir)
    if (orderedFiles.Length = 0) {
        return "当前主题目录：" CurrentDir "`n`n当前目录下未找到可用于上下文重建的关键文件。"
    }

    readingNames := []
    detailLines := []
    foundRequirement := false
    foundImplementation := false

    for filePath in orderedFiles {
        fileName := ExtractFileName(filePath)
        readingNames.Push(fileName)
        detailLines.Push(fileName "：" filePath)

        if (fileName = "需求.txt") {
            foundRequirement := true
        } else if (fileName = "实施文档.md") {
            foundImplementation := true
        }
    }

    intro := "当前主题目录：" CurrentDir
    orderLine := "请优先按时间顺序阅读：" JoinArray(readingNames, " -> ")
    roleLines := []

    if foundRequirement {
        roleLines.Push("需求.txt：原始需求说明。")
    }
    roleLines.Push("vX.md：AI 沟通过程中的版本文档。")
    roleLines.Push("对vX的回复.txt：用户对对应版本的回复。")
    if foundImplementation {
        roleLines.Push("实施文档.md：需求沟通收敛后的最终结论文件，也是后续正式实施时最重要的执行依据。")
    }
    roleLines.Push("你的首要任务是基于以上文件完成上下文重建，不要跳过文件整理和阅读步骤。")

    return intro
        . "`n`n" . orderLine
        . "`n`n关键文件路径：`n" . JoinArray(detailLines, "`n")
        . "`n`n文件说明：`n" . JoinArray(roleLines, "`n")
}

GetOrderedContextFiles(dirPath) {
    orderedFiles := []
    requirementPath := dirPath "\需求.txt"
    implementationPath := dirPath "\实施文档.md"

    if FileExist(requirementPath) {
        orderedFiles.Push(requirementPath)
    }

    versions := []
    Loop Files, dirPath "\v*.md", "F" {
        if RegExMatch(A_LoopFileName, "^v(\d+)\.md$", &match) {
            version := match[1] + 0
            versions.Push(Map(
                "version", version,
                "path", A_LoopFileFullPath,
                "replyPath", dirPath "\对v" version "的回复.txt"
            ))
        }
    }

    if (versions.Length > 1) {
        loopCount := versions.Length - 1
        Loop loopCount {
            changed := false
            index := 1
            while (index <= versions.Length - A_Index) {
                if (versions[index]["version"] > versions[index + 1]["version"]) {
                    temp := versions[index]
                    versions[index] := versions[index + 1]
                    versions[index + 1] := temp
                    changed := true
                }
                index += 1
            }
            if !changed {
                break
            }
        }
    }

    for item in versions {
        orderedFiles.Push(item["path"])
        if FileExist(item["replyPath"]) {
            orderedFiles.Push(item["replyPath"])
        }
    }

    if FileExist(implementationPath) {
        orderedFiles.Push(implementationPath)
    }

    return orderedFiles
}

GetLatestVersionNumber(dirPath) {
    latest := 0
    Loop Files, dirPath "\v*.md", "F" {
        if RegExMatch(A_LoopFileName, "^v(\d+)\.md$", &match) {
            version := match[1] + 0
            if (version > latest) {
                latest := version
            }
        }
    }
    return latest
}

NormalizePath(path) {
    path := Trim(path)
    while (SubStr(path, 0) = "\" && StrLen(path) > 3) {
        path := SubStr(path, 1, -1)
    }
    return path
}

TruncateMiddle(text, maxLength) {
    if StrLen(text) <= maxLength {
        return text
    }

    leftLength := Floor((maxLength - 3) / 2)
    rightLength := maxLength - 3 - leftLength
    return SubStr(text, 1, leftLength) "..." SubStr(text, -rightLength + 1)
}

ExtractFileName(path) {
    SplitPath(path, &name)
    return name
}

JoinArray(items, separator) {
    result := ""
    for item in items {
        if (result != "") {
            result .= separator
        }
        result .= item
    }
    return result
}
