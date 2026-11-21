#Requires AutoHotkey v2.0

; 运行环境：每个窗口一个常驻对象
; 只装"这次运行是谁"——身份创建时定死，主题与流程用属性实时读
; 不装业务计算（版本链、目录扫描由规则直接调内核能力），也不装配置常量（脚本路径由规则直接读 AppConfig）

class Environment {

    ; 哪个窗口：1/2/3。身份，实例创建时定死
    WindowId := ""

    ; 该窗口当前主题目录。实时读：点"设目录"后自然生效，不需要更新点
    TopicDir {
        get {
            if (this._topicOverride != "")
                return this._topicOverride
            return GetSession(this.WindowId, "CurrentDir")
        }
        set => this._topicOverride := value
    }

    ; 当前使用的流程 key。实时读：切流程写 flow.txt 后自然生效
    ; 解析函数由启动处注入（business → promptflow 单向），本类不碰 .aiprocess
    FlowKey {
        get {
            if (this._flowOverride != "")
                return this._flowOverride
            ; 静态字段在类上，不在实例上——属性 getter 里的 this 是实例
            if (Environment._flowKeyProvider = "")
                throw Error("环境未注入流程解析器：启动时应调用 Environment.SetFlowKeyProvider")
            return Environment._flowKeyProvider.Call(this.TopicDir)
        }
        set => this._flowOverride := value
    }

    ; 三份实例：窗口号 → Environment
    static _instances := Map()

    ; 流程解析函数（由 business 注入）
    static _flowKeyProvider := ""

    ; 覆盖值：预览用固定演示主题并显式指派流程，靠它绕开实时读
    _topicOverride := ""
    _flowOverride := ""

    ; 注入流程解析函数：(topicDir) → flowKey
    static SetFlowKeyProvider(fn) {
        this._flowKeyProvider := fn
    }

    ; 启动时建三份
    static InitAll() {
        loop 3
            this._Ensure(A_Index)
    }

    ; 取某窗口那一份；空号回退当前窗口，仍取不到则抛错（不返回半成品环境）
    static Of(windowId := "") {
        id := (windowId = "") ? GetActiveWindowId() : windowId
        if (id = "")
            throw Error("无法确定窗口号，取不到运行环境")
        return this._Ensure(id)
    }

    static _Ensure(id) {
        if (!this._instances.Has(id)) {
            e := Environment()
            e.WindowId := id
            this._instances[id] := e
        }
        return this._instances[id]
    }
}
