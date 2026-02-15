// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PingScope",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PingScope",
            targets: ["PingScope"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PingScope",
            dependencies: [],
            path: "Sources/PingScope"
        ),
        .testTarget(
            name: "PingScopeTests",
            dependencies: ["PingScope"],
            path: "Tests/PingScopeTests"
        )
    ]
)
