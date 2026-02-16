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

                readSource.setEventHandler { [identifier] in
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
                    guard let responseHeader = ICMPHeader.from(data: data) else {
                        return
                    }

                    guard responseHeader.type == ICMPHeader.echoReply,
                          responseHeader.identifier == identifier,
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
}

private final class ReadSourceBox: @unchecked Sendable {
    var source: DispatchSourceRead?
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
