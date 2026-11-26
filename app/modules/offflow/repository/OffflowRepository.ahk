#Requires AutoHotkey v2.0

; 读取：只碰文件，不判断对错。
; 缺文件就是缺（返回空/空数组），由 OffflowValidator 统一报。
; 例外：RenderBody 遇到不存在的引用直接抛错——渲染出死引用比报错更坏。

class OffflowRepository {

    static RefPattern := "\{\{ref:([A-Za-z0-9_\-]+)\}\}"

    ; 数据根：本文件在 offlow\repository\ 下，上两级到 offlow，再进 data
    static DataRoot {
        get {
            dir := RegExReplace(A_LineFile, "\\[^\\]+$", "")   ; …\offlow\repository
            dir := RegExReplace(dir, "\\[^\\]+$", "")          ; …\offlow
            return dir "\data"
        }
    }

    ; 只列带 meta.json 的目录——给界面用
    static ListCategories() {
        out := []
        for dir in this._ListDirs() {
            if FileExist(dir "\meta.json") {
                out.Push(OffflowCategory.FromDir(dir))
            }
        }
        return out
    }

    ; 列全部子目录（含不合规的）——给校验器用
    static ListAllDirs() {
        return this._ListDirs()
    }

    ; 正文全文；不存在返回空串
    static ReadBody(key) {
        path := this.DataRoot "\" key "\body.txt"
        return FileExist(path) ? FileRead(path, "UTF-8") : ""
    }

    ; 该类别引用的细则；目录不存在时返回空数组
    static ListReferences(key) {
        out := []
        refRoot := this.DataRoot "\" key "\references"
        if !DirExist(refRoot) {
            return out
        }
        Loop Files, refRoot "\*", "D" {
            out.Push(OffflowReference.FromDir(A_LoopFileFullPath))
        }
        return out
    }

    ; 取一份细则；找不到返回空串（调用方自己决定怎么处理）
    static FindReference(key, id) {
        for ref in this.ListReferences(key) {
            if (ref.Id = id) {
                return ref
            }
        }
        return ""
    }

    ; 正文渲染：把 {{ref:id}} 换成细则文件的绝对路径。未知 id 直接抛错。
    ; 逐段拼接而不是用 RegExReplace 的回调：本机 AHK 的 RegExReplace 第三参只收字符串。
    static RenderBody(key) {
        body := this.ReadBody(key)
        if (body = "") {
            return ""
        }
        refs := this.ListReferences(key)

        out := ""
        pos := 1
        while RegExMatch(body, this.RefPattern, &m, pos) {
            out .= SubStr(body, pos, m.Pos - pos)
            out .= this._ResolveRefPath(refs, key, m[1])
            pos := m.Pos + m.Len
        }
        out .= SubStr(body, pos)
        return out
    }

    ; 单个占位符 → 细则绝对路径；找不到即抛错
    static _ResolveRefPath(refs, key, id) {
        for ref in refs {
            if (ref.Id = id) {
                if !ref.HasBody {
                    throw Error("细则缺 body.md：" key "/" id)
                }
                return ref.Path
            }
        }
        throw Error("引用不存在：" id "（类别 " key "）")
    }

    static _ListDirs() {
        out := []
        root := this.DataRoot
        if !DirExist(root) {
            return out
        }
        Loop Files, root "\*", "D" {
            out.Push(A_LoopFileFullPath)
        }
        return out
    }
}

