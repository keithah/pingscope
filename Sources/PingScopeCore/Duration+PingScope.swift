import Foundation

public extension Duration {
    var seconds: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    var milliseconds: Double {
        seconds * 1_000
    }
}
