#Requires AutoHotkey v2.0

; 复关系（AI 型）：复制上下文重建说明并发送 AI
; 迁移自 PromptManager.CopyContextRelations（:262）+ BuildContextRelationsText（:158），逐行等价
; 组成 = 上下文文本（目录头+通用解读+文件清单）+ 不修改 → 完成通知

class CopyRelations extends AgentActionBase {
    ActionKey := "复关系"
    LogTag := "复关系"
    Type := "ai"
    FailLogText := "文件关系说明复制失败"
    FailFeedbackText := "文件关系说明复制失败"

    Execute() {
        content := this.BuildContextText()
        content := PromptElements.NoModify(content)
        content := PromptElements.ContextRelationTail(content)
        this.Dispatch(content, Map("target", "上下文重建"), "文件关系说明已复制")
    }

    ; 本行为的内容构建：目录头 + 通用解读 + 当前目录完整文件清单
    ; （文件清单的约定排序与 .aiprocess 跳过由 DomainConventions.GetAllFilesRecursive 承担）
    BuildContextText() {
        currentDir := GetCurrentDir()

        allFiles := DomainConventions.GetAllFilesRecursive(currentDir)
        if (allFiles.Length = 0) {
            return "当前主题目录：" currentDir "`n`n当前目录下未找到任何文件。"
        }

        universalGuide := this.LoadTemplate("context_relation.txt")

        fileTree := ""
        for path in allFiles {
            fileTree .= path "`n"
        }

        return "当前主题目录：" currentDir
            . "`n`n## 通用解读提示`n" . universalGuide
            . "`n`n## 当前目录完整文件清单`n" . fileTree
    }
}
