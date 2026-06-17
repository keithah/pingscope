// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PingScope",
    platforms: [
        .macOS(.v26),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "PingScopeCore",
            targets: ["PingScopeCore"]
        ),
        .library(
            name: "PingScopeiOS",
            targets: ["PingScopeiOS"]
        ),
        .executable(
            name: "PingScope",
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
            name: "PingScopeiOS",
            dependencies: ["PingScopeCore"],
            path: "Sources/PingScopeiOS"
        ),
        .executableTarget(
            name: "PingScope",
            dependencies: ["PingScopeCore"],
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
            dependencies: ["PingScopeCore", "PingScopeiOS"],
            path: "Tests/PingScopeFreshTests"
        )
    ]
)
