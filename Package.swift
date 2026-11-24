// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindowFunnel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WindowFunnel", targets: ["WindowFunnel"])],
    targets: [
        .target(name: "FunnelCore"),
        .executableTarget(name: "WindowFunnel", dependencies: ["FunnelCore"]),
        .executableTarget(name: "FunnelCoreChecks", dependencies: ["FunnelCore"], path: "Tests/FunnelCoreTests")
    ]
)
