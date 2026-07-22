import Foundation
import PingScopeCore

struct PingIntervalOption: Identifiable, Equatable {
    let milliseconds: Int
    let label: String

    var id: Int { milliseconds }
    var duration: Duration { .milliseconds(Double(milliseconds)) }
}

enum PingIntervalPresentation {
    nonisolated static let options: [PingIntervalOption] = [
        .init(milliseconds: 1_000, label: "1s"),
        .init(milliseconds: 2_000, label: "2s"),
        .init(milliseconds: 5_000, label: "5s"),
        .init(milliseconds: 10_000, label: "10s"),
        .init(milliseconds: 30_000, label: "30s")
    ]

    nonisolated static func selection(for interval: Duration) -> Int {
        Int(interval.milliseconds.rounded())
    }

    nonisolated static func commonSelection(for intervals: [Duration]) -> Int? {
        let selections = intervals.map(selection(for:))
        guard let first = selections.first,
              selections.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    nonisolated static func options(including milliseconds: Int) -> [PingIntervalOption] {
        guard !options.contains(where: { $0.milliseconds == milliseconds }) else {
            return options
        }
        return options + [PingIntervalOption(milliseconds: milliseconds, label: label(for: milliseconds))]
    }

    private nonisolated static func label(for milliseconds: Int) -> String {
        if milliseconds % 1_000 == 0 {
            return "\(milliseconds / 1_000)s"
        }
        return "\(milliseconds)ms"
    }
}
