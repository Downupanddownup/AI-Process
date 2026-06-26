#Requires AutoHotkey v2.0

; 日志模块：提供统一的日志入口，日志文件按日期存放在 app\logs\ 目录下

global LOG_LEVEL_DEBUG := 0
global LOG_LEVEL_INFO := 1
global LOG_LEVEL_WARN := 2
global LOG_LEVEL_ERROR := 3

; 当前日志级别，数字越小越详细
global CurrentLogLevel := LOG_LEVEL_DEBUG

LogDebug(message) {
    LogMessage(LOG_LEVEL_DEBUG, "DEBUG", message)
}

LogInfo(message) {
    LogMessage(LOG_LEVEL_INFO, "INFO", message)
}

LogWarn(message) {
    LogMessage(LOG_LEVEL_WARN, "WARN", message)
}

LogError(message) {
    LogMessage(LOG_LEVEL_ERROR, "ERROR", message)
}

LogMessage(level, levelName, message) {
    global AppRoot
    if (level < CurrentLogLevel) {
        return
    }
    try {
        logDir := AppRoot "\logs"
        DirCreate(logDir)
        logFile := logDir "\AIProcess_" FormatTime(, "yyyy-MM-dd") ".log"
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend(timestamp " [" levelName "] " message "`n", logFile, "UTF-8")
    } catch {
        ; 忽略日志写入失败，避免日志系统自身导致崩溃
    }
}
