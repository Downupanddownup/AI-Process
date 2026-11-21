#Requires AutoHotkey v2.0

; 配置文件写入件：字符串转义 + 原子写（.tmp → 读回比对 → 覆盖）
;
; 为什么不直接用 JSON.Dump：默认输出是 Tab 缩进、中文转义、布尔变 1/0、键按字母序，
; 与配置规范不符；两个能关的开关又是全局静态的。原因见 基础信息\技术信息.md 第一节。
;
; 结构渲染仍由各配置自己负责（flow.json 的 recipes、meta.json 的三字段），这里只负责
; "把已经拼好的文本安全地落到磁盘上"。

class JsonConfigWriter {

    ; 字符串转义：\\ \" \n \r \t；中文保持原文，不转成 \uXXXX
    static Quote(value) {
        s := String(value)
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, "`"", "\`"")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return "`"" s "`""
    }

    ; 原子写：内容与内存不一致、或 verifyFn 抛错，都不覆盖原文件。
    ; verifyFn 收到读回的文本，由调用方做结构校验（例如解析 JSON 再逐字段比）。
    static WriteAtomic(path, text, verifyFn := "") {
        tmp := path ".tmp"
        try {
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()

            back := FileRead(tmp, "UTF-8")
            if (back != text)
                throw Error("写入自检失败：读回内容与内存不一致")
            if (verifyFn)
                verifyFn(back)

            FileMove(tmp, path, 1)
        } catch as e {
            if FileExist(tmp)
                FileDelete(tmp)
            throw e
        }
    }
}
