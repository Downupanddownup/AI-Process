#Requires AutoHotkey v2.0

; 块库：块从哪找
; 查找顺序只有两段：本流程私有 → 全局。不跨流程
; 固定段（skeleton/ 下）不参与查找——它们由 Skeleton 常量管

class BlockLibrary {

    ; 缓存：路径 → PromptBlock
    static _cache := Map()

    ; 数据根：promptflow/data（本文件在 promptflow/definition/ 下，上两级 + data）
    static DataRoot {
        get {
            return RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+$", "") "\data"
        }
    }

    ; 取一个块
    ; flowBlocksDir 为空时只查全局
    static Get(blockId, flowBlocksDir := "") {
        candidates := []
        if (flowBlocksDir != "") {
            candidates.Push(flowBlocksDir "\" blockId)
        }
        candidates.Push(this.DataRoot "\blocks\" blockId)

        for dirPath in candidates {
            if DirExist(dirPath) {
                if !this._cache.Has(dirPath) {
                    this._cache[dirPath] := PromptBlock.Load(dirPath)
                }
                return this._cache[dirPath]
            }
        }

        ; 找不到：把找过的路径全部报出来，便于定位
        tried := ""
        for p in candidates {
            tried .= (tried = "" ? "" : "、") p
        }
        throw Error("块不存在：" blockId "（已找：" tried "）")
    }

    ; 按 id 列表批量取；任一块缺失即抛错
    static GetMany(blockIds, flowBlocksDir := "") {
        result := []
        for id in blockIds {
            result.Push(this.Get(id, flowBlocksDir))
        }
        return result
    }

    ; 某个块目录下有哪些块 id
    static ListIds(blocksDir) {
        ids := []
        if !DirExist(blocksDir) {
            return ids
        }
        Loop Files, blocksDir "\*", "D" {
            ids.Push(A_LoopFileName)
        }
        return ids
    }

    ; 清缓存（改块后测试用）
    static ClearCache() {
        this._cache := Map()
    }
}
