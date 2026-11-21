#Requires AutoHotkey v2.0

; 私有块写回：建 / 改元数据 / 删
;
; 只写 flows/<builtin|custom>/<key>/blocks/，内置流程一律拒绝；
; 不依赖 UI 与主题。写后用 BlockLibrary.ClearCache() 让读取方看到新内容。
;
; 引用反查只查本流程的 flow.json——私有块不跨流程，跨流程引用本来就不成立。

class BlockEditor {

    ; 与 meta.json 的 kind 取值一致（配置规范 §3.3）
    static KindValues := [
        "禁止修改", "提问", "复杂度分析", "质量把控",
        "执行策略", "复盘模式", "结果格式", "内容约束"
    ]

    ; 新建块：目录 + meta.json + 空 body.txt；失败整目录删掉
    static Create(flowKey, blockId, name, purpose, kind) {
        flow := this._WritableFlow(flowKey)
        this._ValidateFields(name, purpose, kind)

        err := this.ValidateId(flowKey, blockId)
        if (err != "")
            throw Error(err)

        dirPath := flow.BlocksDir "\" blockId
        try {
            DirCreate(dirPath)
            JsonConfigWriter.WriteAtomic(dirPath "\meta.json", this._MetaText(name, purpose, kind))
            f := FileOpen(dirPath "\body.txt", "w", "UTF-8-RAW")
            f.Close()
        } catch as e {
            if DirExist(dirPath)
                DirDelete(dirPath, true)
            throw e
        }

        BlockLibrary.ClearCache()
        return dirPath
    }

    ; 改元数据：id 不可改
    static UpdateMeta(flowKey, blockId, name, purpose, kind) {
        flow := this._WritableFlow(flowKey)
        this._ValidateFields(name, purpose, kind)

        dirPath := flow.BlocksDir "\" blockId
        if !DirExist(dirPath)
            throw Error("块不存在：" blockId)

        JsonConfigWriter.WriteAtomic(dirPath "\meta.json", this._MetaText(name, purpose, kind))
        BlockLibrary.ClearCache()
    }

    ; 写正文：只动 body.txt，不动 meta.json
    static UpdateBody(flowKey, blockId, text) {
        flow := this._WritableFlow(flowKey)

        dirPath := flow.BlocksDir "\" blockId
        if !DirExist(dirPath)
            throw Error("块不存在：" blockId)

        try {
            f := FileOpen(dirPath "\body.txt", "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
        } catch as e {
            throw Error("写入块正文失败：" dirPath " — " e.Message)
        }

        BlockLibrary.ClearCache()
    }

    ; 删除：被本流程任何组合引用就拦下，消息里点名组合
    static Delete(flowKey, blockId) {
        flow := this._WritableFlow(flowKey)

        dirPath := flow.BlocksDir "\" blockId
        if !DirExist(dirPath)
            throw Error("块不存在：" blockId)

        used := this.UsedByCombos(flowKey, blockId)
        if (used.Length > 0)
            throw Error("块仍被引用：" this._Join(used))

        DirDelete(dirPath, true)
        BlockLibrary.ClearCache()
    }

    ; id 合法性：空串表示通过；只与本流程比，允许与全局块同名（复制私有副本的用法）
    static ValidateId(flowKey, blockId) {
        flow := FlowLibrary.Get(flowKey)

        if (Trim(blockId) = "")
            return "块标识不能为空"
        if !RegExMatch(blockId, "^[a-z0-9_]{1,40}$")
            return "块标识只能用英文小写字母、数字与下划线：" blockId
        if DirExist(flow.BlocksDir "\" blockId)
            return "块已存在：" blockId
        return ""
    }

    ; 本流程里引用了该块的组合键
    static UsedByCombos(flowKey, blockId) {
        flow := FlowLibrary.Get(flowKey)
        used := []
        for comboKey, recipe in flow.Recipes {
            for id in recipe.Content {
                if (id = blockId) {
                    used.Push(comboKey)
                    break
                }
            }
        }
        return used
    }

    ; ---- 私有 ----

    static _WritableFlow(flowKey) {
        flow := FlowLibrary.Get(flowKey)
        if (flow.Readonly)
            throw Error("内置流程的块不可修改：" flowKey)
        return flow
    }

    static _ValidateFields(name, purpose, kind) {
        if (Trim(name) = "")
            throw Error("块名称不能为空")
        if (Trim(purpose) = "")
            throw Error("块说明不能为空")
        ; 分类只是给人看的标签：八类作建议，允许自由新增
        if (Trim(kind) = "")
            throw Error("块分类不能为空")
        if (StrLen(Trim(kind)) > 12)
            throw Error("块分类过长（最多 12 字）：" kind)
    }

    ; 固定字段序、两空格、末尾换行——与 data/blocks/*/meta.json 一致
    static _MetaText(name, purpose, kind) {
        return "{`n"
            . "  `"name`": " JsonConfigWriter.Quote(name) ",`n"
            . "  `"purpose`": " JsonConfigWriter.Quote(purpose) ",`n"
            . "  `"kind`": " JsonConfigWriter.Quote(kind) "`n"
            . "}`n"
    }

    static _Join(arr) {
        out := ""
        for item in arr
            out .= (out = "" ? "" : "、") item
        return out
    }

    static _HasValue(arr, value) {
        for item in arr {
            if (item = value)
                return true
        }
        return false
    }
}
