import Foundation

struct BoundedFIFOBuffer<Element> {
    private var storage: [Element?]
    private var head = 0
    private(set) var count = 0

    var isEmpty: Bool { count == 0 }

    init(capacity: Int) {
        precondition(capacity > 0, "BoundedFIFOBuffer capacity must be positive")
        storage = Array(repeating: nil, count: capacity)
    }

    var first: Element? {
        guard count > 0 else { return nil }
        return storage[head]
    }

    /// Appends a value, returning the overwritten oldest value when full.
    @discardableResult
    mutating func append(_ element: Element) -> Element? {
        let capacity = storage.count
        if count == capacity {
            let overwritten = storage[head]
            storage[head] = element
            head = (head + 1) % capacity
            return overwritten
        }

        storage[(head + count) % capacity] = element
        count += 1
        return nil
    }

    mutating func popFirst() -> Element? {
        guard count > 0 else { return nil }
        let element = storage[head]
        storage[head] = nil
        head = (head + 1) % storage.count
        count -= 1
        return element
    }

    mutating func popFirst(
        upTo maximumCount: Int,
        while shouldInclude: (Element) -> Bool
    ) -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(min(maximumCount, count))
        while result.count < maximumCount,
              let first,
              shouldInclude(first),
              let element = popFirst() {
            result.append(element)
        }
        return result
    }
}

public enum DebugLog {
    public static let fileURL: URL = {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("PingScope", isDirectory: true)
            .appendingPathComponent("pingscope-debug.log")
    }()
    static let queue = DispatchQueue(label: "com.pingscope.debug-log", qos: .utility)
    private static let stateLock = NSLock()
    private nonisolated(unsafe) static let timestampFormatter = ISO8601DateFormatter()
    private static let maxFileSizeBytes: UInt64 = 2 * 1024 * 1024
    static let pendingWriteCapacity = 2_048
    private static let drainBatchSize = 64
    private static let maxMessageCharacters = 16_384
    private static let rotatedFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("pingscope-debug.1.log")
    private nonisolated(unsafe) static var handle: FileHandle?
    private nonisolated(unsafe) static var currentFileSize: UInt64?
    private nonisolated(unsafe) static var directoryReady = false
    private nonisolated(unsafe) static var pendingWrites = BoundedFIFOBuffer<(sequence: UInt64, message: String)>(capacity: pendingWriteCapacity)
    private nonisolated(unsafe) static var nextWriteSequence: UInt64 = 0
    private nonisolated(unsafe) static var droppedPendingWriteRanges: [DroppedPendingWriteRange] = []
    private nonisolated(unsafe) static var activeClearSequences: [UInt64] = []
    private nonisolated(unsafe) static var drainScheduled = false

    private struct DroppedPendingWriteRange {
        var firstSequence: UInt64
        var lastSequence: UInt64
        var count: Int
    }

    static var pendingWriteCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingWrites.count
    }

    public nonisolated static func write(_ message: String) {
        stateLock.lock()
        nextWriteSequence &+= 1
        let sequence = nextWriteSequence
        if pendingWrites.append((sequence, message)) != nil {
            recordDroppedWrite(at: sequence)
        }
        let shouldSchedule = !drainScheduled
        if shouldSchedule {
            drainScheduled = true
        }
        stateLock.unlock()

        if shouldSchedule {
            scheduleDrain()
        }
    }

    public nonisolated static func flush() async {
        let targetSequence = latestWriteSequence()
        await withCheckedContinuation { continuation in
            queue.async {
                drainPendingWrites(through: targetSequence)
                do {
                    try handle?.synchronize()
                } catch {
                    reportInternalFailure("flush failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    private nonisolated static func latestWriteSequence() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return nextWriteSequence
    }

    private nonisolated static func scheduleDrain() {
        queue.async {
            // Resolve the active clear cutoff while holding the same lock that
            // removes the batch. A clear racing this drain therefore either
            // happens wholly before it (and constrains it) or wholly after it.
            drainOneBatch(through: nil, respectingActiveClear: true)

            stateLock.lock()
            drainScheduled = false
            let shouldContinue = hasPendingWork(through: activeClearSequences.first)
            if shouldContinue {
                drainScheduled = true
            }
            stateLock.unlock()
            if shouldContinue {
                scheduleDrain()
            }
        }
    }

    private nonisolated static func drainPendingWrites(through targetSequence: UInt64) {
        while drainOneBatch(through: targetSequence) {}
    }

    @discardableResult
    private nonisolated static func drainOneBatch(
        through requestedTargetSequence: UInt64?,
        respectingActiveClear: Bool = false
    ) -> Bool {
        stateLock.lock()
        let targetSequence = respectingActiveClear
            ? activeClearSequences.first
            : requestedTargetSequence
        let batch = pendingWrites.popFirst(upTo: drainBatchSize) { entry in
            targetSequence.map { entry.sequence <= $0 } ?? true
        }
        let batchCount = batch.count
        let droppedCount = takeDroppedWriteCount(through: targetSequence)
        stateLock.unlock()

        guard !batch.isEmpty || droppedCount > 0 else { return false }
        writeBatch(batch.map(\.message), droppedCount: droppedCount)
        return batchCount == drainBatchSize
    }

    /// Records overload at the sequence of the write that encountered it. A
    /// post-clear overload can evict an older entry, but its durability record
    /// still belongs to the post-clear epoch and must survive that clear.
    private nonisolated static func recordDroppedWrite(at sequence: UInt64) {
        if let lastIndex = droppedPendingWriteRanges.indices.last,
           droppedPendingWriteRanges[lastIndex].lastSequence &+ 1 == sequence {
            droppedPendingWriteRanges[lastIndex].lastSequence = sequence
            droppedPendingWriteRanges[lastIndex].count += 1
        } else {
            droppedPendingWriteRanges.append(
                DroppedPendingWriteRange(firstSequence: sequence, lastSequence: sequence, count: 1)
            )
        }
    }

    /// Called only while `stateLock` is held.
    private nonisolated static func takeDroppedWriteCount(through targetSequence: UInt64?) -> Int {
        guard let targetSequence else {
            let total = droppedPendingWriteRanges.reduce(0) { $0 + $1.count }
            droppedPendingWriteRanges.removeAll(keepingCapacity: true)
            return total
        }

        var total = 0
        while let first = droppedPendingWriteRanges.first, first.firstSequence <= targetSequence {
            if first.lastSequence <= targetSequence {
                total += first.count
                droppedPendingWriteRanges.removeFirst()
                continue
            }

            let eligibleCount = Int(targetSequence - first.firstSequence + 1)
            total += eligibleCount
            droppedPendingWriteRanges[0].firstSequence = targetSequence + 1
            droppedPendingWriteRanges[0].count -= eligibleCount
            break
        }
        return total
    }

    /// Called only while `stateLock` is held.
    private nonisolated static func hasPendingWork(through targetSequence: UInt64?) -> Bool {
        guard let targetSequence else {
            return !pendingWrites.isEmpty || !droppedPendingWriteRanges.isEmpty
        }
        let hasEligibleWrite = pendingWrites.first.map { $0.sequence <= targetSequence } ?? false
        let hasEligibleDrop = droppedPendingWriteRanges.first.map { $0.firstSequence <= targetSequence } ?? false
        return hasEligibleWrite || hasEligibleDrop
    }

    private nonisolated static func writeBatch(_ messages: [String], droppedCount: Int) {
        var payload = Data()
        if droppedCount > 0 {
            appendLine("dropped \(droppedCount) queued log message(s)", to: &payload)
        }
        for message in messages {
            appendLine(message, to: &payload)
        }
        guard !payload.isEmpty else { return }

        do {
            try ensureDirectory()
            try rotateIfNeeded(incomingByteCount: UInt64(payload.count))
            let output = try fileHandle()
            try output.write(contentsOf: payload)
            currentFileSize = (currentFileSize ?? 0) + UInt64(payload.count)
        } catch {
            reportInternalFailure("write failed: \(error.localizedDescription)")
            try? FileHandle.standardError.write(contentsOf: payload)
        }
    }

    private nonisolated static func appendLine(_ message: String, to payload: inout Data) {
        let timestamp = timestampFormatter.string(from: Date())
        let boundedMessage = message.count > maxMessageCharacters
            ? String(message.prefix(maxMessageCharacters)) + "…"
            : message
        payload.append(contentsOf: "[\(timestamp)] \(boundedMessage)\n".utf8)
    }

    private nonisolated static func ensureDirectory() throws {
        guard !directoryReady else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        directoryReady = true
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

    private nonisolated static func rotateIfNeeded(incomingByteCount: UInt64) throws {
        let fileManager = FileManager.default
        let knownSize = currentFileSize
            ?? ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0)
        guard knownSize + incomingByteCount > maxFileSizeBytes else {
            currentFileSize = knownSize
            return
        }
        do {
            try handle?.close()
            handle = nil
            if fileManager.fileExists(atPath: rotatedFileURL.path) {
                try fileManager.removeItem(at: rotatedFileURL)
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
            }
            currentFileSize = 0
        } catch {
            handle = nil
            currentFileSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? knownSize
            reportInternalFailure("rotation failed: \(error.localizedDescription)")
            throw error
        }
    }

    private nonisolated static func reportInternalFailure(_ message: String) {
        let line = "PingScope debug log \(message)\n"
        if let data = line.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }

    public nonisolated static func redacted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        return "<redacted:\(UInt(bitPattern: value.hashValue))>"
    }

    public nonisolated static func clear() {
        stateLock.lock()
        let targetSequence = nextWriteSequence
        activeClearSequences.append(targetSequence)
        stateLock.unlock()

        queue.async {
            do {
                drainPendingWrites(through: targetSequence)
                try? handle?.close()
                handle = nil
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                directoryReady = true
                try Data().write(to: fileURL)
                try? FileManager.default.removeItem(at: rotatedFileURL)
                currentFileSize = 0
            } catch {
                directoryReady = false
                reportInternalFailure("clear failed: \(error.localizedDescription)")
            }

            stateLock.lock()
            if let clearIndex = activeClearSequences.firstIndex(of: targetSequence) {
                activeClearSequences.remove(at: clearIndex)
            }
            let shouldSchedule = !drainScheduled && hasPendingWork(through: activeClearSequences.first)
            if shouldSchedule {
                drainScheduled = true
            }
            stateLock.unlock()
            if shouldSchedule {
                scheduleDrain()
            }
        }
    }

    public nonisolated static func recentText(maxBytes: Int = 256 * 1024) async -> String {
        await flush()
        return await withCheckedContinuation { continuation in
            queue.async {
                let requestedBytes = max(0, maxBytes)
                guard requestedBytes > 0,
                      let reader = try? FileHandle(forReadingFrom: fileURL) else {
                    continuation.resume(returning: "")
                    return
                }
                defer { try? reader.close() }
                do {
                    let fileSize = try reader.seekToEnd()
                    let startOffset = fileSize > UInt64(requestedBytes)
                        ? fileSize - UInt64(requestedBytes)
                        : 0
                    try reader.seek(toOffset: startOffset)
                    let data = try reader.read(upToCount: requestedBytes) ?? Data()
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } catch {
                    reportInternalFailure("tail read failed: \(error.localizedDescription)")
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
