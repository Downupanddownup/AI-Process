# Summary 素材说明

## 主题信息

- `themeName` / `themePath`：主题名称和绝对路径。
- `generatedAt`：本次素材生成时间。

## 文件清单

`files` 提供主题下所有需要处理的文件清单，路径均以**主题根目录**为基准的相对路径，方便 AI 直接定位。

结构：

- `humanFiles`：根目录下用户创建的 `.txt` 文件。
- `aiFiles`：根目录下 AI 创建的 `.md` 文件。
- `resultFineTunings`：结果微调子目录下的文件数组，每个元素包含 `name`（子目录名）、`humanFiles`、`aiFiles`。
- `subThemes`：子主题子目录下的文件数组，每个元素包含 `name`（子目录名）、`humanFiles`、`aiFiles`。

每个文件条目包含：

- `path`：从主题根目录开始的相对路径，例如 `结果微调/01/需求.txt`、`实施步骤/01-历史目录/v1.md`。
- `createdAt`：文件创建时间（原始时间戳，格式 `YYYY-MM-DD HH:MM:SS`）。
- `charCount`：文件字符数（含空格和换行）。

## 轮次（rounds）

每个轮次由 `humanFile` 开始、`aiFile` 结束：

- 第 0 轮：`需求.txt` → `v1.md`
- 第 1 轮：`对v1的回复.txt` → `v2.md`
- 以此类推。

每个轮次包含：

- `roundIndex`：轮次编号，从 0 开始。
- `stage`：当前固定为 `"讨论"`，实施确认轮次为 `"实施确认"`。
- `humanFile` / `aiFile`：本轮人输入文件和 AI 输出文件。
- `startTime` / `endTime`：轮次起止时间（原始时间戳）。
- `durationMinutes`：本轮耗时（分钟），向上取整。
- `humanChars` / `aiChars`：人输入和 AI 输出的字符数。
- 如需理解每轮具体内容，请按 `humanFile` / `aiFile` 路径读取原始文件。

## 实施确认轮次

当目录下存在 `实施文档.md` 时，会在 `rounds.items` 末尾追加一个 `category = "实施确认"` 的轮次：

- `humanFile`：目录下编号最大的用户回复文件（例如 `对v4的回复.txt`），代表实施文档前最后一次人输入。
- `aiFile`：`"实施文档.md"`。
- 含义：需求收敛、开始执行的转折点。

## 结果微调（resultFineTunings）

`resultFineTunings` 是结果微调子议题数组，每个元素对应 `结果微调/XX/` 子目录，结构与主主题 `rounds` 一致。

每个结果微调单元内部也可能包含自己的「实施确认」轮次。

## 子主题（subThemes）

`subThemes` 是子主题数组，每个元素对应 `实施步骤/XX/` 子目录，结构与主主题 `rounds` 一致。

每个子主题内部也可能包含自己的「实施确认」轮次。

## 时间与字数统计

- `totalTime`：根目录 + 结果微调 + 子主题所有轮次的活跃总时长。
- `totalHumanChars` / `totalAiChars`：全量人输入和 AI 输出的总字符数。
- `resultFineTunings[i].totalTime`：单个结果微调单元的活跃时长。
- `subThemes[i].totalTime`：单个子主题单元的活跃时长。

## 拆分统计（breakdown）

`breakdown` 拆分了主讨论、结果微调、子主题三部分的贡献：

- `main`：根目录轮次。
- `resultFineTunings`：所有结果微调单元合并。
- `subThemes`：所有子主题单元合并。

每个部分包含：`rounds`（轮次数）、`timeMinutes`（时长）、`humanChars`（人输入字数）、`aiChars`（AI 输出字数）。

---

请基于以上素材，按照 `summary_rules.md` 的规则生成 `Summary.json`。
