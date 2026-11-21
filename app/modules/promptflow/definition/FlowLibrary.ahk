#Requires AutoHotkey v2.0

; 流程库：发现内置与自定义流程、读取、缓存
; 两个固定入口：data/flows/builtin（只读）、data/flows/custom（可编辑）
; 不靠"找找看哪个是只读的"

class FlowLibrary {

    static _cache := Map()

    ; 数据根：promptflow/data
    static DataRoot {
        get {
            return RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+$", "") "\data"
        }
    }

    static BuiltinRoot {
        get {
            return this.DataRoot "\flows\builtin"
        }
    }

    static CustomRoot {
        get {
            return this.DataRoot "\flows\custom"
        }
    }

    ; 全部流程 key（内置 + 自定义）
    static ListKeys() {
        keys := []
        for key in this._ScanDir(this.BuiltinRoot) {
            keys.Push(key)
        }
        for key in this._ScanDir(this.CustomRoot) {
            if !this._Has(keys, key) {
                keys.Push(key)
            }
        }
        return keys
    }

    ; 全部流程的摘要信息，内置在前
    ; → [{key, name, shortName, readonly}, ...]
    ; 不动 ListKeys()——02 的切流程弹窗在用它
    static ListFlows() {
        result := []
        for key in this.ListKeys() {
            try {
                f := this.Get(key)
                result.Push(Map(
                    "key", f.Key,
                    "name", f.Name,
                    "shortName", f.ShortName,
                    "readonly", f.Readonly))
            }
        }
        return result
    }

    ; 按 key 取流程。先内置、后自定义；同名以内置为准
    static Get(flowKey) {
        builtinPath := this.BuiltinRoot "\" flowKey
        if (DirExist(builtinPath) && FileExist(builtinPath "\flow.json")) {
            return this._LoadCached(builtinPath, true)
        }
        customPath := this.CustomRoot "\" flowKey
        if (DirExist(customPath) && FileExist(customPath "\flow.json")) {
            return this._LoadCached(customPath, false)
        }
        throw Error("流程不存在：" flowKey "（已找：" builtinPath "、" customPath "）")
    }

    ; 默认流程：内置 code
    static GetDefault() {
        return this.Get("code")
    }

    ; 清缓存
    static ClearCache() {
        this._cache := Map()
    }

    ; ---- 私有 ----

    static _LoadCached(dirPath, readonly) {
        if !this._cache.Has(dirPath) {
            this._cache[dirPath] := PromptFlow.Load(dirPath, readonly)
        }
        return this._cache[dirPath]
    }

    ; 扫一层子目录，只收含 flow.json 的
    static _ScanDir(root) {
        keys := []
        if !DirExist(root) {
            return keys
        }
        Loop Files, root "\*", "D" {
            dirPath := A_LoopFileFullPath
            if FileExist(dirPath "\flow.json") {
                keys.Push(A_LoopFileName)
            }
        }
        return keys
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
