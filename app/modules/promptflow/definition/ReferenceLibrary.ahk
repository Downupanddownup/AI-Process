#Requires AutoHotkey v2.0

; 参考文档库：三层查找、列、计数
; 查找顺序：流程内 → 骨架私有 → 全局
; Get 与 ListAll 必须同序，同一 id 只取最先命中——否则会出现"列表里有、按 id 取却拿到另一份"

class ReferenceLibrary {

    static _cache := Map()

    ; 数据根：promptflow\data（本文件在 promptflow\definition\ 下，上两级）
    static DataRoot {
        get {
            return RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+$", "") "\data"
        }
    }

    ; 三层路径
    static _GlobalRoot {
        get {
            return this.DataRoot "\references"
        }
    }

    static _SkeletonRoot {
        get {
            return this.DataRoot "\skeleton\references"
        }
    }

    ; 流程内：内置与自定义两处都试
    static _FlowRoots(flowKey) {
        root := this.DataRoot "\flows"
        return [root "\builtin\" flowKey "\references", root "\custom\" flowKey "\references"]
    }

    ; 按 id 取一个；三层都不在则抛错并列出找过的路径
    static Get(id, flowKey := "") {
        for pair in this._Candidates(id, flowKey) {
            dirPath := pair[2]
            if DirExist(dirPath) {
                return this._LoadCached(dirPath, pair[1], flowKey)
            }
        }
        tried := ""
        for pair in this._Candidates(id, flowKey) {
            tried .= (tried = "" ? "" : "、") pair[2]
        }
        throw Error("参考文档不存在：" id "（已找：" tried "）")
    }

    ; 该流程能看到的全部文档：三层合并，同 id 取最先命中
    static ListAll(flowKey := "") {
        docs := Map()
        for pair in this._Candidates("", flowKey, true) {
            scope := pair[1]
            rootDir := pair[2]
            if !DirExist(rootDir) {
                continue
            }
            for id in this._ListIds(rootDir) {
                if !docs.Has(id) {
                    docs[id] := this._LoadCached(rootDir "\" id, scope, flowKey)
                }
            }
        }
        result := []
        for id, doc in docs {
            result.Push(doc)
        }
        return result
    }

    ; 只看全局
    static ListGlobal() {
        return this._ListLayer(this._GlobalRoot, "global")
    }

    ; 只看骨架私有
    static ListSkeleton() {
        return this._ListLayer(this._SkeletonRoot, "skeleton")
    }

    ; 只看某流程自己的
    static ListFlow(flowKey) {
        docs := []
        for dirPath in this._FlowRoots(flowKey) {
            for doc in this._ListLayer(dirPath, "flow", flowKey) {
                docs.Push(doc)
            }
        }
        return docs
    }

    ; 数量
    static Count(flowKey := "") {
        return this.ListAll(flowKey).Length
    }

    ; 是否存在
    static Exists(id, flowKey := "") {
        try {
            this.Get(id, flowKey)
            return true
        } catch {
            return false
        }
    }

    static ClearCache() {
        this._cache := Map()
    }

    ; ---- 私有 ----

    ; 候选目录，按查找顺序；all=true 时返回三层的根（供 ListAll 用）
    static _Candidates(id, flowKey, all := false) {
        result := []
        if (flowKey != "") {
            for dirPath in this._FlowRoots(flowKey) {
                result.Push(["flow", all ? dirPath : dirPath "\" id])
            }
        }
        result.Push(["skeleton", all ? this._SkeletonRoot : this._SkeletonRoot "\" id])
        result.Push(["global", all ? this._GlobalRoot : this._GlobalRoot "\" id])
        return result
    }

    static _ListLayer(root, scope, flowKey := "") {
        docs := []
        if !DirExist(root) {
            return docs
        }
        for id in this._ListIds(root) {
            docs.Push(this._LoadCached(root "\" id, scope, flowKey))
        }
        return docs
    }

    static _ListIds(root) {
        ids := []
        if !DirExist(root) {
            return ids
        }
        Loop Files, root "\*", "D" {
            ids.Push(A_LoopFileName)
        }
        return ids
    }

    static _LoadCached(dirPath, scope, flowKey) {
        if !this._cache.Has(dirPath) {
            this._cache[dirPath] := ReferenceDoc.Load(dirPath, scope, flowKey)
        }
        return this._cache[dirPath]
    }
}
