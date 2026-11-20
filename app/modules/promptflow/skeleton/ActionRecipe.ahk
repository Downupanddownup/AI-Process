#Requires AutoHotkey v2.0

; 一个组合的配方：挂点 → 块 id 列表
; 只有 content 这一个挂点

class ActionRecipe {

    ; "动作|策略"，如 "复回复|impl"
    ComboKey := ""

    ; content 挂点上挂的块 id，顺序即拼装顺序
    Content := []

    ; 从 flow.json 的一条 recipe 构造
    static FromMap(comboKey, m) {
        r := ActionRecipe()
        r.ComboKey := comboKey
        if m.Has("content") {
            for id in m["content"] {
                r.Content.Push(id)
            }
        }
        return r
    }

    ; 是否空配方（复执行两个策略就是空的）
    IsEmpty() {
        return this.Content.Length = 0
    }
}
