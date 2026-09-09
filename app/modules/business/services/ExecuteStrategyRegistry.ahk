#Requires AutoHotkey v2.0

; 执行策略注册表：改吧/步目 策略清单与选择
; 命名说明：不叫 ExecuteStrategies，因 PromptManager 已有同名全局变量（并行期冲突，步骤 08 删旧后亦不回收该名，避免歧义）
; 阶段 1 空壳：实现于步骤 02（收编 PromptManager 的 ExecuteStrategies 与三个函数）

class ExecuteStrategyRegistry {
}
