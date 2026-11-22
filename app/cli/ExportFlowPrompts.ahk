#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off

; 命令行入口：一套流程 → 一份成品 JSON（与维护窗口「一键导出」同一实现）
;
; 用法：ExportFlowPrompts.bat <flowKey> [outDir]
;   成功：<outDir>\<flowKey>-prompts.json，退出码 0，不打印任何东西
;   失败：<outDir>\<flowKey>-prompts.error.txt（原因 + 用法 + 可用流程），退出码 2
;
; 三条纪律（见《AHK调试经验》1.1 / 1.2 / 2.6）：
;   1. 不弹窗：关 #Warn、OnError 兜底、60 秒自灭。弹窗会把调用方挂死；
;   2. 成败只认产物文件：stdout 与退出码在本项目实测都不可信；
;   3. 全局量必须在 #Include 之前补齐：ConfigManager 在加载期就用 ConfigDir 拼路径，
;      漏一个的症状是"没有任何输出、退出码仍是 0"。
; 不引 UI 与 behaviors：那等于在本地起一个应用。

OnError(ErrHandler)
SetTimer(OnTimeout, -60000)

global AppRoot := RegExReplace(A_ScriptDir, "\\[^\\]+$", "")
global ConfigDir := AppRoot "\config"
global TemplateDir := AppRoot "\templates"
global ModulesDir := AppRoot "\modules"
global DataDir := AppRoot "\data"
global LibDir := AppRoot "\lib"

; 失败信息写到哪：先落系统临时目录，解析出 outDir 后改指向它
global gOutDir := A_Temp
global gFlowKey := ""

#Include %A_ScriptDir%\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\modules\core\DataFileUtils.ahk
#Include %A_ScriptDir%\..\modules\core\ConfigManager.ahk
#Include %A_ScriptDir%\..\modules\session\Session.ahk
#Include %A_ScriptDir%\..\modules\promptflow\skeleton\Skeleton.ahk
#Include %A_ScriptDir%\..\modules\promptflow\skeleton\ActionRecipe.ahk
#Include %A_ScriptDir%\..\modules\promptflow\action\ActionPolicy.ahk
#Include %A_ScriptDir%\..\modules\promptflow\action\Action.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\PromptBlock.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\BlockLibrary.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\ReferenceDoc.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\ReferenceLibrary.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\ValidationIssue.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\ValidationReport.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\PromptFlow.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\FlowLibrary.ahk
#Include %A_ScriptDir%\..\modules\promptflow\definition\JsonConfigWriter.ahk
#Include %A_ScriptDir%\..\modules\promptflow\param\PromptParam.ahk
#Include %A_ScriptDir%\..\modules\promptflow\param\PromptParamRule.ahk
#Include %A_ScriptDir%\..\modules\promptflow\engine\PlaceholderEngine.ahk
#Include %A_ScriptDir%\..\modules\promptflow\engine\AssemblerEngine.ahk
#Include %A_ScriptDir%\..\modules\promptflow\runtime\Environment.ahk
#Include %A_ScriptDir%\..\modules\promptflow\PromptAssembler.ahk
#Include %A_ScriptDir%\..\modules\promptflow\PromptValidator.ahk
#Include %A_ScriptDir%\..\modules\promptflow\PromptExporter.ahk
#Include %A_ScriptDir%\..\modules\business\services\DomainConventions.ahk
#Include %A_ScriptDir%\..\modules\business\services\ContextRebuildManifest.ahk
#Include %A_ScriptDir%\..\modules\business\services\VersionChain.ahk

LoadConfig()

; ---- 参数 ----

args := A_Args
if (args.Length < 1) {
    Fail("参数不足。`n" UsageText() "`n可用流程：" ListFlowKeys())
}

gFlowKey := Trim(args[1])
outDir := (args.Length >= 2 && Trim(args[2]) != "") ? Trim(args[2]) : A_Desktop

if !DirExist(outDir) {
    try {
        DirCreate(outDir)
    } catch as e {
        Fail("输出目录建不出来：" outDir "`n— " e.Message)
    }
}
gOutDir := outDir

; 上一次失败留下的错误文件会误导调用方，先清掉
stale := ErrorFile()
if FileExist(stale) {
    try FileDelete(stale)
}

; ---- 流程存在性：早失败，并列出可用 key，调用方一次就能改对 ----

try {
    FlowLibrary.Get(gFlowKey)
} catch {
    Fail("流程不存在：" gFlowKey "`n可用流程：" ListFlowKeys() "`n" UsageText())
}

; ---- 校验闸：block 级挡住，warn 级（如组合未配置）照导 ----

report := PromptValidator.CheckFlow(gFlowKey)
if (report.HasBlocking()) {
    Fail("该流程有阻断级配置问题，导出的成品会误导人：`n" IssueLines(report) "`n修好后重试。")
}

; ---- 产出 ----

target := gOutDir "\" gFlowKey "-prompts.json"
try {
    PromptExporter.Write(gFlowKey, target)
} catch as e {
    Fail("导出失败：" e.Message)
}

; 防"跑成功但没产物"
if !FileExist(target) {
    Fail("导出后没有产物：" target)
}

ExitApp(0)

; ---- 函数 ----

UsageText() {
    return "用法：ExportFlowPrompts.bat <flowKey> [outDir]"
}

ErrHandler(e, mode) {
    Fail("脚本异常（第 " e.Line " 行）：" e.Message)
}

OnTimeout(*) {
    Fail("导出超时（60 秒），未产出文件。")
}

; 错误文件路径：能写 outDir 就写 outDir，否则退回系统临时目录
ErrorFile() {
    global gOutDir, gFlowKey
    name := (gFlowKey != "") ? gFlowKey "-prompts.error.txt" : "ExportFlowPrompts.error.txt"
    dir := gOutDir
    if (dir = "" || !DirExist(dir)) {
        dir := A_Temp
    }
    return dir "\" name
}

Fail(msg, code := 2) {
    WriteText(ErrorFile(), msg "`n")
    ExitApp(code)
}

WriteText(path, text) {
    try {
        f := FileOpen(path, "w", "UTF-8")
        f.Write(text)
        f.Close()
    } catch {
        try {
            f := FileOpen(A_Temp "\ExportFlowPrompts.error.txt", "w", "UTF-8")
            f.Write(text)
            f.Close()
        }
    }
}

ListFlowKeys() {
    keys := ""
    for item in FlowLibrary.ListFlows() {
        keys .= (keys = "" ? "" : "、") item["key"]
    }
    return (keys = "") ? "（一个都没有）" : keys
}

IssueLines(report) {
    s := ""
    for issue in report.Issues {
        if (issue.Severity != "block") {
            continue
        }
        s .= "  · " issue.Scope " — " issue.KindLabel "：" issue.Detail "`n"
    }
    return RTrim(s, "`r`n")
}
