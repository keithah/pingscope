import XCTest
@testable import PingScopeCore
#if os(macOS)
import Darwin
#endif

final class AsyncProcessTests: XCTestCase {
    func testRunCapturesOutputWithConfiguredCap() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'abcdef'; printf '123456' >&2"],
            timeout: .seconds(1),
            maxOutputBytes: 4
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "abcd")
        XCTAssertEqual(String(data: result.standardError, encoding: .utf8), "1234")
    }

    func testRunTerminatesProcessOnTimeout() async throws {
        do {
            _ = try await AsyncProcess.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "sleep 60"],
                timeout: .milliseconds(100)
            )
            XCTFail("Expected AsyncProcess to time out")
        } catch AsyncProcessError.timedOut {
        } catch {
            XCTFail("Expected timedOut, got \(error)")
        }
    }

    func testRunEscalatesToKillWhenProcessIgnoresTerm() async throws {
        do {
            _ = try await AsyncProcess.run(
                executablePath: "/usr/bin/perl",
                arguments: ["-e", "$SIG{TERM} = 'IGNORE'; select(undef, undef, undef, 60);"],
                timeout: .milliseconds(100)
            )
            XCTFail("Expected AsyncProcess to time out")
        } catch AsyncProcessError.timedOut {
        } catch {
            XCTFail("Expected timedOut, got \(error)")
        }
    }

    func testRunTerminatesProcessWhenSurroundingTaskCancelled() async throws {
#if os(macOS)
        let pidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-async-process-cancel-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFileURL) }
        let task = Task {
            try? await AsyncProcess.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "echo $$ > \"$1\"; sleep 60", "pingscope-test", pidFileURL.path]
            )
        }

        let processID = try await waitForProcessID(in: pidFileURL, timeout: .seconds(5))
        XCTAssertTrue(processIsAlive(processID))
        task.cancel()
        let result = await task.value

        XCTAssertNotNil(result)
        XCTAssertFalse(processIsAlive(processID), "cancellation must reap the launched process before returning")
#endif
    }

    func testRepeatedMidReadCancellationDoesNotRaceReaderClosure() async throws {
#if os(macOS)
        for _ in 0..<4 {
            let tasks = (0..<8).map { _ in
                Task {
                    try? await AsyncProcess.run(
                        executablePath: "/usr/bin/perl",
                        arguments: [
                            "-e",
                            "$| = 1; while (1) { print 'x' x 8192; print STDERR 'y' x 8192; }",
                        ],
                        timeout: .seconds(10)
                    )
                }
            }

            try await Task.sleep(for: .milliseconds(20))
            tasks.forEach { $0.cancel() }
            for task in tasks {
                _ = await task.value
            }
        }
#endif
    }

    func testPipeReaderCancellationNeverClosesDuringBlockedRead() async throws {
#if os(macOS)
        let readEntered = DispatchSemaphore(value: 0)
        let allowReadToFinish = DispatchSemaphore(value: 0)
        let state = PipeReaderTestState()
        let reader = AsyncProcessPipeReader(
            maxBytes: 64,
            operations: AsyncProcessPipeOperations(
                read: { _ in
                    state.beginRead()
                    readEntered.signal()
                    allowReadToFinish.wait()
                    state.endRead()
                    return Data()
                },
                close: {
                    state.close()
                }
            )
        )
        let readTask = Task { await reader.read() }
        XCTAssertEqual(readEntered.wait(timeout: .now() + 1), .success)

        reader.cancel()

        XCTAssertEqual(state.closeCount, 0, "cancel must not close a handle while read is active")
        XCTAssertFalse(state.didCloseDuringRead)
        allowReadToFinish.signal()
        _ = await readTask.value
        XCTAssertEqual(state.closeCount, 1)
        XCTAssertFalse(state.didCloseDuringRead)
#endif
    }

    func testBlockingEscalationExecutorRunsOnOperationQueueWorker() async {
#if os(macOS)
        let state = OperationQueueObservationState()
        await AsyncProcessBlockingExecutor.run {
            state.recordCurrentQueue(OperationQueue.current?.name)
        }
        XCTAssertEqual(
            state.queueName,
            "com.pingscope.async-process.blocking",
            "blocking escalation must execute on the bounded OperationQueue, not a Swift cooperative thread"
        )
#endif
    }

    func testBlockingExecutorBoundsEffectiveConcurrency() async {
#if os(macOS)
        let workerPool = AsyncProcessWorkerPool(maxConcurrentOperations: 2)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let state = WorkerConcurrencyTestState()
        let workers = (0..<6).map { _ in
            Task {
                await AsyncProcessBlockingExecutor.run(on: workerPool) {
                    state.begin()
                    entered.signal()
                    release.wait()
                    state.end()
                }
            }
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            entered.wait(timeout: .now() + 0.2),
            .timedOut,
            "the observable worker gate must admit no more than its configured capacity"
        )
        XCTAssertEqual(state.maximumActiveCount, 2)

        for _ in workers.indices {
            release.signal()
        }
        for worker in workers {
            await worker.value
        }
        XCTAssertEqual(state.maximumActiveCount, 2)
#endif
    }

    func testBoundedPipeReaderPoolCancelsQueuedReadersWithoutDeadlock() async {
#if os(macOS)
        let workerPool = AsyncProcessWorkerPool(maxConcurrentOperations: 2)
        let readEntered = DispatchSemaphore(value: 0)
        let releaseRead = DispatchSemaphore(value: 0)
        let state = PipeReaderPoolTestState()
        let readers = (0..<6).map { _ in
            AsyncProcessPipeReader(
                maxBytes: 64,
                operations: AsyncProcessPipeOperations(
                    read: { _ in
                        state.beginRead()
                        readEntered.signal()
                        releaseRead.wait()
                        state.endRead()
                        return Data()
                    },
                    close: {
                        state.close()
                    }
                ),
                workerPool: workerPool
            )
        }
        let readTasks = readers.map { reader in
            Task { await reader.read() }
        }

        XCTAssertEqual(readEntered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(readEntered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            readEntered.wait(timeout: .now() + 0.2),
            .timedOut,
            "queued readers must not exceed the pool's effective concurrency"
        )

        readers.forEach { $0.cancel() }
        releaseRead.signal()
        releaseRead.signal()
        for task in readTasks {
            _ = await task.value
        }

        XCTAssertEqual(state.readCount, 2, "cancelled queued readers must not enter a blocking read")
        XCTAssertEqual(state.maximumActiveReadCount, 2)
        XCTAssertEqual(state.closeCount, readers.count)
#endif
    }

    func testWholeRunAdmissionKeepsReaderPairsWithinCapacity() async throws {
#if os(macOS)
        let resources = AsyncProcessExecutionResources(maxConcurrentRuns: 2)
        XCTAssertEqual(resources.maximumConcurrentRuns, 2)
        XCTAssertEqual(resources.maximumConcurrentReaderOperations, 4)

        let entered = DispatchSemaphore(value: 0)
        let release = AsyncFirstResult<Void>()
        let state = WorkerConcurrencyTestState()
        let activeRuns = (0..<2).map { _ in
            Task {
                try await resources.withRunPermit {
                    state.begin()
                    entered.signal()
                    await release.value()
                    state.end()
                }
            }
        }

        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)

        let launchMarkerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-queued-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: launchMarkerURL) }
        let cancelledQueuedRun = Task {
            try await AsyncProcess.run(
                executablePath: "/usr/bin/touch",
                arguments: [launchMarkerURL.path],
                executionResources: resources
            )
        }
        cancelledQueuedRun.cancel()
        do {
            _ = try await cancelledQueuedRun.value
            XCTFail("Expected queued run admission to observe cancellation")
        } catch is CancellationError {
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: launchMarkerURL.path),
            "a cancelled queued run must never reach Process.run"
        )

        await release.finish(())
        for activeRun in activeRuns {
            try await activeRun.value
        }

        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf admitted"],
            executionResources: resources
        )
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "admitted")
        XCTAssertEqual(state.maximumActiveCount, 2)
#endif
    }

    func testWholeRunAdmissionReleasesPermitWhenProcessLaunchThrows() async {
#if os(macOS)
        let resources = AsyncProcessExecutionResources(maxConcurrentRuns: 1)
        do {
            _ = try await AsyncProcess.run(
                executablePath: "/pingscope/path/that/does/not/exist",
                arguments: [],
                executionResources: resources
            )
            XCTFail("Expected Process.run to throw")
        } catch {
        }

        let recovered = XCTestExpectation(description: "permit released after launch failure")
        let recoveryTask = Task {
            let result = try? await AsyncProcess.run(
                executablePath: "/bin/sh",
                arguments: ["-c", "printf recovered"],
                executionResources: resources
            )
            if String(data: result?.standardOutput ?? Data(), encoding: .utf8) == "recovered" {
                recovered.fulfill()
            }
        }
        await fulfillment(of: [recovered], timeout: 2)
        recoveryTask.cancel()
        _ = await recoveryTask.value
#endif
    }

    func testReapedProcessLifetimeRejectsLateSignals() {
#if os(macOS)
        let lifetime = AsyncProcessLifetimeState()
        let signals = SignalTestState()
        lifetime.markLaunched(processID: 42)

        XCTAssertTrue(lifetime.signalIfUnreaped { processID in
            signals.record(processID)
        })
        lifetime.markReaped()
        XCTAssertFalse(lifetime.signalIfUnreaped { processID in
            signals.record(processID)
        })

        XCTAssertEqual(signals.processIDs, [42])
#endif
    }

    func testCapturedDescendantRejectsKillWhenPIDIdentityChangesDuringGrace() {
#if os(macOS)
        let originalIdentity = AsyncProcessInstanceIdentity(
            processID: 42,
            startSeconds: 100,
            startMicroseconds: 200
        )
        let replacementIdentity = AsyncProcessInstanceIdentity(
            processID: 42,
            startSeconds: 101,
            startMicroseconds: 300
        )
        let identityState = ProcessIdentityTestState(current: originalIdentity)
        let signals = ProcessSignalTestState()
        let descendant = AsyncProcessCapturedProcess(
            identity: originalIdentity,
            currentIdentity: { processID in
                identityState.identity(for: processID)
            }
        )

        XCTAssertTrue(descendant.performIfCurrent { processID in
            signals.record(processID: processID, signal: SIGTERM)
        })

        // Simulate the descendant exiting during TERM grace and the kernel
        // reusing its numeric PID for an unrelated process before escalation.
        identityState.setCurrent(replacementIdentity)

        XCTAssertFalse(descendant.performIfCurrent { processID in
            signals.record(processID: processID, signal: SIGKILL)
        })
        XCTAssertEqual(signals.records, [ProcessSignalRecord(processID: 42, signal: SIGTERM)])
#endif
    }

    func testCancellationRemainsResponsiveWhenDescendantHoldsPipeWriteEnds() async throws {
#if os(macOS)
        let pidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-async-process-pipe-holder-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFileURL) }
        let script = """
        my $pid = fork();
        die "fork failed" unless defined $pid;
        if ($pid == 0) {
            $SIG{TERM} = 'IGNORE';
            print "holding pipe open\\n";
            select(undef, undef, undef, 60);
            exit 0;
        }
        open(my $fh, '>', $ARGV[0]) or die "pid file: $!";
        print $fh $pid;
        close($fh);
        select(undef, undef, undef, 60);
        """
        let task = Task {
            try? await AsyncProcess.run(
                executablePath: "/usr/bin/perl",
                arguments: ["-e", script, pidFileURL.path]
            )
        }
        let childPID = try await waitForProcessID(in: pidFileURL, timeout: .seconds(5))
        defer { _ = Darwin.kill(childPID, SIGKILL) }

        task.cancel()
        _ = await task.value

        XCTAssertFalse(processIsAlive(childPID))
#endif
    }

    func testCancellationKillsCapturedDescendantAfterParentExitsDuringTermGrace() async throws {
#if os(macOS)
        let pidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-async-process-child-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFileURL) }
        let script = """
        my $pid = fork();
        die "fork failed" unless defined $pid;
        if ($pid == 0) {
            $SIG{TERM} = 'IGNORE';
            select(undef, undef, undef, 60);
            exit 0;
        }
        open(my $fh, '>', $ARGV[0]) or die "pid file: $!";
        print $fh $pid;
        close($fh);
        select(undef, undef, undef, 60);
        """
        let task = Task {
            try? await AsyncProcess.run(
                executablePath: "/usr/bin/perl",
                arguments: ["-e", script, pidFileURL.path]
            )
        }

        let childPID = try await waitForProcessID(in: pidFileURL, timeout: .seconds(5))
        defer { _ = Darwin.kill(childPID, SIGKILL) }
        XCTAssertTrue(processIsAlive(childPID))

        task.cancel()
        _ = await task.value

        XCTAssertFalse(
            processIsAlive(childPID),
            "cancellation must not return before the captured TERM-ignoring descendant has been killed"
        )
#endif
    }

    func testTimeoutDoesNotThrowUntilCapturedDescendantCleanupFinishes() async throws {
#if os(macOS)
        let pidFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-async-process-timeout-child-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFileURL) }
        let script = """
        my $pid = fork();
        die "fork failed" unless defined $pid;
        if ($pid == 0) {
            $SIG{TERM} = 'IGNORE';
            select(undef, undef, undef, 60);
            exit 0;
        }
        open(my $fh, '>', $ARGV[0]) or die "pid file: $!";
        print $fh $pid;
        close($fh);
        select(undef, undef, undef, 60);
        """
        let task = Task { () -> Bool in
            do {
                _ = try await AsyncProcess.run(
                    executablePath: "/usr/bin/perl",
                    arguments: ["-e", script, pidFileURL.path],
                    timeout: .milliseconds(100)
                )
                return false
            } catch AsyncProcessError.timedOut {
                return true
            } catch {
                return false
            }
        }

        let childPID = try await waitForProcessID(in: pidFileURL, timeout: .seconds(5))
        defer { _ = Darwin.kill(childPID, SIGKILL) }
        let didTimeOut = await task.value

        XCTAssertTrue(didTimeOut)
        XCTAssertFalse(
            processIsAlive(childPID),
            "timeout must not throw before captured descendant cleanup completes"
        )
#endif
    }

    func testRunDoesNotLaunchProcessWhenTaskIsAlreadyCancelled() async {
        let gate = AsyncFirstResult<Void>()
        let launchMarkerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-already-cancelled-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: launchMarkerURL) }
        let task = Task {
            await gate.value()
            return try? await AsyncProcess.run(
                executablePath: "/usr/bin/touch",
                arguments: [launchMarkerURL.path]
            )
        }
        task.cancel()
        await gate.finish(())

        let result = await task.value

        XCTAssertNil(result)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: launchMarkerURL.path),
            "an already-cancelled task must not launch a child that cleanup can no longer own"
        )
    }

    func testRunReportsNonZeroTerminationStatus() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "exit 3"],
            timeout: .seconds(2)
        )

        XCTAssertEqual(result.terminationStatus, 3)
    }

    func testRunWithoutTimeoutReturnsCapturedOutput() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf 'hello'"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "hello")
    }

    func testRunDrainsOutputLargerThanPipeBufferWithoutDeadlock() async throws {
        // 200 KB exceeds the OS pipe buffer; capping output must not stall the child.
        let result = try await AsyncProcess.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "head -c 200000 /dev/zero"],
            timeout: .seconds(5),
            maxOutputBytes: 10
        )

        XCTAssertEqual(result.standardOutput.count, 10)
    }

    func testRunStopsReadingAfterOutputCap() async throws {
        let result = try await AsyncProcess.run(
            executablePath: "/usr/bin/yes",
            arguments: [],
            timeout: .seconds(5),
            maxOutputBytes: 16
        )

        XCTAssertEqual(result.standardOutput.count, 16)
    }
}

#if os(macOS)
private func waitForProcessID(in fileURL: URL, timeout: Duration) async throws -> pid_t {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
           let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 0 {
            return pid
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw AsyncProcessTestTimeout()
}

private func processIsAlive(_ processID: pid_t) -> Bool {
    if Darwin.kill(processID, 0) == 0 {
        return true
    }
    return errno == EPERM
}

private struct AsyncProcessTestTimeout: Error {}

private final class PipeReaderTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var isReading = false
    private var storedCloseCount = 0
    private var storedDidCloseDuringRead = false

    var closeCount: Int { lock.withLock { storedCloseCount } }
    var didCloseDuringRead: Bool { lock.withLock { storedDidCloseDuringRead } }

    func beginRead() {
        lock.withLock { isReading = true }
    }

    func endRead() {
        lock.withLock { isReading = false }
    }

    func close() {
        lock.withLock {
            storedCloseCount += 1
            storedDidCloseDuringRead = storedDidCloseDuringRead || isReading
        }
    }
}

private final class SignalTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProcessIDs: [pid_t] = []

    var processIDs: [pid_t] { lock.withLock { storedProcessIDs } }

    func record(_ processID: pid_t) {
        lock.withLock { storedProcessIDs.append(processID) }
    }
}

private final class ProcessIdentityTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AsyncProcessInstanceIdentity?

    init(current: AsyncProcessInstanceIdentity?) {
        self.current = current
    }

    func setCurrent(_ identity: AsyncProcessInstanceIdentity?) {
        lock.withLock { current = identity }
    }

    func identity(for processID: pid_t) -> AsyncProcessInstanceIdentity? {
        lock.withLock {
            guard current?.processID == processID else { return nil }
            return current
        }
    }
}

private struct ProcessSignalRecord: Equatable {
    let processID: pid_t
    let signal: Int32
}

private final class ProcessSignalTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecords: [ProcessSignalRecord] = []

    var records: [ProcessSignalRecord] { lock.withLock { storedRecords } }

    func record(processID: pid_t, signal: Int32) {
        lock.withLock {
            storedRecords.append(ProcessSignalRecord(processID: processID, signal: signal))
        }
    }
}

private final class WorkerConcurrencyTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var storedMaximumActiveCount = 0

    var maximumActiveCount: Int { lock.withLock { storedMaximumActiveCount } }

    func begin() {
        lock.withLock {
            activeCount += 1
            storedMaximumActiveCount = max(storedMaximumActiveCount, activeCount)
        }
    }

    func end() {
        lock.withLock { activeCount -= 1 }
    }
}

private final class OperationQueueObservationState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedQueueName: String?

    var queueName: String? { lock.withLock { storedQueueName } }

    func recordCurrentQueue(_ name: String?) {
        lock.withLock { storedQueueName = name }
    }
}

private final class PipeReaderPoolTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeReadCount = 0
    private var storedReadCount = 0
    private var storedMaximumActiveReadCount = 0
    private var storedCloseCount = 0

    var readCount: Int { lock.withLock { storedReadCount } }
    var maximumActiveReadCount: Int { lock.withLock { storedMaximumActiveReadCount } }
    var closeCount: Int { lock.withLock { storedCloseCount } }

    func beginRead() {
        lock.withLock {
            activeReadCount += 1
            storedReadCount += 1
            storedMaximumActiveReadCount = max(storedMaximumActiveReadCount, activeReadCount)
        }
    }

    func endRead() {
        lock.withLock { activeReadCount -= 1 }
    }

    func close() {
        lock.withLock { storedCloseCount += 1 }
    }
}
#endif
