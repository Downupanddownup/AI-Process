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
#Include %A_ScriptDir%\lib\Guid.ahk
#Include %A_ScriptDir%\modules\core\Logger.ahk
#Include %A_ScriptDir%\modules\core\DataFileUtils.ahk
#Include %A_ScriptDir%\modules\core\ConfigManager.ahk
#Include %A_ScriptDir%\modules\core\WindowPositionManager.ahk
#Include %A_ScriptDir%\modules\core\AppBootstrap.ahk
#Include %A_ScriptDir%\modules\session\Session.ahk
#Include %A_ScriptDir%\modules\ui\TrayManager.ahk
#Include %A_ScriptDir%\modules\ui\FlowMaintainWindow.ahk
#Include %A_ScriptDir%\modules\business\FileToolManager.ahk
#Include %A_ScriptDir%\modules\business\QuestionCollector.ahk
#Include %A_ScriptDir%\modules\business\DirectoryManager.ahk
#Include %A_ScriptDir%\modules\business\ThemeManager.ahk
#Include %A_ScriptDir%\modules\business\RepositoryManager.ahk
#Include %A_ScriptDir%\modules\business\RepositoryDialog.ahk
#Include %A_ScriptDir%\modules\business\ArchiveManager.ahk
#Include %A_ScriptDir%\modules\business\RepositoryWindow.ahk
#Include %A_ScriptDir%\modules\business\DomainTreeWindow.ahk
#Include %A_ScriptDir%\modules\business\HistoryIndexManager.ahk
#Include %A_ScriptDir%\modules\business\ActivityLogger.ahk
#Include %A_ScriptDir%\modules\business\AgentWindowManager.ahk
#Include %A_ScriptDir%\modules\business\services\DomainConventions.ahk
#Include %A_ScriptDir%\modules\business\services\ContextRebuildManifest.ahk
#Include %A_ScriptDir%\modules\business\services\ContextRebuildScalePolicy.ahk
#Include %A_ScriptDir%\modules\business\services\ContextRebuildPromptBuilder.ahk
#Include %A_ScriptDir%\modules\business\services\DomainTree.ahk
#Include %A_ScriptDir%\modules\business\services\VersionChain.ahk
#Include %A_ScriptDir%\modules\business\services\PromptElements.ahk
#Include %A_ScriptDir%\modules\business\services\EditorOpener.ahk
#Include %A_ScriptDir%\modules\business\services\ExecuteStrategyRegistry.ahk
#Include %A_ScriptDir%\modules\business\services\ReviewModeRegistry.ahk
#Include %A_ScriptDir%\modules\business\services\ActionGuard.ahk
#Include %A_ScriptDir%\modules\business\services\ThemeStats.ahk
#Include %A_ScriptDir%\modules\business\services\ThemeCost.ahk
; promptflow 子系统：10.2 起面板要显示流程简称，需要流程库。
; 整包引入而不是挑依赖链——#Warn 是静态分析，任何一处类引用缺失都会在启动时报，
; 手工挑必然漏（PromptFlow 引用 BlockLibrary、BlockLibrary 引用 PromptBlock…）。
; 这些文件只有类定义、无顶层调用，全引入无副作用；完整接入（走新入口的开关）仍是 09 的事。
#Include %A_ScriptDir%\modules\promptflow\skeleton\Skeleton.ahk
#Include %A_ScriptDir%\modules\promptflow\skeleton\ActionRecipe.ahk
#Include %A_ScriptDir%\modules\promptflow\action\ActionPolicy.ahk
#Include %A_ScriptDir%\modules\promptflow\action\Action.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\PromptBlock.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\BlockLibrary.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\ReferenceDoc.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\ReferenceLibrary.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\ValidationIssue.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\ValidationReport.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\PromptFlow.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\FlowLibrary.ahk
#Include %A_ScriptDir%\modules\promptflow\definition\FlowEditor.ahk
#Include %A_ScriptDir%\modules\promptflow\param\PromptParam.ahk
#Include %A_ScriptDir%\modules\promptflow\param\PromptParamRule.ahk
#Include %A_ScriptDir%\modules\promptflow\engine\PlaceholderEngine.ahk
#Include %A_ScriptDir%\modules\promptflow\engine\AssemblerEngine.ahk
#Include %A_ScriptDir%\modules\promptflow\engine\FlowEngine.ahk
#Include %A_ScriptDir%\modules\promptflow\runtime\Environment.ahk
#Include %A_ScriptDir%\modules\promptflow\runtime\StartPhase.ahk
#Include %A_ScriptDir%\modules\promptflow\PromptAssembler.ahk
#Include %A_ScriptDir%\modules\promptflow\PromptValidator.ahk
#Include %A_ScriptDir%\modules\business\services\FlowResolver.ahk
#Include %A_ScriptDir%\modules\business\behaviors\AgentActionBase.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\CreateRequirement.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\CopyRequirement.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\CreateReply.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\CopyReply.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\CopyExecute.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\CopyRelations.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\QualityCheck.ahk
#Include %A_ScriptDir%\modules\business\behaviors\actions\Review.ahk
#Include %A_ScriptDir%\modules\business\behaviors\AgentActions.ahk
#Include %A_ScriptDir%\modules\business\summary\HistoricalThemeImporter.ahk
#Include %A_ScriptDir%\modules\business\summary\ThemePathUtils.ahk
#Include %A_ScriptDir%\modules\business\summary\SummaryWindow.ahk
#Include %A_ScriptDir%\modules\business\CostWindow.ahk
#Include %A_ScriptDir%\modules\ui\StyleManager.ahk
#Include %A_ScriptDir%\modules\ui\TextFit.ahk
#Include %A_ScriptDir%\modules\ui\MainWindow.ahk
#Include %A_ScriptDir%\modules\ui\ConfigDialog.ahk
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
InitFileToolManager()
if (!IsWindowPositionValid(AppConfig["WindowPosX"], AppConfig["WindowPosY"])) {
    ClearSavedWindowPosition()
}
InitRepositoryManager()
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
