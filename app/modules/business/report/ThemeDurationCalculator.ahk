; ThemeDurationCalculator.ahk
; 计算主题活跃工作时长：相邻文件创建时间间隔小于阈值则累计，否则视为中断剔除

; 计算主题时长并格式化为字符串
CalculateThemeDuration(themePath) {
    hours := CalculateThemeActiveHours(themePath)
    return FormatDuration(hours)
}

; 计算主题活跃小时数
CalculateThemeActiveHours(themePath) {
    timePoints := CollectThemeFileTimes(themePath)
    if (timePoints.Length < 2) {
        return 0.0
    }

    thresholdMinutes := GetIdleThresholdMinutes()
    return SumActiveIntervals(timePoints, thresholdMinutes)
}

; 收集主题目录下所有文件创建时间（含需求.txt，排除 .aiprocess）
CollectThemeFileTimes(themePath) {
    times := []

    requirementPath := themePath "\需求.txt"
    if (FileExist(requirementPath)) {
        times.Push(FileGetTime(requirementPath, "C"))
    }

    excludePrefix := themePath "\.aiprocess\"
    Loop Files, themePath "\*", "FR" {
        filePath := A_LoopFileFullPath
        if (InStr(filePath, excludePrefix) = 1) {
            continue
        }
        times.Push(A_LoopFileTimeCreated)
    }

    SortTimePointsAsc(times)
    return times
}

; 对排序后的时间点做活跃间隔累加，返回小时数
SumActiveIntervals(timePoints, thresholdMinutes) {
    totalSeconds := 0
    thresholdSeconds := thresholdMinutes * 60
    n := timePoints.Length

    Loop n - 1 {
        diff := DateDiff(timePoints[A_Index + 1], timePoints[A_Index], "Seconds")
        if (diff > 0 && diff <= thresholdSeconds) {
            totalSeconds += diff
        }
    }

    return totalSeconds / 3600
}

; 升序排序时间数组（简单冒泡，数据量极小）
SortTimePointsAsc(times) {
    n := times.Length
    Loop n - 1 {
        i := 1
        Loop n - A_Index {
            if (times[i] > times[i + 1]) {
                tmp := times[i]
                times[i] := times[i + 1]
                times[i + 1] := tmp
            }
            i += 1
        }
    }
}

; 读取空闲阈值（分钟），默认 60
GetIdleThresholdMinutes() {
    global AppConfig
    if (AppConfig.Has("IdleThresholdMinutes")) {
        return AppConfig["IdleThresholdMinutes"]
    }
    return 60
}

; 格式化小时数为 X.X小时
FormatDuration(hours) {
    return Format("{:.1f}", hours) "小时"
}
