#Requires AutoHotkey v2.0

; 全局配置

global AppConfig := Map()
global SettingsFile := ConfigDir "\settings.ini"

; 确保默认文件和配置存在
EnsureDefaultFiles() {
    global ConfigDir, TemplateDir, SettingsFile
    DirCreate(ConfigDir)
    DirCreate(TemplateDir)
    executeTemplateDir := TemplateDir "\execute"
    DirCreate(executeTemplateDir)

    if !FileExist(SettingsFile) {
        ; 创建带 BOM 的 UTF-16 LE 空文件，确保后续 IniWrite 中文不乱码
        FileAppend("", SettingsFile, "UTF-16")
    }

    ; 确保 settings.ini 是 UTF-16 LE 带 BOM 格式
    EnsureIniUtf16Bom(SettingsFile)

    ; 写入默认配置
    if (IniRead(SettingsFile, "App", "Hotkey", "") = "") {
        IniWrite("F2", SettingsFile, "App", "Hotkey")
    }
    if (IniRead(SettingsFile, "Window", "Width", "") = "") {
        IniWrite("210", SettingsFile, "Window", "Width")
    }
    if (IniRead(SettingsFile, "Window", "Height", "") = "") {
        IniWrite("215", SettingsFile, "Window", "Height")
    }
    if (IniRead(SettingsFile, "Behavior", "AlwaysOnTop", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "AlwaysOnTop")
    }
    if (IniRead(SettingsFile, "Behavior", "StartVisible", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "StartVisible")
    }
    if (IniRead(SettingsFile, "Behavior", "CloseToTray", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "CloseToTray")
    }
    if (IniRead(SettingsFile, "Behavior", "MinimizeToTray", "") = "") {
        IniWrite("1", SettingsFile, "Behavior", "MinimizeToTray")
    }
    if (IniRead(SettingsFile, "Behavior", "AutoHideAfterCreate", "") = "") {
        IniWrite("0", SettingsFile, "Behavior", "AutoHideAfterCreate")
    }
    if (IniRead(SettingsFile, "Editor", "OpenWithIdea", "") = "") {
        IniWrite("1", SettingsFile, "Editor", "OpenWithIdea")
    }
    if (IniRead(SettingsFile, "Editor", "OpenMdWithIdea", "") = "") {
        IniWrite("1", SettingsFile, "Editor", "OpenMdWithIdea")
    }
    if (IniRead(SettingsFile, "Prompt", "AppendNoModifyPrompt", "") = "") {
        IniWrite("1", SettingsFile, "Prompt", "AppendNoModifyPrompt")
    }
    if (IniRead(SettingsFile, "Editor", "IdeaCommand", "") = "") {
        IniWrite("idea64.exe", SettingsFile, "Editor", "IdeaCommand")
    }

    ; [Hotkey] 段
    if (IniRead(SettingsFile, "Hotkey", "Window1Hotkey", "") = "") {
        IniWrite("F2", SettingsFile, "Hotkey", "Window1Hotkey")
    }
    if (IniRead(SettingsFile, "Hotkey", "Window2Hotkey", "") = "") {
        IniWrite("F3", SettingsFile, "Hotkey", "Window2Hotkey")
    }
    if (IniRead(SettingsFile, "Hotkey", "EnableWindow2", "") = "") {
        IniWrite("0", SettingsFile, "Hotkey", "EnableWindow2")
    }

    ; [Window1] 段
    if (IniRead(SettingsFile, "Window1", "CurrentDir", "") = "") {
        IniWrite("", SettingsFile, "Window1", "CurrentDir")
    }
    if (IniRead(SettingsFile, "Window1", "AgentTitleContains", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentTitleContains")
    }
    if (IniRead(SettingsFile, "Window1", "AgentProcessName", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentProcessName")
    }
    if (IniRead(SettingsFile, "Window1", "AgentClassName", "") = "") {
        IniWrite("", SettingsFile, "Window1", "AgentClassName")
    }
    if (IniRead(SettingsFile, "Window1", "AgentAfterCopyAction", "") = "") {
        IniWrite("3", SettingsFile, "Window1", "AgentAfterCopyAction")
    }

    ; [Window2] 段
    if (IniRead(SettingsFile, "Window2", "CurrentDir", "") = "") {
        IniWrite("", SettingsFile, "Window2", "CurrentDir")
    }
    if (IniRead(SettingsFile, "Window2", "AgentTitleContains", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentTitleContains")
    }
    if (IniRead(SettingsFile, "Window2", "AgentProcessName", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentProcessName")
    }
    if (IniRead(SettingsFile, "Window2", "AgentClassName", "") = "") {
        IniWrite("", SettingsFile, "Window2", "AgentClassName")
    }
    if (IniRead(SettingsFile, "Window2", "AgentAfterCopyAction", "") = "") {
        IniWrite("3", SettingsFile, "Window2", "AgentAfterCopyAction")
    }

    if (IniRead(SettingsFile, "Prompt", "AppendNoModifyPrompt", "") = "") {
        IniWrite("1", SettingsFile, "Prompt", "AppendNoModifyPrompt")
    }

    if (IniRead(SettingsFile, "Behavior", "AutoHideAfterCreate", "") = "") {
        IniWrite("0", SettingsFile, "Behavior", "AutoHideAfterCreate")
    }

    if (IniRead(SettingsFile, "Editor", "OpenMdWithIdea", "") = "") {
        IniWrite("1", SettingsFile, "Editor", "OpenMdWithIdea")
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

; 加载配置
LoadConfig() {
    global AppConfig, SettingsFile, AppRoot
    AppConfig := Map()
    AppConfig["Hotkey"] := IniRead(SettingsFile, "App", "Hotkey", "F2")
    AppConfig["IconSource"] := IniRead(SettingsFile, "App", "IconSource", "shell32.dll")
    AppConfig["IconIndex"] := IniRead(SettingsFile, "App", "IconIndex", "44") + 0
    AppConfig["WindowWidth"] := IniRead(SettingsFile, "Window", "Width", "210") + 0
    AppConfig["WindowHeight"] := IniRead(SettingsFile, "Window", "Height", "150") + 0
    if (AppConfig["WindowHeight"] < 215) {
        AppConfig["WindowHeight"] := 215
    }
    LoadHotkeyConfig()
    LoadWindowSessions()
    AppConfig["AlwaysOnTop"] := IniRead(SettingsFile, "Behavior", "AlwaysOnTop", "1") = "1"
    AppConfig["StartVisible"] := IniRead(SettingsFile, "Behavior", "StartVisible", "1") = "1"
    AppConfig["CloseToTray"] := IniRead(SettingsFile, "Behavior", "CloseToTray", "1") = "1"
    AppConfig["MinimizeToTray"] := IniRead(SettingsFile, "Behavior", "MinimizeToTray", "1") = "1"
    AppConfig["AutoHideAfterCreate"] := IniRead(SettingsFile, "Behavior", "AutoHideAfterCreate", "0") = "1"
    AppConfig["OpenWithIdea"] := IniRead(SettingsFile, "Editor", "OpenWithIdea", "1") = "1"
    AppConfig["OpenMdWithIdea"] := IniRead(SettingsFile, "Editor", "OpenMdWithIdea", "1") = "1"
    AppConfig["OpenMdScriptPath"] := AppRoot "\OpenMarkdown.ps1"
    AppConfig["AppendNoModifyPrompt"] := IniRead(SettingsFile, "Prompt", "AppendNoModifyPrompt", "1") = "1"
    AppConfig["IdeaCommand"] := IniRead(SettingsFile, "Editor", "IdeaCommand", "idea64.exe")
}

; 加载热键配置
LoadHotkeyConfig() {
    global AppConfig, SettingsFile
    AppConfig["Window1Hotkey"] := IniRead(SettingsFile, "Hotkey", "Window1Hotkey", "F2")
    AppConfig["Window2Hotkey"] := IniRead(SettingsFile, "Hotkey", "Window2Hotkey", "F3")
    AppConfig["EnableWindow2"] := IniRead(SettingsFile, "Hotkey", "EnableWindow2", "0") = "1"
}

; 加载各窗口会话数据
LoadWindowSessions() {
    global WindowSessions, SettingsFile
    for windowId in [1, 2] {
        section := "Window" windowId
        WindowSessions[windowId]["CurrentDir"] := IniRead(SettingsFile, section, "CurrentDir", "")
        WindowSessions[windowId]["AgentTitleContains"] := IniRead(SettingsFile, section, "AgentTitleContains", "")
        WindowSessions[windowId]["AgentProcessName"] := IniRead(SettingsFile, section, "AgentProcessName", "")
        WindowSessions[windowId]["AgentClassName"] := IniRead(SettingsFile, section, "AgentClassName", "")
        WindowSessions[windowId]["AgentAfterCopyAction"] := IniRead(SettingsFile, section, "AgentAfterCopyAction", "3") + 0
    }
}

; 保存指定窗口的会话数据
SaveWindowSession(windowId) {
    global WindowSessions, SettingsFile
    section := "Window" windowId
    IniWrite(WindowSessions[windowId]["CurrentDir"], SettingsFile, section, "CurrentDir")
    IniWrite(WindowSessions[windowId]["AgentTitleContains"], SettingsFile, section, "AgentTitleContains")
    IniWrite(WindowSessions[windowId]["AgentProcessName"], SettingsFile, section, "AgentProcessName")
    IniWrite(WindowSessions[windowId]["AgentClassName"], SettingsFile, section, "AgentClassName")
    IniWrite(WindowSessions[windowId]["AgentAfterCopyAction"], SettingsFile, section, "AgentAfterCopyAction")
}

; 保存 2 号窗口启用状态
SaveEnableWindow2(enabled) {
    global SettingsFile
    IniWrite(enabled ? "1" : "0", SettingsFile, "Hotkey", "EnableWindow2")
}

; 确保 INI 文件使用 UTF-16 LE 带 BOM 格式，避免中文乱码
EnsureIniUtf16Bom(filePath) {
    ; 读取文件前几个字节判断是否有 UTF-16 LE BOM (FF FE)
    try {
        raw := FileRead(filePath, "RAW")
        if (raw.Length >= 2 && raw[1] = 0xFF && raw[2] = 0xFE) {
            return  ; 已经是 UTF-16 LE BOM
        }
    } catch {
        return
    }

    ; 读取当前内容（按系统默认编码），重新写入为 UTF-16 LE 带 BOM
    try {
        text := FileRead(filePath)
        FileDelete(filePath)
        FileAppend(text, filePath, "UTF-16")
    } catch {
        ; 忽略转换失败
    }
}
