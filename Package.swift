// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PingMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PingMonitor",
            targets: ["PingMonitor"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PingMonitor",
            dependencies: [],
            path: "Sources/PingMonitor"
        ),
        .testTarget(
            name: "PingMonitorTests",
            dependencies: ["PingMonitor"],
            path: "Tests/PingMonitorTests"
        )
    ]
)
