#Requires AutoHotkey v2.0

; 一个块：一个目录，内含 meta.json（说明）与 body.txt（本体）
; 目录名即块 id

class PromptBlock {

    ; 块 id = 目录名
    Id := ""

    ; meta.json 三项
    Name := ""
    Purpose := ""
    Kind := ""

    ; body.txt 原文
    Body := ""

    ; 块目录的绝对路径
    Dir := ""

    ; 从块目录加载；缺文件或解析失败直接抛错，不静默跳过
    static Load(dirPath) {
        if !DirExist(dirPath) {
            throw Error("块目录不存在：" dirPath)
        }
        bodyPath := dirPath "\body.txt"
        metaPath := dirPath "\meta.json"
        if !FileExist(bodyPath) {
            throw Error("块缺少 body.txt：" dirPath)
        }
        if !FileExist(metaPath) {
            throw Error("块缺少 meta.json：" dirPath)
        }

        b := PromptBlock()
        b.Dir := dirPath
        SplitPath(dirPath, &dirName)
        b.Id := dirName
        b.Body := FileRead(bodyPath, "UTF-8")

        try {
            meta := JSON.Load(FileRead(metaPath, "UTF-8"))
        } catch as e {
            throw Error("meta.json 解析失败：" metaPath " — " e.Message)
        }
        b.Name := meta.Has("name") ? meta["name"] : ""
        b.Purpose := meta.Has("purpose") ? meta["purpose"] : ""
        b.Kind := meta.Has("kind") ? meta["kind"] : ""
        return b
    }

    ; 是否声明了全部三项
    IsComplete() {
        return (this.Name != "" && this.Purpose != "" && this.Kind != "")
    }
}
