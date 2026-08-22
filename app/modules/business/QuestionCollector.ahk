#Requires AutoHotkey v2.0

; 提问采集：从 vN.md 提取问题主干，供"建回复"使用

QUESTION_AREA_MARKER := "待确认问题区"
QUESTION_AREA_PATTERN := "^\s*#{0,4}\s*[0-9一二三四五六七八九十a-zA-Z]{0,4}\s*[、.．]?\s*" QUESTION_AREA_MARKER
; Q 行：允许可选的 md 标题（# 1~6 个）/ 加粗（**）前缀，兼容旧纯文本格式
QUESTION_LINE_PATTERN := "^(?:#{1,6}\s*)?(?:\*\*)?Q\d+(?:[（(][^）)]*[）)])?\s*[：:]"
REPLY_SEPARATOR := "`r`n`r`n`r`n`r`n`r`n"


; 从 md 文件提取问题主干，返回数组，元素形如 "Q1：问题主干"
ExtractQuestionsFromMd(mdPath) {
    questions := []
    if !FileExist(mdPath) {
        return questions
    }
    content := FileRead(mdPath, "UTF-8")
    lines := StrSplit(content, "`n", "`r")

    ; 单遍扫描 + 围栏感知：``` / ~~~ 围栏内的行不参与任何解析
    inFence := false
    inArea := false
    Loop lines.Length {
        line := lines[A_Index]
        if RegExMatch(line, "^[``~]{3,}") {
            inFence := !inFence
            continue
        }
        if inFence {
            continue
        }
        if !inArea {
            ; 行首锚定定位问题区起点
            if RegExMatch(line, QUESTION_AREA_PATTERN) {
                inArea := true
            }
            continue
        }
        ; 问题区内：遇到非 Q 开头的标题行即结束（Q 标题行本身不误触发结束）
        if RegExMatch(line, "^#+\s") && !RegExMatch(line, QUESTION_LINE_PATTERN) {
            break
        }
        if RegExMatch(line, QUESTION_LINE_PATTERN) {
            questions.Push(StripMdPrefix(line))
        }
    }

    ; 未找到问题区 → 退化全文扫描（兼容旧格式文档）
    if !inArea {
        questions := []
        inFence := false
        Loop lines.Length {
            line := lines[A_Index]
            if RegExMatch(line, "^[``~]{3,}") {
                inFence := !inFence
                continue
            }
            if inFence {
                continue
            }
            if RegExMatch(line, QUESTION_LINE_PATTERN) {
                questions.Push(StripMdPrefix(line))
            }
        }
    }
    return questions
}


; 剥离 Q 行行首的 md 前缀（### / **）与行尾残留的 **，输出纯文本问题主干
StripMdPrefix(line) {
    q := RegExReplace(Trim(line), "^(?:#{1,6}\s*)?(?:\*\*)?", "")
    q := RegExReplace(q, "\s*\*\*\s*$", "")
    return q
}


; 组装回复文件正文：每条问题一行 + 答：，问题间空一行，末尾接分割线
BuildReplyText(questions) {
    text := ""
    for q in questions {
        if (text != "") {
            text .= "`r`n`r`n"
        }
        text .= q "`r`n答："
    }
    if (text != "") {
        text .= REPLY_SEPARATOR
    }
    return text
}