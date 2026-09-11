# AHK 调试经验

> 这份文档回答一个问题：**改这个项目的代码时，怎么把调试做得安静、可验证、不打断人。**
> 怎么用看 [README](README.md)；目录/版本链/执行规则看 [约定.md](约定.md)；这份工具为什么这样设计看 [工具价值.md](工具价值.md)。本文只讲调试与验证。
>
> 它是**手工维护**的，不是每轮自动生成的经验链（那条已在 `06-删除经验总结生成链` 里删掉——理由：token 贵、难量化、统计已有脚本）。
> 条目骨架固定为 **症状 → 根因 → 做法 → 实测数字**，方便按"症状"搜。
> 全文分两层：**通用原则**（换机器、换项目也成立）／**本机本项目实测**（会变，换环境要重测）。

## 一、第一原则：调试脚本不许弹窗

一次调试弹十几个模态框，不只是烦——**弹窗会把调用方卡死**（实测被挂起到超时两次）。弹窗有三个来源，对策各不相同：

| 来源 | 时机 | 对策 |
|---|---|---|
| 未捕获的**运行期**错误 | 脚本执行中 | `OnError` 兜底：写日志 + 退出 |
| `#Warn` 的告警 | 执行中 | 临时脚本一律写 `#Warn All, Off` |
| **加载期**错误 | 脚本还没开始跑 | `OnError` **拦不住**——语法错、重复声明、类与全局冲突都在此列；只能靠第 4.2 节先自查 |

### 1.1 头三件套（每个临时脚本都带上）

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
OnError(ErrHandler)
ErrHandler(e, mode) {
    FileAppend("ERR line " e.Line " : " e.Message "`n", A_Temp "\ahk_dbg.txt", "UTF-8")
    ExitApp()
}
SetTimer(() => ExitApp(), -10000)   ; 自灭：万一下面卡住，10 秒后自己退出
```

最后那行还有个用处：`#Warn` 的告警弹窗会把进程**挂死**（02 主线那轮踩过），自灭定时器兜得住。

### 1.2 结果写文件，不写屏幕

- 输出一律 `FileAppend(..., A_Temp "\ahk_dbg.txt", "UTF-8")`，之后读文件核对；
- 测试脚本里**不要** `MsgBox`；
- 需要"跑起来按键看"的验证（GUI 手验）**留给人**，别自己按键盘——会打搅正在运行的面板。

### 1.3 想知道"跑到哪了"：正向标记 + 逐文件探针

判"脚本跑完没有"别问退出码（见 3.2），让它自己留证据：

- **正向标记**：脚本最后一行写一个标记文件，出现即"加载并执行到底"；
- **逐文件探针**：`#Include` 之间各插一行日志，哪行没出现，问题就在下一个文件。校验 48 个模块那次，两路都过了（探针最后一行是 `48 HotkeyManager.ahk OK`）。

### 1.4 三条硬纪律

1. **别按镜像名杀进程**：`taskkill /F /IM AutoHotkey64.exe` 会把主面板一起杀掉（02 主线那轮的真实事故）——**只按 PID 精确杀**；
2. **别在项目目录里跑会启动应用的脚本**：`AIProcess.ahk` 有单实例检测，会去激活/干扰正在跑的面板；
3. **临时脚本放 `%TEMP%`**，跑完清理，项目目录里不留调试残渣。

## 二、AHK v2 的坑（本机实测）

### 2.1 多行循环体必须加花括号

```autohotkey
for s in list
    out .= s        ; ← 只有这一行属于循环体
    out .= "`n"      ; ← 这行在循环外执行，读不到循环变量 → 报"变量未赋值"
```

**症状**：报"变量未赋值"，但那个变量看着明明在循环里赋过值。
**教训**：遇到这类报错先怀疑**结构**（花括号），别急着怀疑变量名——我曾据此误判 `base` 是保留名，重测确认 `base`／`full`／`pair` 都能当普通变量。

### 2.2 变量名别撞内建

| 名字 | 撞什么 | 报错 |
|---|---|---|
| `gui` | `Gui` 类 | `This Class cannot be used as an output variable` |
| `log` | 内建数学函数 `Log()` | `This Func cannot be used as an output variable` |

两个都踩过（前者记在 02 主线 v6，后者是本次）。**报错信息不会告诉你是名字的问题**，只能从 "Class/Func" 这两个词认出来。

### 2.3 高 DPI：布局是"逻辑尺寸"，量宽是"物理尺寸"

本机 `A_ScreenDPI=144`（150% 缩放），实测：

| 量 | 值 |
|---|---|
| 控件 `w126` 逻辑宽 | **189** 物理像素 |
| 控件 `w62` 逻辑宽 | **93** 物理像素 |
| `OpenCode` 文字宽 | **82** 物理像素 |

**症状**：明明算得下，却被截了（或反过来溢出）。
**根因**：拿布局的**逻辑宽度**（126）去和 GDI 量出的**物理宽度**（82/98…）比较——两套坐标系差 1.5 倍。语法、行号、算术全对、静态检查一路绿灯，只在 150% 缩放的机器上表现为"名字莫名其妙被截"（02 主线那轮的真 bug）。
**做法**：量宽与可用宽必须**同源**——文字用 `GetTextExtentPoint32W`、可用宽用 `GetClientRect`，都用物理像素。这条已收口在 `app/modules/ui/TextFit.ahk`。

### 2.4 只能按像素量宽，不能按字数

同一个 8pt 字体（`Microsoft YaHei UI`，本机实测，物理像素）：

| 字符 | 宽 | 说明 |
|---|---|---|
| `i` | 4px | 最窄 |
| `m` | 15px | 最宽，是 `i` 的 **3.75 倍** |
| 汉字 | 16px | 与 `W` 相当 |
| `OpenCode`（8 个半角） | 82px | |
| `Claude Code`（11 个字符） | 98px | 比上面宽 20% |

**做法**：任何"装不装得下"的判断都按像素量（`MeasureTextWidth`），别用"几个字"的预算——中英混排按字数算必然一头错。

### 2.5 编码与行尾：逐文件核对，别套全局规则

- **`.ahk` 行尾在本项目并不统一**：`MainWindow.ahk`／`DirectoryManager.ahk`／`AIProcess.ahk`／`DomainConventions.ahk`／`DataFileUtils.ahk` 是 **CRLF**；`StyleManager.ahk` 这类是 **LF**。改哪个文件就按**那个文件改动前**的行尾；
- **编辑工具可能悄悄改行尾**：改完两个 CRLF 文件后 git 立刻报 `LF will be replaced by CRLF`，一查是被改成 LF 了 → 逐文件核对 `CR 字节数 == LF 字节数 == 行数`，并确认首三字节不是 BOM；
- **新建文件跟"血缘最近"的那个**：`ui/TextFit.ahk` 从 `MainWindow.ahk` 抽出来，就跟着它用 CRLF + UTF-8 无 BOM；
- **PowerShell 侧的坑**：临时 `.ps1` 里含中文时，必须存成 **UTF-8 带 BOM**——否则 PowerShell 5.1 按 ANSI 读，中文全变乱码、脚本直接语法错（本次实测踩到，加 BOM 即好）；
- **`settings.ini` 是 UTF-16LE**：别手改，走 `SafeIniWrite` 一类封装。

### 2.6 `#Include`：抄启动器的顺序，自己补启动器全局量

自己拼一份"全模块校验"脚本时：

- **顺序照抄 `AIProcess.ahk`**。别按目录递归排——例如 `AgentActions.ahk:35` 的 `global CopyExecute` 必须排在 `actions/CopyExecute.ahk:7` 的类声明**之后**；顺序反了会报"类声明与已有全局冲突"，看着像项目 bug，其实是自己排错了；
- **自己补启动器全局量**：`AppRoot`／`ConfigDir`／`TemplateDir`／`ModulesDir`／`DataDir`／`LibDir`。`ConfigManager.ahk:6`、`FileToolManager.ahk:10` 在**加载期**就用 `ConfigDir` 拼路径，少一个脚本会在中途静默停住（"没输出也没标记"，极易误判成项目坏了）。

## 三、验证方法论

### 3.1 两类验证分开做

| 类 | 验什么 | 怎么做 |
|---|---|---|
| 语法／加载 | 能不能加载、有没有引用残留 | 整树校验（4.2）+ `grep` 残留 |
| 行为 | 逻辑对不对 | 真机实跑（量宽／拼装），对基线逐值比对 |

### 3.2 退出码与 `/ErrorStdOut` 在本机都不可靠

| 试法 | 结果 |
|---|---|
| 好脚本 `ExitApp()` 直接调 `AutoHotkey64.exe` | 退出码 **2** |
| 语法错脚本 | 退出码 **2**（分不出来） |
| `/ErrorStdOut` + 语法错脚本 | stdout **0 字节** |
| 对照：`FileAppend("*")` 的 stdout 重定向 | 正常收到输出（说明重定向本身是通的） |
| 经 `cmd.exe /c` 包一层 | 也没给出可信信号 |

**结论**：判成败用**正向标记**（1.3／4.2），别用退出码。`03-质检码` 那轮也记过同样一笔。

### 3.3 用真实数据验，不造假数据

- 量宽就用**真实控件几何 + 真实字体 + 真实 DPI**（起一个同字体同宽高的临时 Gui，**不 Show 也能量**）；
- 拼装规则就用**真实目录**当输入（直接拿 `需求/.../结果微调/02` 这类真路径跑）；
- 回归就对**既有基线逐值比对**（本次 Agent 槽位 7 个值全对：`Claude Code` → `Clau...Code` 86px、`Kimi Code - 需求.txt` → `Kimi ...求.txt` 90px 等）。

### 3.4 边界四件套

每次都给这几个输入跑一遍：**空串／句柄为 0／退化输入（如裸盘符 `D:`）／超长**。

### 3.5 报告里写清"验了哪些、没验哪些"

- GUI 手验这类会打搅人的，明确写"留给人"并说明原因；
- 别把"静态检查通过"写成"验证通过"——量宽那个 bug 正是"静态全绿、实跑才露"。

### 3.6 量出来的和"看出来的"可能不是一回事

曾收到反馈"标签和按钮没左对齐，差几个像素"。逐像素量完：两者在**同一列**（都是 `MarginX` = 8 逻辑像素），可见差异 ≤1 物理像素，来自**字形左侧边距 + 按钮边框内缩**。结论是"不改"——加 -1 逻辑像素的补偿反而会随字体／缩放跑偏。
**做法**：视觉差**先量再改**；量完可能发现它根本不是布局问题。

## 四、可直接抄的两段骨架

### 4.1 临时调试脚本

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
OnError(ErrHandler)
ErrHandler(e, mode) {
    FileAppend("ERR line " e.Line " : " e.Message "`n", A_Temp "\ahk_dbg.txt", "UTF-8")
    ExitApp()
}
SetTimer(() => ExitApp(), -10000)

; 要调项目里的函数就按绝对路径 include —— 只读，不改项目文件
#Include D:\PersonWorkSpace\AI-Process\app\modules\ui\TextFit.ahk

probeGui := Gui("+ToolWindow -AlwaysOnTop", "probe")
probeGui.SetFont("s8", "Microsoft YaHei UI")
lbl := probeGui.AddText("xm ym w126 h18", "x")   ; 不 Show 也能量
h := lbl.Hwnd

out := ""
for s in ["i", "m", "中", "OpenCode"] {
    out .= MeasureTextWidth(s, h) "px  " s "`n"
}
FileAppend(out, A_Temp "\ahk_dbg.txt", "UTF-8")
ExitApp()
```

### 4.2 整树校验（探针 + 标记）

先用 PowerShell 生成校验脚本（顺序抄启动器、补全局量、每步写日志）：

```powershell
$app  = 'D:\PersonWorkSpace\AI-Process\app'
$log  = 'C:\Users\<你>\AppData\Local\Temp\ahk_validate.txt'
$gen  = 'C:\Users\<你>\AppData\Local\Temp\validate.ahk'
$main = Get-Content -Path (Join-Path $app 'AIProcess.ahk')
$sb   = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('#Requires AutoHotkey v2.0')
[void]$sb.AppendLine('#Warn All, Off')
[void]$sb.AppendLine('global AppRoot := "' + $app + '"')
[void]$sb.AppendLine('global ConfigDir := AppRoot "\config"')
[void]$sb.AppendLine('global TemplateDir := AppRoot "\templates"')
[void]$sb.AppendLine('global ModulesDir := AppRoot "\modules"')
[void]$sb.AppendLine('global DataDir := AppRoot "\data"')
[void]$sb.AppendLine('global LibDir := AppRoot "\lib"')
foreach ($line in $main) {
    if ($line -match '^#Include') {
        $inc = $line -replace '%A_ScriptDir%', $app
        [void]$sb.AppendLine($inc)
        [void]$sb.AppendLine('FileAppend("OK ' + [System.IO.Path]::GetFileName($inc) + '`n", "' + $log + '", "UTF-8")')
    }
}
[void]$sb.AppendLine('FileAppend("PARSED OK`n", "' + $log + '", "UTF-8")')
[void]$sb.AppendLine('ExitApp()')
[System.IO.File]::WriteAllText($gen, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
```

跑 `AutoHotkey64.exe <validate.ahk>`，**然后读日志文件**（不看退出码）：

- 末行是 `PARSED OK` → 整树加载并执行到底；
- 末行是 `OK xx.ahk` → 问题在**下一个**文件；
- 没有任何日志 → 生成脚本自己有问题（多半是全局量没补全）。

## 五、交活前自查清单

- [ ] 整树校验通过（末行 `PARSED OK`）
- [ ] `grep` 确认被搬走／改名的函数没有引用残留
- [ ] 改动文件的**行尾与编码**逐文件核对过（`CR == LF == 行数`、无 BOM）
- [ ] 边界四件套跑过（空串／0 句柄／退化输入／超长）
- [ ] 回归对既有基线逐值比对过
- [ ] 报告里写清"验了哪些、没验哪些"
- [ ] 临时脚本已清走（项目目录不留；`%TEMP%` 里的用完即删）

## 六、案例索引

| 经验 | 出处 |
|---|---|
| 150% 坐标混比的真 bug、`gui` 保留名、`#Warn` 弹窗挂死、误杀进程 | `需求/问题优先级排序/实施步骤/02-解绑旁显示Agent名称/v6.md` |
| 按像素量宽的由来（`i` 与 `m` 差 3.5 倍、字数预算不成立） | 同目录 `v2.md` |
| 量宽函数的层次判断（不进 core、不新建文件） | 同目录 `v3.md` |
| 搬运 + 回归、行尾逐文件核对、include 顺序、语法校验通路 | `…/02-解绑旁显示Agent名称/结果微调/01/已实施.md` |
| 字形侧边距 vs 按钮边框内缩（"看起来没对齐"） | `…/结果微调/02/v2.md` |
| 为什么不搞"自动生成的经验链" | `需求/问题优先级排序/实施步骤/06-删除经验总结生成链/` |
