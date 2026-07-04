#Requires AutoHotkey v2.0

; 通用工具函数

NormalizePath(path) {
    path := Trim(path)
    while (SubStr(path, 0) = "\" && StrLen(path) > 3) {
        path := SubStr(path, 1, -1)
    }
    return path
}

PathsEqual(path1, path2) {
    return StrCompare(NormalizePath(path1), NormalizePath(path2), 0) = 0
}

IsPathPrefix(prefix, fullPath) {
    normalizedPrefix := NormalizePath(prefix) "\"
    normalizedFull := NormalizePath(fullPath) "\"
    return InStr(normalizedFull, normalizedPrefix, 0) = 1
}

TruncateMiddle(text, maxLength) {
    if StrLen(text) <= maxLength {
        return text
    }

    leftLength := Floor((maxLength - 3) / 2)
    rightLength := maxLength - 3 - leftLength
    return SubStr(text, 1, leftLength) "..." SubStr(text, -rightLength + 1)
}

ExtractFileName(path) {
    SplitPath(path, &name)
    return name
}

JoinArray(items, separator) {
    result := ""
    for item in items {
        if (result != "") {
            result .= separator
        }
        result .= item
    }
    return result
}
