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
global OpenWithIdeaCheckbox := ""
global SetDirectoryButton := ""
global CreateRequirementButton := ""
global CopyRequirementPromptButton := ""
global CreateReplyButton := ""
global CopyReplyPromptButton := ""
global CopyRelationsButton := ""
global CopyDiscussButton := ""
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
        IniWrite("210", SettingsFile, "Window", "Width")
        IniWrite("182", SettingsFile, "Window", "Height")
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
    AppConfig["WindowWidth"] := IniRead(SettingsFile, "Window", "Width", "210") + 0
    AppConfig["WindowHeight"] := IniRead(SettingsFile, "Window", "Height", "182") + 0
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
    global MainGui, CurrentPathText, CurrentPathHwnd, OpenWithIdeaCheckbox, AppConfig
    global SetDirectoryButton
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyDiscussButton

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

    CurrentPathText := MainGui.AddText("xm ym w140 h18 +0x200", "当前：未设置")
    CurrentPathText.OnEvent("Click", ShowFullPath)
    CurrentPathHwnd := CurrentPathText.Hwnd

    SetDirectoryButton := MainGui.AddButton("x+6 yp-2 w48 h22", "设目录")
    SetDirectoryButton.OnEvent("Click", PromptForDirectory)

    OpenWithIdeaCheckbox := MainGui.AddCheckbox("xm y+6", "创建后用 IDEA 打开")
    OpenWithIdeaCheckbox.Value := AppConfig["OpenWithIdea"] ? 1 : 0
    OpenWithIdeaCheckbox.OnEvent("Click", ToggleIdeaOpen)

    CreateRequirementButton := MainGui.AddButton("xm y+8 w90 h24", "建需求")
    CreateRequirementButton.OnEvent("Click", CreateRequirementFile)

    CopyRequirementPromptButton := MainGui.AddButton("x+6 yp w90 h24", "复需求")
    CopyRequirementPromptButton.OnEvent("Click", CopyRequirementPrompt)

    CreateReplyButton := MainGui.AddButton("xm y+6 w90 h24", "建回复")
    CreateReplyButton.OnEvent("Click", CreateReplyFile)

    CopyReplyPromptButton := MainGui.AddButton("x+6 yp w90 h24", "复回复")
    CopyReplyPromptButton.OnEvent("Click", CopyReplyPrompt)

    CopyRelationsButton := MainGui.AddButton("xm y+6 w90 h24", "复关系")
    CopyRelationsButton.OnEvent("Click", CopyContextRelations)

    CopyDiscussButton := MainGui.AddButton("x+6 yp w90 h24", "先别改")
    CopyDiscussButton.OnEvent("Click", CopyDiscussPrompt)

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
    global CurrentDir
    defaultValue := CurrentDir != "" ? CurrentDir : ""
    SetTimer(SetTopmostInputBox, 10)
    result := InputBox("请粘贴当前主题目录路径：", "设置目录", "w360 h140", defaultValue)

    if (result.Result != "OK") {
        return
    }

    rawPath := Trim(result.Value)
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
    ShowFeedback("当前目录已切换")
}

SetTopmostInputBox() {
    hwnd := WinExist("设置目录 ahk_class #32770")
    if hwnd {
        WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
    }
}

UpdateCurrentPathDisplay() {
    global CurrentDir, CurrentPathText
    if CurrentDir = "" {
        CurrentPathText.Text := "当前：未设置"
        return
    }

    split := StrSplit(CurrentDir, "\")
    dirName := split.Length ? split[split.Length] : CurrentDir
    CurrentPathText.Text := "当前：" dirName
}

SetControlsEnabled(enabled) {
    global CreateRequirementButton, CopyRequirementPromptButton, CreateReplyButton
    global CopyReplyPromptButton, CopyRelationsButton, CopyDiscussButton
    CreateRequirementButton.Enabled := enabled
    CopyRequirementPromptButton.Enabled := enabled
    CreateReplyButton.Enabled := enabled
    CopyReplyPromptButton.Enabled := enabled
    CopyRelationsButton.Enabled := enabled
    CopyDiscussButton.Enabled := enabled
}

ToggleIdeaOpen(ctrl, *) {
    global AppConfig, SettingsFile
    checked := ctrl.Value = 1
    AppConfig["OpenWithIdea"] := checked
    IniWrite(checked ? "1" : "0", SettingsFile, "Editor", "OpenWithIdea")
    ShowFeedback(checked ? "已开启 IDEA 打开" : "已关闭 IDEA 打开")
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
}

CopyRequirementPrompt(*) {
    global CurrentDir
    if !EnsureCurrentDirectory() {
        return
    }

    content := LoadTemplate("requirement_prompt.txt")
    content := StrReplace(content, "{{filePath}}", CurrentDir "\需求.txt")
    A_Clipboard := content
    ShowFeedback("需求提示词已复制")
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
    A_Clipboard := content
    ShowFeedback("回复提示词已复制")
}

CopyContextRelations(*) {
    if !EnsureCurrentDirectory() {
        return
    }

    content := BuildContextRelationsText()
    A_Clipboard := content
    ShowFeedback("文件关系说明已复制")
}

CopyDiscussPrompt(*) {
    A_Clipboard := "先别改，谈谈"
    ShowFeedback("已复制：先别改，谈谈")
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

LoadTemplate(fileName) {
    global TemplateDir
    path := TemplateDir "\" fileName
    if !FileExist(path) {
        throw Error("模板文件不存在：" path)
    }
    return FileRead(path, "UTF-8")
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
