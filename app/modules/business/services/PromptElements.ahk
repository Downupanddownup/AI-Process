#Requires AutoHotkey v2.0

; 提示词元素库：可复用业务元素，每个元素自包含"内容 + 生效条件"
; 收编自 PromptManager 的六个 AppendXxxIfNeeded，恒化后语义：
; - 元素均为必选（原开关判定已删除，不再读取会话开关）
; - 不修改/提问规则：模板内容 Trim 首尾空白，空内容不追加
; - 完成通知（上下文重建）：无条件追加，恒定非静默（-Silent 已随开关移除）
; - 拼接规则：RTrim(已有内容) + 一个空行 + 段落

class PromptElements {

    ; 业务元素：行为约束（不修改正式代码）
    static NoModify(content) {
        extraPrompt := Trim(PromptElements._LoadTemplate("elements\no_modify_prompt.txt"), "`r`n `t")
        if (extraPrompt = "") {
            return content
        }
        return PromptElements._Append(content, extraPrompt)
    }

    ; 业务元素：提问规则（仅复需求走，由行为类调用决定）
    static QuestionRules(content) {
        rulesContent := Trim(PromptElements._LoadTemplate("elements\question_rules.txt"), "`r`n `t")
        if (rulesContent = "") {
            return content
        }
        return PromptElements._Append(content, rulesContent)
    }

    ; 业务元素：提问模板指引（模板缺失抛错，对齐原 EnsureTemplateExists）
    static QuestionTemplate(content) {
        global TemplateDir
        PromptElements._EnsureTemplate("elements\question_format.txt")
        hint := "如需提问，请参照提问模板：" TemplateDir "\elements\question_format.txt"
        return PromptElements._Append(content, hint)
    }

    ; 业务元素：打开 md 结束指令（模板原样追加，不 Trim）
    static OpenMd(content) {
        global AppConfig
        template := PromptElements._LoadTemplate("elements\open_md_prompt.txt")
        template := StrReplace(template, "{{scriptPath}}", AppConfig["OpenMdScriptPath"])
        template := StrReplace(template, "{{windowId}}", GetActiveWindowId())
        return PromptElements._Append(content, template)
    }

    ; 业务元素：上下文重建完成通知（无条件追加，恒定非静默）
    static ContextRelationTail(content) {
        global AppConfig
        windowId := GetActiveWindowId()
        template := PromptElements._LoadTemplate("elements\context_relation_tail.txt")
        template := StrReplace(template, "{{scriptPath}}", AppConfig["NotificationScriptPath"])
        template := StrReplace(template, "{{windowId}}", windowId)
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
