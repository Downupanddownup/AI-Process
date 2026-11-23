#Requires AutoHotkey v2.0

; 导出件：一套流程 → 一份成品 JSON（九个组合，每条 = 动作身份 + 职责 + 整份提示词）
;
; 位置在 promptflow 层：只依赖组装引擎、流程库、序列化件；不知道 AppRoot、窗口、.aiprocess。
; 单一实现：UI 与 CLI 都只调这里，谁都不许自己拼文本、自己转义——要改成品，只改这个文件。
; 拼接只有一条路：PromptAssembler.Build（预览、发送、导出共用）；本文件只做"装进 JSON"，
; 不拆行、不重排、不再拼第二遍。演示环境也只在这里造一次（DemoEnv），预览调用时传自己的窗口号。
; 为什么不用 JSON.Dump：中文转 \u、布尔变 1、键按字母序，两个开关还是全局静态的，关掉会打坏
; 校验器的布尔判断（见《AHK调试经验》6.1）。

class PromptExporter {

    ; 组合 → 这个动作在流程里管什么。
    ; 写死是有意的：它描述动作的职责，不描述某套流程的具体做法，所以换块不过期。
    static Duties := Map(
        "复需求|single",    "把需求.txt 交给 AI，产出第一版回应（v1.md），结尾开提问区。",
        "复回复|direct",    "拿上一版回应与你的回复，让 AI 出下一版：讨论轮主轴。",
        "复回复|impl",      "同上，但产出实施文档：定稿，讨论到此封顶。",
        "复执行|steps_dir", "只拆不做：按已明确的约定拆出实施步骤目录。",
        "复执行|tweak",     "按定稿直接动手，结果写进结果文档。",
        "复关系|auto",      "新会话上下文重建：按目录约定重读文件，恢复现场。",
        "复盘|defense",     "出题考你能不能凭脑复述；作答时不翻文档。",
        "复盘|tech",        "出题提炼技术点，练到能复述原理。",
        "质检码|single",    "对某一版方案做专项自检，只出清单，不改正文。"
    )

    ; 演示主题：预览与导出共用的替换环境。
    ; 由本文件位置推（app\modules\promptflow\ → app），不依赖 AppRoot 全局——
    ; CLI 里少一个必须补的全局量，就少一处"漏了即静默死"的可能。
    static DemoTopicDir {
        get {
            appDir := RegExReplace(A_LineFile, "\\[^\\]+\\[^\\]+\\[^\\]+$", "")
            return appDir "\templates\preview-topic"
        }
    }

    ; 成品文本（不做 IO）。任一组合拼不出来即抛错，不产出半份
    static Export(flowKey) {
        flow := FlowLibrary.Get(flowKey)
        env := this.DemoEnv(flowKey)
        combos := []
        for comboKey in Skeleton.GetOrderedComboKeys() {
            combos.Push(this._Combo(env, comboKey))
        }
        return this._Dump(flow, combos)
    }

    ; 写文件：Export → 原子写 → 写后自检；返回字符数
    ; 自检读回解析：转义写错会在这一步当场暴露，而不是等人打开文件才发现
    static Write(flowKey, path) {
        text := this.Export(flowKey)
        JsonConfigWriter.WriteAtomic(path, text, (back) => this._Verify(back))
        return StrLen(text)
    }

    ; ---- 私有 ----

    ; 演示环境：预览与导出共用这一处构造，别再各造一份
    ; windowId 由调用方给：预览传当前活动窗口，导出用默认值 2（固定，两份导出才可比）
    ; FlowKey 必须显式设：{{ref:…}} 的解析靠它
    static DemoEnv(flowKey, windowId := "2") {
        env := Environment()
        env.TopicDir := this.DemoTopicDir
        env.WindowId := windowId
        env.FlowKey := flowKey
        return env
    }

    ; 一个组合：拼装 + 身份 + 职责 + 整份提示词
    ; prompt 存组装结果本身，原样一个字符串——不拆行、不重排，导出层不做第二次拼接
    static _Combo(env, comboKey) {
        parts := StrSplit(comboKey, "|")
        actKey := parts[1]
        polKey := parts[2]

        text := PromptAssembler.Build(actKey, polKey, env)

        pol := Action.FromSkeleton(actKey).GetPolicy(polKey)
        label := (pol && pol.Label != "") ? pol.Label : ""

        return Map(
            "combo", comboKey,
            "display", (label = "") ? actKey : actKey " · " label,
            "action", actKey,
            "policy", polKey,
            "duty", this.Duties.Has(comboKey) ? this.Duties[comboKey] : "",
            "prompt", this._NormalizeEol(text)
        )
    }

    ; 统一行尾：源文件行尾不统一（有的 LF、有的 CRLF），拼起来会混
    static _NormalizeEol(text) {
        return StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
    }

    ; 定向序列化：固定字段序、两空格、中文原文、末尾一个换行
    static _Dump(flow, combos) {
        out := "{`n"
        out .= '  "flow": { "key": ' this._Q(flow.Key) ', "name": ' this._Q(flow.Name) " },`n"
        out .= '  "env": { "topic": ' this._Q(this.DemoTopicDir) ', "windowId": "2" },`n'
        out .= '  "combos": [`n'

        for i, c in combos {
            out .= "    {`n"
            out .= '      "combo": ' this._Q(c["combo"]) ",`n"
            out .= '      "display": ' this._Q(c["display"]) ",`n"
            out .= '      "action": ' this._Q(c["action"]) ",`n"
            out .= '      "policy": ' this._Q(c["policy"]) ",`n"
            out .= '      "duty": ' this._Q(c["duty"]) ",`n"
            out .= '      "prompt": ' this._Q(c["prompt"]) "`n"
            out .= (i < combos.Length) ? "    },`n" : "    }`n"
        }

        out .= "  ]`n}`n"
        return out
    }

    ; 写后自检：能解析、九个组合、每条有 prompt
    static _Verify(back) {
        try {
            doc := JSON.Load(back)
        } catch as e {
            throw Error("导出自检失败：写出的文件不是合法 JSON — " e.Message)
        }
        if !doc.Has("combos") {
            throw Error("导出自检失败：缺 combos")
        }
        combos := doc["combos"]
        if (combos.Length != 9) {
            throw Error("导出自检失败：组合数为 " combos.Length "，应为 9")
        }
        for c in combos {
            if !c.Has("prompt") {
                throw Error("导出自检失败：" c["combo"] " 缺 prompt")
            }
            if (StrLen(c["prompt"]) = 0) {
                throw Error("导出自检失败：" c["combo"] " 的 prompt 为空")
            }
        }
    }

    static _Q(s) {
        return JsonConfigWriter.Quote(s)
    }
}
