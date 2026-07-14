// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PingScope",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "PingScopeCore",
            targets: ["PingScopeCore"]
        ),
        .library(
            name: "PingScopeCloudSync",
            targets: ["PingScopeCloudSync"]
        ),
        .library(
            name: "PingScopeHistoryKit",
            targets: ["PingScopeHistoryKit"]
        ),
        .library(
            name: "PingScopeiOS",
            targets: ["PingScopeiOS"]
        ),
        .executable(
            name: "PingScopePackage",
            targets: ["PingScope"]
        ),
        .executable(
            name: "PingScopeExportValidate",
            targets: ["PingScopeExportValidate"]
        ),
        .executable(
            name: "PingScopeProbeValidate",
            targets: ["PingScopeProbeValidate"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PingScopeCore",
            dependencies: [],
            path: "Sources/PingScopeCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "PingScopeCloudSync",
            dependencies: ["PingScopeCore"],
            path: "Sources/PingScopeCloudSync"
        ),
        .target(
            name: "PingScopeHistoryKit",
            dependencies: ["PingScopeCore"],
            path: "Sources/PingScopeHistoryKit"
        ),
        .target(
            name: "PingScopeiOS",
            dependencies: ["PingScopeCore", "PingScopeHistoryKit"],
            path: "Sources/PingScopeiOS"
        ),
        .executableTarget(
            name: "PingScope",
            dependencies: ["PingScopeCore", "PingScopeHistoryKit"],
            path: "Sources/PingScopeApp"
        ),
        .executableTarget(
            name: "PingScopeExportValidate",
            dependencies: ["PingScopeCore"],
            path: "Sources/PingScopeExportValidate"
        ),
        .executableTarget(
            name: "PingScopeProbeValidate",
            dependencies: ["PingScopeCore"],
            path: "Sources/PingScopeProbeValidate"
        ),
        .testTarget(
            name: "PingScopeTests",
            dependencies: ["PingScopeCore", "PingScopeCloudSync", "PingScopeHistoryKit", "PingScopeiOS", "PingScope"],
            path: "Tests/PingScopeFreshTests"
        )
    ]
)
