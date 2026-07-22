import Foundation
import XCTest
@testable import PingScopeExtensionSupport

final class WidgetSnapshotDataDecodingTests: XCTestCase {
    func testWidgetTargetDecodesValidCustomColorThroughProductionPresentation() throws {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let customColor: [String: Any] = [
            "light": ["red": 0.2, "green": 0.4, "blue": 0.8],
            "dark": ["red": 0.3, "green": 0.5, "blue": 0.9],
        ]

        let snapshot = try decodeSnapshot(hostID: hostID, displayColor: customColor)
        let expected = WidgetGraphDisplayColor(
            light: WidgetGraphRGB(red: 0.2, green: 0.4, blue: 0.8),
            dark: WidgetGraphRGB(red: 0.3, green: 0.5, blue: 0.9)
        )

        XCTAssertEqual(snapshot.hosts.count, 1)
        XCTAssertEqual(snapshot.hosts[0].displayColor?.light.red, 0.2)
        XCTAssertEqual(snapshot.graphPresentation.legend.first?.displayColor, expected)
        XCTAssertEqual(snapshot.graphPresentation.legend.first?.latencyIdentityColor, expected)
    }

    func testWidgetTargetRetainsHostAndFallsBackToAutomaticForMalformedColors() throws {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let validRGB: [String: Any] = ["red": 0.2, "green": 0.4, "blue": 0.8]
        let cases: [(String, Any?)] = [
            ("legacy absent field", nil),
            ("missing channel", [
                "light": ["red": 0.2, "green": 0.4],
                "dark": validRGB,
            ]),
            ("wrong type", [
                "light": ["red": "invalid", "green": 0.4, "blue": 0.8],
                "dark": validRGB,
            ]),
            ("negative component", [
                "light": ["red": -0.1, "green": 0.4, "blue": 0.8],
                "dark": validRGB,
            ]),
            ("component above one", [
                "light": validRGB,
                "dark": ["red": 0.2, "green": 1.1, "blue": 0.8],
            ]),
        ]

        for (name, displayColor) in cases {
            let snapshot: WidgetSnapshotData
            do {
                snapshot = try decodeSnapshot(hostID: hostID, displayColor: displayColor)
            } catch {
                XCTFail("\(name) dropped the complete widget snapshot: \(error)")
                continue
            }
            assertAutomaticFallback(snapshot, hostID: hostID, name: name)
        }
    }

    func testWidgetTargetProductionPresentationRejectsInvalidInMemoryAdaptiveColor() throws {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
        var snapshot = try decodeSnapshot(
            hostID: hostID,
            displayColor: [
                "light": ["red": 0.2, "green": 0.4, "blue": 0.8],
                "dark": ["red": 0.3, "green": 0.5, "blue": 0.9],
            ]
        )
        snapshot.hosts[0].displayColor = WidgetSnapshotData.DisplayColor(
            light: WidgetSnapshotData.RGB(red: .infinity, green: 0.4, blue: 0.8),
            dark: WidgetSnapshotData.RGB(red: 0.2, green: 0.4, blue: 0.8)
        )

        XCTAssertEqual(
            snapshot.graphPresentation.legend.first?.displayColor,
            .automatic(for: hostID)
        )
    }

    func testWidgetTargetTreatsNonFiniteJSONNumberAsAutomaticWhenRepresentable() throws {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!
        let payload = Data("""
        {
          "version":1,
          "primaryHostID":"\(hostID.uuidString)",
          "hosts":[{
            "id":"\(hostID.uuidString)",
            "displayName":"Host",
            "address":"host.example",
            "method":"tcp",
            "isPrimary":true,
            "displayColor":{
              "light":{"red":1e999,"green":0.4,"blue":0.8},
              "dark":{"red":0.2,"green":0.4,"blue":0.8}
            }
          }],
          "health":[],
          "recentSamples":[],
          "networkStatus":"connected",
          "generatedAt":0
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(WidgetSnapshotData.self, from: payload)
        assertAutomaticFallback(snapshot, hostID: hostID, name: "non-finite component")
    }

    private func decodeSnapshot(hostID: UUID, displayColor: Any?) throws -> WidgetSnapshotData {
        var host: [String: Any] = [
            "id": hostID.uuidString,
            "displayName": "Host",
            "address": "host.example",
            "method": "tcp",
            "isPrimary": true,
        ]
        if let displayColor {
            host["displayColor"] = displayColor
        }
        let payload: [String: Any] = [
            "version": 1,
            "primaryHostID": hostID.uuidString,
            "hosts": [host],
            "health": [],
            "recentSamples": [],
            "networkStatus": "connected",
            "generatedAt": 0,
        ]
        return try JSONDecoder().decode(
            WidgetSnapshotData.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private func assertAutomaticFallback(
        _ snapshot: WidgetSnapshotData,
        hostID: UUID,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let automatic = WidgetGraphDisplayColor.automatic(for: hostID)
        XCTAssertEqual(snapshot.hosts.count, 1, name, file: file, line: line)
        XCTAssertEqual(snapshot.hosts.first?.id, hostID, name, file: file, line: line)
        XCTAssertNil(snapshot.hosts.first?.displayColor, name, file: file, line: line)
        XCTAssertEqual(snapshot.graphPresentation.legend.first?.displayColor, automatic, name, file: file, line: line)
        XCTAssertEqual(snapshot.graphPresentation.legend.first?.latencyIdentityColor, automatic, name, file: file, line: line)
    }
}
