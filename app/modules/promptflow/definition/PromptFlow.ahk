#Requires AutoHotkey v2.0

; 一套流程：一组配方 + 该流程的私有块目录
; 内置流程只读，自定义流程可编辑——由 Readonly 标记，不靠目录位置判断

class PromptFlow {

    Key := ""
    Name := ""
    Readonly := false

    ; 流程目录绝对路径
    Dir := ""

    ; 私有块目录
    BlocksDir := ""

    ; 组合键 → ActionRecipe
    Recipes := Map()

    ; 从流程目录加载（目录内须有 flow.json）
    static Load(dirPath, readonly) {
        flowFile := dirPath "\flow.json"
        if !FileExist(flowFile) {
            throw Error("流程缺少 flow.json：" dirPath)
        }

        try {
            data := JSON.Load(FileRead(flowFile, "UTF-8"))
        } catch as e {
            throw Error("flow.json 解析失败：" flowFile " — " e.Message)
        }

        f := PromptFlow()
        f.Dir := dirPath
        f.BlocksDir := dirPath "\blocks"
        f.Key := data.Has("key") ? data["key"] : ""
        f.Name := data.Has("name") ? data["name"] : ""
        f.Readonly := readonly

        if data.Has("recipes") {
            for comboKey, recipeMap in data["recipes"] {
                f.Recipes[comboKey] := ActionRecipe.FromMap(comboKey, recipeMap)
            }
        }
        return f
    }

    ; 按组合键取配方；找不到抛错，不返回空
    GetRecipe(comboKey) {
        if !this.Recipes.Has(comboKey) {
            throw Error("流程 " this.Key " 没有组合的配方：" comboKey)
        }
        return this.Recipes[comboKey]
    }

    ; 全部组合键
    GetComboKeys() {
        keys := []
        for k in this.Recipes {
            keys.Push(k)
        }
        return keys
    }

    ; 该流程的私有块 id 列表
    ListBlockIds() {
        return BlockLibrary.ListIds(this.BlocksDir)
    }
}
