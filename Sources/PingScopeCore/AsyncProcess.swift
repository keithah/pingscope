import Foundation

public struct AsyncProcessResult: Sendable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data
}

public enum AsyncProcessError: Error, Equatable, Sendable {
    case timedOut
}

public enum AsyncProcess {
    public static func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration? = nil,
        maxOutputBytes: Int = 1_048_576
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
        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try process.run()

            async let outputData = outputReadHandle.readToEnd(maxBytes: maxOutputBytes)
            async let errorData = errorReadHandle.readToEnd(maxBytes: maxOutputBytes)

            if let timeout {
                try await process.waitForTermination(timeout: timeout, box: box)
            } else {
                await process.waitForTermination()
            }

            return AsyncProcessResult(
                terminationStatus: process.terminationStatus,
                standardOutput: await outputData,
                standardError: await errorData
            )
        } onCancel: {
            box.terminate()
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        terminateChildProcesses()
        if process.isRunning {
            process.terminate()
        }
    }

    private func terminateChildProcesses() {
        guard process.processIdentifier > 0 else { return }
        let childKiller = Process()
        childKiller.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        childKiller.arguments = ["-TERM", "-P", "\(process.processIdentifier)"]
        childKiller.standardOutput = FileHandle.nullDevice
        childKiller.standardError = FileHandle.nullDevice
        do {
            try childKiller.run()
            childKiller.waitUntilExit()
        } catch {
            return
        }
    }
}

private extension Process {
    func waitForTermination(timeout: Duration, box: ProcessBox) async throws {
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                let gate = ContinuationGate()
                let timeoutTask = Task {
                    try? await Task.sleep(for: timeout)
                    guard gate.claim() else { return }
                    box.terminate()
                    continuation.resume(throwing: AsyncProcessError.timedOut)
                }
                let resumeSuccess: @Sendable () -> Void = {
                    guard gate.claim() else { return }
                    timeoutTask.cancel()
                    continuation.resume()
                }

                terminationHandler = { _ in
                    resumeSuccess()
                }
                if !isRunning {
                    resumeSuccess()
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    func waitForTermination() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let gate = ContinuationGate()
                let resume: @Sendable () -> Void = {
                    guard gate.claim() else { return }
                    continuation.resume()
                }
                terminationHandler = { _ in
                    resume()
                }
                if !isRunning {
                    resume()
                }
            }
        } onCancel: {
            let box = ProcessBox(self)
            box.terminate()
        }
    }
}

private extension FileHandle {
    func readToEnd(maxBytes: Int) async -> Data {
        var data = Data()
        while true {
            let chunk = readData(ofLength: 8_192)
            if chunk.isEmpty {
                return data
            }
            let remaining = max(0, maxBytes - data.count)
            if remaining > 0 {
                data.append(chunk.prefix(remaining))
            }
        }
    }
}
