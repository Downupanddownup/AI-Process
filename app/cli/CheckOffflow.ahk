#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off

; 命令行入口：流程外提示词的自检（与界面无关，AI 可直接调用）
;
; 用法：CheckOffflow.bat [outDir]
;   产物：<outDir>\offlow-check.txt
;     通过 → 第一行 OK，第二行条数
;     失败 → 逐行「条目 / 文件 / 问题」
;   成败只认产物文件，不看 stdout、不看退出码（项目既有经验）。
; 纪律：不弹窗、OnError 兜底、60 秒自灭。

OnError(ErrHandler)
SetTimer(OnTimeout, -60000)

global AppRoot := RegExReplace(A_ScriptDir, "\\[^\\]+$", "")
global ConfigDir := AppRoot "\config"
global TemplateDir := AppRoot "\templates"
global ModulesDir := AppRoot "\modules"
global DataDir := AppRoot "\data"
global LibDir := AppRoot "\lib"

global gOutDir := A_Temp
global gPromptMarker := ".offlow-prompts"   ; 成品目录归属标记：没有它，一个文件都不删

#Include %A_ScriptDir%\..\lib\JSON.ahk
#Include %A_ScriptDir%\..\modules\offflow\definition\OffflowPrompt.ahk
#Include %A_ScriptDir%\..\modules\offflow\definition\OffflowReference.ahk
#Include %A_ScriptDir%\..\modules\offflow\repository\OffflowRepository.ahk
#Include %A_ScriptDir%\..\modules\offflow\action\OffflowPromptReferenceCopy.ahk
#Include %A_ScriptDir%\..\modules\offflow\validation\OffflowValidator.ahk

; ---- 输出目录 ----

args := A_Args
if (args.Length >= 1 && Trim(args[1]) != "") {
    gOutDir := Trim(args[1])
}
if !DirExist(gOutDir) {
    try {
        DirCreate(gOutDir)
    } catch {
        gOutDir := A_Temp
    }
}

target := gOutDir "\offlow-check.txt"

; ---- 跑校验 ----

problems := []
try {
    problems := OffflowValidator.CheckAll()
} catch as e {
    Fail("自检脚本异常（第 " e.Line " 行）：" e.Message)
}

; ---- 落成品 + 一致性断言 ----
; 每条落一份成品文件，内容就是 RenderBody 的返回值——一个字节不加，
; 等价于"取用时复制到剪贴板的那段"。写完立刻读回比对，不等即报错。

promptDir := gOutDir "\offlow-prompts"
keys := []

; 先确认成品目录是我们的再清空；不是就一个文件都不删、也不写成品
refuse := PreparePromptDir(promptDir)
if (refuse != "") {
    problems.Push("offlow-prompts / " promptDir " / " refuse)
} else {
    try {
        for dir in OffflowRepository.ListAllDirs() {
            SplitPath(dir, &key)
            keys.Push(key)

            try {
                body := OffflowRepository.RenderBody(key)
            } catch as e {
                problems.Push(key " / offlow-prompts/" key ".txt / 渲染失败：" e.Message)
                continue
            }

            path := promptDir "\" key ".txt"
            if !WriteRaw(path, body) {
                problems.Push(key " / offlow-prompts/" key ".txt / 写不进去")
                continue
            }
            if (ReadRaw(path) != body) {
                problems.Push(key " / offlow-prompts/" key ".txt / 成品与渲染不一致")
            }
        }
    } catch as e {
        Fail("自检脚本异常（第 " e.Line " 行）：" e.Message)
    }
}

; ---- 写报告 ----
; 报告只放结论与索引；提示词成品在 offlow-prompts\ 下，各占一个文件。

text := (problems.Length = 0)
    ? "OK`n条数：" OffflowValidator.CountPrompts() "`n"
    : "失败 " problems.Length " 条`n"

if (problems.Length > 0) {
    for p in problems {
        text .= p "`n"
    }
}

text .= "`n成品：" promptDir "`n"
text .= "条目：" JoinKeys(keys) "`n"
WriteText(target, text)
ExitApp(problems.Length = 0 ? 0 : 2)

; ---- 函数 ----

JoinKeys(keys) {
    s := ""
    for k in keys {
        s .= (s = "" ? "" : "、") k
    }
    return (s = "") ? "（无）" : s
}

; 准备成品目录：只有确认是我们的才清空；返回空串表示可以写
; - 不存在：建目录 + 写标记
; - 存在且有标记：只删该目录下 *.txt（不递归、不删子目录、不删目录）
; - 存在但无标记：一个文件都不删，返回拒绝原因
PreparePromptDir(dir) {
    global gPromptMarker
    marker := dir "\" gPromptMarker

    if !DirExist(dir) {
        try {
            DirCreate(dir)
        } catch {
            return "成品目录建不出来：" dir
        }
        try {
            f := FileOpen(marker, "w", "UTF-8-RAW")
            f.Write("offlow prompts dir`n")
            f.Close()
        } catch {
            return "成品目录标记写不进去：" marker
        }
        return ""
    }

    if !FileExist(marker) {
        return "成品目录已存在且非本工具创建，未做清空（换一个输出目录，或人工确认后放一份 " gPromptMarker "）"
    }

    Loop Files, dir "\*.txt", "F" {
        try FileDelete(A_LoopFileFullPath)
    }
    return ""
}

; 原样写：UTF-8 无 BOM、不追加换行（BOM 会让成品与剪贴板差三个字节）
WriteRaw(path, text) {
    SplitPath(path, , &parentDir)
    if (parentDir != "" && !DirExist(parentDir)) {
        try {
            DirCreate(parentDir)
        } catch {
            return false
        }
    }
    try {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
        return true
    } catch {
        return false
    }
}

; 原样读回，用于断言
ReadRaw(path) {
    try {
        f := FileOpen(path, "r", "UTF-8-RAW")
        s := f.Read()
        f.Close()
        return s
    } catch {
        return ""
    }
}

ErrHandler(e, mode) {
    Fail("脚本异常（第 " e.Line " 行）：" e.Message)
}

OnTimeout(*) {
    Fail("自检超时（60 秒），未产出文件。")
}

Fail(msg) {
    global gOutDir
    WriteText(gOutDir "\offlow-check.txt", msg "`n")
    ExitApp(2)
}

WriteText(path, text) {
    try {
        f := FileOpen(path, "w", "UTF-8")
        f.Write(text)
        f.Close()
    } catch {
        try {
            f := FileOpen(A_Temp "\offlow-check.txt", "w", "UTF-8")
            f.Write(text)
            f.Close()
        }
    }
}
