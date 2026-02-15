import Foundation

struct MenuBarState: Sendable, Equatable {
    var displayText: String
    var status: MenuBarStatus
    var lastRawLatencyMS: Double?

    static let initial = MenuBarState(displayText: "N/A", status: .gray, lastRawLatencyMS: nil)
}
