#Requires AutoHotkey v2.0

; 提问采集：从 vN.md 提取问题主干，供"建回复"使用

QUESTION_AREA_MARKER := "待确认问题区"
REPLY_SEPARATOR := "`r`n`r`n`r`n`r`n`r`n"


; 从 md 文件提取问题主干，返回数组，元素形如 "Q1：问题主干"
ExtractQuestionsFromMd(mdPath) {
    questions := []
    if !FileExist(mdPath) {
        return questions
    }
    content := FileRead(mdPath, "UTF-8")
    lines := StrSplit(content, "`n", "`r")

    ; 优先在"待确认问题区"块内提取
    begin := 1
    end := lines.Length
    Loop lines.Length {
        if InStr(lines[A_Index], QUESTION_AREA_MARKER) {
            begin := A_Index + 1
            ; 区块结束于下一个 md 标题行
            Loop lines.Length - begin + 1 {
                idx := begin + A_Index - 1
                if RegExMatch(lines[idx], "^#+\s") {
                    end := idx - 1
                    break
                }
            }
            break
        }
    }

    ; 未找到区块 → 退化全文扫描（兼容旧格式文档）
    Loop end - begin + 1 {
        line := lines[begin + A_Index - 1]
        if RegExMatch(line, "^Q\d+(?:[（(][^）)]*[）)])?\s*[：:]", &m) {
            questions.Push(Trim(line))
        }
    }
    return questions
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