import Foundation
import XCTest

final class BuildGraphOptimizationTests: XCTestCase {
    func testAppStoreSchemeDoesNotBuildDeveloperIDApp() throws {
        let root = try repositoryRoot()
        let scheme = try String(contentsOf: root.appendingPathComponent("PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-AppStore.xcscheme"), encoding: .utf8)
        XCTAssertFalse(scheme.contains("BlueprintName = \"PingScopeApp\""), "App Store scheme should not build the Developer ID app target")
    }

    func testSwiftPMUsesModuleAlignedTestTargets() throws {
        let manifest = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let expectedTargets: [(String, [String], String)] = [
            ("PingScopeCoreTests", ["PingScopeCore"], "Tests/PingScopeFreshTests/Core"),
            ("PingScopeHistoryKitTests", ["PingScopeCore", "PingScopeHistoryKit"], "Tests/PingScopeFreshTests/History"),
            ("PingScopeCloudSyncTests", ["PingScopeCore", "PingScopeCloudSync", "PingScopeObjCExceptionBoundary"], "Tests/PingScopeFreshTests/Cloud"),
            ("PingScopeiOSTests", ["PingScopeCore", "PingScopeHistoryKit", "PingScopeiOS"], "Tests/PingScopeFreshTests/iOS"),
            ("PingScopeMacAppTests", ["PingScopeCore", "PingScopeHistoryKit", "PingScope"], "Tests/PingScopeFreshTests/MacApp"),
            ("PingScopeExtensionSupportTests", ["PingScopeCore", "PingScopeExtensionSupport"], "Tests/PingScopeFreshTests/ExtensionSupport"),
            ("PingScopeBuildGraphTests", [], "Tests/PingScopeFreshTests/BuildGraph")
        ]

        XCTAssertEqual(expectedTargets.count, 7, "Every module-aligned test target must be guarded")

        for (name, dependencies, path) in expectedTargets {
            XCTAssertTrue(manifest.contains("name: \"\(name)\""), "Missing \(name)")
            let dependencyList = dependencies.map { "\"\($0)\"" }.joined(separator: ", ")
            XCTAssertTrue(
                manifest.contains("dependencies: [\(dependencyList)]"),
                "\(name) should declare only [\(dependencyList)]"
            )
            XCTAssertTrue(manifest.contains("path: \"\(path)\""), "\(name) should retain its isolated path")
        }
        XCTAssertFalse(manifest.contains("name: \"PingScopeTests\""), "Monolithic test target remains")
    }

    func testSwiftPMTargetPathsCompileEveryPackageSourceExactlyOnce() throws {
        let root = try repositoryRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let targetPaths = [
            "Sources/PingScopeExtensionSupport",
            "Sources/PingScopeCore",
            "Sources/PingScopeCloudSync",
            "Sources/PingScopeHistoryKit",
            "Sources/PingScopeLiveActivitySupport",
            "Sources/PingScopeiOS",
            "Sources/PingScopeApp",
            "Sources/PingScopeExportValidate",
            "Sources/PingScopeProbeValidate",
        ]

        XCTAssertFalse(manifest.contains("exclude:"), "Implicit target membership should not omit source files")
        XCTAssertFalse(manifest.contains("sources:"), "Implicit target membership should compile each target path recursively")
        for path in targetPaths {
            XCTAssertEqual(manifest.components(separatedBy: "path: \"\(path)\"").count - 1, 1, path)
        }

        let packageSources = try targetPaths.flatMap { path in
            try swiftSources(beneath: root.appendingPathComponent(path), relativeTo: root)
        }
        let allPackageEligibleSources = try swiftSources(
            beneath: root.appendingPathComponent("Sources"),
            relativeTo: root
        ).filter { !$0.hasPrefix("Sources/PingScopeiOSApp/") }

        XCTAssertEqual(packageSources.count, Set(packageSources).count, "A source is covered by more than one target path")
        XCTAssertEqual(Set(packageSources), Set(allPackageEligibleSources), "A SwiftPM source is orphaned or assigned outside its target path")
    }

    func testExtensionTargetsUseMinimalPackageProductsAndFrameworkPhases() throws {
        let project = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let widgetTarget = try targetBlock(named: "widgetExtension", in: project)
        let widgetFrameworks = try buildPhase(named: "Frameworks", for: widgetTarget, in: project)
        XCTAssertTrue(try targetDeclaresPackageProduct("PingScopeExtensionSupport", target: widgetTarget, in: project))
        XCTAssertTrue(try frameworkPhase(widgetFrameworks, linksPackageProduct: "PingScopeExtensionSupport", in: project))

        let liveActivityTarget = try targetBlock(named: "PingScopeLiveActivityExtension", in: project)
        let liveActivityFrameworks = try buildPhase(named: "Frameworks", for: liveActivityTarget, in: project)
        XCTAssertTrue(try targetDeclaresPackageProduct("PingScopeLiveActivitySupport", target: liveActivityTarget, in: project))
        XCTAssertTrue(try frameworkPhase(liveActivityFrameworks, linksPackageProduct: "PingScopeLiveActivitySupport", in: project))

        for productName in ["PingScopeCore", "PingScopeiOS", "PingScopeHistoryKit", "PingScopeCloudSync"] {
            XCTAssertFalse(try targetDeclaresPackageProduct(productName, target: widgetTarget, in: project), "Widget target links monolithic product \(productName)")
            XCTAssertFalse(try frameworkPhase(widgetFrameworks, linksPackageProduct: productName, in: project), "Widget framework phase links monolithic product \(productName)")
            XCTAssertFalse(try targetDeclaresPackageProduct(productName, target: liveActivityTarget, in: project), "Live Activity target links monolithic product \(productName)")
            XCTAssertFalse(try frameworkPhase(liveActivityFrameworks, linksPackageProduct: productName, in: project), "Live Activity framework phase links monolithic product \(productName)")
        }

        XCTAssertTrue(try packageProductBlock(named: "PingScopeExtensionSupport", in: project).contents.contains("isa = XCSwiftPackageProductDependency;"))
        XCTAssertTrue(try packageProductBlock(named: "PingScopeLiveActivitySupport", in: project).contents.contains("isa = XCSwiftPackageProductDependency;"))
        XCTAssertTrue(project.contains("path = PingScopeWidget;"), "Widget synchronized source group is missing")
        XCTAssertTrue(project.contains("path = PingScopeLiveActivity;"), "Live Activity synchronized source group is missing")
    }

    func testIOSAppBuildsAndEmbedsBothExtensionTargets() throws {
        let project = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let iosAppTarget = try targetBlock(named: "PingScopeiOSApp", in: project)
        let embedPhase = try buildPhase(named: "Embed App Extensions", for: iosAppTarget, in: project)

        XCTAssertTrue(try target(iosAppTarget, dependsOn: "PingScopeLiveActivityExtension", in: project), "iOS app must depend on Live Activity")
        XCTAssertTrue(try target(iosAppTarget, dependsOn: "widgetExtension", in: project), "iOS app must depend on Widget")
        XCTAssertTrue(embedPhase.contents.contains("PingScopeLiveActivityExtension.appex in Embed App Extensions"))
        XCTAssertTrue(embedPhase.contents.contains("widgetExtension.appex in Embed App Extensions"))
    }

    func testMacSchemesUseFlavorMatchedTestHosts() throws {
        let root = try repositoryRoot()
        let appStoreScheme = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-AppStore.xcscheme"),
            encoding: .utf8
        )
        let developerScheme = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/xcshareddata/xcschemes/PingScope-DeveloperID.xcscheme"),
            encoding: .utf8
        )
        let project = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertFalse(appStoreScheme.contains("BlueprintName = \"PingScopeTests\""))
        XCTAssertFalse(appStoreScheme.contains("BlueprintName = \"PingScopeUITests\""))
        XCTAssertTrue(developerScheme.contains("BlueprintName = \"PingScopeTests\""))
        XCTAssertTrue(
            developerScheme.contains("buildImplicitDependencies = \"NO\""),
            "The Developer ID test graph must use its explicit PingScopeApp dependency instead of discovering both mac app flavors"
        )
        XCTAssertTrue(project.contains("TEST_TARGET_NAME = PingScopeApp;"))
    }

    func testDeveloperIDReleaseValidatesAndEmbedsProvisioningProfileBeforeSigning() throws {
        let root = try repositoryRoot()
        let releaseScript = try String(
            contentsOf: root.appendingPathComponent("scripts/release-github.sh"),
            encoding: .utf8
        )
        let signingScript = try String(
            contentsOf: root.appendingPathComponent("deploy/sign-notarize.sh"),
            encoding: .utf8
        )
        let profileLibraryURL = root.appendingPathComponent("scripts/lib/developer-id-profile.sh")
        let profileLibrary = try String(contentsOf: profileLibraryURL, encoding: .utf8)

        XCTAssertTrue(releaseScript.contains("--provisioning-profile"))
        XCTAssertTrue(signingScript.contains("--provisioning-profile"))
        XCTAssertTrue(signingScript.contains("validate_developer_id_profile"))
        XCTAssertTrue(signingScript.contains("embed_developer_id_profile"))
        XCTAssertLessThan(
            try XCTUnwrap(signingScript.range(of: "embed_developer_id_profile")?.lowerBound),
            try XCTUnwrap(signingScript.range(of: "codesign_sign_macos_bundle_contents")?.lowerBound),
            "the profile must be embedded before the app signature is created"
        )
        XCTAssertTrue(profileLibrary.contains("com.hadm.PingScope"))
        XCTAssertTrue(profileLibrary.contains("ProvisionsAllDevices"))
        XCTAssertTrue(profileLibrary.contains("ExpirationDate"))
    }

    func testSparkleToolDiscoveryFindsResolvedXcodeArtifactsByDefault() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-sparkle-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let tool = temporaryRoot.appendingPathComponent(
            ".build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
        )
        try FileManager.default.createDirectory(
            at: tool.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "cd \"$2\"; source \"$1\"; find_sparkle_tool generate_keys",
            "pingscope-test",
            try repositoryRoot().appendingPathComponent("scripts/lib/sparkle-tools.sh").path,
            temporaryRoot.path,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let discoveredPath = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        XCTAssertEqual(process.terminationStatus, 0, discoveredPath)
        XCTAssertEqual(discoveredPath, ".build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys")
    }

    func testSoakCPUCheckCalculatesDutyCycleFromPSDurations() throws {
        let script = try repositoryRoot().appendingPathComponent("scripts/soak-cpu-check.sh").path
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "source \"$1\"; cpu_time_to_seconds 01:02:03; elapsed_time_to_seconds 1-02:03:04; duty_cycle_percent 3723 93784",
            "pingscope-test",
            script,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let values = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0, values)
        XCTAssertEqual(values.split(separator: "\n").map(String.init), ["3723.000", "93784.000", "3.970"])
    }

    func testReleaseVersionIsConsistentAcrossAllBuildConfigurations() throws {
        let project = try String(
            contentsOf: try repositoryRoot().appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let marketingVersions = project
            .components(separatedBy: .newlines)
            .filter { $0.contains("MARKETING_VERSION =") }
        let buildVersions = project
            .components(separatedBy: .newlines)
            .filter { $0.contains("CURRENT_PROJECT_VERSION =") }

        XCTAssertFalse(marketingVersions.isEmpty)
        XCTAssertTrue(marketingVersions.allSatisfy { $0.contains("MARKETING_VERSION = 0.5.0;") })
        XCTAssertFalse(buildVersions.isEmpty)
        XCTAssertTrue(buildVersions.allSatisfy { $0.contains("CURRENT_PROJECT_VERSION = 93;") })
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func swiftSources(beneath directory: URL, relativeTo root: URL) throws -> [String] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        return try enumerator.compactMap { element in
            guard let file = element as? URL, file.pathExtension == "swift" else { return nil }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            return String(file.path.dropFirst(root.path.count + 1))
        }.sorted()
    }

    private struct PBXObject {
        let identifier: String
        let contents: String
    }

    private func targetBlock(named name: String, in project: String) throws -> PBXObject {
        try object(in: project) { block in
            block.contents.contains("isa = PBXNativeTarget;") && block.contents.contains("name = \(name);")
        }
    }

    private func packageProductBlock(named name: String, in project: String) throws -> PBXObject {
        try object(in: project) { block in
            block.contents.contains("isa = XCSwiftPackageProductDependency;") && block.contents.contains("productName = \(name);")
        }
    }

    private func buildPhase(named name: String, for target: PBXObject, in project: String) throws -> PBXObject {
        let identifier = try XCTUnwrap(reference(named: name, in: target.contents))
        return try objectBlock(identifier, in: project)
    }

    private func targetDeclaresPackageProduct(_ name: String, target: PBXObject, in project: String) throws -> Bool {
        target.contents.contains(try packageProductBlock(named: name, in: project).identifier)
    }

    private func frameworkPhase(_ phase: PBXObject, linksPackageProduct name: String, in project: String) throws -> Bool {
        let product = try packageProductBlock(named: name, in: project)
        return objectBlocks(in: project).contains { buildFile in
            buildFile.contents.contains("isa = PBXBuildFile;")
                && buildFile.contents.contains("productRef = \(product.identifier)")
                && phase.contents.contains(buildFile.identifier)
        }
    }

    private func target(_ target: PBXObject, dependsOn dependencyName: String, in project: String) throws -> Bool {
        let dependencyTarget = try targetBlock(named: dependencyName, in: project)
        return objectBlocks(in: project).contains { dependency in
            dependency.contents.contains("isa = PBXTargetDependency;")
                && dependency.contents.contains("target = \(dependencyTarget.identifier)")
                && target.contents.contains(dependency.identifier)
        }
    }

    private func reference(named name: String, in block: String) -> String? {
        block.split(separator: "\n").first { $0.contains("/* \(name) */") }?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .first
            .map(String.init)
    }

    private func object(in project: String, where matches: (PBXObject) -> Bool) throws -> PBXObject {
        try XCTUnwrap(objectBlocks(in: project).first(where: matches))
    }

    private func objectBlock(_ identifier: String, in project: String) throws -> PBXObject {
        try object(in: project) { $0.identifier == identifier }
    }

    private func objectBlocks(in project: String) -> [PBXObject] {
        var blocks: [PBXObject] = []
        let lines = project.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        while index < lines.count {
            let line = String(lines[index])
            let identifier = line
                .trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 1)
                .first
                .map(String.init)
            guard let identifier,
                  line.hasPrefix("\t\t"),
                  identifier.count == 24,
                  identifier.allSatisfy(\.isHexDigit) else {
                index += 1
                continue
            }
            var contents = line
            while !contents.trimmingCharacters(in: .whitespaces).hasSuffix("};"), index + 1 < lines.count {
                index += 1
                contents += "\n\(lines[index])"
            }
            blocks.append(PBXObject(identifier: identifier, contents: contents))
            index += 1
        }
        return blocks
    }
}
