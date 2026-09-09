#Requires AutoHotkey v2.0

; 提示词元素库：可复用业务元素，每个元素自包含"内容 + 生效条件"
; 收编自 PromptManager 的六个 AppendXxxIfNeeded，语义逐行等价：
; - 开关关闭 → 原样返回；开关开启 → 追加对应段落
; - 不修改/提问规则：模板内容 Trim 首尾空白，空内容不追加
; - 执行通知/完成通知：无条件追加，"完成通知"开关只控制 -Silent 有无
; - 拼接规则：RTrim(已有内容) + 一个空行 + 段落

class PromptElements {

    ; 行为约束：不修改正式代码（开关 AppendNoModifyPrompt）
    static NoModify(content) {
        if !GetSession(GetActiveWindowId(), "AppendNoModifyPrompt") {
            return content
        }
        extraPrompt := Trim(PromptElements._LoadTemplate("elements\no_modify_prompt.txt"), "`r`n `t")
        if (extraPrompt = "") {
            return content
        }
        return PromptElements._Append(content, extraPrompt)
    }

    ; 提问规则（开关 AppendQuestionRules）
    static QuestionRules(content) {
        if !GetSession(GetActiveWindowId(), "AppendQuestionRules") {
            return content
        }
        rulesContent := Trim(PromptElements._LoadTemplate("elements\question_rules.txt"), "`r`n `t")
        if (rulesContent = "") {
            return content
        }
        return PromptElements._Append(content, rulesContent)
    }

    ; 提问模板指引（开关 AppendQuestionTemplate；模板缺失抛错，对齐原 EnsureTemplateExists）
    static QuestionTemplate(content) {
        global TemplateDir
        if !GetSession(GetActiveWindowId(), "AppendQuestionTemplate") {
            return content
        }
        PromptElements._EnsureTemplate("elements\question_format.txt")
        hint := "如需提问，请参照提问模板：" TemplateDir "\elements\question_format.txt"
        return PromptElements._Append(content, hint)
    }

    ; 打开 md 结束指令（开关 OpenMdWithIdea；模板原样追加，不 Trim）
    static OpenMd(content) {
        global AppConfig
        if !GetSession(GetActiveWindowId(), "OpenMdWithIdea") {
            return content
        }
        template := PromptElements._LoadTemplate("elements\open_md_prompt.txt")
        template := StrReplace(template, "{{scriptPath}}", AppConfig["OpenMdScriptPath"])
        template := StrReplace(template, "{{windowId}}", GetActiveWindowId())
        return PromptElements._Append(content, template)
    }

    ; 执行完成通知（无条件追加；ShowExecuteNotification 关时以 -Silent 调用）
    static ExecuteNotification(content) {
        global AppConfig
        windowId := GetActiveWindowId()
        template := PromptElements._LoadTemplate("elements\execute_notification_prompt.txt")
        template := StrReplace(template, "{{scriptPath}}", AppConfig["NotificationScriptPath"])
        template := StrReplace(template, "{{windowId}}", windowId)
        silentArg := GetSession(windowId, "ShowExecuteNotification") ? "" : " -Silent"
        template := StrReplace(template, "{{silentArg}}", silentArg)
        return PromptElements._Append(content, template)
    }

    ; 上下文重建完成通知（无条件追加；-Silent 同上）
    static ContextRelationTail(content) {
        global AppConfig
        windowId := GetActiveWindowId()
        template := PromptElements._LoadTemplate("elements\context_relation_tail.txt")
        template := StrReplace(template, "{{scriptPath}}", AppConfig["NotificationScriptPath"])
        template := StrReplace(template, "{{windowId}}", windowId)
        silentArg := GetSession(windowId, "ShowExecuteNotification") ? "" : " -Silent"
        template := StrReplace(template, "{{silentArg}}", silentArg)
        return PromptElements._Append(content, template)
    }

    ; ---- 私有技术方法 ----

    ; 拼接：已有内容去尾换行 + 一个空行 + 段落（对齐旧各 Append 函数）
    static _Append(content, extra) {
        return RTrim(content, "`r`n") "`r`n`r`n" extra
    }

    ; 模板读取（= 原 LoadTemplate，私有副本，避免跨层耦合）
    static _LoadTemplate(fileName) {
        global TemplateDir
        path := TemplateDir "\" fileName
        if !FileExist(path) {
            LogError("模板文件不存在：" path)
            throw Error("模板文件不存在：" path)
        }
        return FileRead(path, "UTF-8")
    }

    ; 模板存在性检查（= 原 EnsureTemplateExists）
    static _EnsureTemplate(fileName) {
        global TemplateDir
        path := TemplateDir "\" fileName
        if !FileExist(path) {
            LogError("模板文件不存在：" path)
            throw Error("模板文件不存在：" path)
        }
    }
}
