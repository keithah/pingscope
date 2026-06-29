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
    private nonisolated(unsafe) static var handle: FileHandle?
    private nonisolated(unsafe) static var currentFileSize: UInt64?

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
            let output = try fileHandle()
            try output.write(contentsOf: data)
            currentFileSize = (currentFileSize ?? 0) + UInt64(data.count)
        } catch {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }

    private nonisolated static func fileHandle() throws -> FileHandle {
        if let handle {
            return handle
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let opened = try FileHandle(forWritingTo: fileURL)
        _ = try opened.seekToEnd()
        handle = opened
        currentFileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
        return opened
    }

    private nonisolated static func rotateIfNeeded(incomingByteCount: UInt64) {
        let fileManager = FileManager.default
        let knownSize = currentFileSize
            ?? ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0)
        guard knownSize + incomingByteCount > maxFileSizeBytes else {
            currentFileSize = knownSize
            return
        }
        try? handle?.close()
        handle = nil
        try? fileManager.removeItem(at: rotatedFileURL)
        try? fileManager.moveItem(at: fileURL, to: rotatedFileURL)
        currentFileSize = 0
    }

    nonisolated static func redacted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        return "<redacted:\(UInt(bitPattern: value.hashValue))>"
    }

    nonisolated static func clear() {
        queue.async {
            do {
                try? handle?.close()
                handle = nil
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data().write(to: fileURL)
                try? FileManager.default.removeItem(at: rotatedFileURL)
                currentFileSize = 0
            } catch {
                let line = "PingScope debug log clear failed: \(error.localizedDescription)\n"
                if let data = line.data(using: .utf8) {
                    try? FileHandle.standardError.write(contentsOf: data)
                }
            }
        }
    }
}
