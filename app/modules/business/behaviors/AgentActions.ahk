#Requires AutoHotkey v2.0

; 领域行为入口门面：七个业务行为的统一声明点（UI 的行为调用走这里；策略下拉框等 UI 细节仍直连各自服务）
; 注意：AHK v2 函数/方法内为 assume-local，引用行为类（全局变量）必须显式 global 声明

class AgentActions {

    ; 建需求（local）
    static CreateRequirement(*) {
        global CreateRequirement
        return (CreateRequirement()).Run()
    }

    ; 复需求（ai）
    static CopyRequirement(*) {
        global CopyRequirement
        return (CopyRequirement()).Run()
    }

    ; 建回复（local）
    static CreateReply(*) {
        global CreateReply
        return (CreateReply()).Run()
    }

    ; 复回复（ai）
    static CopyReply(*) {
        global CopyReply
        return (CopyReply()).Run()
    }

    ; 复执行（ai）
    static CopyExecute(*) {
        global CopyExecute
        return (CopyExecute()).Run()
    }

    ; 复关系（ai）
    static CopyRelations(*) {
        global CopyRelations
        return (CopyRelations()).Run()
    }

    ; 质检码（ai）
    static QualityCheck(*) {
        global QualityCheck
        return (QualityCheck()).Run()
    }
}
