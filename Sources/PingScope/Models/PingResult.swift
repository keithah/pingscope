import Foundation

/// Result of a single ping operation
struct PingResult: Sendable, Equatable {
    let host: String
    let port: UInt16
    let timestamp: Date
    let latency: Duration?
    let error: PingError?

    /// Whether the ping succeeded
    var isSuccess: Bool {
        latency != nil && error == nil
    }

    /// Whether the ping timed out
    var isTimeout: Bool {
        error == .timeout
    }

    /// Factory method for successful ping results
    static func success(host: String, port: UInt16, latency: Duration) -> PingResult {
        PingResult(
            host: host,
            port: port,
            timestamp: Date(),
            latency: latency,
            error: nil
        )
    }

    /// Factory method for failed ping results
    static func failure(host: String, port: UInt16, error: PingError) -> PingResult {
        PingResult(
            host: host,
            port: port,
            timestamp: Date(),
            latency: nil,
            error: error
        )
    }
}
