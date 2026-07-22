import Foundation
#if os(macOS)
import Darwin
#endif

public struct AsyncProcessResult: Sendable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data
}

public enum AsyncProcessError: Error, Equatable, Sendable {
    case timedOut
    case unavailable
}

public enum AsyncProcess {
#if os(macOS)
    private static let defaultExecutionResources = AsyncProcessExecutionResources(maxConcurrentRuns: 32)
#endif

    public static func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration? = nil,
        maxOutputBytes: Int = 1_048_576,
        logger: (@Sendable (String) -> Void)? = nil
    ) async throws -> AsyncProcessResult {
#if os(macOS)
        return try await run(
            executablePath: executablePath,
            arguments: arguments,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes,
            logger: logger,
            executionResources: defaultExecutionResources
        )
#else
        throw AsyncProcessError.unavailable
#endif
    }

#if os(macOS)
    static func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration? = nil,
        maxOutputBytes: Int = 1_048_576,
        logger: (@Sendable (String) -> Void)? = nil,
        executionResources: AsyncProcessExecutionResources
    ) async throws -> AsyncProcessResult {
        try await executionResources.withRunPermit {
            try await runAdmitted(
                executablePath: executablePath,
                arguments: arguments,
                timeout: timeout,
                maxOutputBytes: maxOutputBytes,
                logger: logger,
                readerWorkerPool: executionResources.readerWorkerPool
            )
        }
    }

    private static func runAdmitted(
        executablePath: String,
        arguments: [String],
        timeout: Duration?,
        maxOutputBytes: Int,
        logger: (@Sendable (String) -> Void)?,
        readerWorkerPool: AsyncProcessWorkerPool
    ) async throws -> AsyncProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let outputReadHandle = output.fileHandleForReading
        let errorReadHandle = error.fileHandleForReading
        let outputReader = AsyncProcessPipeReader(
            handle: outputReadHandle,
            maxBytes: maxOutputBytes,
            workerPool: readerWorkerPool
        )
        let errorReader = AsyncProcessPipeReader(
            handle: errorReadHandle,
            maxBytes: maxOutputBytes,
            workerPool: readerWorkerPool
        )
        let box = ProcessBox(
            outputReader: outputReader,
            errorReader: errorReader,
            logger: logger
        )
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try process.run()
                box.markLaunchFinished(processID: process.processIdentifier)
            } catch {
                box.markLaunchFinished(processID: nil)
                await box.finishOperationAndWaitForTermination()
                throw error
            }

            async let outputData = outputReader.read()
            async let errorData = errorReader.read()

            if let timeout {
                try await process.waitForTermination(timeout: timeout, box: box)
            } else {
                await process.waitForTermination(box: box)
            }

            let result = AsyncProcessResult(
                terminationStatus: process.terminationStatus,
                standardOutput: await outputData,
                standardError: await errorData
            )
            // Atomically close the operation boundary and join any cleanup
            // installed by a cancellation handler before returning to caller.
            await box.finishOperationAndWaitForTermination()
            return result
        } onCancel: {
            box.terminateDetached()
        }
    }
#endif
}

#if os(macOS)
final class AsyncProcessExecutionResources: @unchecked Sendable {
    let maximumConcurrentRuns: Int
    let maximumConcurrentReaderOperations: Int
    let readerWorkerPool: AsyncProcessWorkerPool
    private let runPermitPool: AsyncPermitPool

    init(maxConcurrentRuns: Int) {
        let maximumConcurrentRuns = max(1, maxConcurrentRuns)
        let maximumConcurrentReaderOperations = maximumConcurrentRuns * 2
        self.maximumConcurrentRuns = maximumConcurrentRuns
        self.maximumConcurrentReaderOperations = maximumConcurrentReaderOperations
        self.runPermitPool = AsyncPermitPool(permits: maximumConcurrentRuns)
        self.readerWorkerPool = AsyncProcessWorkerPool(
            maxConcurrentOperations: maximumConcurrentReaderOperations,
            name: "com.pingscope.async-process.pipe-reader"
        )
    }

    func withRunPermit<Result: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        try await runPermitPool.acquire()
        let lease = AsyncPermitLease(pool: runPermitPool)
        do {
            try Task.checkCancellation()
            let result = try await operation()
            await lease.release()
            return result
        } catch {
            await lease.release()
            throw error
        }
    }
}

struct AsyncProcessInstanceIdentity: Equatable, Hashable, Sendable {
    let processID: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

/// A PID plus its captured kernel start time. Re-reading the identity before
/// every operation prevents an exited descendant's reused numeric PID from
/// being treated as the process captured before TERM grace.
struct AsyncProcessCapturedProcess: @unchecked Sendable {
    let identity: AsyncProcessInstanceIdentity
    private let currentIdentity: @Sendable (pid_t) -> AsyncProcessInstanceIdentity?

    init(
        identity: AsyncProcessInstanceIdentity,
        currentIdentity: @escaping @Sendable (pid_t) -> AsyncProcessInstanceIdentity?
    ) {
        self.identity = identity
        self.currentIdentity = currentIdentity
    }

    var isCurrent: Bool {
        currentIdentity(identity.processID) == identity
    }

    @discardableResult
    func performIfCurrent(_ operation: (pid_t) -> Void) -> Bool {
        guard isCurrent else { return false }
        operation(identity.processID)
        return true
    }
}

private final class ProcessBox: @unchecked Sendable {
    private static let termGracePeriod = Duration.milliseconds(200)
    private let outputReader: AsyncProcessPipeReader
    private let errorReader: AsyncProcessPipeReader
    private let lifetime = AsyncProcessLifetimeState()
    private let logger: (@Sendable (String) -> Void)?
    private let lock = NSLock()
    private var terminationTask: Task<Void, Never>?
    private var launchFinished = false
    private var operationFinished = false

    init(
        outputReader: AsyncProcessPipeReader,
        errorReader: AsyncProcessPipeReader,
        logger: (@Sendable (String) -> Void)?
    ) {
        self.outputReader = outputReader
        self.errorReader = errorReader
        self.logger = logger
    }

    func terminateAndWait() async {
        if let terminationTask = requestTermination() {
            await terminationTask.value
        }
    }

    func terminateDetached() {
        _ = requestTermination()
    }

    func markLaunchFinished(processID: pid_t?) {
        if let processID, processID > 0 {
            lifetime.markLaunched(processID: processID)
        }
        lock.lock()
        launchFinished = true
        lock.unlock()
    }

    func markProcessReaped() {
        lifetime.markReaped()
    }

    func finishOperationAndWaitForTermination() async {
        let terminationTask = lock.withLock { () -> Task<Void, Never>? in
            operationFinished = true
            return self.terminationTask
        }
        if let terminationTask {
            await terminationTask.value
        }
    }

    /// Cancellation handlers are synchronous and frequently run on the main
    /// actor. They only install this one cleanup owner; all blocking process
    /// work and the bounded TERM/KILL escalation happen off-thread.
    private func requestTermination() -> Task<Void, Never>? {
        lock.lock()
        if let terminationTask {
            lock.unlock()
            return terminationTask
        }
        guard !operationFinished else {
            lock.unlock()
            return nil
        }
        // Readers own their handles. Cancellation is only a flag here; the
        // reader closes after its active read returns, never concurrently.
        outputReader.cancel()
        errorReader.cancel()
        let task = Task(priority: .utility) { [self] in
            await AsyncProcessBlockingExecutor.run {
                self.terminateAndEscalate()
            }
        }
        terminationTask = task
        lock.unlock()
        return task
    }

    private func terminateAndEscalate() {
        // Cancellation may arrive before `Process.run()` assigns a PID. Wait
        // for that synchronous launch attempt to finish so cleanup cannot miss
        // a child that appears just after an early no-op signal.
        while true {
            lock.lock()
            let didFinishLaunching = launchFinished
            lock.unlock()
            if didFinishLaunching { break }
            Thread.sleep(forTimeInterval: 0.001)
        }

        guard let parentProcessID = lifetime.unreapedProcessID else { return }
        // Capture the complete tree before TERM. Once the parent exits its
        // children are reparented, so a later `pkill -P parent` can no longer
        // find the survivors that still require escalation.
        let descendants = captureDescendantProcesses(of: parentProcessID)
        descendants.reversed().forEach { descendant in
            descendant.performIfCurrent { signalProcess($0, signal: SIGTERM) }
        }
        _ = lifetime.signalIfUnreaped { processID in
            signalProcess(processID, signal: SIGTERM)
        }

        let deadline = ContinuousClock.now.advanced(by: Self.termGracePeriod)
        while ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        // Escalate every captured survivor independently of the parent's
        // status. The parent commonly exits on TERM while a child ignores it.
        descendants.reversed().forEach { descendant in
            descendant.performIfCurrent { signalProcess($0, signal: SIGKILL) }
        }
        _ = lifetime.signalIfUnreaped { processID in
            signalProcess(processID, signal: SIGKILL)
        }
        let killDeadline = ContinuousClock.now.advanced(by: Self.termGracePeriod)
        while descendants.contains(where: \.isCurrent),
              ContinuousClock.now < killDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func signalProcess(_ processID: pid_t, signal: Int32) {
        guard processID > 0 else { return }
        if Darwin.kill(processID, signal) != 0, errno != ESRCH {
            logger?("async process signal \(signal) failed errno=\(errno)")
        }
    }

    private func captureDescendantProcesses(of rootProcessID: pid_t) -> [AsyncProcessCapturedProcess] {
        guard rootProcessID > 0,
              let rootIdentity = currentProcessIdentity(rootProcessID) else { return [] }
        var descendants: [AsyncProcessCapturedProcess] = []
        var pendingParents = [
            AsyncProcessCapturedProcess(
                identity: rootIdentity,
                currentIdentity: currentProcessIdentity
            ),
        ]
        var seen = Set([rootProcessID])

        while let parent = pendingParents.popLast() {
            guard parent.isCurrent else { continue }
            for childProcessID in directChildProcessIDs(of: parent.identity.processID)
                where childProcessID > 0 && seen.insert(childProcessID).inserted {
                guard let identity = currentProcessIdentity(childProcessID) else { continue }
                let child = AsyncProcessCapturedProcess(
                    identity: identity,
                    currentIdentity: currentProcessIdentity
                )
                descendants.append(child)
                pendingParents.append(child)
            }
        }
        return descendants
    }

    private func directChildProcessIDs(of parentProcessID: pid_t) -> [pid_t] {
        let childLookup = Process()
        let output = Pipe()
        childLookup.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        childLookup.arguments = ["-P", "\(parentProcessID)"]
        childLookup.standardOutput = output
        childLookup.standardError = FileHandle.nullDevice
        do {
            try childLookup.run()
            // Drain before waiting so an unusually broad process tree cannot
            // fill pgrep's pipe and deadlock descendant discovery.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            childLookup.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
        } catch {
            logger?("async process descendant discovery failed: \(error)")
            return []
        }
    }

}

private func currentProcessIdentity(_ processID: pid_t) -> AsyncProcessInstanceIdentity? {
    guard processID > 0 else { return nil }
    var info = proc_bsdinfo()
    let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    let actualSize = proc_pidinfo(
        processID,
        PROC_PIDTBSDINFO,
        0,
        &info,
        expectedSize
    )
    guard actualSize == expectedSize, info.pbi_pid == UInt32(processID) else { return nil }
    return AsyncProcessInstanceIdentity(
        processID: processID,
        startSeconds: info.pbi_start_tvsec,
        startMicroseconds: info.pbi_start_tvusec
    )
}

/// Runs process-management work that may block (pgrep, waitpid, and bounded
/// grace sleeps) on bounded OperationQueue workers instead of Swift's
/// cooperative executor.
final class AsyncProcessWorkerPool: @unchecked Sendable {
    private let operationQueue: OperationQueue

    init(maxConcurrentOperations: Int, name: String = "com.pingscope.async-process.worker") {
        let operationQueue = OperationQueue()
        operationQueue.name = name
        operationQueue.qualityOfService = .utility
        operationQueue.maxConcurrentOperationCount = max(1, maxConcurrentOperations)
        self.operationQueue = operationQueue
    }

    func run<Result: Sendable>(
        _ operation: @escaping @Sendable () -> Result
    ) async -> Result {
        await withCheckedContinuation { continuation in
            operationQueue.addOperation {
                continuation.resume(returning: operation())
            }
        }
    }
}

enum AsyncProcessBlockingExecutor {
    private static let workerPool = AsyncProcessWorkerPool(
        maxConcurrentOperations: 8,
        name: "com.pingscope.async-process.blocking"
    )

    static func run(_ operation: @escaping @Sendable () -> Void) async {
        await workerPool.run(operation)
    }

    static func run(
        on workerPool: AsyncProcessWorkerPool,
        _ operation: @escaping @Sendable () -> Void
    ) async {
        await workerPool.run(operation)
    }
}

/// Tracks whether the PID assigned to this Process instance is still safe to
/// signal. Holding the lock across the signal closes the check/signal race with
/// the termination handler that records Foundation's reap notification.
final class AsyncProcessLifetimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var processID: pid_t?
    private var isReaped = false

    var unreapedProcessID: pid_t? {
        lock.withLock { isReaped ? nil : processID }
    }

    func markLaunched(processID: pid_t) {
        lock.withLock {
            self.processID = processID
            isReaped = false
        }
    }

    func markReaped() {
        lock.withLock { isReaped = true }
    }

    @discardableResult
    func signalIfUnreaped(_ signal: (pid_t) -> Void) -> Bool {
        lock.withLock {
            guard !isReaped, let processID, processID > 0 else { return false }
            signal(processID)
            return true
        }
    }
}

struct AsyncProcessPipeOperations: @unchecked Sendable {
    let read: @Sendable (Int) -> Data?
    let close: @Sendable () -> Void

    init(
        read: @escaping @Sendable (Int) -> Data?,
        close: @escaping @Sendable () -> Void
    ) {
        self.read = read
        self.close = close
    }

    init(handle: FileHandle) {
        read = { byteCount in
            try? handle.read(upToCount: byteCount) ?? Data()
        }
        close = {
            try? handle.close()
        }
    }
}

/// Owns a pipe's read handle for its entire lifetime. Cancellation is a flag;
/// only the dispatch-queue reader closes the handle, after any active read has
/// returned, so FileHandle is never closed concurrently with read(upToCount:).
final class AsyncProcessPipeReader: @unchecked Sendable {
    private static let defaultWorkerPool = AsyncProcessWorkerPool(
        // Two readers are used per subprocess. This remains well above the
        // app's host fan-out while placing a hard ceiling on blocking reads.
        maxConcurrentOperations: 64,
        name: "com.pingscope.async-process.pipe-reader"
    )

    private let operations: AsyncProcessPipeOperations
    private let maxBytes: Int
    private let workerPool: AsyncProcessWorkerPool
    private let lock = NSLock()
    private var isCancelled = false

    convenience init(
        handle: FileHandle,
        maxBytes: Int,
        workerPool: AsyncProcessWorkerPool? = nil
    ) {
        self.init(
            maxBytes: maxBytes,
            operations: AsyncProcessPipeOperations(handle: handle),
            workerPool: workerPool ?? Self.defaultWorkerPool
        )
    }

    init(
        maxBytes: Int,
        operations: AsyncProcessPipeOperations,
        workerPool: AsyncProcessWorkerPool? = nil
    ) {
        self.maxBytes = maxBytes
        self.operations = operations
        self.workerPool = workerPool ?? Self.defaultWorkerPool
    }

    func cancel() {
        lock.withLock { isCancelled = true }
    }

    func read() async -> Data {
        await workerPool.run {
            self.readBlocking()
        }
    }

    private func readBlocking() -> Data {
        defer { operations.close() }
        var data = Data()

        while true {
            if lock.withLock({ isCancelled }) {
                return data
            }
            guard let chunk = operations.read(8_192), !chunk.isEmpty else {
                return data
            }
            let remaining = max(0, maxBytes - data.count)
            guard remaining > 0 else { return data }
            data.append(chunk.prefix(remaining))
            if data.count >= maxBytes {
                return data
            }
        }
    }
}

private extension Process {
    func waitForTermination(timeout: Duration, box: ProcessBox) async throws {
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                let gate = ContinuationGate()
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    guard gate.claim() else { return }
                    await box.terminateAndWait()
                    continuation.resume(throwing: AsyncProcessError.timedOut)
                }
                let resumeSuccess: @Sendable () -> Void = {
                    guard gate.claim() else { return }
                    timeoutTask.cancel()
                    continuation.resume()
                }

                terminationHandler = { _ in
                    box.markProcessReaped()
                    resumeSuccess()
                }
                if !isRunning {
                    box.markProcessReaped()
                    resumeSuccess()
                }
            }
        } onCancel: {
            box.terminateDetached()
        }
    }

    func waitForTermination(box: ProcessBox) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ContinuationGate()
                let resume: @Sendable () -> Void = {
                    guard gate.claim() else { return }
                    continuation.resume()
                }
                terminationHandler = { _ in
                    box.markProcessReaped()
                    resume()
                }
                if !isRunning {
                    box.markProcessReaped()
                    resume()
                }
            }
        } onCancel: {
            box.terminateDetached()
        }
    }
}
#endif
