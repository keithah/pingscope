import Foundation
import XCTest

final class CorePlatformImportGuardTests: XCTestCase {
    func testPingScopeCoreAndHistoryKitHaveNoPlatformFrameworkImports() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guardedSourceDirectories = [
            repositoryRoot.appendingPathComponent("Sources/PingScopeCore"),
            repositoryRoot.appendingPathComponent("Sources/PingScopeHistoryKit"),
        ]
        let forbiddenImports = [
            "import CoreLocation",
            "import NetworkExtension",
            "import CoreTelephony",
            "import CoreWLAN",
            "import MapKit",
            "import UIKit",
            "import AppKit",
        ]
        var violations: [String] = []

        for sourceDirectory in guardedSourceDirectories {
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: sourceDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            )
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for (offset, line) in contents.components(separatedBy: .newlines).enumerated() {
                    if forbiddenImports.contains(line.trimmingCharacters(in: .whitespaces)) {
                        violations.append("\(fileURL.lastPathComponent):\(offset + 1): \(line)")
                    }
                }
            }
        }

        XCTAssertEqual(violations, [], violations.joined(separator: "\n"))
    }
}
