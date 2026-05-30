#Requires AutoHotkey v2.0
#SingleInstance Force

Persistent

global AppRoot := A_ScriptDir
global ConfigDir := AppRoot "\config"
global TemplateDir := AppRoot "\templates"
global SettingsFile := ConfigDir "\settings.ini"

global AppConfig := Map()
global CurrentDir := ""
global PathSummaryHwnd := 0
global PathInput := ""
global PathSummary := ""
global StatusText := ""
global OpenWithIdeaCheckbox := ""
global CreateRequirementButton := ""
global CopyRequirementPromptButton := ""
global CreateReplyButton := ""
global CopyReplyPromptButton := ""
global CopyRelationsButton := ""
global MainGui := ""
global HoverTooltipVisible := false

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

    if !FileExist(SettingsFile) {
        IniWrite("F2", SettingsFile, "App", "Hotkey")
        IniWrite("560", SettingsFile, "Window", "Width")
        IniWrite("320", SettingsFile, "Window", "Height")
        IniWrite("1", SettingsFile, "Behavior", "AlwaysOnTop")
        IniWrite("1", SettingsFile, "Behavior", "StartVisible")
        IniWrite("1", SettingsFile, "Behavior", "CloseToTray")
        IniWrite("1", SettingsFile, "Behavior", "MinimizeToTray")
        IniWrite("1", SettingsFile, "Editor", "OpenWithIdea")
        IniWrite("idea64.exe", SettingsFile, "Editor", "IdeaCommand")
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
        "这是一个回复文件，请你查看这个文件：{{filePath}}。如果你还有新的想法或问题，请创建 {{nextVersionFile}}；如果没有新的问题，请创建 实施文档.md。"
        , replyTemplate, "UTF-8")
    }

    relationTemplate := TemplateDir "\context_relation.txt"
    if !FileExist(relationTemplate) {
        FileAppend(
        "当前目录中的 需求.txt 是原始需求说明；vX.md 是 AI 沟通过程中的版本文档；对vX的回复.txt 是用户对对应版本的回复；实施文档.md 是整个需求沟通收敛后的最终结论文件，也是后续正式实施时最重要的执行依据。这些文件按时间顺序构成完整沟通过程。新会话接管时，应优先阅读这些文件并完成上下文重建。"
        , relationTemplate, "UTF-8")
    }
}

LoadConfig() {
    global AppConfig, SettingsFile
    AppConfig := Map()
    AppConfig["Hotkey"] := IniRead(SettingsFile, "App", "Hotkey", "F2")
    AppConfig["WindowWidth"] := IniRead(SettingsFile, "Window", "Width", "560") + 0
    AppConfig["WindowHeight"] := IniRead(SettingsFile, "Window", "Height", "320") + 0
    AppConfig["AlwaysOnTop"] := IniRead(SettingsFile, "Behavior", "AlwaysOnTop", "1") = "1"
    AppConfig["StartVisible"] := IniRead(SettingsFile, "Behavior", "StartVisible", "1") = "1"
    AppConfig["CloseToTray"] := IniRead(SettingsFile, "Behavior", "CloseToTray", "1") = "1"
    AppConfig["MinimizeToTray"] := IniRead(SettingsFile, "Behavior", "MinimizeToTray", "1") = "1"
    AppConfig["OpenWithIdea"] := IniRead(SettingsFile, "Editor", "OpenWithIdea", "1") = "1"
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
    global MainGui, PathInput, PathSummary, StatusText, OpenWithIdeaCheckbox, AppConfig
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, PathSummaryHwnd

    guiOptions := "+Resize -MaximizeBox +MinimizeBox"
    if AppConfig["AlwaysOnTop"] {
        guiOptions .= " +AlwaysOnTop"
    }

    MainGui := Gui(guiOptions, "AIProcess 快捷面板")
    MainGui.BackColor := "F7F7F7"
    MainGui.MarginX := 12
    MainGui.MarginY := 10
    MainGui.SetFont("s9", "Microsoft YaHei UI")
    MainGui.OnEvent("Close", HandleClose)
    MainGui.OnEvent("Escape", HideToTray)

    MainGui.AddText("xm ym", "当前目录")
    PathInput := MainGui.AddEdit("xm y+6 w420 vPathInput")
    MainGui.AddButton("x+8 yp-1 w96", "定位切换").OnEvent("Click", ApplyCurrentDirectory)

    MainGui.AddText("xm y+12", "目录摘要")
    PathSummary := MainGui.AddText("xm y+6 w520 h34 +0x200 Border vPathSummary", "未设置当前主题目录")
    PathSummaryHwnd := PathSummary.Hwnd

    OpenWithIdeaCheckbox := MainGui.AddCheckbox("xm y+12", "创建后用 IDEA 打开文件")
    OpenWithIdeaCheckbox.Value := AppConfig["OpenWithIdea"] ? 1 : 0
    OpenWithIdeaCheckbox.OnEvent("Click", ToggleIdeaOpen)

    CreateRequirementButton := MainGui.AddButton("xm y+16 w160 h30", "创建需求.txt")
    CreateRequirementButton.OnEvent("Click", CreateRequirementFile)

    CopyRequirementPromptButton := MainGui.AddButton("x+12 yp w160 h30", "复制需求文件提示词")
    CopyRequirementPromptButton.OnEvent("Click", CopyRequirementPrompt)

    CreateReplyButton := MainGui.AddButton("x+12 yp w176 h30", "创建对vX的回复.txt")
    CreateReplyButton.OnEvent("Click", CreateReplyFile)

    CopyReplyPromptButton := MainGui.AddButton("xm y+12 w160 h30", "复制回复文件提示词")
    CopyReplyPromptButton.OnEvent("Click", CopyReplyPrompt)

    CopyRelationsButton := MainGui.AddButton("x+12 yp w160 h30", "复制文件关系说明")
    CopyRelationsButton.OnEvent("Click", CopyContextRelations)

    StatusText := MainGui.AddText("xm y+16 w520 h44 +0x200 Border vStatusText", "就绪")

    SetControlsEnabled(false)
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
    global HoverTooltipVisible, CurrentDir, PathSummaryHwnd

    if (hwnd = PathSummaryHwnd && CurrentDir != "") {
        ToolTip(CurrentDir)
        HoverTooltipVisible := true
        return
    }

    if HoverTooltipVisible {
        ToolTip()
        HoverTooltipVisible := false
    }
}

ApplyCurrentDirectory(*) {
    global CurrentDir, PathInput
    rawPath := Trim(PathInput.Value)
    if rawPath = "" {
        SetStatus("请先输入目录路径", true)
        return
    }

    if !DirExist(rawPath) {
        SetStatus("路径不是有效目录", true)
        return
    }

    CurrentDir := NormalizePath(rawPath)
    UpdateCurrentPathDisplay()
    SetControlsEnabled(true)
    SetStatus("当前目录已切换到：" CurrentDir)
}

UpdateCurrentPathDisplay() {
    global CurrentDir, PathSummary
    if CurrentDir = "" {
        PathSummary.Text := "未设置当前主题目录"
        return
    }

    split := StrSplit(CurrentDir, "\")
    dirName := split.Length ? split[split.Length] : CurrentDir
    PathSummary.Text := dirName " | " TruncateMiddle(CurrentDir, 58)
}

SetControlsEnabled(enabled) {
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton
    CreateRequirementButton.Enabled := enabled
    CopyRequirementPromptButton.Enabled := enabled
    CreateReplyButton.Enabled := enabled
    CopyReplyPromptButton.Enabled := enabled
    CopyRelationsButton.Enabled := enabled
}

ToggleIdeaOpen(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["OpenWithIdea"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Editor", "OpenWithIdea")
    SetStatus(checked ? "已开启：创建后用 IDEA 打开文件" : "已关闭：创建后用 IDEA 打开文件")
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
        SetStatus("已创建：需求.txt")
    } else {
        SetStatus("文件已存在：需求.txt", true)
    }

    if AppConfig["OpenWithIdea"] {
        OpenFileInIdea(filePath)
    }
}

CreateReplyFile(*) {
    global CurrentDir, AppConfig
    if !EnsureCurrentDirectory() {
        return
    }

    latestVersion := GetLatestVersionNumber(CurrentDir)
    if (latestVersion = 0) {
        SetStatus("当前目录下未找到 vX.md 文件", true)
        return
    }

    replyPath := CurrentDir "\对v" latestVersion "的回复.txt"
    existed := FileExist(replyPath)
    if !existed {
        FileAppend("", replyPath, "UTF-8")
        SetStatus("已创建：" ExtractFileName(replyPath))
    } else {
        SetStatus("文件已存在：" ExtractFileName(replyPath), true)
    }

    if AppConfig["OpenWithIdea"] {
        OpenFileInIdea(replyPath)
    }
}

CopyRequirementPrompt(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    content := LoadTemplate("requirement_prompt.txt")
    content := StrReplace(content, "{{filePath}}", CurrentDir "\需求.txt")
    A_Clipboard := content
    SetStatus("需求提示词已复制到剪贴板")
}

CopyReplyPrompt(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    latestVersion := GetLatestVersionNumber(CurrentDir)
    if (latestVersion = 0) {
        SetStatus("当前目录下未找到 vX.md 文件", true)
        return
    }

    currentReplyFile := CurrentDir "\对v" latestVersion "的回复.txt"
    nextVersionFile := "v" (latestVersion + 1) ".md"
    content := LoadTemplate("reply_prompt.txt")
    content := StrReplace(content, "{{filePath}}", currentReplyFile)
    content := StrReplace(content, "{{nextVersionFile}}", nextVersionFile)
    A_Clipboard := content
    SetStatus("回复提示词已复制到剪贴板")
}

CopyContextRelations(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    content := LoadTemplate("context_relation.txt")
    A_Clipboard := content
    SetStatus("文件关系说明已复制到剪贴板")
}

EnsureCurrentDirectory() {
    global CurrentDir
    if CurrentDir = "" {
        SetStatus("请先设置当前主题目录", true)
        return false
    }
    return true
}

OpenFileInIdea(filePath) {
    global AppConfig
    try {
        Run('"' AppConfig["IdeaCommand"] '" "' filePath '"')
    } catch Error {
        SetStatus("IDEA 打开失败，请检查 settings.ini 中的 IdeaCommand", true)
    }
}

SetStatus(message, isError := false) {
    global StatusText
    prefix := isError ? "错误：" : "提示："
    StatusText.Text := prefix " " message
}

LoadTemplate(fileName) {
    global TemplateDir
    path := TemplateDir "\" fileName
    if !FileExist(path) {
        throw Error("模板文件不存在：" path)
    }
    return FileRead(path, "UTF-8")
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
