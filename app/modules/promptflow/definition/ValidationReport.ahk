#Requires AutoHotkey v2.0

; 一份校验报告：聚合 + 统计 + 汇总句
; 报告是数据，怎么显示由 UI 决定；本类不拼"请修改 xxx"这类句子

class ValidationReport {

    Issues := []

    ; 追加一条
    Add(issue) {
        this.Issues.Push(issue)
        return this
    }

    ; 追加一批
    AddAll(issues) {
        for i in issues {
            this.Issues.Push(i)
        }
        return this
    }

    ; 通过 = 没有阻断级
    IsValid() {
        return !this.HasBlocking()
    }

    HasBlocking() {
        for i in this.Issues {
            if (i.Severity = "block") {
                return true
            }
        }
        return false
    }

    Count() {
        return this.Issues.Length
    }

    BlockingCount() {
        n := 0
        for i in this.Issues {
            if (i.Severity = "block") {
                n++
            }
        }
        return n
    }

    WarnCount() {
        return this.Issues.Length - this.BlockingCount()
    }

    ; 汇总句：按中文名聚合计数，阻断在前
    ; 形如：共 3 处阻断、1 处提醒：块不存在 2、meta.json 不可解析 1、段序被改 1
    Summary() {
        if (this.Issues.Length = 0) {
            return "校验通过：未发现问题"
        }

        ; 按 KindLabel 计数，保持出现顺序
        order := []
        counts := Map()
        for i in this.Issues {
            if !counts.Has(i.KindLabel) {
                counts[i.KindLabel] := 0
                order.Push(i.KindLabel)
            }
            counts[i.KindLabel] += 1
        }

        parts := ""
        for label in order {
            parts .= (parts = "" ? "" : "、") label " " counts[label]
        }

        head := "共 " this.BlockingCount() " 处阻断"
        if (this.WarnCount() > 0) {
            head .= "、" this.WarnCount() " 处提醒"
        }
        return head "：" parts
    }
}
