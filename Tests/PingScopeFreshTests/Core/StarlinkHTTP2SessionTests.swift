import XCTest
@testable import PingScopeCore

/// Exercises StarlinkHTTP2Session's frame handling end-to-end through
/// StarlinkHTTP2Transport.unary against a scripted loopback TCP server, since
/// the session itself is private to the transport.
final class StarlinkHTTP2SessionTests: XCTestCase {
    private func host(port: UInt16, timeout: Duration = .seconds(5)) -> HostConfig {
        HostConfig(
            displayName: "Dish",
            address: "127.0.0.1",
            method: .starlink,
            port: port,
            timeout: timeout
        )
    }

    private func grpcFrame(message: Data) -> Data {
        var frame = Data([0])
        var length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(message)
        return frame
    }

    func testAssemblesGRPCResponseSplitAcrossDataFrames() async throws {
        let message = Data((0..<64).map { UInt8($0) })
        let response = grpcFrame(message: message)
        let splitIndex = response.count / 2
        var wire = Data()
        wire.append(HTTP2Frame(type: .data, flags: 0, streamID: 1, payload: response.prefix(splitIndex)).encoded())
        wire.append(HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: response.suffix(from: splitIndex)).encoded())
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .respond(wire)))
        defer { server.shutdown() }

        let received = try await StarlinkHTTP2Transport().unary(
            path: "/SpaceX.API.Device.Device/Handle",
            requestFrame: grpcFrame(message: Data()),
            host: host(port: server.port)
        )

        XCTAssertEqual(received, response)
    }

    func testHandlesServerSettingsFrameBeforeResponse() async throws {
        let message = Data("status".utf8)
        let response = grpcFrame(message: message)
        var wire = Data()
        wire.append(HTTP2Frame(type: .settings, flags: 0, streamID: 0, payload: Data()).encoded())
        wire.append(HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: response).encoded())
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .respond(wire)))
        defer { server.shutdown() }

        let received = try await StarlinkHTTP2Transport().unary(
            path: "/test",
            requestFrame: grpcFrame(message: Data()),
            host: host(port: server.port)
        )

        XCTAssertEqual(received, response)
    }

    func testIgnoresDataFramesForOtherStreams() async throws {
        let message = Data("mine".utf8)
        let response = grpcFrame(message: message)
        var wire = Data()
        // A complete gRPC frame on the wrong stream must not satisfy stream 1.
        wire.append(HTTP2Frame(type: .data, flags: 0, streamID: 3, payload: grpcFrame(message: Data("other".utf8))).encoded())
        wire.append(HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: response).encoded())
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .respond(wire)))
        defer { server.shutdown() }

        let received = try await StarlinkHTTP2Transport().unary(
            path: "/test",
            requestFrame: grpcFrame(message: Data()),
            host: host(port: server.port)
        )

        XCTAssertEqual(received, response)
    }

    func testGoawayFrameFailsAsUnavailable() async throws {
        let wire = HTTP2Frame(type: .goaway, flags: 0, streamID: 0, payload: Data(count: 8)).encoded()
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .respond(wire)))
        defer { server.shutdown() }

        do {
            _ = try await StarlinkHTTP2Transport().unary(
                path: "/test",
                requestFrame: grpcFrame(message: Data()),
                host: host(port: server.port)
            )
            XCTFail("expected unary to throw")
        } catch let error as StarlinkStatusFetchError {
            XCTAssertEqual(error, .unavailable)
        }
    }

    func testConnectionClosedWithoutResponseFailsAsInvalidStatus() async throws {
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .drainThenClose))
        defer { server.shutdown() }

        do {
            _ = try await StarlinkHTTP2Transport().unary(
                path: "/test",
                requestFrame: grpcFrame(message: Data()),
                host: host(port: server.port)
            )
            XCTFail("expected unary to throw")
        } catch let error as StarlinkStatusFetchError {
            XCTAssertEqual(error, .invalidStatus)
        }
    }

    func testOversizedResponseFailsAsResponseTooLarge() async throws {
        // Declares a gRPC payload far beyond the 256KB cap, so the session can
        // never assemble a complete frame and must bail once the buffered data
        // crosses the cap instead of growing without bound.
        var oversized = Data([0])
        var declaredLength = UInt32(1_000_000).bigEndian
        withUnsafeBytes(of: &declaredLength) { oversized.append(contentsOf: $0) }
        var wire = Data()
        var remaining = 300 * 1024
        var first = true
        while remaining > 0 {
            let chunkSize = min(60 * 1024, remaining)
            var payload = Data(count: chunkSize)
            if first {
                payload.replaceSubrange(0..<oversized.count, with: oversized)
                first = false
            }
            wire.append(HTTP2Frame(type: .data, flags: 0, streamID: 1, payload: payload).encoded())
            remaining -= chunkSize
        }
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .respond(wire)))
        defer { server.shutdown() }

        do {
            _ = try await StarlinkHTTP2Transport().unary(
                path: "/test",
                requestFrame: grpcFrame(message: Data()),
                host: host(port: server.port)
            )
            XCTFail("expected unary to throw")
        } catch let error as StarlinkStatusFetchError {
            XCTAssertEqual(error, .responseTooLarge)
        }
    }

    func testSilentServerFailsAsTimedOut() async throws {
        // The server accepts and keeps the connection open without responding;
        // the transport must give up after host.timeout + 1s.
        let server = try XCTUnwrap(ScriptedHTTP2Server(behavior: .respond(Data())))
        defer { server.shutdown() }

        do {
            _ = try await StarlinkHTTP2Transport().unary(
                path: "/test",
                requestFrame: grpcFrame(message: Data()),
                host: host(port: server.port, timeout: .milliseconds(100))
            )
            XCTFail("expected unary to throw")
        } catch let error as StarlinkStatusFetchError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testUnaryResolvesWhenCancelledBeforeSessionInstall() async throws {
        for _ in 0..<32 {
            let requestFrame = grpcFrame(message: Data())
            let targetHost = host(port: 65_000)
            let task = Task {
                try await StarlinkHTTP2Transport().unary(
                    path: "/test",
                    requestFrame: requestFrame,
                    host: targetHost
                )
            }
            task.cancel()

            let resolved = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    do {
                        _ = try await task.value
                    } catch {}
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(2))
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }

            XCTAssertTrue(resolved, "cancelled Starlink HTTP/2 unary never resolved")
            guard resolved else { return }
        }
    }
}

/// A one-shot loopback TCP server that reads the client's request bytes and
/// then follows a scripted behavior, for driving the HTTP/2 session.
private final class ScriptedHTTP2Server: @unchecked Sendable {
    enum Behavior {
        /// Write these bytes, then keep the connection open (draining any
        /// further client writes) until the client hangs up.
        case respond(Data)
        /// Read the request, then close without sending anything.
        case drainThenClose
    }

    let port: UInt16
    private let listenFD: Int32
    private let behavior: Behavior
    private let queue = DispatchQueue(label: "pingscope.tests.scripted-http2-server")

    init?(behavior: Behavior) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(fd, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            close(fd)
            return nil
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                getsockname(fd, pointer, &length)
            }
        }
        let resolvedPort = UInt16(bigEndian: address.sin_port)
        guard resolvedPort != 0 else {
            close(fd)
            return nil
        }
        listenFD = fd
        port = resolvedPort
        self.behavior = behavior
        queue.async { [self] in serve() }
    }

    func shutdown() {
        close(listenFD)
    }

    private func serve() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        // Consume the client's request bytes before acting so behaviors are
        // ordered after the request, not racing it.
        _ = read(client, &buffer, buffer.count)
        switch behavior {
        case .respond(let data):
            writeAll(data, to: client)
            while read(client, &buffer, buffer.count) > 0 {}
            close(client)
        case .drainThenClose:
            close(client)
        }
    }

    private func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}
