import Foundation
import XCTest
@testable import PingScopeCore

final class StarlinkHTTP2TransportTests: XCTestCase {
    func testRequestBuilderUsesHTTP2PriorKnowledgeAndGRPCHeaders() throws {
        let body = StarlinkProtobufCodec().makeGetStatusGRPCFrame()

        let request = StarlinkHTTP2RequestBuilder.requestBytes(
            authority: "192.168.100.1:9200",
            path: StarlinkStatusGRPCClient.statusPath,
            body: body
        )

        XCTAssertTrue(request.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))

        var parser = HTTP2FrameParser()
        try parser.append(Data(request.dropFirst(24)))
        let frames = try parser.drainFrames()

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].type, .settings)
        XCTAssertEqual(frames[0].streamID, 0)
        XCTAssertEqual(frames[1].type, .headers)
        XCTAssertEqual(frames[1].flags, HTTP2FrameFlags.endHeaders)
        XCTAssertEqual(frames[1].streamID, 1)
        XCTAssertTrue(frames[1].payload.contains(Data(StarlinkStatusGRPCClient.statusPath.utf8)))
        XCTAssertTrue(frames[1].payload.contains(Data("192.168.100.1:9200".utf8)))
        XCTAssertTrue(frames[1].payload.contains(Data("application/grpc".utf8)))
        XCTAssertTrue(frames[1].payload.contains(Data("trailers".utf8)))
        XCTAssertEqual(frames[2].type, .data)
        XCTAssertEqual(frames[2].flags, HTTP2FrameFlags.endStream)
        XCTAssertEqual(frames[2].streamID, 1)
        XCTAssertEqual(frames[2].payload, body)
    }

    func testFrameParserRetainsPartialFramesUntilComplete() throws {
        let frame = HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: Data([1, 2, 3, 4])).encoded()
        var parser = HTTP2FrameParser()

        try parser.append(Data(frame.prefix(10)))
        XCTAssertEqual(try parser.drainFrames(), [])

        try parser.append(Data(frame.dropFirst(10)))
        let frames = try parser.drainFrames()

        XCTAssertEqual(frames, [HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: Data([1, 2, 3, 4]))])
    }

    func testSettingsAckFrameHasAckFlag() throws {
        var parser = HTTP2FrameParser()
        try parser.append(StarlinkHTTP2RequestBuilder.settingsAckFrame())

        let frame = try XCTUnwrap(try parser.drainFrames().first)

        XCTAssertEqual(frame.type, .settings)
        XCTAssertEqual(frame.flags, HTTP2FrameFlags.ack)
        XCTAssertEqual(frame.streamID, 0)
        XCTAssertTrue(frame.payload.isEmpty)
    }

    func testFrameParserRejectsOversizedFramesBeforeRetainingPayload() throws {
        let oversizedPayload = Data(repeating: 0xff, count: 256 * 1024 + 1)
        let frame = HTTP2Frame(type: .data, flags: HTTP2FrameFlags.endStream, streamID: 1, payload: oversizedPayload).encoded()
        var parser = HTTP2FrameParser()

        XCTAssertThrowsError(try parser.append(frame)) { error in
            XCTAssertEqual(error as? StarlinkStatusFetchError, .responseTooLarge)
        }
    }
}
