#Requires AutoHotkey v2.0

; 校验器：一次攒齐所有问题，返回报告，不抛异常、不调 UI
; 唯一入口 CheckFlow(flowKey)
; 只在流程维护、点保存前调用；发送链路只走 06（06 遇错抛异常）

class PromptValidator {

    ; 校验一套流程，返回 ValidationReport
    static CheckFlow(flowKey) {
        report := ValidationReport()

        ; ① 读配置：读不了就终止（没有配方就不知道要查什么）
        try {
            flow := FlowLibrary.Get(flowKey)
        } catch as e {
            report.Add(ValidationIssue.Create("bad_config", flowKey, "流程配置不可读：" e.Message))
            return report
        }

        legal := Skeleton.GetAllComboKeys()

        ; ② 配置自检
        this._CheckConfigIdentity(report, flow, flowKey)
        configured := this._CheckComboKeys(report, flow, legal)
        this._CheckUnconfigured(report, flow, legal)

        ; ③ 逐组合细查
        checkedBlocks := Map()
        for comboKey in configured {
            this._CheckOneCombo(report, flow, flowKey, comboKey, legal, checkedBlocks)
        }

        return report
    }

    ; ---- 私有 ----

    ; key 与目录名、readonly 与目录位置
    static _CheckConfigIdentity(report, flow, flowKey) {
        SplitPath(flow.Dir, &dirName)
        if (flow.Key != dirName) {
            report.Add(ValidationIssue.Create("bad_config", flowKey,
                "key 与目录名不一致：key=" flow.Key "，目录=" dirName))
        }

        ; readonly：要读 flow.json 的原始字段，不能看 flow.Readonly
        ; 因为 PromptFlow.Load 的 Readonly 是按目录位置算的，恒与位置一致，拿它比等于没比
        inBuiltin := InStr(flow.Dir, "\flows\builtin\") ? true : false
        cfgPath := flow.Dir "\flow.json"
        if FileExist(cfgPath) {
            try {
                raw := JSON.Load(FileRead(cfgPath, "UTF-8"))
            } catch {
                return
            }
            if raw.Has("readonly") {
                rawReadonly := (raw["readonly"] = true)
                if (rawReadonly != inBuiltin) {
                    expect := inBuiltin ? "true" : "false"
                    report.Add(ValidationIssue.Create("bad_config", flowKey,
                        "readonly 与目录位置不匹配：在 " (inBuiltin ? "builtin" : "custom")
                        " 下应为 " expect "，实际写了 " (rawReadonly ? "true" : "false")))
                }
            }
        }
    }

    ; recipes 的键必须是合法组合；返回合法且已配的组合列表
    static _CheckComboKeys(report, flow, legal) {
        configured := []
        for comboKey in flow.GetComboKeys() {
            if !this._Has(legal, comboKey) {
                report.Add(ValidationIssue.Create("bad_config", comboKey,
                    "未知组合；骨架里合法的组合见 Skeleton.Layouts"))
                continue
            }
            configured.Push(comboKey)
        }
        return configured
    }

    ; 合法但没配的组合：warn，不拦保存
    static _CheckUnconfigured(report, flow, legal) {
        for comboKey in legal {
            ; 注意：GetRecipe 在缺配方时抛错，这里要判存在性而不是取值
            if !flow.Recipes.Has(comboKey) {
                report.Add(ValidationIssue.Create("combo_unconfigured", comboKey,
                    "该组合未配置，点此按钮会报错"))
            }
        }
    }

    ; 一个组合的细查：段序、段文件、块、占位符
    static _CheckOneCombo(report, flow, flowKey, comboKey, legal, checkedBlocks) {
        parts := StrSplit(comboKey, "|")
        actKey := parts[1]
        polKey := parts[2]

        act := Action.FromSkeleton(actKey)
        pol := act.GetPolicy(polKey)
        if (pol = "") {
            report.Add(ValidationIssue.Create("bad_config", comboKey,
                "动作 " actKey " 没有策略 " polKey))
            return
        }

        layout := Skeleton.GetLayout(actKey, polKey)
        if (layout.Length = 0) {
            report.Add(ValidationIssue.Create("bad_config", comboKey,
                "骨架里没有这个组合的段序"))
            return
        }

        ; 段序完整性（防御性）：第一段必须是 brief，最后一段必须是 end_*
        firstId := layout[1]["id"]
        lastId := layout[layout.Length]["id"]
        if (firstId != "brief" || SubStr(lastId, 1, 4) != "end_") {
            report.Add(ValidationIssue.Create("order_broken", comboKey,
                "段序被改：第一段=" firstId "，最后一段=" lastId))
        }

        ; 段文件
        segmentTexts := []
        for seg in layout {
            if (seg["kind"] != "block") {
                continue
            }
            path := ""
            try {
                path := Skeleton.GetSegmentFile(seg["id"], pol)
            } catch as e {
                report.Add(ValidationIssue.Create("missing_segment", comboKey, e.Message))
                continue
            }
            if !FileExist(path) {
                report.Add(ValidationIssue.Create("missing_segment", comboKey,
                    "段 " seg["id"] " 文件不存在：" path, [path]))
                continue
            }
            segmentTexts.Push([FileRead(path, "UTF-8"), path])
        }

        ; 块
        recipe := flow.GetRecipe(comboKey)
        blockTexts := []
        for blockId in recipe.Content {
            try {
                blk := BlockLibrary.Get(blockId, flow.BlocksDir)
            } catch as e {
                report.Add(ValidationIssue.Create("block_not_found", comboKey, e.Message))
                continue
            }
            blockTexts.Push([blk.Body, blk.Dir])
            ; 块本身的结构问题只报一次（多个组合可能共用）
            if !checkedBlocks.Has(blk.Dir) {
                checkedBlocks[blk.Dir] := true
                if (blk.Name = "" || blk.Purpose = "" || blk.Kind = "") {
                    report.Add(ValidationIssue.Create("bad_meta", comboKey,
                        "块 " blockId " 的 meta.json 缺字段（name / purpose / kind）：" blk.Dir, [blk.Dir]))
                }
            }
        }

        ; 占位符与引用
        for pair in segmentTexts {
            this._CheckPlaceholders(report, pair[1], pair[2], flowKey)
        }
        for pair in blockTexts {
            this._CheckPlaceholders(report, pair[1], pair[2], flowKey)
        }
    }

    ; 一段文本里的占位符：固定词查词表，引用查 _kinds 与参考文档库
    static _CheckPlaceholders(report, text, source, flowKey) {
        all := PromptParam.LoadAll()
        kinds := PromptParam.GetKinds()
        for name in PlaceholderEngine.ExtractNames(text) {
            idx := InStr(name, ":")
            if (idx > 1) {
                prefix := SubStr(name, 1, idx - 1)
                refId := SubStr(name, idx + 1)
                if !kinds.Has(prefix) {
                    report.Add(ValidationIssue.Create("bad_reference", source,
                        "未知的占位符类型：" prefix "（引用 " name "）"))
                    continue
                }
                if (prefix = "ref" && !ReferenceLibrary.Exists(refId, flowKey)) {
                    report.Add(ValidationIssue.Create("bad_reference", source,
                        "参考文档不存在：" refId "（引用 " name "）"))
                }
                continue
            }
            if !PromptParam.IsRegistered(name, all) {
                report.Add(ValidationIssue.Create("placeholder_unregistered", source,
                    "占位符未登记：" name))
            }
        }
    }

    static _Has(arr, value) {
        for item in arr {
            if (item = value) {
                return true
            }
        }
        return false
    }
}
