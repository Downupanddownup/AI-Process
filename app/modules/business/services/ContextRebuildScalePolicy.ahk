#Requires AutoHotkey v2.0

class ContextRebuildScalePolicy {
    static FullReadMaxFileCount := 50
    static FullReadMaxTextBytes := 200 * 1024

    static ShouldUseSkeleton(manifest) {
        return manifest["FileCount"] > this.FullReadMaxFileCount
            || manifest["TextBytes"] > this.FullReadMaxTextBytes
    }
}
