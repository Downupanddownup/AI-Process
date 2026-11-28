#Requires AutoHotkey v2.0

; 判定：只判对错，返回问题清单（字符串数组）。
; 不改文件、不调 UI、不 print——输出形态由调用方决定。

class OffflowValidator {

    ; 判一条；key 为目录名
    static Check(key) {
        problems := []
        catDir := OffflowRepository.DataRoot "\" key

        ; ① meta 三项
        metaPath := catDir "\meta.json"
        if !FileExist(metaPath) {
            problems.Push(key " / meta.json / 不存在")
        } else {
            cat := OffflowPrompt.FromDir(catDir)
            if (cat.Name = "") {
                problems.Push(key " / meta.json / 缺 name")
            }
            if (cat.Purpose = "") {
                problems.Push(key " / meta.json / 缺 purpose")
            }
            if (cat.HasCategory) {
                if (Trim(cat.Category) = "") {
                    problems.Push(key " / meta.json / category 为空")
                } else if (StrLen(cat.Category) > 12) {
                    problems.Push(key " / meta.json / category 超过 12 字（" StrLen(cat.Category) "）")
                }
            }
            if (cat.HasHidden && cat.HiddenRaw != "1" && cat.HiddenRaw != "0"
                && cat.HiddenRaw != "true" && cat.HiddenRaw != "false") {
                problems.Push(key " / meta.json / hidden 只接受 true/false，实际为 " cat.HiddenRaw)
            }
            try {
                raw := JSON.Load(FileRead(metaPath, "UTF-8"))
                if raw.Has("key") && _OffflowValStr(raw["key"]) != key {
                    problems.Push(key " / meta.json / key 与目录名不一致：" _OffflowValStr(raw["key"]))
                }
            }
        }

        ; ② 正文非空
        bodyPath := catDir "\body.txt"
        if !FileExist(bodyPath) {
            problems.Push(key " / body.txt / 不存在")
        } else if (Trim(FileRead(bodyPath, "UTF-8")) = "") {
            problems.Push(key " / body.txt / 为空")
        }

        ; ③④ 引用：目标存在、细则内不得再引用
        refs := OffflowRepository.ListReferences(key)
        for ref in refs {
            if !ref.HasBody {
                problems.Push(key " / references/" ref.Id " / 缺 body.md")
                continue
            }
            if RegExMatch(ref.Body, "\{\{ref:") {
                problems.Push(key " / references/" ref.Id "/body.md / 细则内不得再写 {{ref:}}")
            }
        }

        ; 正文里每个 {{ref:id}} 都要能落到一份细则
        body := OffflowRepository.ReadBody(key)
        pos := 1
        while RegExMatch(body, OffflowRepository.RefPattern, &m, pos) {
            id := m[1]
            if (OffflowRepository.FindReference(key, id) = "") {
                problems.Push(key " / body.txt / 引用不存在：" id)
            }
            pos := m.Pos + m.Len
        }

        return problems
    }

    ; 判全部（含缺 meta.json 的目录）
    static CheckAll() {
        problems := []
        templateProblems := this.CheckReferenceCopyTemplate()
        for p in templateProblems {
            problems.Push(p)
        }
        canBuildReference := templateProblems.Length = 0
        sharedBuildFailed := false

        for dir in OffflowRepository.ListAllDirs() {
            SplitPath(dir, &key)
            itemProblems := this.Check(key)
            for p in itemProblems {
                problems.Push(p)
            }
            if itemProblems.Length > 0 || !canBuildReference || sharedBuildFailed {
                continue
            }
            try {
                OffflowPromptReferenceCopy.Build(key)
            } catch as e {
                if InStr(e.Message, "公共提示词") = 1 {
                    problems.Push("共享 / prompt_reference_copy.txt / " e.Message)
                    sharedBuildFailed := true
                } else {
                    problems.Push(key " / prompt_reference_copy.txt / " e.Message)
                }
            }
        }
        return problems
    }

    static CheckReferenceCopyTemplate() {
        path := OffflowPromptReferenceCopy.TemplatePath
        if !FileExist(path) {
            return ["共享 / prompt_reference_copy.txt / 不存在"]
        }
        try {
            if Trim(FileRead(path, "UTF-8")) = "" {
                return ["共享 / prompt_reference_copy.txt / 为空"]
            }
        } catch as e {
            return ["共享 / prompt_reference_copy.txt / 无法读取：" e.Message]
        }
        return []
    }

    ; 条数（报告用）
    static CountPrompts() {
        return OffflowRepository.ListAllDirs().Length
    }
}

_OffflowValStr(v) {
    if (v = true) {
        return "true"
    }
    if (v = false) {
        return "false"
    }
    return String(v)
}
