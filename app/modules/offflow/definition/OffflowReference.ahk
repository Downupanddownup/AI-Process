#Requires AutoHotkey v2.0

; 一份"细则"：类别自己引用的参考资料，块正文里用 {{ref:id}} 指向它。
; 与流程的参考文档同形（body.md ＋ meta.json），但只归本类别，不与流程共享。

class OffflowReference {

    Id := ""        ; 目录名，也是 {{ref:id}} 里的 id
    Name := ""      ; 显示名
    Purpose := ""   ; 这份细则解决什么
    Path := ""      ; body.md 的绝对路径（复制时替换进正文）
    Body := ""      ; body.md 全文
    HasBody := false

    static FromDir(dir) {
        r := OffflowReference()
        SplitPath(dir, &name)
        r.Id := name
        r.Path := dir "\body.md"

        metaPath := dir "\meta.json"
        if FileExist(metaPath) {
            try {
                data := JSON.Load(FileRead(metaPath, "UTF-8"))
                r.Name := data.Has("name") ? _OffflowRefStr(data["name"]) : ""
                r.Purpose := data.Has("purpose") ? _OffflowRefStr(data["purpose"]) : ""
            }
        }

        if FileExist(r.Path) {
            r.HasBody := true
            r.Body := FileRead(r.Path, "UTF-8")
        }
        return r
    }
}

_OffflowRefStr(v) {
    if (v = true) {
        return "true"
    }
    if (v = false) {
        return "false"
    }
    return String(v)
}
