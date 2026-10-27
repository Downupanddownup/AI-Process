#Requires AutoHotkey v2.0

class ContextRebuildPromptBuilder {
    static Build(themeDir) {
        manifest := ContextRebuildManifest.Build(themeDir)
        if (manifest["FileCount"] = 0) {
            return "当前主题目录：" themeDir "`n`n当前目录下未找到任何文件。"
        }

        templateName := ContextRebuildScalePolicy.ShouldUseSkeleton(manifest)
            ? "context_relation_skeleton.txt"
            : "context_relation_full.txt"
        content := this.LoadTemplate(templateName)
        content := StrReplace(content, "{{scaleSummary}}", manifest["Summary"])
        content := StrReplace(content, "{{fileManifest}}", manifest["ManifestText"])
        return "当前主题目录：" themeDir "`n`n## 通用解读提示`n" content
    }

    static LoadTemplate(fileName) {
        global TemplateDir
        path := TemplateDir "\" fileName
        if (!FileExist(path)) {
            throw Error("上下文重建模板不存在：" path)
        }
        return FileRead(path, "UTF-8")
    }
}
