#Requires AutoHotkey v2.0

; 骨架：工具的形状，不可配
; 职责：策略清单 + 每个"动作×策略"的段序列 + 参数绑定
; 位置：skeleton/ —— 被引擎读的结构数据，改了等于改工具
; 依据：九份基线的实测段序（02 步）；挂点只定位置，挂什么归 flow.json（04 步）

class Skeleton {

    ; ============ 一、策略清单 ============
    ; 动作 key 中文原值：进日志 action 字段，统计依赖，不可改
    ; 策略 key 英文小写：标识符，进配置
    ; label：界面与日志原文，与现状一致，不改
    static Policies := Map(
        "复需求", [
            Map("key", "single", "label", "", "brief", "requirement.txt", "feedback", "需求提示词已复制")
        ],
        "复回复", [
            Map("key", "direct", "label", "", "brief", "reply_direct.txt", "feedback", "回复提示词已复制"),
            Map("key", "impl", "label", "实", "brief", "reply_impl.txt", "feedback", "回复提示词已复制")
        ],
        "质检码", [
            Map("key", "single", "label", "", "brief", "quality_check.txt", "feedback", "质检提示词已复制")
        ],
        "复盘", [
            Map("key", "defense", "label", "答辩", "brief", "defense.txt", "feedback", "答辩提示词已复制"),
            Map("key", "tech", "label", "技炼", "brief", "tech.txt", "feedback", "技炼提示词已复制")
        ],
        "复执行", [
            Map("key", "tweak", "label", "改吧", "brief", "tweak.txt", "feedback", "改吧提示词已复制"),
            Map("key", "steps_dir", "label", "步目", "brief", "steps_dir.txt", "feedback", "步目提示词已复制")
        ],
        "复关系", [
            ; 两档 brief 由运行规模二选一，不是用户可选
            Map("key", "auto", "label", "", "brief", "context_relation_full.txt",
                "briefAlt", "context_relation_skeleton.txt", "feedback", "文件关系说明已复制")
        ]
    )

    ; ============ 二、段序列 ============
    ; 数组即顺序。kind=block 是不可换位的固定段；kind=slot 是唯一挂点（入口）
    ; 挂点里挂什么不在本表：那是 flow.json 的事，本表只给位置
    static Layouts := Map(
        ; 复需求：brief → 挂点 → 提问模板 → 打开
        "复需求|single", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "question_format"),
            Map("kind", "block", "id", "end_open_generated")
        ],
        ; 复回复 direct：brief → 挂点 → 提问模板 → 打开
        "复回复|direct", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "question_format"),
            Map("kind", "block", "id", "end_open_generated")
        ],
        ; 复回复 impl：brief → 挂点 → 打开（无提问模板）
        "复回复|impl", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "end_open_generated")
        ],
        ; 质检码：brief → 挂点 → 提问模板 → 打开
        "质检码|single", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "question_format"),
            Map("kind", "block", "id", "end_open_generated")
        ],
        ; 复盘两模式：brief → 挂点 → 提问模板 → 打开
        "复盘|defense", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "question_format"),
            Map("kind", "block", "id", "end_open_generated")
        ],
        "复盘|tech", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "question_format"),
            Map("kind", "block", "id", "end_open_generated")
        ],
        ; 复执行两策略：brief → 挂点 → 保存即执行（无提问模板）
        "复执行|tweak", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "end_open_fixed")
        ],
        "复执行|steps_dir", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "end_open_fixed")
        ],
        ; 复关系：brief → 文件清单 → 挂点 → 完成通知
        ; 顺序依据：基线 09 实测为 brief → manifest_block → no_modify → end_notify
        ; 挂点放在清单之后，才能让 no_modify 排在清单后（与基线一致）
        "复关系|auto", [
            Map("kind", "block", "id", "brief"),
            Map("kind", "block", "id", "manifest_block"),
            Map("kind", "slot",  "id", "content"),
            Map("kind", "block", "id", "end_notify")
        ]
    )

    ; ============ 三、参数绑定 ============
    ; 段 id → 用到的占位符名。值由占位引擎结合运行环境解释
    ; 块（flow.json 引用的）也在此登记，虽然它们不在 Layouts 里
    static Bindings := Map(
        "brief",              ["filePath", "nextVersionFile", "nextVersionPath", "scaleSummary"],
        "manifest_block",     ["fileManifest"],
        "end_open_generated", ["openMdScript", "windowId"],
        "end_open_fixed",     ["openMdScript", "windowId", "resultFilePath"],
        "end_notify",         ["notifyScript", "windowId"],
        ; 块级声明（Skeleton 不拼它们，但校验器需要知道它们用哪些占位符）
        "result_format",      ["resultTemplatePath"],
        "steps_rules",        ["resultFilePath"]
    )

    ; ============ 查询 ============

    ; 组合键
    static ComposeKey(actionKey, policyKey) {
        return actionKey "|" policyKey
    }

    ; 某动作的策略清单；无则空数组
    static GetPolicies(actionKey) {
        return this.Policies.Has(actionKey) ? this.Policies[actionKey] : []
    }

    ; 某组合的段序列；无则空数组
    static GetLayout(actionKey, policyKey) {
        key := this.ComposeKey(actionKey, policyKey)
        return this.Layouts.Has(key) ? this.Layouts[key] : []
    }

    ; 某段用到的占位符；无则空数组
    static GetBinding(segmentId) {
        return this.Bindings.Has(segmentId) ? this.Bindings[segmentId] : []
    }

    ; 全部挂点 id（校验器用）
    static GetAllSlotIds() {
        ids := []
        for k, layout in this.Layouts {
            for seg in layout {
                if (seg["kind"] = "slot" && !this._Has(ids, seg["id"])) {
                    ids.Push(seg["id"])
                }
            }
        }
        return ids
    }

    ; 全部固定段 id（校验器用）
    static GetAllBlockIds() {
        ids := []
        for k, layout in this.Layouts {
            for seg in layout {
                if (seg["kind"] = "block" && !this._Has(ids, seg["id"])) {
                    ids.Push(seg["id"])
                }
            }
        }
        return ids
    }

    ; 全部组合键（校验器、预览用）
    static GetAllComboKeys() {
        keys := []
        for k in this.Layouts {
            keys.Push(k)
        }
        return keys
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
