import Foundation

actor HistoryWriteBuffer {
    private let store: any PingHistoryStore
    private let maxBatchSize: Int
    private let flushDelay: Duration
    private let logger: (@Sendable (String) -> Void)?
    private var pending: BoundedBuffer<PingResult>
    private var flushTask: Task<Void, Never>?
    private var isDiscarding = false
    private var generation = 0
    private var consecutiveFailureCount = 0
    private var lastFailureLogAt: Date?

    init(
        store: any PingHistoryStore,
        maxBatchSize: Int = 32,
        maxPendingResults: Int = 2048,
        flushDelay: Duration = .milliseconds(250),
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.store = store
        self.maxBatchSize = max(1, maxBatchSize)
        self.pending = BoundedBuffer(capacity: max(self.maxBatchSize, maxPendingResults))
        self.flushDelay = flushDelay
        self.logger = logger
    }

    func append(_ result: PingResult) {
        pending.append(result)
        guard !isDiscarding else { return }
        if pending.count >= maxBatchSize {
            guard flushTask == nil else { return }
            scheduleImmediateFlush()
            return
        }
        scheduleFlushIfNeeded()
    }

    func flushNow() async {
        generation += 1
        await cancelFlushTasks()
        await drainAllPending(allowsBackoff: false)
        guard !pending.isEmpty, !isDiscarding else { return }
        scheduleFlushIfNeeded()
    }

    func discardPending() async {
        generation += 1
        isDiscarding = true
        while true {
            pending.removeAll()
            guard flushTask != nil else {
                pending.removeAll()
                isDiscarding = false
                return
            }
            await cancelFlushTasks()
        }
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil, !pending.isEmpty else { return }
        let scheduledGeneration = generation
        flushTask = Task { [flushDelay] in
            do {
                try await Task.sleep(for: flushDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await autoFlush(generation: scheduledGeneration)
        }
    }

    private func scheduleImmediateFlush() {
        guard flushTask == nil else { return }
        let scheduledGeneration = generation
        flushTask = Task {
            guard !Task.isCancelled else { return }
            await autoFlush(generation: scheduledGeneration)
        }
    }

    private func autoFlush(generation scheduledGeneration: Int) async {
        guard scheduledGeneration == generation, !Task.isCancelled else { return }
        await drainPending(allowsBackoff: true)
        guard scheduledGeneration == generation, !Task.isCancelled else { return }
        flushTask = nil
        if pending.count >= maxBatchSize {
            scheduleImmediateFlush()
        } else {
            scheduleFlushIfNeeded()
        }
    }

    private func drainAllPending(allowsBackoff: Bool) async {
        while !pending.isEmpty {
            guard await drainPending(allowsBackoff: allowsBackoff) else { return }
        }
    }

    @discardableResult
    private func drainPending(allowsBackoff: Bool) async -> Bool {
        guard !pending.isEmpty else { return true }
        let batch = pending.popPrefix(maxBatchSize)
        do {
            try await store.appendAndWait(batch)
            if consecutiveFailureCount > 0 {
                logger?("history write recovered pending=\(pending.count)")
            }
            consecutiveFailureCount = 0
            lastFailureLogAt = nil
            return true
        } catch {
            pending.prepend(contentsOf: batch)
            consecutiveFailureCount += 1
            logFailureIfNeeded(error)
            if allowsBackoff {
                await retryBackoff()
            }
            return false
        }
    }

    private func logFailureIfNeeded(_ error: Error) {
        let now = Date()
        if let lastFailureLogAt, now.timeIntervalSince(lastFailureLogAt) < 60 {
            return
        }
        lastFailureLogAt = now
        logger?("history write failed failures=\(consecutiveFailureCount) pending=\(pending.count) dropped=\(pending.droppedCount) error=\(error)")
    }

    private func retryBackoff() async {
        guard !Task.isCancelled else { return }
        let exponent = min(consecutiveFailureCount - 1, 5)
        let milliseconds = 250 * (1 << exponent)
        try? await Task.sleep(for: .milliseconds(Double(milliseconds)))
    }

    private func cancelFlushTasks() async {
        while let task = flushTask {
            flushTask = nil
            task.cancel()
            await task.value
        }
    }
}
