#Requires AutoHotkey v2.0

class SettleOffflowPrompt extends AgentActionBase {
    ActionKey := "沉淀"
    Type := "ai"
    FailLogText := "沉淀提示词复制失败"
    FailFeedbackText := "沉淀提示词复制失败"

    Execute() {
        chain := VersionChain.Of(GetCurrentDir())
        nextVersionFile := "v" chain.NextVersion() ".md"
        latestReply := chain.LatestReplyPath()
        sourceFile := latestReply != "" && FileExist(latestReply) ? "对v" chain.LatestVersion "的回复.txt" : DomainConventions.RequirementFile

        content := PromptSource.Build("沉淀", "single")
        properties := Map("target", nextVersionFile, "source", sourceFile)
        this.Dispatch(content, properties, "沉淀提示词已复制")
    }
}
