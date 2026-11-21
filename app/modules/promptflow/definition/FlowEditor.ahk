#Requires AutoHotkey v2.0

; 流程写回：新建 / 改名 / 删除 / 写某个组合的 content
;
; 与 FlowLibrary 同域分居：一个读、一个写。只依赖 JSON / FlowLibrary / BlockLibrary / Skeleton，
; 不依赖 business/ 与 UI——不知道 .aiprocess，也不知道窗口与默认流程。
;
; 序列化不走 JSON.Dump：它的默认输出（Tab 缩进、\u 转义、布尔变 1/0、键按字母序）与
; 配置规范不符，而两个能关的开关是全局静态的，关掉会打坏 07 的布尔判断。
; 原因与对策见 基础信息\技术信息.md 第一节。

class FlowEditor {

    ; 写盘时的组合顺序：与 配置规范.md §2.2 列出的九个组合顺序一致。
    ; 不取 Map 的遍历顺序——AHK 的 Map 不保证插入序，取到的会是另一种顺序，
    ; 那样每次写盘都会把 recipes 重排一遍。
    static ComboOrder := [
        "复需求|single", "复回复|direct", "复回复|impl", "质检码|single",
        "复盘|defense", "复盘|tech", "复执行|tweak", "复执行|steps_dir", "复关系|auto"
    ]

    ; ---- 写操作 ----

    ; 新建流程：blank=false 时从 originKey 复制 flow.json 与私有块目录
    ; 返回新流程目录的绝对路径
    static Create(originKey, newKey, name, shortName := "", blank := false) {
        err := this.ValidateKey(newKey)
        if (err != "")
            throw Error(err)
        if (Trim(name) = "")
            throw Error("流程名称不能为空")
        if (Trim(shortName) = "")
            shortName := name

        dest := FlowLibrary.CustomRoot "\" newKey
        if DirExist(dest)
            throw Error("流程已存在：" newKey)

        data := ""
        if (blank) {
            data := Map("key", newKey, "name", name, "shortName", shortName,
                        "readonly", false, "recipes", Map())
        } else {
            data := this._LoadRaw(originKey)
            data["key"] := newKey
            data["name"] := name
            data["shortName"] := shortName
            data["readonly"] := false
        }

        try {
            DirCreate(dest)
            if (!blank) {
                origin := FlowLibrary.Get(originKey)
                this._CopyDir(origin.BlocksDir, dest "\blocks")
            }
            this._WriteRaw(dest, data)
        } catch as e {
            ; 建到一半失败：整目录删掉，不留半成品
            if DirExist(dest)
                DirDelete(dest, true)
            throw e
        }

        FlowLibrary.ClearCache()
        return dest
    }

    ; 改名：只动 name / shortName，key 不变
    static Rename(flowKey, name, shortName := "") {
        dirPath := this._EnsureWritable(flowKey)
        if (Trim(name) = "")
            throw Error("流程名称不能为空")
        if (Trim(shortName) = "")
            shortName := name

        data := this._LoadRaw(flowKey)
        data["name"] := name
        data["shortName"] := shortName
        this._WriteRaw(dirPath, data)
        FlowLibrary.ClearCache()
    }

    ; 删除：只删 custom 下的流程目录；谁在用由调用方先查
    static Delete(flowKey) {
        dirPath := this._EnsureWritable(flowKey)
        DirDelete(dirPath, true)
        FlowLibrary.ClearCache()
    }

    ; 写某个组合的 content（顺序即拼装顺序，允许空数组）
    static SetRecipe(flowKey, comboKey, blockIds) {
        dirPath := this._EnsureWritable(flowKey)
        if !this._IsComboKey(comboKey)
            throw Error("未知组合：" comboKey)
        if !(blockIds is Array)
            throw Error("块列表必须是数组")

        data := this._LoadRaw(flowKey)
        if !data.Has("recipes")
            data["recipes"] := Map()

        list := []
        for id in blockIds
            list.Push(String(id))
        data["recipes"][comboKey] := Map("content", list)

        this._WriteRaw(dirPath, data)
        FlowLibrary.ClearCache()
    }

    ; ---- 校验 ----

    ; key 合法性：空串表示通过，否则是给人看的错误说明
    static ValidateKey(newKey) {
        if (Trim(newKey) = "")
            return "流程标识不能为空"
        if !RegExMatch(newKey, "^[a-z0-9]+$")
            return "流程标识只能用英文小写字母与数字：" newKey
        if (DirExist(FlowLibrary.BuiltinRoot "\" newKey) || DirExist(FlowLibrary.CustomRoot "\" newKey))
            return "流程已存在：" newKey
        return ""
    }

    ; ---- 私有 ----

    ; 拿到一个可写的自定义流程目录；内置 / 不存在都抛错
    static _EnsureWritable(flowKey) {
        flow := FlowLibrary.Get(flowKey)
        if (flow.Readonly)
            throw Error("内置流程只读，不能修改：" flowKey)
        dirPath := FlowLibrary.CustomRoot "\" flowKey
        if !DirExist(dirPath)
            throw Error("流程目录不存在：" dirPath)
        return dirPath
    }

    ; 读原始 flow.json（不经 PromptFlow：要保留五个字段之外的内容）
    static _LoadRaw(flowKey) {
        filePath := FlowLibrary.CustomRoot "\" flowKey "\flow.json"
        if !FileExist(filePath)
            filePath := FlowLibrary.BuiltinRoot "\" flowKey "\flow.json"
        if !FileExist(filePath)
            throw Error("流程不存在：" flowKey)
        try {
            return JSON.Load(FileRead(filePath, "UTF-8"))
        } catch as e {
            throw Error("flow.json 解析失败：" filePath " — " e.Message)
        }
    }

    ; 序列化 + 原子写 + 写后自检
    static _WriteRaw(dirPath, data) {
        target := dirPath "\flow.json"
        tmp := target ".tmp"
        try {
            text := this._DumpFlow(data)
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()

            ; 自检：读回来必须和内存里那份一致，才允许覆盖
            back := JSON.Load(FileRead(tmp, "UTF-8"))
            this._Verify(data, back)
            FileMove(tmp, target, 1)
        } catch as e {
            if FileExist(tmp)
                FileDelete(tmp)
            throw Error("写入 flow.json 失败：" target " — " e.Message)
        }
    }

    ; 值级比对：key / name / shortName / readonly（按 0/1 归一）/ 每个组合的块顺序
    static _Verify(data, back) {
        for field in ["key", "name", "shortName"] {
            expected := data.Has(field) ? this._Str(data[field]) : ""
            actual := back.Has(field) ? this._Str(back[field]) : ""
            if (expected != actual)
                throw Error("写入自检失败：" field)
        }

        wantBool := (data.Has("readonly") && data["readonly"]) ? 1 : 0
        gotBool := (back.Has("readonly") && back["readonly"]) ? 1 : 0
        if (wantBool != gotBool)
            throw Error("写入自检失败：readonly")

        orig := data.Has("recipes") ? data["recipes"] : Map()
        read := back.Has("recipes") ? back["recipes"] : Map()
        if (orig.Count != read.Count)
            throw Error("写入自检失败：recipes 组合数")

        for comboKey, recipe in orig {
            if !read.Has(comboKey)
                throw Error("写入自检失败：recipes 缺 " comboKey)
            a := recipe.Has("content") ? recipe["content"] : []
            b := read[comboKey].Has("content") ? read[comboKey]["content"] : []
            if (a.Length != b.Length)
                throw Error("写入自检失败：" comboKey " 的块数")
            loop a.Length {
                if (this._Str(a[A_Index]) != this._Str(b[A_Index]))
                    throw Error("写入自检失败：" comboKey " 第 " A_Index " 块")
            }
        }
    }

    ; 定向序列化：固定字段序、两空格、中文原文、布尔真值、末尾换行
    static _DumpFlow(data) {
        known := Map("key", 1, "name", 1, "shortName", 1, "readonly", 1, "recipes", 1)

        kv := []
        kv.Push('  "key": ' this._JsonStr(data.Has("key") ? data["key"] : ""))
        kv.Push('  "name": ' this._JsonStr(data.Has("name") ? data["name"] : ""))
        kv.Push('  "shortName": ' this._JsonStr(data.Has("shortName") ? data["shortName"] : ""))
        kv.Push('  "readonly": ' ((data.Has("readonly") && data["readonly"]) ? "true" : "false"))

        ; 约定之外的手写字段：按字母序排在 recipes 之前，值压成一行，不丢数据
        extras := []
        for k, v in data {
            if !known.Has(k)
                extras.Push(k)
        }
        for k in this._SortStrings(extras)
            kv.Push('  ' this._JsonStr(k) ": " JSON.Dump(data[k], 0))

        recipes := data.Has("recipes") ? data["recipes"] : Map()
        kv.Push('  "recipes": ' this._DumpRecipes(recipes))

        body := ""
        for line in kv
            body .= (body = "" ? "" : ",`n") line
        return "{`n" body "`n}`n"
    }

    static _DumpRecipes(recipes) {
        if (recipes.Count = 0)
            return "{}"

        ; 先按约定顺序，再补约定之外的组合（按字母序）
        ordered := []
        for comboKey in this.ComboOrder {
            if recipes.Has(comboKey)
                ordered.Push(comboKey)
        }
        rest := []
        for comboKey, recipe in recipes {
            if !this._HasValue(ordered, comboKey)
                rest.Push(comboKey)
        }
        for comboKey in this._SortStrings(rest)
            ordered.Push(comboKey)

        lines := []
        index := 1
        for comboKey in ordered {
            recipe := recipes[comboKey]
            content := recipe.Has("content") ? recipe["content"] : []
            arr := "["
            for i, id in content {
                if (i > 1)
                    arr .= ", "
                arr .= this._JsonStr(id)
            }
            arr .= "]"

            lines.Push('    ' this._JsonStr(comboKey) ': {')
            lines.Push('      "content": ' arr)
            lines.Push('    }' (index < ordered.Length ? "," : ""))
            index += 1
        }

        text := "{`n"
        for line in lines
            text .= line "`n"
        return text "  }"
    }

    static _HasValue(arr, value) {
        for item in arr {
            if (item = value)
                return true
        }
        return false
    }

    static _JsonStr(s) {
        s := this._Str(s)
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, "`"", "\`"")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return "`"" s "`""
    }

    static _Str(v) {
        return (v = "" ? "" : String(v))
    }

    static _IsComboKey(comboKey) {
        for key in Skeleton.GetAllComboKeys() {
            if (key = comboKey)
                return true
        }
        return false
    }

    ; 递归复制目录（含子目录）
    static _CopyDir(src, dest) {
        DirCreate(dest)
        Loop Files, src "\*.*", "FR" {
            rel := SubStr(A_LoopFileFullPath, StrLen(src) + 2)
            target := dest "\" rel
            SplitPath(target, , &parentDir)
            if (parentDir != "" && !DirExist(parentDir))
                DirCreate(parentDir)
            FileCopy(A_LoopFileFullPath, target, 1)
        }
    }

    ; 少量字符串排序（插入式，避免依赖额外库）
    static _SortStrings(arr) {
        out := []
        for item in arr {
            placed := false
            next := []
            for existing in out {
                if (!placed && StrCompare(item, existing, "C") < 0) {
                    next.Push(item)
                    placed := true
                }
                next.Push(existing)
            }
            if (!placed)
                next.Push(item)
            out := next
        }
        return out
    }
}
