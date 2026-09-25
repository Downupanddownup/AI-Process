# AHK 调试经验

> 这份文档回答一个问题：**改这个项目的代码时，怎么把调试做得安静、可验证、不打断人。**
> 怎么用看 [README](README.md)；目录/版本链/执行规则看 [约定.md](约定.md)；这份工具为什么这样设计看 [工具价值.md](工具价值.md)。本文只讲调试与验证。
> **范围**：AHK 与 PowerShell 两侧都收——两边产物在同一条链上（`SetMarkdownTimeTag` 写轮次 md 的 front matter、`ComputeThemeStats` 写 `stats.json` / `统计.md`），调试时经常要一起看。
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
| `#Warn` 的告警 | **校验别人的文件时**（项目文件没关 `#Warn`，又引用别处的全局） | 包一层带 `#Warn All, Off` 的**包装脚本**再校验 —— 见 1.5 |
| **加载期**错误 | 脚本还没开始跑 | `OnError` **拦不住**——语法错、重复声明、类与全局冲突都在此列；只能靠第 4.2 节先自查 |
| 加载期错误的一个**静默子类** | 脚本还没开始跑 | `#Include` 路径含 `..` 解析失败等：**既不弹窗也不报错**，只是什么都不做（见 2.6）——验证脚本必须自带错误出口才能发现它 |

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

> ⚠ **错误出口必须和验证结果写进同一个文件**（引子那次实测补的）。头三件套解决的是"别弹窗"，**不解决"失败时你看得见"**：验证逻辑若没有 `try/catch` 出口，脚本一抛错就**静默死掉**——输出文件不生成、stdout 为空、退出码仍是 0，外部看到的与"脚本没跑"完全一样。那次连着三次拿到空结果，全卡在这里。
>
> 做法：验证主体整体包 `try`，**成功与 `catch Error as e` 两条路都把结果写进同一个输出文件**（异常那条至少落 `e.Message` / `e.What` / `e.Extra`），再 `ExitApp(0)`。加完之后第一次运行就把真实原因暴露出来了。

### 1.2 结果写文件，不写屏幕

- 输出一律 `FileAppend(..., A_Temp "\ahk_dbg.txt", "UTF-8")`，之后读文件核对；
- **这条对"验证类"脚本是硬要求，不是风格问题**：stdout 与退出码都不可信（3.2），唯一信号是自己写的文件——成功、异常两条路都必须落到它上面，否则失败与没跑长得一模一样；
- 每次验证前**先删旧输出文件**再跑：留旧文件会把上一次的结论误读成本次结论（引子那次是反着用的——文件迟迟不出现，才判定脚本死在了中途）；
- 测试脚本里**不要** `MsgBox`；
- 需要"跑起来按键看"的验证（GUI 手验）**留给人**，别自己按键盘——会打搅正在运行的面板。

### 1.3 想知道"跑到哪了"：正向标记 + 逐文件探针

判"脚本跑完没有"别问退出码（见 3.2），让它自己留证据：

- **正向标记**：脚本最后一行写一个标记文件，出现即"加载并执行到底"；
- **逐文件探针**：`#Include` 之间各插一行日志，哪行没出现，问题就在下一个文件。校验 48 个模块那次，两路都过了（探针最后一行是 `48 HotkeyManager.ahk OK`）。

### 1.4 三条硬纪律

1. **别按镜像名杀进程**：`taskkill /F /IM AutoHotkey64.exe` 会把主面板一起杀掉（02 主线那轮的真实事故）——**只按 PID 精确杀**。
   ⚠ 枚举时**两种进程名都要查**：启动器是 `AutoHotkey.exe`、实际进程是 `AutoHotkey64.exe`。只查前者会得到 0 个，会误判"没有残留"（跨天BUG 那轮实测）。杀完**核对主面板 PID 仍在**再收工；
2. **别在项目目录里跑会启动应用的脚本**：`AIProcess.ahk` 有单实例检测，会去激活/干扰正在跑的面板；
3. **临时脚本放 `%TEMP%`**，跑完清理，项目目录里不留调试残渣。

### 1.5 校验别人的文件：包一层再校验

项目里的 `.ahk` 多半**没关 `#Warn`**，而它引用的全局（`AppRoot`、`JSON`…）是在别的文件里定义的 → 单文件校验必然报"变量似乎从未赋值"，一次校验弹三个框。

做法：在 `%TEMP%` 生成一个包装脚本（**只读项目文件，不改它**）：

```autohotkey
#Requires AutoHotkey v2.0
#Warn All, Off
#Include D:\PersonWorkSpace\AI-Process\app\modules\business\summary\SummaryWindow.ahk
```

`#Warn All, Off` 是**全局指令，对被 include 的文件同样生效** → 弹窗和噪音一起消失，剩下的输出才是真信号。

判读：输出里若出现 `#Warn` 行，**对着行号看一眼**——警告位置在你没改的行上（如 `JSON` / `AppRoot`），那属于"单文件校验的固有噪音"，不是缺陷。（跨天BUG 那轮：改动落在 39 / 96 / 102 / 330 行，警告在 28 / 181 行，位置不相干。）

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
- **`#Include` 只写绝对路径**。含 `..` 的相对写法会解析失败——`#Include %A_ScriptDir%\..\app\...` 实测直接中止，且**没有任何报错**（脚本静默死掉，输出文件不生成，见 1.2）；
- **自己补启动器全局量**：`AppRoot`／`ConfigDir`／`TemplateDir`／`ModulesDir`／`DataDir`／`LibDir`。`ConfigManager.ahk:6`、`FileToolManager.ahk:10` 在**加载期**就用 `ConfigDir` 拼路径，少一个脚本会在中途静默停住（"没输出也没标记"，极易误判成项目坏了）。

### 2.7 命令行开关被 shell 吃掉（Git Bash / MSYS 路径转换）

**症状**：`AutoHotkey.exe /validate x.ahk` 弹框说 `Script file not found. D:/git/Git/validate` —— 看着像 AHK 的错，其实 **AHK 根本没收到那个开关**。

**根因**：Git Bash（MSYS）会把**以 `/` 开头的参数当路径转换**成 Windows 路径。实测（用一个只回显参数的小脚本探）：

| 调用 | 程序实际收到 |
|---|---|
| `powershell -File args.ps1 /validate`（Git Bash 直接调） | **`D:/git/Git/validate`** |
| `MSYS2_ARG_CONV_EXCL='*' powershell -File args.ps1 /validate` | `/validate`（原样） |

**做法**（任选其一）：

- 开关写**双斜杠**：`//validate`、`//ErrorStdOut`；
- 或加转换豁免：`MSYS2_ARG_CONV_EXCL='*' <命令>`。

**代价**：被转成路径后，AHK 会把它当脚本去找 → **弹一个模态框并挂在那里**，一次排查能攒出三个残留进程（清理见 1.4.1：按 PID，别按镜像名）。

## 三、验证方法论

### 3.1 两类验证分开做

| 类 | 验什么 | 怎么做 |
|---|---|---|
| 语法／加载 | 能不能加载、有没有引用残留 | 整树校验（4.2）+ `grep` 残留 |
| 行为 | 逻辑对不对 | 真机实跑（量宽／拼装），对基线逐值比对 |

### 3.2 退出码不可靠，但有两条可靠通路

**退出码**：实测好文件与坏文件的退出码**都是 0**（更早一轮记的是 2——具体值会变，但"分不出来"这个结论不变）。**别用退出码判成败。**

**通路一：`//validate`（判"语法对不对"）** —— 一条命令给明确判定，配方见 4.3。

> ⚠ 本文早前记过"`/ErrorStdOut` + 语法错脚本 → stdout **0 字节**"，**那是假象**：Git Bash 的路径转换把开关名整个吃掉了（见 2.7），传给 AHK 的是 `D:/git/Git/ErrorStdOut`。写成 `//ErrorStdOut` 之后，**语法错会明确打到 stdout**。

**通路二：正向标记（判"执行到哪了"）** —— 见 1.3 / 4.2。这两条不是重复：语法过了**不代表加载得过**（类冲突、include 顺序、重复声明都在加载期），所以整树校验仍要留着。

> 更早那张证据表里还有两行**没复核过**，先记在这里免得丢：`FileAppend("*")` 的 stdout 重定向正常（说明重定向本身通）／经 `cmd.exe /c` 包一层也没给出可信信号。后者值得复测——`cmd` 下不存在 MSYS 转换，若仍无信号，说明还有别的因素。
>
> **复核（写 PromptElements 引子那次）**：这次不是 MSYS——`& $exe /ErrorStdOut $script` 由 PowerShell 直调（不拼路径、不转换），**PowerShell 捕获到的 stdout/stderr 都是空**，而脚本其实已经跑到了加载期预检查（`#Warn` 以"变量似乎从未赋值：global AppConfig"独立浮出来，指向 `OpenMd`）。同一脚本改为"结果一律 `FileOpen` 写 UTF-8 文件"后，立刻读到 `MATCH|1`。所以**空 stdout 不能判"没跑"**；`Start-Process -Wait -PassThru` 那次给的 `exit code: 0` 同样不能判"跑成功"。结论并入 1.2：信号只认自己写的文件。

`03-质检码` 那轮也记过同样一笔。

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

### 3.7 生成产物回归：一条命令做"快照 / 对照"

`test\Verify-Output.ps1`（tracked 工具）：**同一批输入跑两遍、比对产物差异**。改前存快照、改完对照，两次之间只差你改的那部分。

```powershell
# 改动前存基线
powershell -File test\Verify-Output.ps1 -Case Stats -Snapshot before
# 改完对照：无差异会明确打印；有差异列出变动行并返回退出码 1
powershell -File test\Verify-Output.ps1 -Case Stats -Compare before
```

- 预设：`-Case Stats`（`ComputeThemeStats` → `stats.json` / `统计.md`）、`-Case Tag`（`SetMarkdownTimeTag` → 轮次 md）；也可 `-Script` / `-Inputs` / `-Artifacts` 自由指定。
- 语料：默认**代表集**（覆盖"重建轮／质检轮／执行轮／老日志缺 agent"各一支 + 最近的几个），并**自动排除活动主题**（它的日志正在被写，输入天然漂移）；`-Full` 跑全量。
- **三处易变内容必须先抹掉**（工具已内置）：`stats.json` 的 `computedAt` 与 `theme.path`（绝对路径，JSON 里是 `\\`）、`统计.md` 的"计算时间"整行。抹掉后同一输入跑两遍 **0 差异**。
- 四条铁律：**副本上跑**（生成脚本原地写产物）／**子进程调用**（脚本里有 `exit`）／**先删副本里的旧产物**（否则旧文件会被误当本次产出；Tag 例外——md 是原地改写，删了就没得打标）／**输入指纹入清单**（输入本身变了会明确警告）。
- 实测数字：代表集 7 个主题，Stats 约 **6 秒**、Tag 约 **17 秒**；`-Full` 全量 **186 输入 / 372 产物 / 159 秒**；快照落在 `%TEMP%\AIProcess-VerifyOutput\<标签>`。
- ⚠ **全量重算的范围要卡死：只跑"有统计产物的主题"**，别扫"所有含 `.aiprocess` 的目录"。后者会给**老世代主题**（`.aiprocess` 里只有 `Summary.md`、没有 `stats.json`）首次生成产物，父级 `aggregate` 跟着把它们计进来——跨天BUG 那轮误发了 **347 个**，靠 3.8 的方法才精确回退。

### 3.8 回退"多出来的产物"：用 CreationTime 区分新建与覆盖

批量重算/批量生成之后要撤销，最难的是**分不清哪些是本次新增、哪些是本次覆盖**——两者的 `LastWriteTime` 都是现在。

**做法**：看 **`CreationTime`**。`[System.IO.File]::WriteAllText` **覆盖**已存在的文件会保留原创建时间，**新建**才有新创建时间。于是"创建时间落在本次运行窗口内"的，就是本次新增的。

实测：478 个 `stats.json` 里，347 个的创建时间集中在重算的 12:33–12:40（8 分钟内），149 个更早 → 一次挑净，连它们的孪生产物（新建的 `统计.md`）一起删。

⚠ **回退后还要重算一遍剩下的**——因为回退前算出的父级 `aggregate` 里已经含了那些（马上就被删掉的）子主题，不复算就不自洽。

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

### 4.3 单文件语法校验（包装 + `//validate`）

比整树校验便宜得多，适合当"语法／加载"这一类里的**第一步**；管不到加载期问题（那仍走 4.2）。

```powershell
# 1) 生成包装脚本（放 %TEMP%，只读项目文件）
$wrap   = Join-Path $env:TEMP 'ahk_syntax_check.ahk'
$target = 'D:\PersonWorkSpace\AI-Process\app\modules\business\summary\SummaryWindow.ahk'
Set-Content -LiteralPath $wrap -Encoding UTF8 -Value @(
    '#Requires AutoHotkey v2.0'
    '#Warn All, Off'
    '#Include ' + $target
)
```

```bash
# 2) 校验：注意**双斜杠**（单斜杠会被 Git Bash 吃成路径，见 2.7）
"C:/Program Files/AutoHotkey/v2/AutoHotkey.exe" //ErrorStdOut //validate "$TEMP/ahk_syntax_check.ahk"
```

判读：**有输出** = 有语法错（例：`(3) : ==> Missing ")"`）；**无输出** = 语法通过。

⚠ **先做对照组**：拿一个故意写错的文件跑一遍，确认这工具真会报错——不然"无输出"什么都证明不了。

## 五、交活前自查清单

- [ ] 单文件语法校验通过（4.3：`//validate` 无输出；若有 `#Warn` 行，对着行号确认是固有噪音）
- [ ] 整树校验通过（末行 `PARSED OK`）
- [ ] 统计/打标这类"生成产物"的改动，跑过 `test\Verify-Output.ps1` 的 Snapshot → Compare（结果无差异）
- [ ] `grep` 确认被搬走／改名的函数没有引用残留
- [ ] 改动文件的**行尾与编码**逐文件核对过（`CR == LF == 行数`、无 BOM）
- [ ] 边界四件套跑过（空串／0 句柄／退化输入／超长）
- [ ] 回归对既有基线逐值比对过
- [ ] 报告里写清"验了哪些、没验哪些"
- [ ] 临时脚本已清走（项目目录不留；`%TEMP%` 里的用完即删）
- [ ] 临时校验/调试**进程**也清了（按 PID 精确杀，两种进程名都枚举；杀完核对主面板仍在）
- [ ] 产物类改动确认过**重算范围**（只跑有产物的主题，见 3.7）

## 六、案例索引

| 经验 | 出处 |
|---|---|
| 150% 坐标混比的真 bug、`gui` 保留名、`#Warn` 弹窗挂死、误杀进程 | `需求/问题优先级排序/实施步骤/02-解绑旁显示Agent名称/v6.md` |
| 按像素量宽的由来（`i` 与 `m` 差 3.5 倍、字数预算不成立） | 同目录 `v2.md` |
| 量宽函数的层次判断（不进 core、不新建文件） | 同目录 `v3.md` |
| 搬运 + 回归、行尾逐文件核对、include 顺序、语法校验通路 | `…/02-解绑旁显示Agent名称/结果微调/01/已实施.md` |
| 字形侧边距 vs 按钮边框内缩（"看起来没对齐"） | `…/结果微调/02/v2.md` |
| 为什么不搞"自动生成的经验链" | `需求/问题优先级排序/实施步骤/06-删除经验总结生成链/` |
| MSYS 吃开关名（`/validate` → `D:/git/Git/validate`）、`//validate` 配方与对照组、校验期 `#Warn` 弹窗、两种进程名、全量重算的范围纪律、`CreationTime` 回退 | `需求/跨天BUG以及重构/已实施.md`、同目录 `结果微调/01/v1.md` |
| 验证脚本"输出为空 + 退出码 0"的三种成因（`Start-Process` 的 ExitCode 不可信、`..` 相对 include、缺错误出口） | `需求/当前的提示词是否在有意引导deepseek忽略质量约束/v4.md` |
