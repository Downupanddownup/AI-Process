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

> ⚠ **运行方式也是三件套的一部分：一律带 `/ErrorStdOut` 并重定向 stderr**（PowerShell 单斜杠；bash 因 MSYS 转换写 `//ErrorStdOut`，见 2.7）。头三件套只管**运行期**错误——`#Include` 找不到、`log` 这类撞名（2.2）都在**加载期**，`OnError` 一行都轮不到，默认就是一个模态框直接怼到人脸上。
> 实测（13-导出那轮，两次）：漏 include 时带 `/ErrorStdOut` → 错误以文本进 stderr、无弹窗；不带 → 弹框并"把程序挂在那儿"。
> 另一个坑：`//validate` 在 PowerShell 里**不是开关**——AHK 会把它当脚本路径，弹 `Script file not found. //validate`。PowerShell 写 `/validate`，bash 才写 `//validate`。

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

### 1.6 生成临时脚本：用写入工具直写，不经过 shell 拼接

**症状**：PowerShell 生成包装脚本，`'#Include ' + $t` 被拆成两行（`#Include` 拿到空参数报错）；换 bash `printf` 写，路径里的 `\A` 被当转义吃掉（`D:\PersonWorkSpace\AI-Process` 变成带响铃字符的怪路径）。

**做法**：

- 内容固定的脚本（单文件包装、断言尾部）一律用**文件写入工具直写**；
- 必须程序化生成时（整树 include 列表这类），**ASCII 生成器与含中文的片段分文件**，由生成器 `Get-Content -Encoding UTF8 -Raw` 拼入——2.5 的 BOM 坑管 ps1 本身，这条管拼出来的 ahk。

实测：拼接两法各失败一次，改直写后一次到位（结果微调 01 那轮）。

### 1.7 批量跑脚本会开窗：调用方没有控制台时，console 子进程必然新建一个窗口

**症状**：验收一个命令行入口，连跑二十几次脚本，屏幕上跟着闪过几十个 cmd 窗——脚本本身没问题，人被打扰。（13-导出一轮，人当场反馈"出现了几十次的 CMD 窗口闪烁"。）

**根因**：`.bat` / `powershell.exe` / `reg.exe` 都是**控制台程序**。子进程是"接管调用方的控制台"还是"自己新建一个"，取决于调用方有没有控制台：

| 调用方 | 子进程 | 结果 |
|---|---|---|
| 有控制台（人在终端里敲） | 继承同一个 | 不闪 |
| 没有控制台（GUI 进程、`CREATE_NO_WINDOW`、被别的工具捕获 stdio） | 系统必须新建 | **闪一个窗口** |

窗口在子进程启动**之前**就由系统建好，所以 `.bat` 里怎么改都藏不住自己——这不是脚本在开窗。

**做法**：

- **批量验收一律加隐藏**：`Start-Process -FilePath x.bat -ArgumentList … -WindowStyle Hidden -Wait`（对应 `STARTUPINFO` 的 `SW_HIDE`，控制台建出来就是隐藏的）；要看结果就写文件，不要指望窗口；
- **要"任何场景都不闪"**：入口换成 GUI 子系统的启动器（`wscript` 跑 `.vbs`、`.lnk`），或直接调 GUI 子系统的程序——`AutoHotkey.exe` 就是（PE 头 `Subsystem=2`）；
- **判断当前 shell 有没有可用控制台**：`GetConsoleWindow()` 非 0 **且** `[Console]::WindowWidth` 读得到，才算有。本机实测 DSH 侧的 pwsh：句柄非 0，但 `WindowWidth` 读不到——属于"没有可用控制台"，所以起 console 程序必然开窗。

**实测数字**：13-导出一轮验收共约 20 次运行 = 20 个窗口；改隐藏式后同一流程跑一次，产物 15,712 字节、退出码 0，与不隐藏**逐字节相同**、无窗口。

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

### 3.9 GUI 行为断言配方：屏幕外窗口 + 模拟点击 + 回读

"点表头会不会排序""禁用有没有生效"这类 GUI 行为问题，不用手点（与 3.5 互补：真机手验留给人，这条管能自动断言的部分）：

```autohotkey
g := Gui("+ToolWindow", "probe")
lv := g.AddListView("w300 h300 -Multi", ["组合", "块"])
lv.Add(, "复需求", "a")
g.Show("x-3000 y-3000")        ; 屏幕外，不打搅运行中的面板

headerHwnd := SendMessage(0x101F, 0, 0, lv.Hwnd)              ; LVM_GETHEADER
PostMessage(0x201, 1, (5 << 16) | 30, , "ahk_id " headerHwnd) ; WM_LBUTTONDOWN
PostMessage(0x202, 0, (5 << 16) | 30, , "ahk_id " headerHwnd) ; WM_LBUTTONUP
Sleep(500)
; 回读 lv.GetText 逐行行序，与点击前比对，结论写文件
```

实测：用它证实了三个结论——AHK ListView 表头有内建排序、`ColClick` 回调拦不住、摘 HDS_BUTTONS 拦得住（见 6.7）。

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
- [ ] 批量验收脚本加了 `-WindowStyle Hidden`（调用方无控制台时 console 子进程会开窗，见 1.7）
- [ ] 临时校验/调试**进程**也清了（按 PID 精确杀，两种进程名都枚举；杀完核对主面板仍在）
- [ ] 产物类改动确认过**重算范围**（只跑有产物的主题，见 3.7）

## 六、库与环境的事实（登记制）

> 本章从 `需求/关于AI Process的结构，通用与特化/基础信息/技术信息.md` 整体迁入——非根目录文档会被清理，知识归根；迁入后新增 6.7、6.8 两条。
> 判据：一条要进来，必须满足"**不知道它就会写错，且错了不容易发现**"。每条写四样——现象、根因、对策、落点，外加"错过的后果"。一次性踩过的操作失误不在此列。

### 6.1 JSON 序列化（`app/lib/JSON.ahk` v2.1.0）

**默认行为**

| # | 默认值 | 现象 | 开关 | 项目现状 |
|---|---|---|---|---|
| 1 | `EscapeUnicode = true` | 中文写成 `\u5199\u4F5C` | 有 | **已在绕**：`ActivityLogger` / `HistoryIndexManager` / `RepositoryManager` 三处在 Dump 前置 `false` |
| 2 | `BoolsAsInts = true` | `true/false` 读成 `1/0`，写出也是 `1/0` | 有 | **没绕**：布尔落到文件里就是数字 |
| 3 | `Dump(obj, 1)` | Tab 缩进、键**按字母序**排 | **没有** | 无解，只能自己写 |

**为什么不能靠开关**：两个开关都是**全局静态**的，一开影响所有读 JSON 的地方。实测 `JSON.BoolsAsInts := false` 之后，读 `builtin/code/flow.json` 得到的 `readonly` 是 `JSON.True` 对象，不再是 `1`；07 校验器里的 `(raw["readonly"] = true)` 立刻判假 → 内置流程被误报 `bad_config`。**结论：为了让文件好看去关开关，会把读侧弄坏。全局开关一律不碰。**

**对策：按"会不会被人改"分流**

| 文件类型 | 例子 | 写法 |
|---|---|---|
| 给人看、会手改的配置 | `flow.json`、`meta.json` | **定向序列化**：固定字段序、两空格、中文原文、`true/false`、UTF-8 无 BOM、末尾一个换行 |
| 纯机器读写 | `log.jsonl`、历史/仓库索引、`stats.json`、`filetools.json` | 默认 `JSON.Dump` 可以；需要中文可读时自行置 `EscapeUnicode := false` |

**落点**：`FlowEditor._DumpFlow()`（首份定向序列化，含写后自检：写 `.tmp` → 读回比对 → 覆盖）。

**错过的后果**：按默认 `Dump` 写配置，功能上还能读回（等价于 0/1），但中文不可读、布尔不合规范、字段顺序随机、diff 全是噪声——每次写入都把可读配置变成库的私有格式，且不报错。

### 6.2 文件编码

| 文件 | 编码 | 约束 |
|---|---|---|
| `config/settings.ini` | UTF-16 LE 带 BOM | 只能走 `SafeIniWrite`，直接 `IniWrite` 会破坏编码 |
| `.aiprocess` 下的文本 | UTF-8 无 BOM | 与既有文本一致 |
| `flow.json` / 其它要写的 JSON | 写入用 `"UTF-8-RAW"` | `"UTF-8"` 会加 BOM（08 踩过：拼装结果开头多 `EF BB BF`） |
| 读任何 UTF-8 文本 | `FileRead(path, "UTF-8")` | 能正确跳过 BOM |

**错过的后果**：BOM 会让"逐字节比对"永远不通过，也会让某些解析器把首字符读成怪字符；`settings.ini` 用错编码会让整份配置读不出来。

### 6.3 Gui 生命周期（owner 销毁会带走子窗口）

**现象**：绑了 `+Owner` 的窗口，**父窗口销毁时会被连带销毁**，且没有任何回调通知它。销毁之后：

| 操作 | 结果 |
|---|---|
| `if (gui)` | **仍为真**（变量里还有对象） |
| `gui.Hwnd` | 抛 `Gui has no window` |
| `gui.Show()` | 抛 `Gui has no window` |
| `gui.Destroy()` | 不抛（无害） |

典型症状：**"关掉再打开就报 Gui has no window"**，且只有"先关掉父窗口、再打开子窗口"这条路径才会出现。

**根因**：AHK 的 `if (gui)` 判的是"变量里有对象"，不是"窗口还活着"。Windows 的 owner 规则是"父销毁 → 子销毁"，AHK 不会替你把变量置空，也不会通知你。

**对策**：判活函数，**凡是"复用已创建过的窗口"之前都问它**：

```autohotkey
FMGuiAlive(g) {
    if !IsObject(g)
        return false
    try {
        return (g.Hwnd != 0)     ; 死了会抛，抛就是没活
    } catch {
        return false
    }
}
```

三处用法，一处都不能省：**复用**（死了先清理再重建，不要直接 `Show()`）；**关闭**（死了就跳过 `Destroy()`，照样把变量置空）；**绑 owner**（owner 自己也可能是死引用，绑之前同样要判活）。

**落点**：`ui/GuiLifecycle.ahk` 的 `GuiAlive(g)`。已接入 `ui/FlowMaintainWindow.ahk`、`business/RepositoryDialog.ahk`。凡"只建一次、之后复用"的窗口都要接，`+Owner` 的窗口优先。

**错过的后果**：这不是"忘了一次置空"——只修"自己关自己"的路径治不了"被父窗口带走"。同类问题已出现三次。**一次踩到，就要按"这一类"排查**。

**附带一条：`MsgBox` 也要绑 `Owner`**——不写 `Owner` 时是独立顶层窗口，会掉到业务窗口后面（表现为"确认框层级低""点了没反应"）。写法：`MsgBox(text, title, "Icon! YesNo Default2 Owner" hwnd)`。同理，**模态等待期间 owner 可能被关掉**：`WinWaitClose` 返回后要重新判一次 `GuiAlive(父窗口)`。

### 6.4 GUI 布局坐标（`x+8` 的语义）

**现象**：控件跑到窗口外、或整块区域右移，窗口看起来"被裁掉"。

**根因**：AHK 的定位选项里，`x+8` 是**上一个控件的右边缘 + 8**，不是"左边 + 8"。同一列里连续写 `x+8`，每往下一层就右移一个控件宽度。

**对策**：

| 意图 | 写法 |
|---|---|
| 标题 → 它下面的控件 | `xp y+2`（与上一个同左边缘） |
| 跨到下一列 | `x+8`（相对上一列的右缘） |
| 与某个绝对位置对齐 | 直接写数字，如 `x88` |
| 同一行内排按钮 | `x+8 yp`（相对上一个按钮的右缘，正确） |

**ComboBox / DropDownList 的 `h` 是"下拉展开高度"**：`AddComboBox("w300 h24")` 里的 `h` 不是控件高度，而是下拉列表展开后的总高度。要看全建议 `h200`；控件本体的可见高度由字体与行高决定，不受这个值影响。

**落点**：`ui/FlowMaintainWindow.ahk`（主窗口三列、新建/改名两个弹窗）、`ui/BlockMaintainWindow.ahk`（分类下拉）。

**错过的后果**：已犯过两次——主窗口三列错位成"四块区域"、新建弹窗单选被推出窗口右缘。**布局验收必须读真实坐标（`GetPos`），不能只看代码。**

### 6.5 ListView 勾选框

**现象**：`lv.Add("Check", …)` 不报错，但界面上**看不到勾选框**；`lv.OnEvent("ItemCheck", …)` 注册报 `Invalid callback function`。

**根因**：① AHK 不会因为 `Check` 选项自动开 `LVS_EX_CHECKBOXES` 扩展样式——样式没开，状态位设了也不显示；② 这个版本（2.0.2）的 ListView **没有 ItemCheck 事件**，勾选变化拿不到回调。

**对策**：

```autohotkey
; 必须先开样式，再添行；顺序反了前面的行会没有勾选框
SendMessage(0x1036, 0x4, 0x4, lv.Hwnd)      ; LVM_SETEXTENDEDLISTVIEWSTYLE, LVS_EX_CHECKBOXES
lv.Add(, …)
lv.Modify(row, "Check")                      ; 勾选 / 取消用 "-Check"
; 读状态：0x102C = LVM_GETITEMSTATE，mask 0x2000 = STATEIMAGEMASK
s := SendMessage(0x102C, row - 1, 0x2000, lv.Hwnd)
checked := ((s >> 12) & 0xF) = 2            ; 实测未勾为 0，已勾为 2
```

**没有变更事件**，"勾选之后怎么生效"必须显式设计：要么轮询，要么给一个显式按钮（本项目选了后者，见 `ui/FlowBlockPicker.ahk` 的「同步到选中区」）。

**错过的后果**：勾选框不显示、或勾了却没反应；靠"看起来有 Check 参数"判断会一路以为功能正常。

### 6.6 块缓存

**现象**：改了块目录里的 `body.txt` / `meta.json`，界面上（选块弹窗、预览、维护窗口）仍是旧内容。

**根因**：`BlockLibrary` 按块目录路径缓存 `PromptBlock`（`_cache`）；`FlowLibrary` 也有流程缓存。直接改文件不会让缓存失效。

**对策**：**写完块必须 `BlockLibrary.ClearCache()`**；写完 `flow.json` 必须 `FlowLibrary.ClearCache()`。两件事分别由 `BlockEditor` 与 `FlowEditor` 自己负责，不指望调用方记得。

**落点**：`promptflow/definition/BlockEditor.ahk`（三个写方法）、`promptflow/definition/FlowEditor.ahk`。

**错过的后果**："改完看不到变化"，人会以为写盘失败，反复保存；排查时又找不到错误——因为读到的确实是缓存里的旧对象。

### 6.7 ListView 表头有内建排序

**现象**：没注册任何排序处理的 ListView，点表头行也会按该列文本重排（实测为拼音序）；按行号索引数据数组的预览/定位随即错位，而代码里**搜不到任何排序逻辑**。

**根因**：AHK v2（本机 2.0.2）ListView 的内建行为。`ColClick` 事件回调返回非零也**拦不住**（实测）——需要排序的列表（费用窗口）正是靠 `ColClick` 自己重排数据。

**对策**：不需要排序的列表，创建后摘掉表头的按钮样式，点击从机制上不产生行为：

```autohotkey
headerHwnd := SendMessage(0x101F, 0, 0, lv.Hwnd)                        ; LVM_GETHEADER
style := DllCall("GetWindowLongPtr", "ptr", headerHwnd, "int", -16, "ptr")   ; GWL_STYLE
DllCall("SetWindowLongPtr", "ptr", headerHwnd, "int", -16, "ptr", style & ~0x2)   ; 去 HDS_BUTTONS(0x0002)
```

**落点**：`ui/StyleManager.ahk` 的 `DisableListHeaderSort(lvCtrl)`；已接入 `ui/FlowMaintainWindow.ahk` 中列（行号映射预览，必须"行序恒等于填充顺序"）。别动公用样式函数——费用窗口的排序靠表头。

**错过的后果**：以为"代码里没写排序就不会排"——行序与数据数组脱钩，选中"复回复"预览显示"复执行"，排查时在全项目搜不到排序代码，无从下手。

### 6.8 Map 枚举是键序，不是书写顺序

**现象**：Map 按 A、B、C 顺序写入，枚举出来却是按键名排。实测：`Skeleton.Layouts` 书写顺序为 复需求→复回复→…→复关系，枚举顺序为 复关系→复回复→…，恰好是键的二进制序。

**根因**：AHK v2 Map 的枚举顺序不保证等于插入顺序（本机实测为键序）。

**对策**：**任何"展示顺序有意义"的枚举都必须有显式顺序表**；枚举只用来取全集。新增条目不登记进顺序表就掉出列表（顺序表方法带"漏登记垫后"兜底）。

**落点**：`promptflow/skeleton/Skeleton.ahk` 的 `ComboDisplayOrder` / `GetOrderedComboKeys()`。

**错过的后果**：界面列表顺序"自己会变"，新增条目出现在不可预期的位置；顺序乱了还会连累行号映射（见 6.7）。

## 七、案例索引

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
| 表头内建排序三连实测（6.7）、Map 键序（6.8）、shell 拼接两坑（1.6）、GUI 行为断言配方（3.9） | `需求/关于AI Process的结构，通用与特化/结果微调/01/`（v4–v15、已实施.md） |
| 第六章「库与环境的事实」整体迁入 | 原 `需求/关于AI Process的结构，通用与特化/基础信息/技术信息.md` |
| 批量跑脚本开窗（1.7）：`-WindowStyle Hidden`、`GetConsoleWindow` 判控制台、`.bat` 藏不住自己的窗口 | `需求/关于AI Process的结构，通用与特化/实施步骤/13-添加流程提示词一键导出/v6.md` |
