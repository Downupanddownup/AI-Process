#Requires AutoHotkey v2.0

; 一条校验问题：数据 + 构造
; 只描述"哪有问题"，不给修复建议——修法取决于意图，校验器猜不准

class ValidationIssue {

    ; 机器标识
    Kind := ""

    ; 中文名
    KindLabel := ""

    ; "block"（阻断，不能保存）/ "warn"（提醒，可保存）
    Severity := ""

    ; 哪个组合 / 哪个文件
    Scope := ""

    ; 具体信息
    Detail := ""

    ; 找过的路径（第 1、2、7 类有）
    TriedPaths := []

    ; kind → [中文名, 严重度]
    static Table := Map(
        "bad_config",               ["配置不合法",        "block"],
        "missing_segment",          ["必需段缺失",        "block"],
        "block_not_found",          ["块不存在",          "block"],
        "bad_meta",                 ["meta.json 不可解析", "block"],
        "order_broken",             ["段序被改",          "warn"],
        "placeholder_unregistered", ["占位符未登记",      "block"],
        "bad_reference",            ["引用不合法",        "block"],
        "combo_unconfigured",       ["组合未配置",        "warn"]
    )

    static Create(kind, scope, detail, triedPaths := []) {
        if !ValidationIssue.Table.Has(kind) {
            throw Error("未知的问题类型：" kind)
        }
        row := ValidationIssue.Table[kind]
        i := ValidationIssue()
        i.Kind := kind
        i.KindLabel := row[1]
        i.Severity := row[2]
        i.Scope := scope
        i.Detail := detail
        i.TriedPaths := triedPaths
        return i
    }

    ; 是否阻断级
    IsBlocking() {
        return this.Severity = "block"
    }
}
