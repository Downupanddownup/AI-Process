#Requires AutoHotkey v2.0

global OffflowGui := ""
global OffflowList := ""
global OffflowPreview := ""
global OffflowPurposeText := ""
global OffflowReferenceLabel := ""
global OffflowReferenceList := ""
global OffflowReferencePaths := []
global OffflowReferenceHasBody := []
global OffflowReferencesVisible := false
global OffflowPreviewY := 0
global OffflowPreviewMaxHeight := 0
global OffflowContentWidth := 0
global OffflowCopyBodyButton := ""
global OffflowCopyReferenceButton := ""
global OffflowStatus := ""
global OffflowPromptKeys := []
global OffflowPromptNames := []
global OffflowPromptPurposes := []
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

ToggleOffflowPanel(*) {
    global OffflowGui

    if GuiAlive(OffflowGui) {
        CloseOffflowPanel()
    } else {
        ShowOffflowPanel()
    }
}

CreateOffflowPanel() {
    global OffflowGui, OffflowList, OffflowPreview, OffflowPurposeText
    global OffflowReferenceLabel, OffflowReferenceList, OffflowPreviewY, OffflowPreviewMaxHeight, OffflowContentWidth
    global OffflowCopyBodyButton, OffflowCopyReferenceButton, OffflowStatus

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

    contentWidth := width - 24
    contentY := 46
    listHeight := 140
    purposeLabelY := contentY + listHeight + 8
    purposeY := purposeLabelY + 22
    purposeHeight := 54
    previewY := purposeY + purposeHeight + 10
    bottomHeight := 46
    previewHeight := height - previewY - bottomHeight
    bottomY := previewY + previewHeight + 10

    OffflowGui.BackColor := GetDialogBackColor()
    OffflowGui.MarginX := 12
    OffflowGui.MarginY := 12
    OffflowGui.SetFont("s9", "Microsoft YaHei UI")
    OffflowGui.OnEvent("Close", CloseOffflowPanel)
    OffflowGui.OnEvent("Escape", CloseOffflowPanel)

    OffflowGui.AddText("x12 y12 w" contentWidth " h24", "流程外提示词")
    OffflowList := OffflowGui.AddListView("x12 y" contentY " w" contentWidth " h" listHeight " -Multi", ["名称", "类别"])
    categoryWidth := 100
    OffflowList.ModifyCol(1, contentWidth - categoryWidth - 24)
    OffflowList.ModifyCol(2, categoryWidth)
    ApplyDialogListStyle(OffflowList)
    DisableListHeaderSort(OffflowList)
    OffflowList.OnEvent("ItemSelect", OnOffflowPromptSelect)
    OffflowList.OnEvent("DoubleClick", OnOffflowPromptDoubleClick)

    OffflowGui.AddText("x12 y" purposeLabelY " w" contentWidth " h20 cGray", "用途（不随正文复制）")
    OffflowPurposeText := OffflowGui.AddEdit("x12 y" purposeY " w" contentWidth " h" purposeHeight " +ReadOnly +VScroll", "")
    OffflowPreview := OffflowGui.AddEdit("x12 y" previewY " w" contentWidth " h" previewHeight " +ReadOnly +VScroll", "")
    OffflowPreviewY := previewY
    OffflowPreviewMaxHeight := previewHeight
    OffflowContentWidth := contentWidth

    OffflowReferenceLabel := OffflowGui.AddText("x12 y" bottomY " w" contentWidth " h20 cGray", "参考文档（双击打开）")
    OffflowReferenceList := OffflowGui.AddListView("x12 y" bottomY + 24 " w" contentWidth " h70 -Multi", ["名称", "用途"])
    OffflowReferenceList.ModifyCol(1, 140)
    OffflowReferenceList.ModifyCol(2, contentWidth - 164)
    ApplyDialogListStyle(OffflowReferenceList)
    DisableListHeaderSort(OffflowReferenceList)
    OffflowReferenceList.OnEvent("DoubleClick", OnOffflowReferenceDoubleClick)

    OffflowCopyBodyButton := OffflowGui.AddButton("x12 y" bottomY " w88 h28", "复制正文")
    OffflowCopyBodyButton.OnEvent("Click", CopyOffflowBody)
    OffflowCopyReferenceButton := OffflowGui.AddButton("x104 y" bottomY " w88 h28", "复制引用")
    OffflowCopyReferenceButton.OnEvent("Click", CopyOffflowPromptReference)
    closeButton := OffflowGui.AddButton("x" width - 100 " y" bottomY " w88 h28", "关闭")
    closeButton.OnEvent("Click", CloseOffflowPanel)
    OffflowStatus := OffflowGui.AddText("x200 y" bottomY + 5 " w" width - 308 " h20 cGray", "")

    OffflowGui.Show("x" x " y" y " w" width " h" height)
    ClearOffflowReferences()
    RefreshOffflowPanel()
}

RefreshOffflowPanel() {
    global OffflowGui, OffflowList, OffflowPromptKeys, OffflowPromptNames, OffflowPromptPurposes
    global OffflowCopyBodyButton, OffflowCopyReferenceButton

    if !GuiAlive(OffflowGui) {
        return
    }

    OffflowList.Delete()
    OffflowPromptKeys := []
    OffflowPromptNames := []
    OffflowPromptPurposes := []

    try {
        for prompt in OffflowRepository.ListPrompts() {
            if prompt.Hidden {
                continue
            }
            OffflowPromptKeys.Push(prompt.Key)
            OffflowPromptNames.Push(prompt.Name != "" ? prompt.Name : prompt.Key)
            OffflowPromptPurposes.Push(prompt.Purpose)
            OffflowList.Add(, OffflowPromptNames[OffflowPromptNames.Length], prompt.Category)
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

    OffflowCopyBodyButton.Enabled := true
    OffflowCopyReferenceButton.Enabled := true
    OffflowList.Modify(1, "Select Focus")
    UpdateOffflowPreview()
}

OnOffflowPromptSelect(ctrl, item, selected) {
    if selected {
        UpdateOffflowPreview()
    }
}

UpdateOffflowPreview() {
    global OffflowList, OffflowPreview, OffflowPurposeText, OffflowCopyBodyButton, OffflowCopyReferenceButton, OffflowStatus
    global OffflowPromptKeys, OffflowPromptNames, OffflowPromptPurposes
    global OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody

    row := OffflowList.GetNext(0)
    if row = 0 || row > OffflowPromptKeys.Length {
        ClearOffflowSelection("暂无可用提示词")
        return
    }

    OffflowCurrentKey := OffflowPromptKeys[row]
    OffflowCurrentName := OffflowPromptNames[row]
    OffflowPurposeText.Value := ""
    ClearOffflowReferences()
    OffflowRenderedBody := ""
    OffflowCopyBodyButton.Enabled := false
    OffflowCopyReferenceButton.Enabled := false
    OffflowStatus.Text := ""

    try {
        OffflowRenderedBody := OffflowRepository.RenderBody(OffflowCurrentKey)
        OffflowPurposeText.Value := OffflowPromptPurposes[row]
        OffflowPreview.Value := OffflowRenderedBody
        SendMessage(0x00B1, 0, 0, OffflowPurposeText.Hwnd)
        SendMessage(0x00B1, 0, 0, OffflowPreview.Hwnd)
        RefreshOffflowReferences(OffflowCurrentKey)
        OffflowCopyBodyButton.Enabled := true
        OffflowCopyReferenceButton.Enabled := true
    } catch as e {
        OffflowCurrentKey := ""
        OffflowPreview.Value := "预览失败：" e.Message
        OffflowStatus.Text := "无法复制"
    }
}

OnOffflowPromptDoubleClick(ctrl, row, *) {
    global OffflowPromptKeys
    if row > 0 && row <= OffflowPromptKeys.Length {
        CopyOffflowBody()
    }
}

CopyOffflowBody(*) {
    global OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody, OffflowStatus

    if OffflowCurrentKey = "" {
        return
    }

    try {
        A_Clipboard := OffflowRenderedBody
        OffflowStatus.Text := "已复制正文：" OffflowCurrentName
    } catch as e {
        OffflowStatus.Text := "正文复制失败：" e.Message
    }
}

CopyOffflowPromptReference(*) {
    global OffflowCurrentKey, OffflowCurrentName, OffflowStatus

    if OffflowCurrentKey = "" {
        return
    }

    try {
        OffflowPromptReferenceCopy.Copy(OffflowCurrentKey)
        OffflowStatus.Text := "已复制引用：" OffflowCurrentName
    } catch as e {
        OffflowStatus.Text := "引用复制失败：" e.Message
    }
}

ClearOffflowSelection(message := "") {
    global OffflowPreview, OffflowPurposeText, OffflowCopyBodyButton, OffflowCopyReferenceButton, OffflowStatus
    global OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody

    OffflowCurrentKey := ""
    OffflowCurrentName := ""
    OffflowRenderedBody := ""
    ClearOffflowReferences()
    OffflowPurposeText.Value := ""
    OffflowPreview.Value := message
    OffflowStatus.Text := message
    OffflowCopyBodyButton.Enabled := false
    OffflowCopyReferenceButton.Enabled := false
}

RefreshOffflowReferences(key) {
    global OffflowReferenceList, OffflowReferencePaths, OffflowReferenceHasBody, OffflowReferencesVisible
    global OffflowStatus

    ClearOffflowReferences()
    try {
        for ref in OffflowRepository.ListReferences(key) {
            OffflowReferencePaths.Push(ref.Path)
            OffflowReferenceHasBody.Push(ref.HasBody && FileExist(ref.Path))
            OffflowReferenceList.Add(, ref.Name != "" ? ref.Name : ref.Id, ref.Purpose)
        }
    } catch as e {
        ClearOffflowReferences()
        OffflowStatus.Text := "参考读取失败：" e.Message
        return
    }

    OffflowReferencesVisible := OffflowReferencePaths.Length > 0
    UpdateOffflowPanelLayout()
}

ClearOffflowReferences() {
    global OffflowReferenceList, OffflowReferencePaths, OffflowReferenceHasBody, OffflowReferencesVisible

    OffflowReferencePaths := []
    OffflowReferenceHasBody := []
    OffflowReferencesVisible := false
    if OffflowReferenceList {
        OffflowReferenceList.Delete()
    }
    UpdateOffflowPanelLayout()
}

UpdateOffflowPanelLayout() {
    global OffflowGui, OffflowPreview, OffflowReferenceLabel, OffflowReferenceList
    global OffflowReferencesVisible, OffflowPreviewY, OffflowPreviewMaxHeight, OffflowContentWidth

    if !GuiAlive(OffflowGui) || !OffflowPreview {
        return
    }

    if OffflowReferencesVisible {
        previewHeight := OffflowPreviewMaxHeight - 106
        labelY := OffflowPreviewY + previewHeight + 10
        listY := labelY + 24
        OffflowPreview.Move(12, OffflowPreviewY, OffflowContentWidth, previewHeight)
        OffflowReferenceLabel.Move(12, labelY, OffflowContentWidth, 20)
        OffflowReferenceList.Move(12, listY, OffflowContentWidth, 70)
        OffflowReferenceLabel.Visible := true
        OffflowReferenceList.Visible := true
    } else {
        OffflowPreview.Move(12, OffflowPreviewY, OffflowContentWidth, OffflowPreviewMaxHeight)
        OffflowReferenceLabel.Visible := false
        OffflowReferenceList.Visible := false
    }
}

OnOffflowReferenceDoubleClick(ctrl, row, *) {
    OpenOffflowReference(row)
}

OpenOffflowReference(row) {
    global OffflowReferencePaths, OffflowReferenceHasBody, OffflowStatus

    if row <= 0 || row > OffflowReferencePaths.Length {
        return
    }

    path := OffflowReferencePaths[row]
    if !OffflowReferenceHasBody[row] || !FileExist(path) {
        OffflowStatus.Text := "参考正文缺失：" path
        return
    }

    try {
        EditorOpener.Open(path)
    } catch as e {
        OffflowStatus.Text := "参考打开失败：" e.Message
    }
}

CloseOffflowPanel(*) {
    global OffflowGui, OffflowList, OffflowPreview, OffflowPurposeText
    global OffflowReferenceLabel, OffflowReferenceList, OffflowReferencePaths, OffflowReferenceHasBody
    global OffflowReferencesVisible, OffflowPreviewY, OffflowPreviewMaxHeight, OffflowContentWidth
    global OffflowCopyBodyButton, OffflowCopyReferenceButton, OffflowStatus
    global OffflowPromptKeys, OffflowPromptNames, OffflowPromptPurposes
    global OffflowCurrentKey, OffflowCurrentName, OffflowRenderedBody

    if GuiAlive(OffflowGui) {
        try OffflowGui.Destroy()
    }
    OffflowGui := ""
    OffflowList := ""
    OffflowPreview := ""
    OffflowPurposeText := ""
    OffflowReferenceLabel := ""
    OffflowReferenceList := ""
    OffflowReferencePaths := []
    OffflowReferenceHasBody := []
    OffflowReferencesVisible := false
    OffflowPreviewY := 0
    OffflowPreviewMaxHeight := 0
    OffflowContentWidth := 0
    OffflowCopyBodyButton := ""
    OffflowCopyReferenceButton := ""
    OffflowStatus := ""
    OffflowPromptKeys := []
    OffflowPromptNames := []
    OffflowPromptPurposes := []
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
