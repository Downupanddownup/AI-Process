#Requires AutoHotkey v2.0

; 解析规则表：占位符标识 → 取值方式
; 十条规则；两条带动作分支（action.input / config.resultTemplate）
; 依赖：VersionChain、ContextRebuildManifest、DomainConventions 属内核能力，直接复用

class PromptParamRule {

    ; 规则入口：rule 为标识符，env 为运行环境，action 为当前动作
    static Resolve(rule, env, action) {
        if (rule = "action.input") {
            return this._ActionInput(env, action)
        }
        if (rule = "chain.nextName") {
            chain := VersionChain.Of(env.TopicDir)
            return "v" chain.NextVersion() ".md"
        }
        if (rule = "chain.nextPath") {
            chain := VersionChain.Of(env.TopicDir)
            return chain.NextVersionPath()
        }
        if (rule = "chain.resultPath") {
            chain := VersionChain.Of(env.TopicDir)
            return chain.Dir "\" chain.ResultName()
        }
        if (rule = "config.resultTemplate") {
            return this._ResultTemplate(action)
        }
        if (rule = "manifest.summary") {
            ; RTrim：规则的值会插在段中间，末尾换行会与拼装的分隔符叠成多一个空行
            return RTrim(ContextRebuildManifest.Build(env.TopicDir)["Summary"], "`r`n")
        }
        if (rule = "manifest.text") {
            return RTrim(ContextRebuildManifest.Build(env.TopicDir)["ManifestText"], "`r`n")
        }
        if (rule = "config.openMdScript") {
            return env.OpenMdScriptPath
        }
        if (rule = "config.notifyScript") {
            return env.NotificationScriptPath
        }
        if (rule = "window.active") {
            return (env.WindowId != "") ? env.WindowId : GetActiveWindowId()
        }
        if (rule = "window.topicDir") {
            return env.TopicDir
        }
        throw Error("未知的占位规则：" rule)
    }

    ; ---- 私有：按动作分支的两条 ----

    ; 输入文件：按动作取
    static _ActionInput(env, action) {
        chain := VersionChain.Of(env.TopicDir)

        ; 复需求：读需求.txt
        if (action.Key = "复需求") {
            return chain.RequirementPath()
        }

        ; 复回复（两条策略）：读最新回复
        if (action.Key = "复回复") {
            return chain.LatestReplyPath()
        }

        ; 复执行 步目：三档依据（实施文档 → 最新回复 → 最新版本文档）
        if (action.Key = "复执行") {
            return this._StepsSource(chain)
        }

        throw Error("动作 " action.Key " 不使用 filePath 占位符")
    }

    ; 步目拆分依据三档；三档全无则报错
    static _StepsSource(chain) {
        p := chain.ImplDocPath()
        if FileExist(p) {
            return p
        }
        p := chain.LatestReplyPath()
        if FileExist(p) {
            return p
        }
        p := chain.LatestVersionPath()
        if FileExist(p) {
            return p
        }
        throw Error("步目需要实施文档、最新回复或版本文档作为拆分依据，当前都没有")
    }

    ; 结果文档模板：tweak 用 result_doc.md，steps_dir 用 steps_result_doc.md
    static _ResultTemplate(action) {
        global TemplateDir
        if (action.Key != "复执行") {
            throw Error("动作 " action.Key " 不使用 resultTemplatePath 占位符")
        }
        if (action.SelectedPolicy = "steps_dir") {
            return TemplateDir "\execute\steps_result_doc.md"
        }
        return TemplateDir "\execute\result_doc.md"
    }
}
