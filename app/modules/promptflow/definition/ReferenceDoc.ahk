#Requires AutoHotkey v2.0

; 参考文档实体：供 AI 自行阅读的资料
; 只持路径，不持正文——组装只需要知道"文件在哪"，不需要知道"里面写了什么"
; 一旦读了正文，就会有人忍不住把它拼进提示词，那正是 06 犯过的错

class ReferenceDoc {

    ; 目录名即 id
    Id := ""

    ; meta.json 两项
    Name := ""
    Purpose := ""

    ; body.md 的绝对路径 —— 这就是 {{ref:<id>}} 替换成的值
    BodyPath := ""

    ; 文档所在目录
    Dir := ""

    ; "global" / "skeleton" / "flow"
    Scope := ""

    ; Scope=flow 时属于哪个流程，否则为空
    FlowKey := ""

    ; 从文档目录加载；缺文件或解析失败直接抛错
    static Load(dirPath, scope, flowKey := "") {
        if !DirExist(dirPath) {
            throw Error("参考文档目录不存在：" dirPath)
        }
        metaPath := dirPath "\meta.json"
        bodyPath := dirPath "\body.md"
        if !FileExist(metaPath) {
            throw Error("参考文档缺少 meta.json：" dirPath)
        }
        if !FileExist(bodyPath) {
            throw Error("参考文档缺少 body.md：" dirPath)
        }

        d := ReferenceDoc()
        d.Dir := dirPath
        SplitPath(dirPath, &dirName)
        d.Id := dirName
        d.BodyPath := bodyPath
        d.Scope := scope
        d.FlowKey := flowKey

        try {
            meta := JSON.Load(FileRead(metaPath, "UTF-8"))
        } catch as e {
            throw Error("参考文档 meta.json 解析失败：" metaPath " — " e.Message)
        }
        d.Name := meta.Has("name") ? meta["name"] : ""
        d.Purpose := meta.Has("purpose") ? meta["purpose"] : ""
        return d
    }

    IsGlobal() {
        return this.Scope = "global"
    }

    IsSkeleton() {
        return this.Scope = "skeleton"
    }

    IsFlow() {
        return this.Scope = "flow"
    }
}
