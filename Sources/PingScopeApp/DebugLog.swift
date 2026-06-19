import Foundation

enum DebugLog {
    static let fileURL = URL(fileURLWithPath: "/tmp/pingscope-debug.log")
    private static let lock = NSLock()

    nonisolated static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    nonisolated static func clear() {
        lock.lock()
        defer { lock.unlock() }

        try? Data().write(to: fileURL)
    }
}
