# Summary.json 生成规则

## 一、总体要求

1. 输出必须是合法 JSON，不要包含任何 Markdown 格式或注释。
2. 所有字段必须存在，不允许省略。
3. 如果某类内容不存在（如没有失控轮），对应数组为空 `[]`，但字段必须保留。
4. 生成完成后，必须按「自检规则」逐条检查，确保格式正确、逻辑一致。

## 二、轮次分类（6 类 + 实施确认）

每轮必须且只能属于以下一类：

| 分类 | 判定标准 |
|---|---|
| 正常推进 | AI 输出符合用户预期，用户接受或仅作正向补充，无纠正 |
| 细化完善 | 方向已锁定，用户回答 AI 确认性问题、填充细节、做选择题 |
| 探索发散 | 用户还在思考多个方向，未收敛；AI 提供方案/选项 |
| 纠偏拉回 | AI 漏读、误读、过度设计或实现错误；用户纠正但情绪可控 |
| 极端失控 | 情绪明显升级，或用户明确表达协作裂隙、要求暂停/终止 |
| 确认空转 | 无实质信息增量，仅确认、终止或空回复 |
| 实施确认 | `aiFile` 为 `实施文档.md`，代表需求收敛、开始执行的转折点 |

注意：「实施确认」不是 6 类基础分类之一，而是独立的里程碑节点轮次。

## 三、极端失控判定（内部第二步）

只在已标为「纠偏拉回」的轮次中判断。满足其一即升级为「极端失控」：

1. 出现情绪化、贬损、不耐烦、剥夺协作资格的表达；
2. 同一问题在多轮中无法处理，反复拉扯。

## 四、阶段划分（7 个标准名称）

阶段名称必须从以下集合选择：

| 阶段名称 | 判定规则 |
|---|---|
| 需求探索期 | 用户还在描述问题、提出方向，AI 提供多种方案 |
| 方案讨论期 | 围绕具体方案展开讨论，逐步收敛 |
| 方案细化期 | 方向已确定，用户回答 AI 确认性问题、填充实现细节 |
| 执行实施期 | 进入具体实现，讨论代码/文件/模块修改 |
| 纠偏处理期 | 连续多轮出现纠偏/失控，或为处理同一纠偏问题形成的连续段 |
| 结果微调期 | 功能基本完成后做细节/bug/体验微调 |
| 确认收尾期 | 主题接近尾声，用户确认收尾 |

约束：
- 阶段是对轮次按「沟通主题/目的」的聚合，不要求轮次连续。
- 每个轮次只属于一个阶段。
- 阶段数量根据主题实际情况确定，不需要覆盖所有 7 个名称。

## 五、摘要规则

- `humanSummary`：1~2 句话概括用户本轮核心诉求或反馈。
- `aiSummary`：1~2 句话概括 AI 本轮核心输出。
- `overview.abstract`：用 2~4 句话概括整个主题做了什么、目标是什么、结果如何。

## 六、复杂度与协作顺畅度

- `complexity`：低 / 中 / 高。
  - 低：单一、明确、小范围；无跨模块影响。
  - 中：多个相关功能点，或涉及 2~3 个模块。
  - 高：跨多个模块/系统；涉及新架构、新概念、大量边界条件；或需求模糊、反复澄清。
- `collaboration`：顺利 / 波折 / 失控。
  - 顺利：AI 一次理解；版本少；实施文档与需求一致；极少微调。
  - 波折：AI 理解有轻微偏差，少数纠正后正确；有少量微调。
  - 失控：AI 严重误解，方向反复、大量返工；需求与实施文档明显不匹配；或出现极端失控轮。
- `complexityReason` / `collaborationReason`：必须给出具体理由，不能只写结论。

## 七、全量分析原则

主主题分析必须综合以下三部分：

1. 根目录 `rounds.items`；
2. `resultFineTunings` 中每个结果微调单元的 `rounds.items`；
3. `subThemes` 中每个子主题的 `rounds.items`。

因此：

- `overview.abstract` / `complexity` / `collaboration` 必须基于全量轮次判断；
- `metrics.totalRounds`、`totalTimeMinutes`、`totalHumanChars`、`totalAiChars` 必须按全量合并计算；
- `metrics.byRound` / `byTime` / `byChars` 的分母必须基于全量轮次；
- `analysis.correctionAnalysis` / `extremeAnalysis` 应汇总所有子单元中的纠偏/失控轮次。

## 八、指标计算规则

### 7.1 轮次占比

```
顺畅轮次 = 正常推进 + 细化完善 + 探索发散 + 确认空转
纠偏轮次 = 纠偏拉回 + 极端失控

byRound.intentMatchRate = 顺畅轮次 / 总轮次
byRound.correctionRate = 纠偏轮次 / 总轮次
byRound.extremeRate = 极端失控 / 总轮次
```

### 7.2 时间占比

```
smoothMinutes = 顺畅轮次的 durationMinutes 之和
correctionMinutes = 纠偏轮次的 durationMinutes 之和
extremeMinutes = 极端失控轮次的 durationMinutes 之和

byTime.intentMatchRate = smoothMinutes / totalTimeMinutes
byTime.correctionRate = correctionMinutes / totalTimeMinutes
byTime.extremeRate = extremeMinutes / totalTimeMinutes
```

### 7.3 字数占比

```
smoothHumanChars = 顺畅轮次的人输入字符数之和
correctionHumanChars = 纠偏轮次的人输入字符数之和
extremeHumanChars = 极端失控轮次的人输入字符数之和

byChars.intentMatchRate = smoothHumanChars / totalHumanChars
byChars.correctionRate = correctionHumanChars / totalHumanChars
byChars.extremeRate = extremeHumanChars / totalHumanChars
```

## 九、纠偏 / 失控分析规则

### 8.1 逐轮分析

- `correctionAnalysis.perRound`：每个「纠偏拉回」轮次单独分析。
- `extremeAnalysis.perRound`：每个「极端失控」轮次单独分析。
- 不允许合并多个轮次成一条。

每条分析必须包含：

| 字段 | 说明 |
|---|---|
| `roundIndex` | 对应轮次编号 |
| `category` | 纠偏拉回 / 极端失控 |
| `summary` | 1~2 句话讲清 AI 哪里错了、用户怎么纠正 |
| `rootCause` | 从 {漏读, 误读, 幻觉, 模型惯性, 环境差异, 未读代码} 中选一或自由描述 |
| `impact` | 造成的影响，如浪费轮次、返工、方向摇摆 |
| `lesson` | 必须比 summary 更抽象，能跨主题复用 |

### 8.2 最终汇总

- 必须等 `perRound` 全部列完后再写。
- 汇总里要指出主要模式和最关键的一条经验。
- 不允许汇总覆盖或替代 `perRound` 的细节。

## 十、自检规则

生成 JSON 后，必须检查：

1. JSON 可以正常解析，无语法错误。
2. 所有必填字段存在且非空。
3. `rounds.total` 等于 `rounds.items` 的长度。
4. `rounds.items` 的 `roundIndex` 从 0 开始连续递增。
5. `category` 必须是 6 类之一。
6. `isExtreme` 为 `true` 的轮次，`category` 必须是「纠偏拉回」。
7. `isExtreme` 为 `true` 的轮次，`extremeReason` 不能为空。
8. `metrics.byRound` 各类别数量之和等于 `metrics.totalRounds`。
9. 所有比率字段在 0~1 之间。
10. `byTime` 三项分钟数之和等于 `totalTimeMinutes`（允许 1 分钟误差）。
11. `byChars` 三项字符数之和等于 `totalHumanChars`（允许 1 字符误差）。
12. `correctionAnalysis.perRound` 长度等于「纠偏拉回」轮次数。
13. `extremeAnalysis.perRound` 长度等于「极端失控」轮次数。
14. `rounds.phases` 的 `name` 必须在标准集合中。
15. `rounds.phases` 覆盖的轮次范围不遗漏、不重复。

## 十一、输出要求

将生成的 `Summary.json` 保存到 `{themePath}\.aiprocess\Summary.json`。
