/// Errors that can occur during a ping operation
enum PingError: Error, Sendable, Equatable {
    /// Connection timed out
    case timeout
    /// Connection failed with a message
    case connectionFailed(String)
    /// Operation was cancelled
    case cancelled
    /// Host configuration is invalid
    case invalidHost
}
