#Requires AutoHotkey v2.0

; 一条策略：同一动作的一种固定打法
; 数据源是 Skeleton.Policies 的常量，不读磁盘

class ActionPolicy {

    ; 英文小写，标识符：direct / impl / tweak / steps_dir / defense / tech / single / auto
    Key := ""

    ; 界面与日志原文，与现状一致：实 / 改吧 / 步目 / 答辩 / 技炼；单策略时为空
    Label := ""

    ; 开头段模板文件名（相对 data/skeleton/briefs/）
    Brief := ""

    ; 备用开头段：复关系的第二档（按规模选），其余为空
    BriefAlt := ""

    ; 点完按钮的提示语
    Feedback := ""

    ; 从 Skeleton.Policies 的一条 Map 构造
    static FromMap(m) {
        p := ActionPolicy()
        p.Key := m.Has("key") ? m["key"] : ""
        p.Label := m.Has("label") ? m["label"] : ""
        p.Brief := m.Has("brief") ? m["brief"] : ""
        p.BriefAlt := m.Has("briefAlt") ? m["briefAlt"] : ""
        p.Feedback := m.Has("feedback") ? m["feedback"] : ""
        return p
    }
}
