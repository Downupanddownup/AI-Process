#Requires AutoHotkey v2.0

; 展示辅助：把标识翻成"名称（标识）"
;
; 为什么单独成文件：块维护、参考文档维护、选块弹窗三处都要用。塞进任何一个窗口文件，
; 另一个窗口就会隐性依赖它（ComboDisplayName 定义在 FlowMaintainWindow、被 FlowBlockPicker
; 调用那种先例，不值得再复制一次）。
;
; 依赖方向：ui → promptflow 的库（单向）。这里不碰窗口、不碰 owner、不写盘。

class PromptLabels {

    ; 块 → "名称（标识）"
    ; 块不存在时返回 "?缺（标识）"：列表里不能因为一个悬空 id 整页崩掉
    ; flowBlocksDir 为空时只查全局（与 BlockLibrary.Get 同义）
    static Block(blockId, flowBlocksDir := "") {
        try {
            blk := BlockLibrary.Get(blockId, flowBlocksDir)
        } catch {
            return "?缺（" blockId "）"
        }
        name := Trim(blk.Name)
        return (name = "") ? blockId : name "（" blockId "）"
    }

    ; 参考文档 → "名称（标识）"；三层查找走 ReferenceLibrary.Get，与拼装时同序
    static Ref(refId, flowKey := "") {
        try {
            doc := ReferenceLibrary.Get(refId, flowKey)
        } catch {
            return "?缺（" refId "）"
        }
        name := Trim(doc.Name)
        return (name = "") ? refId : name "（" refId "）"
    }

    ; 正文里出现的 {{ref:id}} → "名称（标识）、…"
    ; 只处理 ref: 前缀，{{filePath}} 这类固定词不碰；按首次出现顺序去重
    static RefsInBody(text, flowKey := "") {
        ids := []
        for token in PlaceholderEngine.ExtractNames(text) {
            idx := InStr(token, ":")
            if (idx <= 1 || SubStr(token, 1, idx - 1) != "ref") {
                continue
            }
            id := Trim(SubStr(token, idx + 1))
            if (id = "" || this._Has(ids, id)) {
                continue
            }
            ids.Push(id)
        }

        labels := []
        for id in ids {
            labels.Push(this.Ref(id, flowKey))
        }
        return this.Join(labels)
    }

    static Join(items, sep := "、") {
        out := ""
        for item in items {
            out .= (out = "" ? "" : sep) item
        }
        return out
    }

    static _Has(arr, value) {
        for item in arr {
            if (item = value) {
                return true
            }
        }
        return false
    }
}
