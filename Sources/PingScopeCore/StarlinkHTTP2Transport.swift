import Foundation
@preconcurrency import Network

public struct StarlinkHTTP2Transport: StarlinkGRPCTransport {
    public init() {}

    public func unary(path: String, requestFrame: Data, host: HostConfig) async throws -> Data {
        guard let port = host.port ?? host.method.defaultPort,
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw StarlinkStatusFetchError.unavailable
        }

        let connection = NWConnection(host: NWEndpoint.Host(host.address), port: nwPort, using: .tcp)
        let sessionBox = StarlinkHTTP2SessionBox()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        let session = StarlinkHTTP2Session(
                            connection: connection,
                            path: path,
                            host: host,
                            requestFrame: requestFrame,
                            continuation: continuation
                        )
                        sessionBox.set(session)
                        session.start()
                    }
                }
                group.addTask {
                    try await Task.sleep(for: host.timeout + .seconds(1))
                    throw StarlinkStatusFetchError.timedOut
                }

                do {
                    guard let data = try await group.next() else {
                        throw StarlinkStatusFetchError.unavailable
                    }
                    group.cancelAll()
                    sessionBox.cancel()
                    return data
                } catch {
                    group.cancelAll()
                    sessionBox.cancel()
                    throw error
                }
            }
        } onCancel: {
            sessionBox.cancel()
        }
    }
}

private final class StarlinkHTTP2SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var session: StarlinkHTTP2Session?

    func set(_ session: StarlinkHTTP2Session) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let session = session
        lock.unlock()
        session?.cancel()
    }
}

private final class StarlinkHTTP2Session: @unchecked Sendable {
    private static let maxResponseBytes = 256 * 1024
    private let connection: NWConnection
    private let path: String
    private let host: HostConfig
    private let requestFrame: Data
    private let continuation: CheckedContinuation<Data, any Error>
    private let gate = ContinuationGate()
    private let lock = NSLock()
    private var parser = HTTP2FrameParser()
    private var responseData = Data()

    init(
        connection: NWConnection,
        path: String,
        host: HostConfig,
        requestFrame: Data,
        continuation: CheckedContinuation<Data, any Error>
    ) {
        self.connection = connection
        self.path = path
        self.host = host
        self.requestFrame = requestFrame
        self.continuation = continuation
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendRequest()
                self.receiveMore()
            case .failed:
                self.finish(.failure(StarlinkStatusFetchError.unavailable))
            case .cancelled:
                self.finish(.failure(CancellationError()))
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func sendRequest() {
        let request = StarlinkHTTP2RequestBuilder.requestBytes(
            authority: "\(host.address):\(host.port ?? host.method.defaultPort ?? 9200)",
            path: path,
            body: requestFrame
        )
        connection.send(content: request, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.finish(.failure(StarlinkStatusFetchError.unavailable))
            }
        })
    }

    private func receiveMore() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                self.finish(.failure(StarlinkStatusFetchError.unavailable))
                return
            }
            if let data, !data.isEmpty {
                self.handle(data)
            }
            if isComplete {
                self.finish(.failure(StarlinkStatusFetchError.invalidStatus))
                return
            }
            self.receiveMore()
        }
    }

    private func handle(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try parser.append(data)
            let frames = try parser.drainFrames()
            for frame in frames {
                switch frame.type {
                case .settings where frame.flags & HTTP2FrameFlags.ack == 0:
                    connection.send(content: StarlinkHTTP2RequestBuilder.settingsAckFrame(), completion: .contentProcessed { _ in })
                case .data where frame.streamID == 1:
                    guard responseData.count + frame.payload.count <= Self.maxResponseBytes else {
                        finish(.failure(StarlinkStatusFetchError.responseTooLarge))
                        return
                    }
                    responseData.append(frame.payload)
                    if let completeResponse = completeGRPCFrame(from: responseData) {
                        finish(.success(completeResponse))
                        return
                    }
                case .goaway, .rstStream:
                    finish(.failure(StarlinkStatusFetchError.unavailable))
                    return
                default:
                    break
                }
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func completeGRPCFrame(from data: Data) -> Data? {
        guard data.count >= 5 else {
            return nil
        }
        let start = data.startIndex
        let length = (Int(data[data.index(start, offsetBy: 1)]) << 24)
            | (Int(data[data.index(start, offsetBy: 2)]) << 16)
            | (Int(data[data.index(start, offsetBy: 3)]) << 8)
            | Int(data[data.index(start, offsetBy: 4)])
        guard length <= Self.maxResponseBytes - 5, data.count >= 5 + length else {
            return nil
        }
        return Data(data[start..<data.index(start, offsetBy: 5 + length)])
    }

    private func finish(_ result: Result<Data, any Error>) {
        guard gate.claim() else { return }
        connection.cancel()
        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

enum StarlinkHTTP2RequestBuilder {
    private static let clientPreface = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)

    static func requestBytes(authority: String, path: String, body: Data) -> Data {
        var data = Data()
        data.append(clientPreface)
        data.append(settingsFrame())
        data.append(headersFrame(authority: authority, path: path))
        data.append(dataFrame(body))
        return data
    }

    static func settingsFrame() -> Data {
        HTTP2Frame(type: .settings, flags: 0, streamID: 0, payload: Data()).encoded()
    }

    static func settingsAckFrame() -> Data {
        HTTP2Frame(type: .settings, flags: HTTP2FrameFlags.ack, streamID: 0, payload: Data()).encoded()
    }

    static func headersFrame(authority: String, path: String) -> Data {
        var block = Data()
        block.append(0x83) // :method: POST
        block.append(0x86) // :scheme: http
        writeLiteralHeader(indexedName: 4, value: path, into: &block) // :path
        writeLiteralHeader(indexedName: 1, value: authority, into: &block) // :authority
        writeLiteralHeader(indexedName: 31, value: "application/grpc", into: &block) // content-type
        writeLiteralHeader(name: "te", value: "trailers", into: &block)
        return HTTP2Frame(type: .headers, flags: HTTP2FrameFlags.endHeaders, streamID: 1, payload: block).encoded()
    }

    static func dataFrame(_ body: Data) -> Data {
        HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: body).encoded()
    }

    private static func writeLiteralHeader(indexedName: Int, value: String, into data: inout Data) {
        writeHPACKInteger(UInt64(indexedName), prefixBits: 4, firstByteMask: 0x00, into: &data)
        writeHPACKString(value, into: &data)
    }

    private static func writeLiteralHeader(name: String, value: String, into data: inout Data) {
        data.append(0)
        writeHPACKString(name, into: &data)
        writeHPACKString(value, into: &data)
    }

    private static func writeHPACKString(_ value: String, into data: inout Data) {
        writeHPACKInteger(UInt64(value.utf8.count), prefixBits: 7, firstByteMask: 0x00, into: &data)
        data.append(contentsOf: value.utf8)
    }

    private static func writeHPACKInteger(_ value: UInt64, prefixBits: UInt8, firstByteMask: UInt8, into data: inout Data) {
        let maxPrefix = UInt64((1 << prefixBits) - 1)
        if value < maxPrefix {
            data.append(firstByteMask | UInt8(value))
            return
        }

        data.append(firstByteMask | UInt8(maxPrefix))
        var remainder = value - maxPrefix
        while remainder >= 128 {
            data.append(UInt8(remainder % 128) + 128)
            remainder /= 128
        }
        data.append(UInt8(remainder))
    }
}

struct HTTP2Frame: Equatable, Sendable {
    var type: HTTP2FrameType
    var flags: UInt8
    var streamID: UInt32
    var payload: Data

    func encoded() -> Data {
        var data = Data()
        let length = payload.count
        data.append(UInt8((length >> 16) & 0xff))
        data.append(UInt8((length >> 8) & 0xff))
        data.append(UInt8(length & 0xff))
        data.append(type.rawValue)
        data.append(flags)
        data.append(UInt8((streamID >> 24) & 0x7f))
        data.append(UInt8((streamID >> 16) & 0xff))
        data.append(UInt8((streamID >> 8) & 0xff))
        data.append(UInt8(streamID & 0xff))
        data.append(payload)
        return data
    }
}

enum HTTP2FrameType: UInt8, Sendable {
    case data = 0
    case headers = 1
    case rstStream = 3
    case settings = 4
    case ping = 6
    case goaway = 7
    case windowUpdate = 8
    case continuation = 9
    case unknown = 255

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .data
        case 1: self = .headers
        case 3: self = .rstStream
        case 4: self = .settings
        case 6: self = .ping
        case 7: self = .goaway
        case 8: self = .windowUpdate
        case 9: self = .continuation
        default: self = .unknown
        }
    }
}

enum HTTP2FrameFlags {
    static let endStream: UInt8 = 0x1
    static let ack: UInt8 = 0x1
    static let endHeaders: UInt8 = 0x4
}

struct HTTP2FrameParser {
    private static let maxFramePayloadBytes = 256 * 1024
    private var buffer = Data()

    mutating func append(_ data: Data) throws {
        buffer.append(data)
        guard buffer.count <= Self.maxFramePayloadBytes + 9 else {
            throw StarlinkStatusFetchError.responseTooLarge
        }
    }

    mutating func drainFrames() throws -> [HTTP2Frame] {
        var frames: [HTTP2Frame] = []
        var offset = 0

        while buffer.count - offset >= 9 {
            let length = (Int(byte(at: offset)) << 16) | (Int(byte(at: offset + 1)) << 8) | Int(byte(at: offset + 2))
            guard length <= Self.maxFramePayloadBytes else {
                throw StarlinkStatusFetchError.responseTooLarge
            }
            let totalLength = 9 + length
            guard buffer.count - offset >= totalLength else {
                break
            }

            let type = HTTP2FrameType(rawValue: byte(at: offset + 3))
            let flags = byte(at: offset + 4)
            let streamID = (UInt32(byte(at: offset + 5) & 0x7f) << 24)
                | (UInt32(byte(at: offset + 6)) << 16)
                | (UInt32(byte(at: offset + 7)) << 8)
                | UInt32(byte(at: offset + 8))
            let payloadStart = offset + 9
            let payloadStartIndex = buffer.index(buffer.startIndex, offsetBy: payloadStart)
            let payloadEndIndex = buffer.index(payloadStartIndex, offsetBy: length)
            let payload = Data(buffer[payloadStartIndex..<payloadEndIndex])
            frames.append(HTTP2Frame(type: type, flags: flags, streamID: streamID, payload: payload))
            offset += totalLength
        }

        if offset > 0 {
            let removalEnd = buffer.index(buffer.startIndex, offsetBy: offset)
            buffer.removeSubrange(buffer.startIndex..<removalEnd)
        }
        return frames
    }

    private func byte(at offset: Int) -> UInt8 {
        buffer[buffer.index(buffer.startIndex, offsetBy: offset)]
    }
}
