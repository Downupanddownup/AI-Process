#Requires AutoHotkey v2.0

; 领域约定单源：版本链 / 目录命名 / 约定排序（对应 约定.md 第二章）
; 逐行等价迁出（旧件已删）：实现形状照旧，勿按新写法重写

class DomainConventions {

    ; ==== 文件名常量 ====
    static RequirementFile := "需求.txt"
    static ImplDocFile := "实施文档.md"
    static ExecutedFile := "已实施.md"

    ; ==== 目录名常量 ====
    static ResultIssueRoot := "结果微调"
    static StepsDir := "实施步骤"
    static DataDir := ".aiprocess"

    ; ==== 命名规则（正则） ====
    static VersionFilePattern := "^v(\d+)\.md$"
    static ReplyFilePattern := "^对v(\d+)的回复\.txt$"
    static IssueDirPattern := "^\d{2}$"

    ; ==== 判定 ====
    ; 版本文件 → 返回版本号；非版本文件返回 0
    static IsVersionFile(name) {
        return RegExMatch(name, DomainConventions.VersionFilePattern, &m) ? Integer(m[1]) : 0
    }
    ; 回复文件 → 返回对应版本号；非回复文件返回 0
    static IsReplyFile(name) {
        return RegExMatch(name, DomainConventions.ReplyFilePattern, &m) ? Integer(m[1]) : 0
    }
    static IsRequirementFile(name) {
        return name = DomainConventions.RequirementFile
    }
    static IsImplDocFile(name) {
        return name = DomainConventions.ImplDocFile
    }
    static IsExecutedFile(name) {
        return name = DomainConventions.ExecutedFile
    }
    ; 结果微调子议题目录
    static IsResultIssueDir(dirPath) {
        if (dirPath = "" || !DirExist(dirPath)) {
            return false
        }
        SplitPath(dirPath, &dirName, &parentDir)
        if !RegExMatch(dirName, DomainConventions.IssueDirPattern) {
            return false
        }
        SplitPath(parentDir, &parentName)
        return parentName = DomainConventions.ResultIssueRoot
    }
    ; 对话域：含 需求.txt，或位于 实施步骤 之下
    ; （步骤目录由「步目」拆分时创建，不建 需求.txt，见 约定.md 三）
    static IsDomainDir(dirPath) {
        if (dirPath = "" || !DirExist(dirPath)) {
            return false
        }
        if (DomainConventions.HasRequirement(dirPath)) {
            return true
        }
        SplitPath(dirPath, , &parentDir)
        return ExtractFileName(parentDir) = DomainConventions.StepsDir
    }
    ; 需求.txt 在不在，就是"已开工 / 未开工"的状态位
    static HasRequirement(dirPath) {
        return FileExist(DomainConventions.RequirementPath(dirPath)) ? true : false
    }

    ; ==== 派生路径 ====
    static GetResultIssueRoot(themeDirPath) {
        return themeDirPath "\" DomainConventions.ResultIssueRoot
    }
    static RequirementPath(dirPath) {
        return dirPath "\" DomainConventions.RequirementFile
    }
    static VersionPath(dirPath, n) {
        return dirPath "\v" n ".md"
    }
    static ReplyPath(dirPath, n) {
        return dirPath "\对v" n "的回复.txt"
    }
    static ImplDocPath(dirPath) {
        return dirPath "\" DomainConventions.ImplDocFile
    }
    ; 结果微调子议题目录 → 主题目录
    static GetThemeRootFromIssueDir(dirPath) {
        fileName := ""
        parentName := ""
        parentDir := ""
        themeDir := ""
        SplitPath(dirPath, &fileName, &parentDir)
        SplitPath(parentDir, &parentName, &themeDir)
        return themeDir
    }

    ; ==== 计算 ====
    static GetLatestVersionNumber(dirPath) {
        latest := 0
        Loop Files, dirPath "\v*.md", "F" {
            version := DomainConventions.IsVersionFile(A_LoopFileName)
            if (version > latest) {
                latest := version
            }
        }
        return latest
    }
    static GetNextIssueDirName(issueRootPath) {
        latest := 0
        Loop Files, issueRootPath "\*", "D" {
            dirName := A_LoopFileName
            if RegExMatch(dirName, DomainConventions.IssueDirPattern) {
                version := dirName + 0
                if (version > latest) {
                    latest := version
                }
            }
        }
        return Format("{:02}", latest + 1)
    }
    ; 改吧执行结果名：有实施文档 → 已实施.md，否则 v(N+1).md
    static ComputeResultName(dirPath) {
        if FileExist(DomainConventions.ImplDocPath(dirPath)) {
            return DomainConventions.ExecutedFile
        }
        return "v" (DomainConventions.GetLatestVersionNumber(dirPath) + 1) ".md"
    }

    ; ==== 约定排序 ====
    ; 文件：需求.txt → vN/对vN 交错升序 → 实施文档.md → 其它（原样保留）
    static SortByConvention(fullPaths) {
        requirementFile := ""
        vMap := Map()
        replyMap := Map()
        implDocFile := ""
        otherFiles := []

        for path in fullPaths {
            name := ExtractFileName(path)
            if (version := DomainConventions.IsVersionFile(name)) {
                vMap[version] := path
            } else if (version := DomainConventions.IsReplyFile(name)) {
                replyMap[version] := path
            } else if DomainConventions.IsRequirementFile(name) {
                requirementFile := path
            } else if DomainConventions.IsImplDocFile(name) {
                implDocFile := path
            } else {
                otherFiles.Push(path)
            }
        }

        allVersions := []
        for ver in vMap {
            allVersions.Push(ver)
        }
        for ver in replyMap {
            if !vMap.Has(ver) {
                allVersions.Push(ver)
            }
        }
        DomainConventions._SortIntegers(allVersions)

        result := []
        if (requirementFile != "") {
            result.Push(requirementFile)
        }
        for ver in allVersions {
            if vMap.Has(ver) {
                result.Push(vMap[ver])
            }
            if replyMap.Has(ver) {
                result.Push(replyMap[ver])
            }
        }
        if (implDocFile != "") {
            result.Push(implDocFile)
        }
        for path in otherFiles {
            result.Push(path)
        }
        return result
    }

    ; 子目录：实施步骤 → 结果微调 → 其它（原样保留）
    static SortSubdirsByConvention(fullPaths) {
        stepsDir := ""
        tweakDir := ""
        otherDirs := []

        for path in fullPaths {
            name := ExtractFileName(path)
            if (name = DomainConventions.StepsDir) {
                stepsDir := path
            } else if (name = DomainConventions.ResultIssueRoot) {
                tweakDir := path
            } else {
                otherDirs.Push(path)
            }
        }

        result := []
        if (stepsDir != "") {
            result.Push(stepsDir)
        }
        if (tweakDir != "") {
            result.Push(tweakDir)
        }
        for path in otherDirs {
            result.Push(path)
        }
        return result
    }

    ; 直接子目录：按约定排序，跳过 .aiprocess（同 GetNextIssueDirName 的路子：读盘 + 按约定挑）
    static GetSubdirsByConvention(dirPath) {
        subdirs := []
        Loop Files, dirPath "\*", "D" {
            if (A_LoopFileName = DomainConventions.DataDir) {
                continue
            }
            subdirs.Push(A_LoopFileFullPath)
        }
        return DomainConventions.SortSubdirsByConvention(subdirs)
    }

    ; 递归遍历：按约定排序，跳过 .aiprocess
    static GetAllFilesRecursive(dirPath) {
        result := []
        files := []
        subdirs := []

        Loop Files, dirPath "\*", "FD" {
            if InStr(A_LoopFileAttrib, "D") {
                subdirs.Push(A_LoopFileFullPath)
            } else {
                files.Push(A_LoopFileFullPath)
            }
        }

        sortedFiles := DomainConventions.SortByConvention(files)
        sortedSubdirs := DomainConventions.SortSubdirsByConvention(subdirs)

        for filePath in sortedFiles {
            result.Push(filePath)
        }
        for dir in sortedSubdirs {
            if (ExtractFileName(dir) = DomainConventions.DataDir) {
                continue
            }
            subResult := DomainConventions.GetAllFilesRecursive(dir)
            for subPath in subResult {
                result.Push(subPath)
            }
        }

        return result
    }

    ; 私有：整数数组排序
    static _SortIntegers(arr) {
        if (arr.Length <= 1) {
            return
        }
        loopCount := arr.Length - 1
        Loop loopCount {
            changed := false
            i := 1
            while (i <= arr.Length - A_Index) {
                if (arr[i] > arr[i + 1]) {
                    tmp := arr[i]
                    arr[i] := arr[i + 1]
                    arr[i + 1] := tmp
                    changed := true
                }
                i += 1
            }
            if !changed {
                break
            }
        }
    }
}
