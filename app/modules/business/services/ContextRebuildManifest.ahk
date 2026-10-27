#Requires AutoHotkey v2.0

class ContextRebuildManifest {
    static TextExtensions := Map(
        "ahk", true, "bat", true, "cmd", true, "csv", true,
        "css", true, "html", true, "ini", true, "java", true,
        "js", true, "json", true, "jsonl", true, "log", true,
        "md", true, "ps1", true, "psm1", true, "sql", true,
        "ts", true, "txt", true, "vue", true, "xml", true,
        "yaml", true, "yml", true
    )

    static Build(themeDir) {
        root := RTrim(themeDir, "\/")
        entries := []
        textBytes := 0
        binaryFileCount := 0
        manifestText := ""

        for path in DomainConventions.GetAllFilesRecursive(themeDir) {
            size := FileGetSize(path)
            SplitPath(path, , , &ext)
            isText := this.TextExtensions.Has(StrLower(ext))
            if (isText) {
                textBytes += size
            } else {
                binaryFileCount++
            }
            entries.Push(Map(
                "Path", path,
                "RelativePath", SubStr(path, StrLen(root) + 2),
                "SizeBytes", size,
                "IsText", isText
            ))
            manifestText .= path " [" FormatByteSize(size) "]`n"
        }

        summary := "文件 " entries.Length " 份；可读取文本 " FormatByteSize(textBytes)
            . "；二进制文件 " binaryFileCount " 份。"
        return Map(
            "Entries", entries,
            "FileCount", entries.Length,
            "TextBytes", textBytes,
            "BinaryFileCount", binaryFileCount,
            "Summary", summary,
            "ManifestText", manifestText
        )
    }
}
