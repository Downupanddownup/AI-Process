#Requires AutoHotkey v2.0

; 一条流程外提示词：某个任务的一整套做法（正文 + 它自己引用的细则 + 字段）。
; 字段只描述它是什么，不判断对错——判对错归 OffflowValidator。
; Key 取目录名；meta.json 若另写了 key，冲突由校验器报。

class OffflowPrompt {

    Key := ""             ; 目录名，也是取用的标识
    Name := ""            ; 显示名
    Purpose := ""         ; 这一条解决什么任务
    HasCategory := false  ; meta 里是否写了 category
    Category := ""        ; 分类标签，只用于筛选；空＝未分类
    HasHidden := false    ; meta 里是否写了 hidden
    HiddenRaw := ""       ; hidden 的原值（字符串），交给校验器判
    Hidden := false       ; 是否只在维护面板出现

    ; 从目录加载；meta.json 缺失或解析失败不抛错，字段留空
    static FromDir(dir) {
        p := OffflowPrompt()
        SplitPath(dir, &name)
        p.Key := name

        metaPath := dir "\meta.json"
        if !FileExist(metaPath) {
            return p
        }
        try {
            data := JSON.Load(FileRead(metaPath, "UTF-8"))
        } catch {
            return p
        }

        p.Name := data.Has("name") ? _OffflowPromptStr(data["name"]) : ""
        p.Purpose := data.Has("purpose") ? _OffflowPromptStr(data["purpose"]) : ""

        if data.Has("category") {
            p.HasCategory := true
            p.Category := _OffflowPromptStr(data["category"])
        }

        if data.Has("hidden") {
            p.HasHidden := true
            p.HiddenRaw := _OffflowPromptStr(data["hidden"])
            p.Hidden := (p.HiddenRaw = "1" || p.HiddenRaw = "true")
        }
        return p
    }
}

; JSON 取出来的值可能是数字/布尔，统一成字符串便于比较与展示
_OffflowPromptStr(v) {
    if (v = true) {
        return "true"
    }
    if (v = false) {
        return "false"
    }
    return String(v)
}
