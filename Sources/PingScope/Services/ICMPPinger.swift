import Darwin
import Dispatch
import Foundation

/// ICMP pinger using non-privileged datagram sockets.
/// Only works outside App Store sandbox (Developer ID distribution).
actor ICMPPinger {
    private let identifier: UInt16
    private var sequenceNumber: UInt16 = 0

    init() {
        identifier = UInt16(truncatingIfNeeded: getpid())
    }

    func ping(host: String, timeout: Duration) async throws -> Duration {
        do {
            return try await pingViaSystemUtility(host: host, timeout: timeout)
        } catch {
            // Fallback to socket implementation if the system utility path fails.
        }

        return try await pingViaSocket(host: host, timeout: timeout)
    }

    private func pingViaSocket(host: String, timeout: Duration) async throws -> Duration {
        try await withThrowingTaskGroup(of: Duration.self) { group in
            group.addTask {
                try await self.sendAndReceive(host: host)
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw PingError.timeout
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw PingError.cancelled
            }
            return result
        }
    }

    private func pingViaSystemUtility(host: String, timeout: Duration) async throws -> Duration {
        let timeoutMS = max(250, Self.timeoutMilliseconds(for: timeout))
        let timeoutSeconds = max(1, Int(ceil(Double(timeoutMS) / 1_000.0)))

        let state = ContinuationState()
        let processBox = ProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Duration, Error>) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-n", "-c", "1", "-W", String(timeoutMS), "-t", String(timeoutSeconds), host]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                processBox.process = process

                process.terminationHandler = { process in
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(decoding: data, as: UTF8.self)
                    let trimmedOutput = output
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " | ")

                    if process.terminationStatus == 0,
                       let latencyMS = Self.extractLatencyMilliseconds(from: output) {
                        if state.markResumed() {
                            continuation.resume(returning: .nanoseconds(Int64((latencyMS * 1_000_000).rounded())))
                        }
                    } else if process.terminationStatus == 0 {
                        if state.markResumed() {
                            let message = trimmedOutput.isEmpty
                                ? "ICMP failed: latency could not be parsed"
                                : "ICMP failed: \(trimmedOutput)"
                            continuation.resume(throwing: PingError.connectionFailed(message))
                        }
                    } else if state.markResumed() {
                        let message = trimmedOutput.isEmpty
                            ? "ICMP failed (exit \(process.terminationStatus))"
                            : "ICMP failed (exit \(process.terminationStatus)): \(trimmedOutput)"
                        continuation.resume(throwing: PingError.connectionFailed(message))
                    }
                }

                do {
                    try process.run()
                } catch {
                    if state.markResumed() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.process?.terminate()
        }
    }

    private func sendAndReceive(host: String) async throws -> Duration {
        let address = try resolveHost(host)

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            throw PingError.connectionFailed("Failed to create ICMP socket: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        sequenceNumber &+= 1
        let seq = sequenceNumber

        let packet = buildEchoRequest(sequenceNumber: seq)
        let startTime = ContinuousClock.now

        try sendPacket(fd: fd, packet: packet, to: address)
        try await receiveResponse(fd: fd, expectedSequence: seq)

        return ContinuousClock.now - startTime
    }

    private func resolveHost(_ host: String) throws -> sockaddr_in {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let addrInfo = result else {
            throw PingError.connectionFailed("Failed to resolve host: \(host)")
        }
        defer { freeaddrinfo(result) }

        guard let sockaddr = addrInfo.pointee.ai_addr else {
            throw PingError.connectionFailed("No address found for host: \(host)")
        }

        return sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private func buildEchoRequest(sequenceNumber: UInt16) -> Data {
        let header = ICMPHeader.echoRequestHeader(identifier: identifier, sequenceNumber: sequenceNumber)
        let payload = "PingScope".data(using: .utf8) ?? Data()

        var packet = header.toData() + payload
        let checksum = icmpChecksum(data: packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)
        return packet
    }

    private func sendPacket(fd: Int32, packet: Data, to address: sockaddr_in) throws {
        var addr = address
        let sent: ssize_t = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(fd, buffer.baseAddress, buffer.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        guard sent == packet.count else {
            throw PingError.connectionFailed("Failed to send ICMP packet: \(String(cString: strerror(errno)))")
        }
    }

    private func receiveResponse(fd: Int32, expectedSequence: UInt16) async throws {
        let state = ContinuationState()
        let queue = DispatchQueue(label: "ICMPPinger.read")
        let sourceBox = ReadSourceBox()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
                sourceBox.source = readSource

                readSource.setEventHandler {
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    var senderAddr = sockaddr_in()
                    var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                    let received = withUnsafeMutablePointer(to: &senderAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                            recvfrom(fd, &buffer, buffer.count, 0, sockaddrPtr, &addrLen)
                        }
                    }

                    guard received > 0 else {
                        readSource.cancel()
                        if state.markResumed() {
                            continuation.resume(throwing: PingError.connectionFailed("Failed to receive ICMP response"))
                        }
                        return
                    }

                    let data = Data(buffer.prefix(Int(received)))
                    guard let responseHeader = self.echoReplyHeader(from: data, expectedSequence: expectedSequence) else {
                        return
                    }

                    guard responseHeader.type == ICMPHeader.echoReply,
                          responseHeader.sequenceNumber == expectedSequence else {
                        return
                    }

                    readSource.cancel()
                    if state.markResumed() {
                        continuation.resume(returning: ())
                    }
                }

                readSource.setCancelHandler {
                    if state.markResumed() {
                        continuation.resume(throwing: PingError.cancelled)
                    }
                }

                readSource.resume()
            }
        } onCancel: {
            sourceBox.source?.cancel()
        }
    }

    private func echoReplyHeader(from data: Data, expectedSequence: UInt16) -> ICMPHeader? {
        // On macOS ICMP datagram sockets can deliver either:
        // - bare ICMP packet (starts at ICMP header), or
        // - IPv4 packet (starts at IP header, ICMP header at IHL offset).
        // Accept either format and match on sequence number.
        var candidateOffsets: [Int] = [0]

        if data.count >= 20 {
            let version = data[0] >> 4
            let ihlWords = Int(data[0] & 0x0F)
            let ipHeaderLength = ihlWords * 4
            if version == 4, ipHeaderLength >= 20, ipHeaderLength + ICMPHeader.size <= data.count {
                candidateOffsets.append(ipHeaderLength)
            }
        }

        for offset in candidateOffsets {
            guard data.count >= offset + ICMPHeader.size else {
                continue
            }

            let slice = data.subdata(in: offset..<(offset + ICMPHeader.size))
            guard let header = ICMPHeader.from(data: slice) else {
                continue
            }

            if header.type == ICMPHeader.echoReply, header.sequenceNumber == expectedSequence {
                return header
            }
        }

        return nil
    }

    private static func timeoutMilliseconds(for timeout: Duration) -> Int {
        let components = timeout.components
        let millisecondsFromSeconds = components.seconds * 1_000
        let millisecondsFromAttoseconds = components.attoseconds / 1_000_000_000_000_000
        let total = millisecondsFromSeconds + millisecondsFromAttoseconds
        return Int(min(max(total, 1), 60_000))
    }

    private static func extractLatencyMilliseconds(from output: String) -> Double? {
        guard let timeRange = output.range(of: "time=") else {
            return nil
        }

        let remainder = output[timeRange.upperBound...]
        guard let msRange = remainder.range(of: " ms") else {
            return nil
        }

        let value = remainder[..<msRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value)
    }
}

private final class ReadSourceBox: @unchecked Sendable {
    var source: DispatchSourceRead?
}

private final class ProcessBox: @unchecked Sendable {
    var process: Process?
}

private final class ContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed {
            return false
        }
        resumed = true
        return true
    }
}
