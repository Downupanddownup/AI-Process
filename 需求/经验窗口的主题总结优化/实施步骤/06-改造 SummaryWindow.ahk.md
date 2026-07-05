# 步骤 6：改造 SummaryWindow.ahk

## 目标

让「查看总结」支持 Markdown/JSON fallback，并让列表状态检测同时识别 JSON。

## 修改文件

- `app/modules/business/summary/SummaryWindow.ahk`

## 改造内容

### 6.1 ViewThemeSummary(path)

改为：

```ahk
ViewThemeSummary(themePath) {
    if (themePath = "") {
        MsgBox("当前主题路径为空", "AIProcess", "Iconx")
        return
    }
    if (!DirExist(themePath)) {
        MsgBox("当前主题目录不存在：" themePath, "AIProcess", "Iconx")
        return
    }

    summaryMd := themePath "\.aiprocess\Summary.md"
    summaryJson := themePath "\.aiprocess\Summary.json"

    if (FileExist(summaryMd)) {
        OpenFileInTool(summaryMd)
        return
    }

    if (FileExist(summaryJson)) {
        psScript := AppRoot "\powershell\summary\ConvertSummaryToMarkdown.ps1"
        cmd := 'powershell -ExecutionPolicy Bypass -File "' psScript '" -JsonPath "' summaryJson '"'
        try {
            RunWait(cmd, , "Hide")
        } catch Error as err {
            MsgBox("生成 Markdown 失败：" err.Message, "AIProcess", "Iconx")
            return
        }
        if (FileExist(summaryMd)) {
            OpenFileInTool(summaryMd)
        } else {
            MsgBox("Markdown 生成失败", "AIProcess", "Iconx")
        }
        return
    }

    MsgBox("当前主题尚未生成总结。", "AIProcess", "Iconi")
}
```

### 6.2 RenderThemeList()

把：

```ahk
summaryExists := FileExist(theme.path "\.aiprocess\Summary.md")
```

改为：

```ahk
summaryExists := FileExist(theme.path "\.aiprocess\Summary.md") || FileExist(theme.path "\.aiprocess\Summary.json")
```

## 验收

- 有 `Summary.md` 时直接打开。
- 无 `Summary.md` 但有 `Summary.json` 时，生成 `Summary.md` 后打开。
- 经验总结列表中，已生成 JSON 的主题显示「已总结」。
