#Requires AutoHotkey v2.0

; 编辑器打开服务：用配置的编辑器打开文件（= 原 FileManager.OpenFileInTool，逐行等价）

class EditorOpener {

    static Open(filePath) {
        toolPath := GetCurrentToolPath()
        if (toolPath = "") {
            ShowFeedback("未配置文件处理工具，请在托盘→配置中添加", true)
            return
        }
        try {
            Run('"' toolPath '" "' filePath '"')
        } catch Error {
            ShowFeedback("文件工具打开失败，请检查配置", true)
        }
    }
}
