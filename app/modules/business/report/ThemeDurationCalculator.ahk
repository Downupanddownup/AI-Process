; ThemeDurationCalculator.ahk
; 计算主题从需求创建到最后一个文件创建所经历的时间

CalculateThemeDuration(themePath) {
    startTime := GetRequirementCreationTime(themePath)
    if (startTime = "") {
        return "0.0小时"
    }

    endTime := GetLatestCreationTime(themePath)
    if (endTime = "") {
        endTime := startTime
    }

    hours := CalculateHours(startTime, endTime)
    return FormatDuration(hours)
}

GetRequirementCreationTime(themePath) {
    requirementPath := themePath "\需求.txt"
    if (!FileExist(requirementPath)) {
        return ""
    }
    return FileGetTime(requirementPath, "C")
}

GetLatestCreationTime(themePath) {
    latestTime := ""
    excludePrefix := themePath "\.aiprocess\"

    Loop Files, themePath "\*", "FR" {
        filePath := A_LoopFileFullPath
        if (InStr(filePath, excludePrefix) = 1) {
            continue
        }

        fileTime := A_LoopFileTimeCreated
        if (latestTime = "" || fileTime > latestTime) {
            latestTime := fileTime
        }
    }

    return latestTime
}

CalculateHours(startTime, endTime) {
    if (startTime = "" || endTime = "") {
        return 0.0
    }
    seconds := DateDiff(endTime, startTime, "Seconds")
    if (seconds < 0) {
        seconds := 0
    }
    return seconds / 3600
}

FormatDuration(hours) {
    return Format("{:.1f}", hours) "小时"
}
