#Requires AutoHotkey v2.0

; 对话域树的遍历与呈现（数据的定义在 DomainConventions，本类不重复定义）
; 节点集：对话域 = DomainConventions.IsDomainDir；非对话域但其下有对话域的 → 分组
; 顺序：复用 DomainConventions.GetSubdirsByConvention，不新增排序规则

class DomainTree {

    ; ==== 顶点 ====
    ; 从 fromDir 向上取「最外层」对话域；一个都没有返回 ""（调用方据此把按钮置灰）
    static FindRoot(fromDir) {
        if (fromDir = "") {
            return ""
        }
        rootDir := ""
        current := fromDir
        Loop {
            if (DomainConventions.IsDomainDir(current)) {
                rootDir := current
            }
            SplitPath(current, , &parentDir)
            if (parentDir = "" || parentDir = current) {
                break
            }
            current := parentDir
        }
        return rootDir
    }

    ; ==== 分层遍历 ====
    ; 返回 dirPath 下「可显示」的直接子节点数组（嵌套）
    ; 元素：Map("path" => 目录绝对路径, "isGroup" => 是否分组, "label" => 显示文本, "children" => 子节点数组)
    static ListChildNodes(dirPath) {
        result := []
        for subPath in DomainConventions.GetSubdirsByConvention(dirPath) {
            node := this._BuildNode(subPath)
            if (node) {
                result.Push(node)
            }
        }
        return result
    }

    ; 显示文本：未开工的对话域加 "未·" 前缀；分组用尾随 "/"
    ; （呈现规则留在本类；"未开工"这个领域状态从 DomainConventions 取）
    static LabelFor(dirPath) {
        name := ExtractFileName(dirPath)
        if (DomainConventions.HasRequirement(dirPath)) {
            return name
        }
        return "未·" name
    }

    ; 私有：一个子目录 → 节点；既不是对话域、其下也没有对话域 → 返回 ""（不显示）
    static _BuildNode(dirPath) {
        children := this.ListChildNodes(dirPath)
        if (DomainConventions.IsDomainDir(dirPath)) {
            return Map(
                "path", dirPath,
                "isGroup", false,
                "label", this.LabelFor(dirPath),
                "children", children
            )
        }
        if (children.Length = 0) {
            return ""
        }
        return Map(
            "path", dirPath,
            "isGroup", true,
            "label", ExtractFileName(dirPath) "/",
            "children", children
        )
    }
}
