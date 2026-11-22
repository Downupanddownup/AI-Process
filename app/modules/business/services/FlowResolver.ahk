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

    ; 流程归属落地：升级/进入时给"还没有 flow.txt 的已开工域"定归属，一次定终身
    ; 规则：向上找最近祖先的 flow.txt → 继承（含"坏 key"：父子一起报错，不悄悄修正）；
    ;       找到仓库根都没有 → 顶级域，写当前默认流程 key（显式落地，不留隐式默认）
    ; occasion 只进日志："升级"（建需求漏斗）/ "进入"（设目录、需求树、返）
    static EnsureInherited(dir, occasion) {
        if (!DomainConventions.IsDomainDir(dir) || this._ReadFlow(dir) != "") {
            return
        }
        parentDir := ""
        SplitPath(dir, , &parentDir)
        found := this._ResolveUpward(parentDir)
        flowKey := found.Has("key") ? found["key"] : GetDefaultFlowKey()
        this.Write(dir, flowKey)
        LogActivity("流程归属", "", Map(
            "flow", flowKey,
            "source", found.Has("key") ? found["from"] : "默认",
            "occasion", occasion))
    }

    ; 自 dir 向上找第一个 flow.txt：找到 → Map("key", …, "from", 所在目录)；都没有 → 空 Map
    static _ResolveUpward(dir) {
        p := dir
        while (p != "" && StrLen(p) > 3) {
            key := this._ReadFlow(p)
            if (key != "") {
                return Map("key", key, "from", p)
            }
            if (DomainConventions.IsRepoRootDir(p)) {
                break
            }
            nextDir := ""
            SplitPath(p, , &nextDir)
            p := nextDir
        }
        return Map()
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

    ; 三个窗口里，哪个的当前主题正在用这套流程 → 窗口号；没有 → 0
    ; 读不出该窗口的配置 → 负的窗口号（无法确认，按"可能在用"处理）
    ; 比对 Resolve 出来的 flowKey：ok 与 default 都有值；
    ; 已坏掉的主题（missing）也算"在用"——此时流程目录已不在，删除会直接失败，不会误删
    static IsUsedByAnyWindow(flowKey) {
        if (flowKey = "")
            return 0
        loop 3 {
            dir := GetSession(A_Index, "CurrentDir")
            if (Trim(dir) = "")
                continue
            try {
                r := this.Resolve(dir)
            } catch {
                ; 读不出来就无法确认是否在用。删流程不可逆，按"可能在用"处理：
                ; 返回负窗口号，由调用方提示"先修配置"
                return -A_Index
            }
            if (r["flowKey"] = flowKey)
                return A_Index
        }
        return 0
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
