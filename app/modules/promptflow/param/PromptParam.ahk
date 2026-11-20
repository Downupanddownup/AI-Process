#Requires AutoHotkey v2.0

; 占位登记：一个占位符在中央词表里的条目
; 数据源：data/param/registry.json

class PromptParam {

    ; 占位符名，不含花括号
    Name := ""

    ; 给人看的含义
    Meaning := ""

    ; 解析规则标识，交给 PromptParamRule 查表
    Rule := ""

    ; 取自哪里（人看，不参与计算）
    Source := ""

    ; 数据根：promptflow/data（本文件在 promptflow/param/ 下）
    static DataRoot {
        get {
            return RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+$", "") "\data"
        }
    }

    ; 词表路径
    static RegistryPath {
        get {
            return this.DataRoot "\param\registry.json"
        }
    }

    ; 加载整份词表：返回 Map(name → PromptParam)
    static LoadAll() {
        path := this.RegistryPath
        if !FileExist(path) {
            throw Error("占位词表不存在：" path)
        }
        try {
            data := JSON.Load(FileRead(path, "UTF-8"))
        } catch as e {
            throw Error("占位词表解析失败：" path " — " e.Message)
        }

        all := Map()
        for name, item in data {
            p := PromptParam()
            p.Name := name
            p.Meaning := item.Has("meaning") ? item["meaning"] : ""
            p.Rule := item.Has("rule") ? item["rule"] : ""
            p.Source := item.Has("source") ? item["source"] : ""
            all[name] := p
        }
        return all
    }

    ; 按名查；找不到返回空串
    static Find(name, all) {
        return all.Has(name) ? all[name] : ""
    }

    ; 是否已登记
    static IsRegistered(name, all) {
        return all.Has(name)
    }
}
