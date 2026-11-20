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

        ; 按段序拼接：每段去尾换行后，用两个换行连接
        ; 为什么不直接首尾相接：段文件是从模板按区间切的，但文件最后一段没有尾随空行
        ; （如 requirement_prompt 的 complexity 段止于文件尾），直接接会把"外部信息"和"行为约束"粘成一行
        full := ""
        for seg in layout {
            text := ""
            if (seg["kind"] = "block") {
                if (seg["id"] = "brief") {
                    text := this._ReadText(Skeleton.GetBriefFile(this._PickBrief(pol, env)))
                } else {
                    text := this._ReadText(Skeleton.GetSegmentFile(seg["id"]))
                }
            } else if (seg["kind"] = "slot") {
                for blockId in recipe.Content {
                    blk := BlockLibrary.Get(blockId, flow.BlocksDir)
                    if (text != "") {
                        text .= "`n`n"
                    }
                    text .= blk.Body
                }
            } else {
                throw Error("未知的段类型：" seg["kind"])
            }

            text := RTrim(text, "`r`n")
            if (text = "") {
                continue
            }
            if (full != "") {
                full .= "`n`n"
            }
            full .= text
        }

        ; 占位符只替换一次，对整份文本
        return PlaceholderEngine.Resolve(full, env, act)
    }

    ; 两档 brief 二选一：没有 briefAlt 就直接用 brief，有则按规模选
    static _PickBrief(pol, env) {
        if (pol.BriefAlt = "") {
            return pol.Brief
        }
        manifest := ContextRebuildManifest.Build(env.TopicDir)
        return Skeleton.ShouldUseSkeletonBrief(manifest) ? pol.BriefAlt : pol.Brief
    }

    ; 读文本；不存在即抛错，不静默
    static _ReadText(path) {
        if !FileExist(path) {
            throw Error("段文件不存在：" path)
        }
        return FileRead(path, "UTF-8")
    }
}
