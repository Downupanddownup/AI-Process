#Requires AutoHotkey v2.0

; 参考文档写回：建 / 改元数据 / 改正文 / 删
;
; 只写 flows/custom/<key>/references/，内置流程一律拒绝；
; 不依赖 UI 与主题。写后用 ReferenceLibrary.ClearCache() 让读取方看到新内容。
;
; 引用反查扫的是块正文里的 {{ref:<id>}}——与块维护"扫 flow.json 配方"是两种匹配，
; 因为参考文档被引用在正文里，不在配方里。

class ReferenceEditor {

    ; 新建：目录 + meta.json + 空 body.md；失败整目录删掉
    static Create(flowKey, refId, name, purpose) {
        flow := this._WritableFlow(flowKey)
        this._ValidateFields(name, purpose)

        err := this.ValidateId(flowKey, refId)
        if (err != "")
            throw Error(err)

        dirPath := flow.ReferencesDir "\" refId
        try {
            DirCreate(dirPath)
            JsonConfigWriter.WriteAtomic(dirPath "\meta.json", this._MetaText(name, purpose))
            f := FileOpen(dirPath "\body.md", "w", "UTF-8-RAW")
            f.Close()
        } catch as e {
            if DirExist(dirPath)
                DirDelete(dirPath, true)
            throw e
        }

        ReferenceLibrary.ClearCache()
        return dirPath
    }

    ; 改元数据：id 不可改
    static UpdateMeta(flowKey, refId, name, purpose) {
        flow := this._WritableFlow(flowKey)
        this._ValidateFields(name, purpose)

        dirPath := flow.ReferencesDir "\" refId
        if !DirExist(dirPath)
            throw Error("参考文档不存在：" refId)

        JsonConfigWriter.WriteAtomic(dirPath "\meta.json", this._MetaText(name, purpose))
        ReferenceLibrary.ClearCache()
    }

    ; 写正文：只动 body.md，不动 meta.json
    static UpdateBody(flowKey, refId, text) {
        flow := this._WritableFlow(flowKey)

        dirPath := flow.ReferencesDir "\" refId
        if !DirExist(dirPath)
            throw Error("参考文档不存在：" refId)

        try {
            f := FileOpen(dirPath "\body.md", "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
        } catch as e {
            throw Error("写入参考文档正文失败：" dirPath " — " e.Message)
        }

        ReferenceLibrary.ClearCache()
    }

    ; 删除：被本流程任一私有块的正文引用就拦下，消息里点名块
    static Delete(flowKey, refId) {
        flow := this._WritableFlow(flowKey)

        dirPath := flow.ReferencesDir "\" refId
        if !DirExist(dirPath)
            throw Error("参考文档不存在：" refId)

        used := this.UsedByBlocks(flowKey, refId)
        if (used.Length > 0)
            throw Error("参考文档仍被块引用：" this._Join(used))

        DirDelete(dirPath, true)
        ReferenceLibrary.ClearCache()
    }

    ; id 合法性：空串表示通过；只与本流程私有比，允许与全局同名（复制私有副本的用法）
    static ValidateId(flowKey, refId) {
        flow := FlowLibrary.Get(flowKey)

        if (Trim(refId) = "")
            return "参考文档标识不能为空"
        if !RegExMatch(refId, "^[a-z0-9_]{1,40}$")
            return "参考文档标识只能用英文小写字母、数字与下划线：" refId
        if DirExist(flow.ReferencesDir "\" refId)
            return "参考文档已存在：" refId
        return ""
    }

    ; 本流程里正文引用了该文档的块 id
    static UsedByBlocks(flowKey, refId) {
        flow := FlowLibrary.Get(flowKey)
        used := []

        pattern := "\{\{ref:\s*" refId "\s*\}\}"
        for blockId in BlockLibrary.ListIds(flow.BlocksDir) {
            bodyPath := flow.BlocksDir "\" blockId "\body.txt"
            if !FileExist(bodyPath)
                continue
            if RegExMatch(FileRead(bodyPath, "UTF-8"), pattern) {
                used.Push(blockId)
            }
        }
        return used
    }

    ; ---- 私有 ----

    static _WritableFlow(flowKey) {
        flow := FlowLibrary.Get(flowKey)
        if (flow.Readonly)
            throw Error("内置流程只读，不能修改：" flowKey)
        return flow
    }

    static _ValidateFields(name, purpose) {
        if (Trim(name) = "")
            throw Error("参考文档名称不能为空")
        if (Trim(purpose) = "")
            throw Error("参考文档说明不能为空")
    }

    ; 固定字段序、两空格、末尾换行——与 data/references/*/meta.json 一致；参考文档没有 kind
    static _MetaText(name, purpose) {
        return "{`n"
            . "  `"name`": " JsonConfigWriter.Quote(name) ",`n"
            . "  `"purpose`": " JsonConfigWriter.Quote(purpose) "`n"
            . "}`n"
    }

    static _Join(arr) {
        out := ""
        for item in arr
            out .= (out = "" ? "" : "、") item
        return out
    }
}
