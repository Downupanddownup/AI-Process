#Requires AutoHotkey v2.0

; 占位引擎：把块文本里的 {{词}} 解释成值
; 三件事：扫出名字、校验登记、替换并检查残留
; 核心约束：未登记即报错，残留即报错

class PlaceholderEngine {

    ; 扫出文本里出现的全部占位符名（去重，按首次出现顺序）
    static ExtractNames(text) {
        names := []
        pos := 1
        while RegExMatch(text, "\{\{([^}\r\n]+)\}\}", &m, pos) {
            name := m[1]
            if !this._Has(names, name) {
                names.Push(name)
            }
            pos := m.Pos + m.Len
        }
        return names
    }

    ; 校验一段文本里的占位符是否全部登记；不通过即抛错并点名
    static Validate(text, sourceId := "") {
        all := PromptParam.LoadAll()
        missing := []
        for name in this.ExtractNames(text) {
            if !PromptParam.IsRegistered(name, all) {
                missing.Push(name)
            }
        }
        if (missing.Length > 0) {
            list := ""
            for n in missing {
                list .= (list = "" ? "" : "、") n
            }
            where := (sourceId = "") ? "" : "（来源：" sourceId "）"
            throw Error("占位符未登记：" list where)
        }
        return true
    }

    ; 替换全部占位符；替换后再扫，有残留即抛错
    static Resolve(text, env, action) {
        all := PromptParam.LoadAll()
        result := text

        ; 先扫出唯一名字，再逐个全替换——避免边换边扫导致位置漂移
        for name in this.ExtractNames(text) {
            param := PromptParam.Find(name, all)
            if (param = "") {
                throw Error("占位符未登记：" name)
            }
            value := PromptParamRule.Resolve(param.Rule, env, action)
            result := StrReplace(result, "{{" name "}}", value)
        }

        ; 残留检查
        left := this.ExtractNames(result)
        if (left.Length > 0) {
            list := ""
            for n in left {
                list .= (list = "" ? "" : "、") n
            }
            throw Error("占位符替换后仍有残留：" list)
        }
        return result
    }

    ; 私有：数组包含
    static _Has(arr, value) {
        for item in arr {
            if (item = value) {
                return true
            }
        }
        return false
    }
}
