import FunnelCore

func runChromeConnectionChecks() {
    var connection = ChromeConnection()
    expectFalse(connection.begin(userInitiated: false))
    expectTrue(connection.begin(userInitiated: true))
    expectTrue(connection.isConnecting)
    expectFalse(connection.begin(userInitiated: true))
    connection.finish(tabCount: 15, error: nil)
    expectTrue(connection.isConnected)
    expectFalse(connection.isConnecting)
    expectEqual(connection.tabCount, 15)

    // Regression: polling must not alternate the connection button or success badge.
    for _ in 0..<3 {
        expectTrue(connection.begin(userInitiated: false))
        expectTrue(connection.isConnected)
        expectFalse(connection.isConnecting)
        expectEqual(connection.tabCount, 15)
        expectFalse(connection.begin(userInitiated: false))
        connection.finish(tabCount: 15, error: nil)
        expectTrue(connection.isConnected)
        expectFalse(connection.isConnecting)
    }
    expectTrue(connection.begin(userInitiated: false))
    connection.finish(tabCount: 0, error: "自动化权限已撤销")
    expectFalse(connection.isConnected)
    expectFalse(connection.enabled)
    expectFalse(connection.isRefreshing)
    expectEqual(connection.error, "自动化权限已撤销")
    expectFalse(connection.begin(userInitiated: false))
    expectTrue(connection.begin(userInitiated: true))
    connection.finish(tabCount: 16, error: nil)
    expectTrue(connection.isConnected)
    expectEqual(connection.tabCount, 16)
    expectNil(connection.error)
    print("Ran Chrome connection checks: explicit connect, 3 silent polls, error and retry")
}
