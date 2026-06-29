import Foundation

enum DebugLog {
    static let fileURL: URL = {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("PingScope", isDirectory: true)
            .appendingPathComponent("pingscope-debug.log")
    }()
    private static let queue = DispatchQueue(label: "com.pingscope.debug-log", qos: .utility)
    private nonisolated(unsafe) static let timestampFormatter = ISO8601DateFormatter()
    private static let maxFileSizeBytes: UInt64 = 2 * 1024 * 1024
    private static let rotatedFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("pingscope-debug.1.log")

    nonisolated static func write(_ message: String) {
        queue.async {
            writeLine(message)
        }
    }

    nonisolated static func flush() {
        queue.sync {}
    }

    private nonisolated static func writeLine(_ message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            rotateIfNeeded(incomingByteCount: UInt64(data.count))
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL)
            }
        } catch {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }

    private nonisolated static func rotateIfNeeded(incomingByteCount: UInt64) {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let currentSize = attributes[.size] as? UInt64,
              currentSize + incomingByteCount > maxFileSizeBytes else {
            return
        }
        try? fileManager.removeItem(at: rotatedFileURL)
        try? fileManager.moveItem(at: fileURL, to: rotatedFileURL)
    }

    nonisolated static func clear() {
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data().write(to: fileURL)
                try? FileManager.default.removeItem(at: rotatedFileURL)
            } catch {
                let line = "PingScope debug log clear failed: \(error.localizedDescription)\n"
                if let data = line.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
            }
        }
    }
}
