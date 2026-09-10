#Requires AutoHotkey v2.0

; 领域行为入口门面：七个业务行为的统一声明点（UI 唯一依赖点）
; 阶段 1 空壳：步骤 06 才切换 UI 绑定到此入口
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
