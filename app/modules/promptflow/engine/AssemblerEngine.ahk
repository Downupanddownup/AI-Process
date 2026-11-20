#Requires AutoHotkey v2.0

; 拼装引擎：按骨架段序把段与块接成一整份提示词
; 规则：段与块直接首尾相接，不加分隔符（它们自带尾随换行）；占位符最后统一替换一次
; 注意：局部变量不叫 action —— 会与 Action 类名冲突（AHK 不分大小写）

class AssemblerEngine {

    ; 主入口：组合 + 环境 → 整份文本
    static Assemble(actionKey, policyKey, env) {
        act := Action.FromSkeleton(actionKey)
        pol := act.GetPolicy(policyKey)
        if (pol = "") {
            throw Error("动作 " actionKey " 没有策略 " policyKey)
        }

        layout := Skeleton.GetLayout(actionKey, policyKey)
        if (layout.Length = 0) {
            throw Error("组合不在骨架里：" Skeleton.ComposeKey(actionKey, policyKey))
        }

        flow := FlowLibrary.GetDefault()
        comboKey := Skeleton.ComposeKey(actionKey, policyKey)
        recipe := flow.GetRecipe(comboKey)

        ; 按段序拼接
        full := ""
        for seg in layout {
            if (seg["kind"] = "block") {
                full .= this._ReadText(Skeleton.GetSegmentFile(seg["id"], pol))
            } else if (seg["kind"] = "slot") {
                for blockId in recipe.Content {
                    blk := BlockLibrary.Get(blockId, flow.BlocksDir)
                    full .= blk.Body
                }
            } else {
                throw Error("未知的段类型：" seg["kind"])
            }
        }

        ; 占位符只替换一次，对整份文本
        return PlaceholderEngine.Resolve(full, env, act)
    }

    ; 读文本；不存在即抛错，不静默
    static _ReadText(path) {
        if !FileExist(path) {
            throw Error("段文件不存在：" path)
        }
        return FileRead(path, "UTF-8")
    }
}
