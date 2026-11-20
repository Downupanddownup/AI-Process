#Requires AutoHotkey v2.0

; 对外唯一入口：组合 + 运行环境 → 最终提示词
; 预览与发送都调它，不存在第二条组装路径
; 本类只做门面：不碰文件、不碰占位符，全部交给 AssemblerEngine

class PromptAssembler {

    ; 拼一份提示词
    ; 返回：整份文本；任何一步不通过都抛错，不降级
    static Build(actionKey, policyKey, environment) {
        return AssemblerEngine.Assemble(actionKey, policyKey, environment)
    }

    ; 九个组合各拼一份，返回 Map(组合键 → 文本)；任一失败即抛错
    static BuildAll(environment) {
        result := Map()
        for actionKey, policies in Skeleton.Policies {
            for policyMap in policies {
                policyKey := policyMap["key"]
                comboKey := Skeleton.ComposeKey(actionKey, policyKey)
                result[comboKey] := this.Build(actionKey, policyKey, environment)
            }
        }
        return result
    }

    ; 组合清单（供预览列表用）
    static ListComboKeys() {
        return Skeleton.GetAllComboKeys()
    }
}
