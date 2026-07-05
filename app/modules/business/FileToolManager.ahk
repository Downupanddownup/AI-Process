#Requires AutoHotkey v2.0

; 文件处理工具管理模块

; ============================================================
; 数据层
; ============================================================

global g_FileToolsData := Map("default", "", "tools", [])
global g_FileToolsPath := ConfigDir "\filetools.json"

InitFileToolManager() {
    if FileExist(g_FileToolsPath) {
        LoadFileTools()
    }
}

LoadFileTools() {
    global g_FileToolsData, g_FileToolsPath
    try {
        jsonText := FileRead(g_FileToolsPath, "UTF-8")
        g_FileToolsData := JSON.Load(jsonText)
    } catch {
        g_FileToolsData := Map("default", "", "tools", [])
    }
}

SaveFileTools() {
    global g_FileToolsData, g_FileToolsPath, SettingsFile
    try {
        jsonText := JSON.Dump(g_FileToolsData)
        if FileExist(g_FileToolsPath) {
            FileDelete(g_FileToolsPath)
        }
        FileAppend(jsonText, g_FileToolsPath, "UTF-8")

        toolPath := GetCurrentToolPath()
        if (toolPath != "") {
            IniWrite(g_FileToolsData["default"], SettingsFile, "FileTool", "DefaultTool")
            IniWrite(toolPath, SettingsFile, "FileTool", "FileToolPath")
        } else {
            IniWrite("", SettingsFile, "FileTool", "DefaultTool")
            IniWrite("", SettingsFile, "FileTool", "FileToolPath")
        }
    } catch Error {
        ShowFeedback("保存工具配置失败: " Error.Message, true)
    }
}

GetCurrentToolPath() {
    global g_FileToolsData
    defaultName := g_FileToolsData["default"]
    if (defaultName = "") {
        return ""
    }
    for tool in g_FileToolsData["tools"] {
        if (tool["name"] = defaultName) {
            return tool["path"]
        }
    }
    return ""
}

HasDefaultTool() {
    return GetCurrentToolPath() != ""
}

GetDefaultToolName() {
    global g_FileToolsData
    return g_FileToolsData["default"]
}

MigrateFromIdeaCommand() {
    global SettingsFile, g_FileToolsData
    ideaPath := IniRead(SettingsFile, "Editor", "IdeaCommand", "")
    if (ideaPath = "") {
        return
    }

    toolName := ExtractDefaultName(ideaPath)
    newTool := Map("name", toolName, "path", ideaPath, "id", GenerateToolId())
    g_FileToolsData["default"] := toolName
    g_FileToolsData["tools"] := [newTool]

    SaveFileTools()
}

; ============================================================
; 操作层
; ============================================================

GenerateToolId() {
    return Format("tool_{1:04d}", A_TickCount & 0xFFFF)
}

AddFileTool(name, path) {
    global g_FileToolsData
    path := StripQuotes(path)
    if (!ValidateToolPath(path)) {
        return false
    }
    for tool in g_FileToolsData["tools"] {
        if (tool["name"] = name) {
            ShowFeedback("工具名已存在：" name, true)
            return false
        }
    }
    newTool := Map("name", name, "path", path, "id", GenerateToolId())
    g_FileToolsData["tools"].Push(newTool)
    if (g_FileToolsData["default"] = "") {
        g_FileToolsData["default"] := name
    }
    SaveFileTools()
    return true
}

EditFileTool(id, name, path) {
    global g_FileToolsData
    path := StripQuotes(path)
    if (!ValidateToolPath(path)) {
        return false
    }
    oldName := ""
    for tool in g_FileToolsData["tools"] {
        if (tool["id"] = id) {
            oldName := tool["name"]
            tool["name"] := name
            tool["path"] := path
            break
        }
    }
    if (g_FileToolsData["default"] = oldName) {
        g_FileToolsData["default"] := name
    }
    SaveFileTools()
    return true
}

DeleteFileTool(id) {
    global g_FileToolsData
    toolName := ""
    newTools := []
    for tool in g_FileToolsData["tools"] {
        if (tool["id"] = id) {
            toolName := tool["name"]
        } else {
            newTools.Push(tool)
        }
    }
    g_FileToolsData["tools"] := newTools
    if (g_FileToolsData["default"] = toolName) {
        if (newTools.Length > 0) {
            g_FileToolsData["default"] := newTools[1]["name"]
        } else {
            g_FileToolsData["default"] := ""
        }
    }
    SaveFileTools()
}

SetDefaultTool(id) {
    global g_FileToolsData
    for tool in g_FileToolsData["tools"] {
        if (tool["id"] = id) {
            g_FileToolsData["default"] := tool["name"]
            SaveFileTools()
            return true
        }
    }
    return false
}

; ============================================================
; 工具函数
; ============================================================

StripQuotes(s) {
    s := Trim(s)
    l := SubStr(s, 1, 1)
    r := SubStr(s, -1)
    if (l = '"' && r = '"') {
        s := SubStr(s, 2, StrLen(s) - 2)
    }
    if (l = "'" && r = "'") {
        s := SubStr(s, 2, StrLen(s) - 2)
    }
    return Trim(s)
}

ExtractDefaultName(path) {
    cleaned := StripQuotes(path)
    SplitPath(cleaned, &fileName)
    return RegExReplace(fileName, "(?i)\.exe$", "")
}

ValidateToolPath(path) {
    if (path = "") {
        ShowFeedback("路径不能为空", true)
        return false
    }
    if (!FileExist(path)) {
        ShowFeedback("文件不存在：" path, true)
        return false
    }
    if (!RegExMatch(path, "i)\.exe$")) {
        ShowFeedback("请选择一个 .exe 可执行文件", true)
        return false
    }
    return true
}

; ============================================================
; UI 层
; ============================================================

global g_FileToolDialog := ""
global g_FileToolListView := ""

ShowFileToolDialog(ownerHwnd := 0) {
    global g_FileToolDialog, g_FileToolListView

    if (g_FileToolDialog && g_FileToolDialog.Hwnd) {
        g_FileToolDialog.Show()
        WinActivate("ahk_id " g_FileToolDialog.Hwnd)
        RefreshFileToolList()
        return
    }
    g_FileToolDialog := ""
    g_FileToolListView := ""

    dialogOptions := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        dialogOptions .= " +Owner" ownerHwnd
    }

    g_FileToolDialog := Gui(dialogOptions, "文件处理工具")
    g_FileToolDialog.BackColor := "F7F7F7"
    g_FileToolDialog.MarginX := 12
    g_FileToolDialog.MarginY := 10
    g_FileToolDialog.SetFont("s8", "Microsoft YaHei UI")
    g_FileToolDialog.OnEvent("Close", (*) => (g_FileToolDialog.Hide(), RefreshConfigFileToolLabel()))
    g_FileToolDialog.OnEvent("Escape", (*) => (g_FileToolDialog.Hide(), RefreshConfigFileToolLabel()))

    g_FileToolDialog.AddText("xm ym w380 h18", "工具列表")
    g_FileToolListView := g_FileToolDialog.AddListView("xm y+6 w380 h160", ["默认", "名称", "路径"])
    g_FileToolListView.ModifyCol(1, 40)
    g_FileToolListView.ModifyCol(2, 110)
    g_FileToolListView.ModifyCol(3, 210)

    addBtn := g_FileToolDialog.AddButton("xm y+10 w60 h24", "新增")
    addBtn.OnEvent("Click", ShowFileToolAddDialog)

    editBtn := g_FileToolDialog.AddButton("x+6 yp w60 h24", "编辑")
    editBtn.OnEvent("Click", ShowFileToolEditDialog)

    delBtn := g_FileToolDialog.AddButton("x+6 yp w60 h24", "删除")
    delBtn.OnEvent("Click", OnDeleteFileTool)

    defBtn := g_FileToolDialog.AddButton("x+6 yp w72 h24", "设为默认")
    defBtn.OnEvent("Click", OnSetDefaultFileTool)

    g_FileToolDialog.AddText("xm y+10 w380 h14 cGray", "测试当前选中工具：")

    testTxtBtn := g_FileToolDialog.AddButton("xm y+4 w90 h24", "测试打开 TXT")
    testTxtBtn.OnEvent("Click", (*) => TestOpenWithTool("txt"))

    testMdBtn := g_FileToolDialog.AddButton("x+6 yp w90 h24", "测试打开 MD")
    testMdBtn.OnEvent("Click", (*) => TestOpenWithTool("md"))

    closeBtn := g_FileToolDialog.AddButton("x+100 yp w60 h24", "关闭")
    closeBtn.OnEvent("Click", (*) => (g_FileToolDialog.Hide(), RefreshConfigFileToolLabel()))

    RefreshFileToolList()
    g_FileToolDialog.Show("w430 h360")
}

RefreshFileToolList() {
    global g_FileToolListView, g_FileToolsData
    if (!g_FileToolListView) {
        return
    }
    g_FileToolListView.Delete()
    defaultName := g_FileToolsData["default"]
    for tool in g_FileToolsData["tools"] {
        star := (tool["name"] = defaultName) ? "★" : ""
        g_FileToolListView.Add("", star, tool["name"], tool["path"])
    }
}

GetSelectedFileToolId() {
    global g_FileToolListView, g_FileToolsData
    if (!g_FileToolListView) {
        return ""
    }
    row := g_FileToolListView.GetNext(0, "F")
    if (row = 0) {
        ShowFeedback("请先选择一个工具", true)
        return ""
    }
    toolName := g_FileToolListView.GetText(row, 2)
    for tool in g_FileToolsData["tools"] {
        if (tool["name"] = toolName) {
            return tool["id"]
        }
    }
    return ""
}

GetFileToolById(id) {
    global g_FileToolsData
    for tool in g_FileToolsData["tools"] {
        if (tool["id"] = id) {
            return tool
        }
    }
    return ""
}

; --- 新增工具 ---

ShowFileToolAddDialog(*) {
    global g_FileToolDialog
    ownerHwnd := g_FileToolDialog ? g_FileToolDialog.Hwnd : 0
    options := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        options .= " +Owner" ownerHwnd
    }

    addGui := Gui(options, "新增工具")
    addGui.BackColor := "F7F7F7"
    addGui.MarginX := 12
    addGui.MarginY := 10
    addGui.SetFont("s8", "Microsoft YaHei UI")

    addGui.AddText("xm ym w300 h18", "程序路径（从资源管理器复制粘贴）")
    pathEdit := addGui.AddEdit("xm y+4 w300 h24", "")

    addGui.AddText("xm y+10 w300 h18", "工具名称（自动提取，可修改）")
    nameEdit := addGui.AddEdit("xm y+4 w300 h24", "")

    pathEdit.OnEvent("Change", (*) => OnPathChanged(pathEdit, nameEdit))

    okBtn := addGui.AddButton("xm y+12 w72 h24 Default", "确定")
    cancelBtn := addGui.AddButton("x+8 yp w72 h24", "取消")
    cancelBtn.OnEvent("Click", (*) => addGui.Destroy())

    okBtn.OnEvent("Click", (*) => (
        SubmitAddFileTool(addGui, nameEdit, pathEdit)
    ))

    addGui.Show("w330 h210")
}

OnPathChanged(pathEdit, nameEdit) {
    path := Trim(pathEdit.Value)
    if (path != "" && Trim(nameEdit.Value) = "") {
        nameEdit.Value := ExtractDefaultName(path)
    }
}

SubmitAddFileTool(addGui, nameEdit, pathEdit) {
    name := Trim(nameEdit.Value)
    path := Trim(pathEdit.Value)
    if (path != "" && name = "") {
        name := ExtractDefaultName(path)
        nameEdit.Value := name
    }
    if (name = "") {
        ShowFeedback("请输入工具名称", true)
        return
    }
    if (path = "") {
        ShowFeedback("请输入程序路径", true)
        return
    }
    if (AddFileTool(name, path)) {
        addGui.Destroy()
        RefreshFileToolList()
        ShowFeedback("工具已添加")
    }
}

; --- 编辑工具 ---

ShowFileToolEditDialog(*) {
    global g_FileToolDialog
    id := GetSelectedFileToolId()
    if (id = "") {
        return
    }
    tool := GetFileToolById(id)
    if (tool = "") {
        return
    }

    ownerHwnd := g_FileToolDialog ? g_FileToolDialog.Hwnd : 0
    options := "+AlwaysOnTop +ToolWindow"
    if ownerHwnd {
        options .= " +Owner" ownerHwnd
    }

    editGui := Gui(options, "编辑工具")
    editGui.BackColor := "F7F7F7"
    editGui.MarginX := 12
    editGui.MarginY := 10
    editGui.SetFont("s8", "Microsoft YaHei UI")

    editGui.AddText("xm ym w300 h18", "程序路径（从资源管理器复制粘贴）")
    pathEdit := editGui.AddEdit("xm y+4 w300 h24", tool["path"])

    editGui.AddText("xm y+10 w300 h18", "工具名称")
    nameEdit := editGui.AddEdit("xm y+4 w300 h24", tool["name"])

    okBtn := editGui.AddButton("xm y+12 w72 h24 Default", "确定")
    cancelBtn := editGui.AddButton("x+8 yp w72 h24", "取消")
    cancelBtn.OnEvent("Click", (*) => editGui.Destroy())

    okBtn.OnEvent("Click", (*) => (
        SubmitEditFileTool(editGui, nameEdit, pathEdit, id)
    ))

    editGui.Show("w330 h210")
}

SubmitEditFileTool(editGui, nameEdit, pathEdit, id) {
    name := Trim(nameEdit.Value)
    path := Trim(pathEdit.Value)
    if (name = "") {
        ShowFeedback("请输入工具名称", true)
        return
    }
    if (path = "") {
        ShowFeedback("请输入程序路径", true)
        return
    }
    if (EditFileTool(id, name, path)) {
        editGui.Destroy()
        RefreshFileToolList()
        ShowFeedback("工具已更新")
    }
}

; --- 删除工具 ---

OnDeleteFileTool(*) {
    global g_FileToolDialog
    id := GetSelectedFileToolId()
    if (id = "") {
        return
    }
    tool := GetFileToolById(id)
    if (tool = "") {
        return
    }
    ownerHwnd := g_FileToolDialog ? g_FileToolDialog.Hwnd : 0
    result := MsgBox("确定要删除工具 '" tool["name"] "' 吗？", "确认删除", "Icon? YesNo Owner" ownerHwnd)
    if (result = "Yes") {
        DeleteFileTool(id)
        RefreshFileToolList()
        ShowFeedback("工具已删除")
    }
}

; --- 设为默认 ---

OnSetDefaultFileTool(*) {
    id := GetSelectedFileToolId()
    if (id = "") {
        return
    }
    if (SetDefaultTool(id)) {
        RefreshFileToolList()
        ShowFeedback("默认工具已切换")
    }
}

; --- 测试打开 ---

TestOpenWithTool(fileType) {
    global AppRoot
    id := GetSelectedFileToolId()
    if (id = "") {
        return
    }
    tool := GetFileToolById(id)
    if (tool = "") {
        return
    }

    testDir := AppRoot "\.测试文件"
    DirCreate(testDir)

    testFile := testDir "\测试." (fileType = "md" ? "md" : "txt")

    if (!FileExist(testFile)) {
        if (fileType = "md") {
            FileAppend("# 测试 Markdown 预览`n`n这是一个测试文件。", testFile, "UTF-8")
        } else {
            FileAppend("测试 TXT 文件打开", testFile, "UTF-8")
        }
    }

    try {
        Run('"' tool["path"] '" "' testFile '"')
    } catch Error {
        ShowFeedback("工具启动失败，请检查路径", true)
    }
}
