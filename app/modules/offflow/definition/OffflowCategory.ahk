#Requires AutoHotkey v2.0

; 一个"类别"：同一类任务的一整套做法。
; 字段只描述它是什么，不判断对错——判对错归 OffflowValidator。
; Key 取目录名；meta.json 若另写了 key，冲突由校验器报。

class OffflowCategory {

    Key := ""           ; 目录名，也是取用的标识
    Name := ""          ; 界面显示名
    Purpose := ""       ; 这套做法解决什么任务
    HasHidden := false  ; meta 里是否写了 hidden
    HiddenRaw := ""     ; hidden 的原值（字符串），交给校验器判
    Hidden := false     ; 是否只在维护面板出现

    ; 从目录加载；meta.json 缺失或解析失败不抛错，字段留空
    static FromDir(dir) {
        c := OffflowCategory()
        SplitPath(dir, &name)
        c.Key := name

        metaPath := dir "\meta.json"
        if !FileExist(metaPath) {
            return c
        }
        try {
            data := JSON.Load(FileRead(metaPath, "UTF-8"))
        } catch {
            return c
        }

        c.Name := data.Has("name") ? _OffflowStr(data["name"]) : ""
        c.Purpose := data.Has("purpose") ? _OffflowStr(data["purpose"]) : ""

        if data.Has("hidden") {
            c.HasHidden := true
            c.HiddenRaw := _OffflowStr(data["hidden"])
            c.Hidden := (c.HiddenRaw = "1" || c.HiddenRaw = "true")
        }
        return c
    }
}

; JSON 取出来的值可能是数字/布尔，统一成字符串便于比较与展示
_OffflowStr(v) {
    if (v = true) {
        return "true"
    }
    if (v = false) {
        return "false"
    }
    return String(v)
}
