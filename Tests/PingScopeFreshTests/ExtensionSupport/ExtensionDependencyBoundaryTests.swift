import Foundation
import XCTest

final class ExtensionDependencyBoundaryTests: XCTestCase {
    func testExtensionTargetsDoNotLinkMonolithicProducts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: root.appendingPathComponent("PingScope.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        for target in ["widgetExtension", "PingScopeLiveActivityExtension"] {
            let targetRange = try XCTUnwrap(project.range(of: "/* \(target) */ = {"))
            let followingTargetRange = project.range(of: "\n\t\t};", range: targetRange.upperBound..<project.endIndex)
            let targetBody = String(project[targetRange.lowerBound..<(followingTargetRange?.lowerBound ?? project.endIndex)])
            XCTAssertFalse(targetBody.contains("PingScopeCore"), "\(target) links PingScopeCore")
            XCTAssertFalse(targetBody.contains("PingScopeiOS"), "\(target) links PingScopeiOS")
        }
    }

    func testLiveActivitySupportTargetDoesNotDependOnMonolithicProducts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let targetStart = try XCTUnwrap(
            manifest.range(of: ".target(\n            name: \"PingScopeLiveActivitySupport\"")
        )
        let targetEnd = try XCTUnwrap(
            manifest.range(of: "\n        ),", range: targetStart.upperBound..<manifest.endIndex)
        )
        let targetBody = String(manifest[targetStart.lowerBound..<targetEnd.upperBound])

        XCTAssertFalse(targetBody.contains("PingScopeCore"), targetBody)
        XCTAssertFalse(targetBody.contains("PingScopeiOS"), targetBody)
        XCTAssertFalse(targetBody.contains("PingScopeHistoryKit"), targetBody)

        let supportDirectory = root.appendingPathComponent("Sources/PingScopeLiveActivitySupport")
        let supportSources = try FileManager.default.contentsOfDirectory(
            at: supportDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        for sourceURL in supportSources {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            XCTAssertFalse(source.contains("import PingScopeCore"), sourceURL.lastPathComponent)
            XCTAssertFalse(source.contains("@_exported import PingScopeCore"), sourceURL.lastPathComponent)
        }
    }
}
