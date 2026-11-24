public struct ChromeConnection {
    public private(set) var enabled = false
    public private(set) var isRefreshing = false
    public private(set) var isConnecting = false
    public private(set) var tabCount: Int?
    public private(set) var error: String?
    public var isConnected: Bool { enabled && tabCount != nil && error == nil }
    public init() {}
    public mutating func begin(userInitiated: Bool) -> Bool {
        guard !isRefreshing, userInitiated || enabled else { return false }
        isRefreshing = true
        // Polling is not a reconnect: keep the existing connection presentation intact.
        isConnecting = userInitiated
        if userInitiated { enabled = true; error = nil }
        return true
    }
    public mutating func finish(tabCount: Int, error: String?) {
        isRefreshing = false
        isConnecting = false
        self.error = error
        enabled = error == nil
        self.tabCount = error == nil ? tabCount : nil
    }
}
