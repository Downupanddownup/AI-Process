#Requires AutoHotkey v2.0

global OffflowGui := ""
global OffflowList := ""
global OffflowPreview := ""
global OffflowCopyButton := ""
global OffflowStatus := ""
global OffflowPromptKeys := []
global OffflowPromptNames := []
global OffflowCurrentKey := ""
global OffflowCurrentName := ""
global OffflowRenderedBody := ""

ShowOffflowPanel(*) {
    global OffflowGui

    if GuiAlive(OffflowGui) {
        OffflowGui.Show()
        WinActivate("ahk_id " OffflowGui.Hwnd)
        RefreshOffflowPanel()
        return
    }
    CreateOffflowPanel()
}

CreateOffflowPanel() {
    global OffflowGui, OffflowList, OffflowPreview, OffflowCopyButton, OffflowStatus

    area := GetOffflowWorkArea()
    OffflowGui := Gui("+AlwaysOnTop +ToolWindow -Caption", "流程外提示词")
    dpiScale := DllCall("GetDpiForWindow", "ptr", OffflowGui.Hwnd, "uint") / 96
    if dpiScale <= 0 {
        dpiScale := 1
    }
    physicalWidth := Min(620, Max(420, Floor(area["w"] * 0.45)))
    width := Round(physicalWidth / dpiScale)
    height := Round(area["h"] / dpiScale)
    physicalWidth := Round(width * dpiScale)
    x := area["x"] + area["w"] - physicalWidth
    y := area["y"]

    listWidth := 180
    previewX := 12 + listWidth + 10
    previewWidth := width - previewX - 12
    contentY := 46
    bottomHeight := 46
    contentHeight := height - contentY - bottomHeight
    bottomY := contentY + contentHeight + 10

    OffflowGui.BackColor := GetDialogBackColor()
    OffflowGui.MarginX := 12
    OffflowGui.MarginY := 12
    OffflowGui.SetFont("s9", "Microsoft YaHei UI")
    OffflowGui.OnEvent("Close", CloseOffflowPanel)
    OffflowGui.OnEvent("Escape", CloseOffflowPanel)

    OffflowGui.AddText("x12 y12 w" width - 24 " h24", "流程外提示词")
    OffflowList := OffflowGui.AddListView("x12 y" contentY " w" listWidth " h" contentHeight " -Multi", ["名称"])
    OffflowList.ModifyCol(1, listWidth - 24)
    ApplyDialogListStyle(OffflowList)
    DisableListHeaderSort(OffflowList)
    OffflowList.OnEvent("ItemSelect", OnOffflowPromptSelect)
    OffflowList.OnEvent("DoubleClick", OnOffflowPromptDoubleClick)

    OffflowPreview := OffflowGui.AddEdit("x" previewX " y" contentY " w" previewWidth " h" contentHeight " +ReadOnly +VScroll", "")

    OffflowCopyButton := OffflowGui.AddButton("x12 y" bottomY " w88 h28", "复制")
    OffflowCopyButton.OnEvent("Click", CopyOffflowPrompt)
    closeButton := OffflowGui.AddButton("x" width - 100 " y" bottomY " w88 h28", "关闭")
    closeButton.OnEvent("Click", CloseOffflowPanel)
    OffflowStatus := OffflowGui.AddText("x112 y" bottomY + 5 " w" width - 224 " h20 cGray", "")

    OffflowGui.Show("x" x " y" y " w" width " h" height)
    RefreshOffflowPanel()
}

RefreshOffflowPanel() {
    global OffflowGui, OffflowList, OffflowPromptKeys, OffflowPromptNames

    if !GuiAlive(OffflowGui) {
        return
    }

    OffflowList.Delete()
    OffflowPromptKeys := []
    OffflowPromptNames := []

    try {
        for prompt in OffflowRepository.ListPrompts() {
            if prompt.Hidden {
                continue
            }
            OffflowPromptKeys.Push(prompt.Key)
            OffflowPromptNames.Push(prompt.Name != "" ? prompt.Name : prompt.Key)
            OffflowList.Add(, OffflowPromptNames[OffflowPromptNames.Length])
        }
    } catch as e {
        ClearOffflowSelection("读取失败：" e.Message)
        return
    }

    if OffflowPromptKeys.Length = 0 {
        OffflowList.Add(, "暂无可用提示词")
        ClearOffflowSelection("暂无可用提示词")
        return
    }

    OffflowCopyButton.Enabled := true
    OffflowList.Modify(1, "Select Focus")
    UpdateOffflowPreview()
}

OnOffflowPromptSelect(ctrl, item, selected) {
    if selected {
        UpdateOffflowPreview()
    }
}

UpdateOffflowPreview() {
    global OffflowList, OffflowPreview, OffflowCopyButton, OffflowStatus
    global OffflowPromptKeys, OffflowPromptNames, OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody

    row := OffflowList.GetNext(0)
    if row = 0 || row > OffflowPromptKeys.Length {
        ClearOffflowSelection("暂无可用提示词")
        return
    }

    OffflowCurrentKey := OffflowPromptKeys[row]
    OffflowCurrentName := OffflowPromptNames[row]
    OffflowRenderedBody := ""
    OffflowCopyButton.Enabled := false
    OffflowStatus.Text := ""

    try {
        OffflowRenderedBody := OffflowRepository.RenderBody(OffflowCurrentKey)
        OffflowPreview.Value := OffflowRenderedBody
        SendMessage(0x00B1, 0, 0, OffflowPreview.Hwnd)
        OffflowCopyButton.Enabled := true
    } catch as e {
        OffflowCurrentKey := ""
        OffflowPreview.Value := "预览失败：" e.Message
        OffflowStatus.Text := "无法复制"
    }
}

OnOffflowPromptDoubleClick(ctrl, row, *) {
    global OffflowPromptKeys
    if row > 0 && row <= OffflowPromptKeys.Length {
        CopyOffflowPrompt()
    }
}

CopyOffflowPrompt(*) {
    global OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody, OffflowStatus

    if OffflowCurrentKey = "" {
        return
    }

    try {
        A_Clipboard := OffflowRenderedBody
        OffflowStatus.Text := "已复制：" OffflowCurrentName
    } catch as e {
        OffflowStatus.Text := "复制失败：" e.Message
    }
}

ClearOffflowSelection(message := "") {
    global OffflowPreview, OffflowCopyButton, OffflowStatus
    global OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody

    OffflowCurrentKey := ""
    OffflowCurrentName := ""
    OffflowRenderedBody := ""
    OffflowPreview.Value := message
    OffflowStatus.Text := message
    OffflowCopyButton.Enabled := false
}

CloseOffflowPanel(*) {
    global OffflowGui, OffflowList, OffflowPreview, OffflowCopyButton, OffflowStatus
    global OffflowPromptKeys, OffflowPromptNames, OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody

    if GuiAlive(OffflowGui) {
        try OffflowGui.Destroy()
    }
    OffflowGui := ""
    OffflowList := ""
    OffflowPreview := ""
    OffflowCopyButton := ""
    OffflowStatus := ""
    OffflowPromptKeys := []
    OffflowPromptNames := []
    OffflowCurrentKey := ""
    OffflowCurrentName := ""
    OffflowRenderedBody := ""
}

GetOffflowWorkArea() {
    try {
        WinGetPos(&windowX, &windowY, &windowWidth, &windowHeight, "A")
        area := OffflowWorkAreaAt(windowX + windowWidth / 2, windowY + windowHeight / 2)
        if area.Has("x") {
            return area
        }
    }

    MouseGetPos(&mouseX, &mouseY)
    area := OffflowWorkAreaAt(mouseX, mouseY)
    if area.Has("x") {
        return area
    }

    MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
    return Map("x", left, "y", top, "w", right - left, "h", bottom - top)
}

OffflowWorkAreaAt(x, y) {
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        if x >= left && x < right && y >= top && y < bottom {
            return Map("x", left, "y", top, "w", right - left, "h", bottom - top)
        }
    }
    return Map()
}
