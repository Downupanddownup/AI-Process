#Requires AutoHotkey v2.0

class OffflowPromptReferenceCopy {

    static TemplatePath {
        get => OffflowRepository.DataRoot "\prompt_reference_copy.txt"
    }

    static Build(key) {
        if Trim(key) = "" {
            throw Error("方案 key 为空")
        }

        promptDir := OffflowRepository.DataRoot "\" key
        if !DirExist(promptDir) {
            throw Error("方案目录不存在：" promptDir)
        }

        prompt := OffflowPrompt.FromDir(promptDir)
        if prompt.Name = "" {
            throw Error("方案缺 name：" key)
        }
        if prompt.Purpose = "" {
            throw Error("方案缺 purpose：" key)
        }

        bodyPath := OffflowRepository.BodyPath(key)
        if !FileExist(bodyPath) {
            throw Error("方案正文不存在：" bodyPath)
        }
        if Trim(FileRead(bodyPath, "UTF-8")) = "" {
            throw Error("方案正文为空：" bodyPath)
        }

        if !FileExist(this.TemplatePath) {
            throw Error("公共提示词不存在：" this.TemplatePath)
        }
        template := FileRead(this.TemplatePath, "UTF-8")
        if Trim(template) = "" {
            throw Error("公共提示词为空：" this.TemplatePath)
        }

        values := Map(
            "name", prompt.Name,
            "purpose", prompt.Purpose,
            "bodyPath", bodyPath,
            "referencesPath", OffflowRepository.ReferencesPath(key)
        )

        out := ""
        pos := 1
        while RegExMatch(template, "\{\{([A-Za-z][A-Za-z0-9_]*)\}\}", &m, pos) {
            out .= SubStr(template, pos, m.Pos - pos)
            if !values.Has(m[1]) {
                throw Error("公共提示词含未知字段：" m[1])
            }
            out .= values[m[1]]
            pos := m.Pos + m.Len
        }
        out .= SubStr(template, pos)
        return out
    }

    static Copy(key) {
        text := this.Build(key)
        A_Clipboard := text
    }
}
