#Requires AutoHotkey v2.0

; 需求树窗口：把递归的对话域结构铺成一棵可点的树，双击 = 「设目录」的快捷操作
; 全程只读目录结构；唯一的写动作是双击后切当前目录（不碰文件、不建 需求.txt）

global DomainTreeWindow := ""
global DomainTreeView := ""
global DomainTreeNodeByItem := Map()      ; itemId → Map("path", …, "isGroup", …)
global DomainTreeCurrentItem := 0         ; 建树时记下"当前目录"那个节点；0 = 不在树里
global DomainTreeSuppressExpand := false


ShowDomainTreeWindow(*) {
    rootDir := DomainTree.FindRoot(GetCurrentDir())
    if (rootDir = "") {
        ShowFeedback("当前目录不在任何对话域内", true)
        return
    }

    ; 重开 = 销毁重建：避开 TreeView 没有 DeleteAll，也顺带清掉上一次的展开与选中态
    CloseDomainTreeWindow()
    CreateDomainTreeWindow()
    BuildDomainTree(rootDir)
    ShowDomainTreeWindowAtCenter()
}


CreateDomainTreeWindow() {
    global DomainTreeWindow, DomainTreeView, MainGui

    ownerHwnd := MainGui ? MainGui.Hwnd : 0
    guiOptions := ""
    if (ownerHwnd) {
        guiOptions .= "+Owner" ownerHwnd
    }

    DomainTreeWindow := Gui(guiOptions, "需求树")
    DomainTreeWindow.BackColor := "F7F7F7"
    DomainTreeWindow.MarginX := 10
    DomainTreeWindow.MarginY := 10
    DomainTreeWindow.SetFont("s8", "Microsoft YaHei UI")
    DomainTreeWindow.OnEvent("Close", CloseDomainTreeWindow)
    DomainTreeWindow.OnEvent("Escape", CloseDomainTreeWindow)

    ; -Buttons 去掉节点前的 +/-（口径是「全展开、不存在收缩」）
    DomainTreeView := DomainTreeWindow.AddTreeView("xm ym w340 h460 -Buttons")
    ; 单击 = 只选中 → 不挂 ItemSelect，控件的默认行为就是我们要的
    DomainTreeView.OnEvent("DoubleClick", OnDomainTreeDoubleClick)
    DomainTreeView.OnEvent("ItemExpand", OnDomainTreeItemExpand)
}


BuildDomainTree(rootDir) {
    global DomainTreeView

    rootItem := DomainTreeView.Add(DomainTree.LabelFor(rootDir), 0)
    RegisterDomainTreeNode(rootItem, rootDir, false)

    for node in DomainTree.ListChildNodes(rootDir) {
        AddDomainTreeNode(node, rootItem)
    }

    DomainTreeView.Modify(rootItem, "Expand")
}


AddDomainTreeNode(node, parentItem) {
    global DomainTreeView

    itemId := DomainTreeView.Add(node["label"], parentItem)
    RegisterDomainTreeNode(itemId, node["path"], node["isGroup"])

    for child in node["children"] {
        AddDomainTreeNode(child, itemId)
    }
    DomainTreeView.Modify(itemId, "Expand")
}


; 节点登记：只存双击要用的两个事实，顺带在建树时就认出"当前目录"那个节点
; （省掉一张 path→item 的映射表；路径比较复用既有的 PathsEqual）
RegisterDomainTreeNode(itemId, dirPath, isGroup) {
    global DomainTreeNodeByItem, DomainTreeCurrentItem

    DomainTreeNodeByItem[itemId] := Map("path", dirPath, "isGroup", isGroup)
    if (PathsEqual(dirPath, GetCurrentDir())) {
        DomainTreeCurrentItem := itemId
    }
}


; 先建完再 Show：建树期间的 Modify/Add 不会回抛事件，也不会闪
ShowDomainTreeWindowAtCenter() {
    global DomainTreeWindow, MainGui

    width := 360
    height := 480
    if (MainGui) {
        WinGetPos(&mainX, &mainY, &mainW, &mainH, "ahk_id " MainGui.Hwnd)
        x := mainX + Floor((mainW - width) / 2)
        y := mainY + Floor((mainH - height) / 2)
        DomainTreeWindow.Show("w" width " h" height " x" x " y" y)
    } else {
        DomainTreeWindow.Show("w" width " h" height)
    }
    LocateCurrentDirInTree()
}


; 打开时定位：当前目录若在树里有节点 → 选中并滚入视野；
; 不在（如 基础信息、仓库根、已被删除的目录）→ 不选任何节点
LocateCurrentDirInTree() {
    global DomainTreeView, DomainTreeCurrentItem

    if (DomainTreeCurrentItem = 0) {
        return
    }
    DomainTreeView.Modify(DomainTreeCurrentItem, "Select")
    DomainTreeView.Modify(DomainTreeCurrentItem, "Vis")
}


OnDomainTreeDoubleClick(ctrl, *) {
    global DomainTreeNodeByItem

    ; 不依赖回调参数签名：双击必然先完成选中，用 GetSelection() 取节点最稳
    itemId := ctrl.GetSelection()
    if (itemId = 0 || !DomainTreeNodeByItem.Has(itemId)) {
        return
    }

    node := DomainTreeNodeByItem[itemId]
    if (node["isGroup"]) {
        return      ; 分组节点是容器不是对话域，双击无动作
    }

    SetCurrentDirAndRefresh(node["path"], "需求树")
    CloseDomainTreeWindow()
}


OnDomainTreeItemExpand(ctrl, itemId, *) {
    global DomainTreeSuppressExpand

    if DomainTreeSuppressExpand {
        return
    }
    ; 「不存在收缩」：被收起就展回去。展开一个已展开的节点是空操作，故不必区分方向。
    DomainTreeSuppressExpand := true
    ctrl.Modify(itemId, "Expand")
    DomainTreeSuppressExpand := false
}


CloseDomainTreeWindow(*) {
    global DomainTreeWindow, DomainTreeView, DomainTreeNodeByItem, DomainTreeCurrentItem

    if (DomainTreeWindow) {
        DomainTreeWindow.Destroy()
        DomainTreeWindow := ""
    }
    DomainTreeView := ""
    DomainTreeNodeByItem := Map()
    DomainTreeCurrentItem := 0
}
