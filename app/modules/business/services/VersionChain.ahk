#Requires AutoHotkey v2.0

; 版本链领域对象：封装"当前目录的版本链"，行为类不再手拼路径/算版本
; 薄封装 DomainConventions；目标文件不存在时不崩溃，判空归调用方（与现状一致）

class VersionChain {

    __New(dirPath) {
        this.Dir := dirPath
        this.LatestVersion := DomainConventions.GetLatestVersionNumber(dirPath)
    }

    static Of(dirPath) {
        return VersionChain(dirPath)
    }

    RequirementPath() {
        return DomainConventions.RequirementPath(this.Dir)
    }
    VersionPath(n) {
        return DomainConventions.VersionPath(this.Dir, n)
    }
    LatestVersionPath() {
        return DomainConventions.VersionPath(this.Dir, this.LatestVersion)
    }
    NextVersion() {
        return this.LatestVersion + 1
    }
    NextVersionPath() {
        return DomainConventions.VersionPath(this.Dir, this.NextVersion())
    }
    ReplyPath(n) {
        return DomainConventions.ReplyPath(this.Dir, n)
    }
    LatestReplyPath() {
        return DomainConventions.ReplyPath(this.Dir, this.LatestVersion)
    }
    ImplDocPath() {
        return DomainConventions.ImplDocPath(this.Dir)
    }
    HasImplDoc() {
        return FileExist(this.ImplDocPath())
    }
    ExecutedPath() {
        return this.Dir "\" DomainConventions.ExecutedFile
    }
    ResultName() {
        return DomainConventions.ComputeResultName(this.Dir)
    }

    ; 步目依据三档：实施文档 → 最新回复 → 最新版本；全无返回空串
    ; 守卫（判空提示）与占位规则（取值）都调它——同一规则只留这一份实现
    StepsSource() {
        p := this.ImplDocPath()
        if FileExist(p)
            return p
        p := this.LatestReplyPath()
        if FileExist(p)
            return p
        p := this.LatestVersionPath()
        if FileExist(p)
            return p
        return ""
    }
}
