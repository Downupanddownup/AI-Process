#Requires AutoHotkey v2.0

; 占位引擎：把块文本里的 {{词}} 解释成值
; 两类占位符：
;   固定词（filePath / windowId …）—— 查词表
;   引用（{{ref:<id>}}）—— 查 _kinds，再查参考文档库
; 核心约束：未登记即报错，未知类型即报错，残留即报错

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

    ; 校验一段文本：固定词必须在词表里，引用必须有对应的类型定义
    static Validate(text, sourceId := "") {
        all := PromptParam.LoadAll()
        kinds := PromptParam.GetKinds()
        missing := []
        badKind := []
        for name in this.ExtractNames(text) {
            prefix := this._PrefixOf(name)
            if (prefix != "") {
                if !kinds.Has(prefix) {
                    badKind.Push(prefix)
                }
                continue
            }
            if !PromptParam.IsRegistered(name, all) {
                missing.Push(name)
            }
        }
        where := (sourceId = "") ? "" : "（来源：" sourceId "）"
        if (badKind.Length > 0) {
            throw Error("未知的占位符类型：" this._Join(badKind) where)
        }
        if (missing.Length > 0) {
            throw Error("占位符未登记：" this._Join(missing) where)
        }
        return true
    }

    ; 替换全部占位符；替换后再扫，有残留即抛错
    static Resolve(text, env, action) {
        all := PromptParam.LoadAll()
        kinds := PromptParam.GetKinds()
        result := text

        for name in this.ExtractNames(text) {
            prefix := this._PrefixOf(name)
            if (prefix != "") {
                if !kinds.Has(prefix) {
                    throw Error("未知的占位符类型：" prefix)
                }
                refId := SubStr(name, StrLen(prefix) + 2)
                if (prefix = "ref") {
                    value := ReferenceLibrary.Get(refId, env.FlowKey).BodyPath
                } else {
                    throw Error("占位符类型没有实现：" prefix)
                }
            } else {
                param := PromptParam.Find(name, all)
                if (param = "") {
                    throw Error("占位符未登记：" name)
                }
                value := PromptParamRule.Resolve(param.Rule, env, action)
            }
            result := StrReplace(result, "{{" name "}}", value)
        }

        ; 残留检查
        left := this.ExtractNames(result)
        if (left.Length > 0) {
            throw Error("占位符替换后仍有残留：" this._Join(left))
        }
        return result
    }

    ; ---- 私有 ----

    ; 名字里含冒号则返回冒号前的类型前缀，否则返回空
    static _PrefixOf(name) {
        idx := InStr(name, ":")
        return (idx > 1) ? SubStr(name, 1, idx - 1) : ""
    }

    static _Join(arr) {
        s := ""
        for x in arr {
            s .= (s = "" ? "" : "、") x
        }
        return s
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
