#Requires AutoHotkey v2.0

; 一个动作：系统的一种意图单元
; 数据源是 Skeleton.Policies 的常量，不读磁盘

class Action {

    ; 中文原值，进日志 action 字段，统计依赖，不可改
    Key := ""

    ; "ai"（产出提示词）/ "local"（只动文件）
    Type := ""

    ; 本动作的固定策略清单（ActionPolicy 数组）
    Policies := []

    ; 运行时选中的策略 Key，由 UI 当前选择决定
    SelectedPolicy := ""

    ; 两个脚本动作：不产提示词，无策略
    static LocalActions := ["建需求", "建回复"]

    ; 从 Skeleton 构造一个动作
    static FromSkeleton(actionKey) {
        a := Action()
        a.Key := actionKey
        a.Type := a.IsLocal(actionKey) ? "local" : "ai"
        for m in Skeleton.GetPolicies(actionKey) {
            a.Policies.Push(ActionPolicy.FromMap(m))
        }
        if (a.Policies.Length > 0) {
            a.SelectedPolicy := a.Policies[1].Key
        }
        return a
    }

    ; 是否脚本动作
    IsLocal(actionKey := "") {
        key := (actionKey = "") ? this.Key : actionKey
        for k in Action.LocalActions {
            if (k = key) {
                return true
            }
        }
        return false
    }

    ; 按 Key 取策略；找不到返回空串，由调用方报错
    GetPolicy(policyKey) {
        for p in this.Policies {
            if (p.Key = policyKey) {
                return p
            }
        }
        return ""
    }

    ; 默认策略：第一条
    GetDefaultPolicy() {
        return this.Policies.Length > 0 ? this.Policies[1] : ""
    }
}
