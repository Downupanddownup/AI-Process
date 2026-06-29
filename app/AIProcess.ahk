#Requires AutoHotkey v2.0
#SingleInstance Off

Persistent

global AppRoot := A_ScriptDir
global ConfigDir := AppRoot "\config"
global TemplateDir := AppRoot "\templates"
global ModulesDir := AppRoot "\modules"
global DataDir := AppRoot "\data"
global LibDir := AppRoot "\lib"

#Include %A_ScriptDir%\lib\JSON.ahk
#Include %A_ScriptDir%\modules\core\Logger.ahk
#Include %A_ScriptDir%\modules\core\DataFileUtils.ahk
#Include %A_ScriptDir%\modules\core\ConfigManager.ahk
#Include %A_ScriptDir%\modules\core\WindowPositionManager.ahk
#Include %A_ScriptDir%\modules\core\AppBootstrap.ahk
#Include %A_ScriptDir%\modules\session\Session.ahk
#Include %A_ScriptDir%\modules\ui\TrayManager.ahk
#Include %A_ScriptDir%\modules\business\FileManager.ahk
#Include %A_ScriptDir%\modules\business\PromptManager.ahk
#Include %A_ScriptDir%\modules\business\DirectoryManager.ahk
#Include %A_ScriptDir%\modules\business\ThemeManager.ahk
#Include %A_ScriptDir%\modules\business\HistoryIndexManager.ahk
#Include %A_ScriptDir%\modules\business\ActivityLogger.ahk
#Include %A_ScriptDir%\modules\business\AgentWindowManager.ahk
#Include %A_ScriptDir%\modules\business\AgentDispatcher.ahk
#Include %A_ScriptDir%\modules\business\summary\SummaryDataCollector.ahk
#Include %A_ScriptDir%\modules\business\summary\SummaryGenerator.ahk
#Include %A_ScriptDir%\modules\business\summary\HistoricalThemeImporter.ahk
#Include %A_ScriptDir%\modules\business\summary\SummaryWindow.ahk
#Include %A_ScriptDir%\modules\ui\StyleManager.ahk
#Include %A_ScriptDir%\modules\ui\MainWindow.ahk
#Include %A_ScriptDir%\modules\ui\ConfigDialog.ahk
#Include %A_ScriptDir%\modules\ui\OptionsDialog.ahk
#Include %A_ScriptDir%\modules\ui\HotkeyManager.ahk

if (!EnsureSingleInstance()) {
    if (HasSetDirArg()) {
        SendSetDirToExistingInstance(GetSetDirArg())
    } else {
        ActivateExistingInstance()
    }
    ExitApp()
}

EnsureDefaultFiles()
LoadConfig()
CreateTray()
CreateMainGui()
UpdateBindButtonState()

if (HasSetDirArg()) {
    ; 第一个实例被右键菜单启动，处理设目录后继续运行
    SetActiveWindowId(1)
    SetCurrentDirAndOpenRequirement(GetSetDirArg())
    StartedFromContextMenu := true
}

RegisterGlobalHotkey()
OnMessage(0x4000, OnSetDirMessage)
if (AppConfig["StartVisible"] && !StartedFromContextMenu) {
    ShowMainWindow()
}

OnMessage(0x200, OnMouseMove)
OnMessage(0x05, OnWindowSize)

return
