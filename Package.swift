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
        .library(
            name: "PingScopeLiveActivitySupport",
            targets: ["PingScopeLiveActivitySupport"]
        ),
        .library(name: "PingScopeExtensionSupport", targets: ["PingScopeExtensionSupport"]),
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
            name: "PingScopeExtensionSupport",
            path: "Sources/PingScopeExtensionSupport"
        ),
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
            dependencies: ["PingScopeCore", "PingScopeObjCExceptionBoundary"],
            path: "Sources/PingScopeCloudSync"
        ),
        .target(
            name: "PingScopeObjCExceptionBoundary",
            path: "Sources/PingScopeObjCExceptionBoundary",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fobjc-arc-exceptions"])
            ]
        ),
        .target(
            name: "PingScopeHistoryKit",
            dependencies: ["PingScopeCore"],
            path: "Sources/PingScopeHistoryKit"
        ),
        .target(
            name: "PingScopeLiveActivitySupport",
            dependencies: ["PingScopeExtensionSupport"],
            path: "Sources/PingScopeLiveActivitySupport"
        ),
        .target(
            name: "PingScopeiOS",
            dependencies: ["PingScopeCore", "PingScopeHistoryKit", "PingScopeLiveActivitySupport"],
            path: "Sources/PingScopeiOS"
        ),
        .executableTarget(
            name: "PingScope",
            dependencies: ["PingScopeCore", "PingScopeCloudSync", "PingScopeHistoryKit"],
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
            name: "PingScopeCoreTests",
            dependencies: ["PingScopeCore"],
            path: "Tests/PingScopeFreshTests/Core"
        ),
        .testTarget(
            name: "PingScopeHistoryKitTests",
            dependencies: ["PingScopeCore", "PingScopeHistoryKit"],
            path: "Tests/PingScopeFreshTests/History"
        ),
        .testTarget(
            name: "PingScopeCloudSyncTests",
            dependencies: ["PingScopeCore", "PingScopeCloudSync", "PingScopeObjCExceptionBoundary"],
            path: "Tests/PingScopeFreshTests/Cloud"
        ),
        .testTarget(
            name: "PingScopeiOSTests",
            dependencies: ["PingScopeCore", "PingScopeHistoryKit", "PingScopeiOS"],
            path: "Tests/PingScopeFreshTests/iOS"
        ),
        .testTarget(
            name: "PingScopeMacAppTests",
            dependencies: ["PingScopeCore", "PingScopeHistoryKit", "PingScope"],
            path: "Tests/PingScopeFreshTests/MacApp"
        ),
        .testTarget(
            name: "PingScopeExtensionSupportTests",
            dependencies: ["PingScopeCore", "PingScopeExtensionSupport"],
            path: "Tests/PingScopeFreshTests/ExtensionSupport"
        ),
        .testTarget(
            name: "PingScopeBuildGraphTests",
            dependencies: [],
            path: "Tests/PingScopeFreshTests/BuildGraph"
        )
    ]
)
