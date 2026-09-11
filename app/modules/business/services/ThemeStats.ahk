#Requires AutoHotkey v2.0

; ThemeStats.ahk
; 主题统计只读服务：读 {主题根}\.aiprocess\stats.json，把原始值转成列表要显示的文本。
; 只读、无副作用、不依赖任何业务模块（调用方知道它，它不知道调用方）。

; ⚠ 显示口径与 PowerShell 侧必须同源，改口径时两边一起改：
;   时长 → app/powershell/time/TimeCalculator.psm1       Format-FriendlyDuration
;   字符 → app/powershell/summary/ComputeThemeStats.ps1  Format-FriendlyCount

; 读统计文件。返回 Map：
;   HasData     是否真正读到（文件不存在 / 解析失败 / 目录缺失 时为 false）
;   其余键      按“键存在且非空”放入；值为 0 是有效值，照常放入
; 只读该主题自身的数据段，不读 aggregate（那是含子主题的汇总）。
LoadThemeStats(themePath) {
    result := Map("HasData", false)

    if (themePath = "") {
        return result
    }

    statsFile := themePath "\.aiprocess\stats.json"
    if (!FileExist(statsFile)) {
        return result
    }

    try {
        data := JSON.Load(FileRead(statsFile, "UTF-8"))
    } catch {
        return result
    }
    if (!IsObject(data)) {
        return result
    }

    result["HasData"] := true

    sections := Map(
        "time", ["activeSec", "humanSec", "aiSec"],
        "rounds", ["discussion", "execute", "rebuild"],
        "files", ["humanChars", "aiChars"])
    for sectionName, keys in sections {
        if (!data.Has(sectionName) || !IsObject(data[sectionName])) {
            continue
        }
        node := data[sectionName]
        for key in keys {
            if (node.Has(key) && node[key] != "") {
                result[key] := node[key] + 0
            }
        }
    }

    return result
}

; 单个时长格
FormatStatDuration(stats, key) {
    if (!stats.Has(key)) {
        return "—"
    }
    return FormatStatDurationSec(stats[key])
}

; 人 / AI 对：任一缺失即整格 —
FormatStatHumanAi(stats) {
    if (!stats.Has("humanSec") || !stats.Has("aiSec")) {
        return "—"
    }
    return FormatStatDurationSec(stats["humanSec"]) " / " FormatStatDurationSec(stats["aiSec"])
}

; 轮次格：rebuild 缺失或为 0 时省略 —— 旧世代主题缺该字段，与新世代显示一致
FormatStatRounds(stats) {
    if (!stats.Has("discussion") || !stats.Has("execute")) {
        return "—"
    }
    text := "讨" stats["discussion"] "·执" stats["execute"]
    if (stats.Has("rebuild") && stats["rebuild"] > 0) {
        text .= "·重" stats["rebuild"]
    }
    return text
}

; 字符格
FormatStatCount(stats, key) {
    if (!stats.Has(key)) {
        return "—"
    }
    return FormatStatCountValue(stats[key]) "字"
}

; ---------- 以下为内部换算（AHK 无私有函数，统一带 Stat 段防与其他模块撞名）----------

; 秒 → 文本：≥1 时 写 "X.X 时"；否则 "N 分"（向下取整，避免出现“60 分”）
; 与 PS 侧 Format-FriendlyDuration 分段阈值一致（其「分」亦为 Floor）
FormatStatDurationSec(sec) {
    sec := Integer(sec)
    if (sec < 3600) {
        return Floor(sec / 60) " 分"
    }
    return Format("{:.1f}", sec / 3600) " 时"
}

; 数值 → 文本：<1万 千分位；<1亿 按万（3 位有效数字）；否则按亿
; 与 PS 侧 Format-FriendlyCount 同规则（AHK 不支持 {:N0}，千分位手写）
FormatStatCountValue(n) {
    n := Integer(n)
    if (n < 10000) {
        return AddStatThousandsSep(n)
    }
    if (n < 100000000) {
        w := n / 10000
        if (w < 10) {
            return Format("{:.2f}", w) "万"
        }
        if (w < 100) {
            return Format("{:.1f}", w) "万"
        }
        return AddStatThousandsSep(Round(w)) "万"
    }
    y := n / 100000000
    if (y < 10) {
        return Format("{:.2f}", y) "亿"
    }
    if (y < 100) {
        return Format("{:.1f}", y) "亿"
    }
    return AddStatThousandsSep(Round(y)) "亿"
}

AddStatThousandsSep(n) {
    s := String(n)
    out := ""
    Loop StrLen(s) {
        out .= SubStr(s, A_Index, 1)
        remaining := StrLen(s) - A_Index
        if (remaining > 0 && Mod(remaining, 3) = 0) {
            out .= ","
        }
    }
    return out
}
