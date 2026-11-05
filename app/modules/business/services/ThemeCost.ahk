#Requires AutoHotkey v2.0

; ThemeCost.ahk
; 需求成本只读服务：把 history/index 的访问记录与各统计单元的 stats.json 合成"一个需求一行"的成本数据，
; 以及按同一口径展开的成本树。只读、无副作用、不依赖任何界面模块。
;
; 口径（见 约定.md 第一章）：
;   统计单元    = 含 .aiprocess 的目录
;   根统计单元  = 祖先中没有统计单元的统计单元
;   合计 / 自身 = stats.json 的 aggregate / time（含义见 StatsSchema，本文件只读不重算）
; 与 ThemeStats 的区别：ThemeStats 读 time（自身），本文件读 aggregate（含子主题）——两者不可互换。
;
; ⚠ 父子关系与 PS 侧 ThemeAggregation.Get-ChildThemes 同源：每支下探到第一个含 .aiprocess 的目录为止，
;   跳过隐藏目录。改判据时两边一起改（照 ThemeStats 与 TimeCalculator 的"口径同源"写法）。

class ThemeCost {

    ; ==================== 行（列表用） ====================

    ; 全部需求的成本行。只收根统计单元，且必须已有 stats.json（没有统计的不进列表）。
    static LoadRows() {
        rows := []
        visitCount := Map()

        for record in ReadAllIndexRecords() {
            path := record.Has("path") ? record["path"] : ""
            if (path = "") {
                continue
            }
            visitCount[path] := visitCount.Has(path) ? visitCount[path] + 1 : 1
        }

        for path, visits in visitCount {
            if (!DomainConventions.IsRootStatUnit(path)) {
                continue
            }
            data := ThemeCost.ReadStats(path)
            if (!IsObject(data)) {
                continue
            }
            rows.Push(ThemeCost.BuildRow(path, data, visits))
        }

        return rows
    }

    static BuildRow(path, data, visits) {
        createdAt := ThemeCost.GetText(data, "aggregate", "createdAt")
        lastActive := ThemeCost.GetText(data, "aggregate", "lastActiveAt")
        spanDays := ThemeCost.SpanDays(createdAt, lastActive)

        roundD := ThemeCost.GetNum(data, "aggregate", "discussion")
        roundE := ThemeCost.GetNum(data, "aggregate", "execute")
        roundR := ThemeCost.GetNum(data, "aggregate", "rebuild")
        roundU := ThemeCost.GetNum(data, "aggregate", "unknown")

        childCount := 0
        if (data.Has("children") && IsObject(data["children"])) {
            childCount := data["children"].Length
        }

        return Map(
            "path", path,
            "name", ExtractFileName(path),
            "project", ExtractProjectName(path),
            "totalSec", ThemeCost.SectionTotal(data, "aggregate"),
            "humanSec", ThemeCost.GetNum(data, "aggregate", "humanSec"),
            "cognitionSec", ThemeCost.GetNum(data, "aggregate", "humanCognitionSec"),
            "aiSec", ThemeCost.GetNum(data, "aggregate", "aiSec"),
            "roundD", roundD,
            "roundE", roundE,
            "roundR", roundR,
            "roundU", roundU,
            "rounds", roundD + roundE + roundR + roundU,
            "humanChars", ThemeCost.GetNum(data, "aggregate", "humanChars"),
            "aiChars", ThemeCost.GetNum(data, "aggregate", "aiChars"),
            "files", ThemeCost.GetNum(data, "aggregate", "files"),
            "children", childCount,
            "spanDays", spanDays,
            "lastActive", lastActive,
            "visits", visits,
            "computedAt", data.Has("computedAt") ? data["computedAt"] : ""
        )
    }

    ; 排序：不改原数组。数值键按值、文本键按字符串比较。
    static SortRows(rows, key, desc) {
        sorted := rows.Clone()
        count := sorted.Length
        if (count < 2) {
            return sorted
        }
        Loop count - 1 {
            position := A_Index + 1
            item := sorted[position]
            cursor := position - 1
            while (cursor >= 1) {
                if (ThemeCost.CompareRows(sorted[cursor], item, key, desc) <= 0) {
                    break
                }
                sorted[cursor + 1] := sorted[cursor]
                cursor -= 1
            }
            sorted[cursor + 1] := item
        }
        return sorted
    }

    static CompareRows(a, b, key, desc) {
        aValue := a.Has(key) ? a[key] : ""
        bValue := b.Has(key) ? b[key] : ""
        result := 0
        if (aValue Is Number && bValue Is Number) {
            result := (aValue = bValue) ? 0 : (aValue > bValue ? 1 : -1)
        } else {
            result := StrCompare(String(aValue), String(bValue))
        }
        return desc ? -result : result
    }

    ; ==================== 树（弹窗用） ====================

    ; 从根统计单元展开成本树；节点带 自身 / 合计 / 返工 / 按天。
    static BuildTree(rootPath) {
        return ThemeCost.BuildNode(rootPath, 0)
    }

    static BuildNode(dirPath, depth) {
        data := ThemeCost.ReadStats(dirPath)
        if (!IsObject(data)) {
            return ""
        }

        node := Map(
            "path", dirPath,
            "name", ExtractFileName(dirPath),
            "isRework", DomainConventions.IsResultIssueDir(dirPath),
            "self", ThemeCost.SectionTotal(data, "time"),
            "total", ThemeCost.SectionTotal(data, "aggregate"),
            ; 以下时间类指标一律取 aggregate（与「合计」同口径，保证 合计 = 认知 + AI 自洽）；
            ; 仅「自身」取 time，供弹窗单列一行。
            "humanSec", ThemeCost.GetNum(data, "aggregate", "humanSec"),
            "aiSec", ThemeCost.GetNum(data, "aggregate", "aiSec"),
            "cognitionSec", ThemeCost.GetNum(data, "aggregate", "humanCognitionSec"),
            "gapSec", ThemeCost.GetNum(data, "aggregate", "gapTotalSec"),
            "exclHumanSec", ThemeCost.GetNum(data, "aggregate", "humanExcludedSec"),
            "exclAiSec", ThemeCost.GetNum(data, "aggregate", "aiExcludedSec"),
            "exclCount", ThemeCost.GetNum(data, "aggregate", "excludedCount"),
            "humanChars", ThemeCost.GetNum(data, "aggregate", "humanChars"),
            "aiChars", ThemeCost.GetNum(data, "aggregate", "aiChars"),
            "files", ThemeCost.GetNum(data, "aggregate", "files"),
            "humanFiles", ThemeCost.GetNum(data, "aggregate", "humanFiles"),
            "aiFiles", ThemeCost.GetNum(data, "aggregate", "aiFiles"),
            "roundD", ThemeCost.GetNum(data, "aggregate", "discussion"),
            "roundE", ThemeCost.GetNum(data, "aggregate", "execute"),
            "roundR", ThemeCost.GetNum(data, "aggregate", "rebuild"),
            "roundU", ThemeCost.GetNum(data, "aggregate", "unknown"),
            "createdAt", ThemeCost.GetText(data, "aggregate", "createdAt"),
            "lastActiveAt", ThemeCost.GetText(data, "aggregate", "lastActiveAt"),
            "computedAt", data.Has("computedAt") ? data["computedAt"] : "",
            "agents", ThemeCost.GetAgentText(data),
            "visits", 0,
            "reworkSec", 0,
            "children", [],
            "days", ThemeCost.OwnDays(data)
        )

        if (depth < 10) {
            for childPath in ThemeCost.ListChildStatUnits(dirPath, 0) {
                childNode := ThemeCost.BuildNode(childPath, depth + 1)
                if (IsObject(childNode)) {
                    node["children"].Push(childNode)
                    ThemeCost.MergeDays(node["days"], childNode["days"])
                }
            }
        }

        ThemeCost.SortNodesByTotal(node["children"])
        node["reworkSec"] := ThemeCost.SumRework(node)
        return node
    }

    ; 子统计单元：每支下探到第一个含 .aiprocess 的目录为止；跳过隐藏目录（.aiprocess 即隐藏）
    static ListChildStatUnits(dirPath, depth) {
        found := []
        if (depth > 10) {
            return found
        }
        Loop Files, dirPath "\*", "D" {
            if (InStr(A_LoopFileAttrib, "H")) {
                continue
            }
            subPath := A_LoopFileFullPath
            if (DomainConventions.IsStatUnit(subPath)) {
                found.Push(subPath)
            } else {
                for deeper in ThemeCost.ListChildStatUnits(subPath, depth + 1) {
                    found.Push(deeper)
                }
            }
        }
        return found
    }

    ; 返工合计：子树里 结果微调\NN 的合计；遇到返工节点即止（它的合计已含其内部）
    static SumRework(node) {
        if (node["isRework"]) {
            return node["total"]
        }
        total := 0
        for child in node["children"] {
            total += ThemeCost.SumRework(child)
        }
        return total
    }

    static SortNodesByTotal(nodes) {
        count := nodes.Length
        if (count < 2) {
            return
        }
        Loop count - 1 {
            position := A_Index + 1
            item := nodes[position]
            cursor := position - 1
            while (cursor >= 1 && nodes[cursor]["total"] < item["total"]) {
                nodes[cursor + 1] := nodes[cursor]
                cursor -= 1
            }
            nodes[cursor + 1] := item
        }
    }

    ; 该节点自己的按天分布（roundDetail 的 sendTime + totalSec）
    static OwnDays(data) {
        days := Map()
        if (!data.Has("roundDetail") || !IsObject(data["roundDetail"])) {
            return days
        }
        for entry in data["roundDetail"] {
            if (!IsObject(entry) || !entry.Has("sendTime")) {
                continue
            }
            stamp := entry["sendTime"]
            if (stamp = "") {
                continue
            }
            day := SubStr(stamp, 1, 10)
            ; 按天与合计同口径：每轮取「认知 + AI」；旧数据缺这两个字段时退回 totalSec
            seconds := 0
            if (entry.Has("humanCognitionSec") || entry.Has("aiSec")) {
                cognition := entry.Has("humanCognitionSec") ? entry["humanCognitionSec"] + 0 : 0
                ai := entry.Has("aiSec") ? entry["aiSec"] + 0 : 0
                seconds := cognition + ai
            } else if (entry.Has("totalSec")) {
                seconds := entry["totalSec"] + 0
            }
            days[day] := days.Has(day) ? days[day] + seconds : seconds
        }
        return days
    }

    static MergeDays(target, source) {
        for day, seconds in source {
            target[day] := target.Has(day) ? target[day] + seconds : seconds
        }
    }

    ; ==================== 读 stats.json ====================

    static ReadStats(dirPath) {
        statsFile := dirPath "\" DomainConventions.DataDir "\stats.json"
        if (!FileExist(statsFile)) {
            return ""
        }
        try {
            data := JSON.Load(FileRead(statsFile, "UTF-8"))
        } catch {
            return ""
        }
        return IsObject(data) ? data : ""
    }

    static GetNum(data, section, key) {
        if (!IsObject(data) || !data.Has(section)) {
            return 0
        }
        node := data[section]
        if (!IsObject(node) || !node.Has(key)) {
            return 0
        }
        value := node[key]
        if (value = "") {
            return 0
        }
        return value + 0
    }

    static GetText(data, section, key) {
        if (!IsObject(data) || !data.Has(section)) {
            return ""
        }
        node := data[section]
        if (!IsObject(node) || !node.Has(key)) {
            return ""
        }
        value := node[key]
        return value = "" ? "" : String(value)
    }

    static SectionTotal(data, section) {
        return ThemeCost.GetNum(data, section, "humanCognitionSec") + ThemeCost.GetNum(data, section, "aiSec")
    }

    static GetAgentText(data) {
        if (!data.Has("agents") || !IsObject(data["agents"])) {
            return ""
        }
        names := ""
        for agent in data["agents"] {
            name := IsObject(agent) && agent.Has("name") ? agent["name"] : String(agent)
            if (name = "") {
                continue
            }
            names := (names = "") ? name : names " · " name
        }
        return names
    }

    ; "2026-11-02 10:27:32" → 20261102102732（取纯数字）
    static ToAhkTime(text) {
        if (text = "") {
            return ""
        }
        digits := RegExReplace(text, "\D")
        if (StrLen(digits) < 8) {
            return ""
        }
        return digits
    }

    ; 两个 "YYYY-MM-DD HH:mm:ss" 之间的天数；算不出返回 0。
    ; 不依赖 DateDiff（各版本单位名不一致），直接按公历日数算。
    static SpanDays(createdAt, lastActiveAt) {
        startStamp := ThemeCost.ToAhkTime(createdAt)
        endStamp := ThemeCost.ToAhkTime(lastActiveAt)
        if (StrLen(startStamp) < 14 || StrLen(endStamp) < 14) {
            return 0
        }

        startDays := ThemeCost.CivilDays(Integer(SubStr(startStamp, 1, 4)), Integer(SubStr(startStamp, 5, 2)), Integer(SubStr(startStamp, 7, 2)))
        endDays := ThemeCost.CivilDays(Integer(SubStr(endStamp, 1, 4)), Integer(SubStr(endStamp, 5, 2)), Integer(SubStr(endStamp, 7, 2)))

        startSec := Integer(SubStr(startStamp, 9, 2)) * 3600 + Integer(SubStr(startStamp, 11, 2)) * 60 + Integer(SubStr(startStamp, 13, 2))
        endSec := Integer(SubStr(endStamp, 9, 2)) * 3600 + Integer(SubStr(endStamp, 11, 2)) * 60 + Integer(SubStr(endStamp, 13, 2))

        spanSeconds := (endDays - startDays) * 86400 + (endSec - startSec)
        if (spanSeconds < 0) {
            return 0
        }
        return spanSeconds / 86400
    }

    ; 公历日期 → 1970-01-01 起的天数
    static CivilDays(year, month, day) {
        if (month <= 2) {
            year -= 1
        }
        era := Floor(year / 400)
        yearOfEra := year - era * 400
        monthOfYear := month > 2 ? month - 3 : month + 9
        dayOfYear := Floor((153 * monthOfYear + 2) / 5) + day - 1
        dayOfEra := yearOfEra * 365 + Floor(yearOfEra / 4) - Floor(yearOfEra / 100) + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }
}
