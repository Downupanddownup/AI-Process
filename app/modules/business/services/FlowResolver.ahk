#Requires AutoHotkey v2.0

; 流程解析：这个主题该用哪套流程
;
; 数据源：<主题目录>\.aiprocess\flow.txt —— 一行纯文本，内容是流程 key
; 四种状态互斥：
;   ok             文件存在且流程存在
;   default        文件不存在或为空 → 用默认流程
;   missing        文件写了，但该流程不存在（flowKey 保留原值，供提示用）
;   broken-default 默认流程本身不存在（全局配置坏了）
;
; 一条硬约束：绝不静默回落。只有"文件不存在/为空"才回默认；
; "写了但流程不存在"必须报 missing，否则主题会悄悄换流程，用户查不到原因。

class FlowResolver {

    ; 流程选择文件名（放在 .aiprocess 下）
    static FileName := "flow.txt"

    ; 解析某主题用哪套流程
    ; 返回 Map("status", …, "flowKey", …)
    static Resolve(topicDir) {
        key := this._ReadFlow(topicDir)

        ; 文件不存在或为空 → 默认
        if (key = "") {
            def := GetDefaultFlowKey()
            if !this.Exists(def) {
                return Map("status", "broken-default", "flowKey", def)
            }
            return Map("status", "default", "flowKey", def)
        }

        ; 文件写了但流程不存在
        if !this.Exists(key) {
            return Map("status", "missing", "flowKey", key)
        }

        return Map("status", "ok", "flowKey", key)
    }

    ; 写流程选择到主题的 .aiprocess\flow.txt
    ; 目录不存在时自己建（走 DomainConventions.EnsureDataDir）
    static Write(topicDir, flowKey) {
        dataDir := DomainConventions.EnsureDataDir(topicDir)
        file := dataDir "\" this.FileName
        ; UTF-8 无 BOM：与 .aiprocess 下其它文本一致
        if FileExist(file) {
            FileDelete(file)
        }
        FileAppend(flowKey "`n", file, "UTF-8-RAW")
        return file
    }

    ; 新建主题时该取哪个流程
    ; 顶级主题（parentDir 为空）→ 默认流程
    ; 子主题 → 父主题当前的值（含"坏 key"：父子一起报错，不悄悄修正）
    static ResolveForNew(parentDir := "") {
        if (parentDir = "") {
            return GetDefaultFlowKey()
        }
        return this.Resolve(parentDir)["flowKey"]
    }

    ; 该流程是否存在
    ; 注意：FlowLibrary 有缓存，新建/删除流程后调用方要 FlowLibrary.ClearCache()
    static Exists(flowKey) {
        if (flowKey = "") {
            return false
        }
        try {
            FlowLibrary.Get(flowKey)
            return true
        } catch {
            return false
        }
    }

    ; 主题的流程简称；流程缺失时返回「缺失」
    ; 面板与主题列表两处显示共用它——避免两处对同一主题给出不同答案
    static ShortNameOf(topicDir) {
        r := this.Resolve(topicDir)
        if (r["status"] = "ok" || r["status"] = "default") {
            try {
                return FlowLibrary.Get(r["flowKey"]).ShortName
            }
        }
        return "缺失"
    }

    ; 读 flow.txt；不存在或空白返回空串。
    ; 先 FileExist 再 FileRead——直接读不存在的文件会抛错。
    static _ReadFlow(topicDir) {
        if (topicDir = "") {
            return ""
        }
        file := DomainConventions.DataDirPath(topicDir) "\" this.FileName
        if !FileExist(file) {
            return ""
        }
        return Trim(FileRead(file, "UTF-8"), " `t`r`n")
    }
}
