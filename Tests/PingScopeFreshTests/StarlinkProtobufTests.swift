import Foundation
import XCTest
@testable import PingScopeCore

final class StarlinkProtobufTests: XCTestCase {
    func testEncodesGetStatusRequestFrame() throws {
        let codec = StarlinkProtobufCodec()

        let message = codec.makeGetStatusRequestMessage()
        let frame = codec.makeGetStatusGRPCFrame()

        XCTAssertEqual([UInt8](message), [0xE2, 0x3E, 0x00])
        XCTAssertEqual(frame.count, 8)
        XCTAssertEqual([UInt8](frame.prefix(5)), [0, 0, 0, 0, 3])
        XCTAssertEqual(Data(frame.dropFirst(5)), message)
    }

    func testDecodesModernDishStatusFromGRPCFrame() throws {
        let codec = StarlinkProtobufCodec()
        let response = makeResponse(
            latency: 42.25,
            dropRate: 0.125,
            downlink: 80_000_000,
            uplink: 12_000_000,
            deviceInfo: makeDeviceInfo(hardwareVersion: "rev4", softwareVersion: "2026.06", countryCode: "US"),
            deviceState: makeDeviceState(uptime: 3_600),
            obstructionStats: makeObstructionStats(fraction: 0.03125, obstructedSeconds: 45, currentlyObstructed: true),
            alerts: makeAlerts([3, 6, 18])
        )

        let status = try codec.decodeStatus(fromGRPCFrame: codec.makeGRPCFrame(message: response))

        XCTAssertEqual(status.popPingLatencyMilliseconds ?? 0, 42.25, accuracy: 0.001)
        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.telemetry.state, "CONNECTED")
        XCTAssertEqual(status.telemetry.popPingDropRate ?? 0, 0.125, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.downlinkThroughputBps ?? 0, 80_000_000, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.uplinkThroughputBps ?? 0, 12_000_000, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.fractionObstructed ?? 0, 0.03125, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.last24hObstructedSeconds ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.uptimeSeconds ?? 0, 3_600, accuracy: 0.001)
        XCTAssertEqual(status.telemetry.hardwareVersion, "rev4")
        XCTAssertEqual(status.telemetry.softwareVersion, "2026.06")
        XCTAssertEqual(status.telemetry.countryCode, "US")
        XCTAssertEqual(status.telemetry.activeAlerts, ["obstructed", "slow_ethernet_speeds", "slow_ethernet_speeds_100", "thermal_throttle"])
    }

    func testDecodesOldDishStateWhenFirmwareProvidesIt() throws {
        let codec = StarlinkProtobufCodec()
        let response = makeResponse(latency: nil, dropRate: 1, oldDishState: 2)

        let status = try codec.decodeStatus(fromResponseMessage: response)

        XCTAssertEqual(status.telemetry.state, "SEARCHING")
        XCTAssertFalse(status.isConnected)
    }

    func testInfersOutageStateWhenLatencyIsAbsent() throws {
        let codec = StarlinkProtobufCodec()
        let response = makeResponse(latency: nil, dropRate: nil, outage: makeOutage(cause: 6))

        let status = try codec.decodeStatus(fromResponseMessage: response)

        XCTAssertEqual(status.telemetry.state, "OBSTRUCTED")
        XCTAssertFalse(status.isConnected)
    }

    func testRejectsInvalidPayloads() {
        let codec = StarlinkProtobufCodec()

        XCTAssertThrowsError(try codec.decodeStatus(fromGRPCFrame: Data([1, 0, 0, 0, 0])))
        XCTAssertThrowsError(try codec.decodeStatus(fromResponseMessage: Data()))
    }

    /// The decoder runs on bytes received over plain TCP from a user-configured
    /// address, so hostile lengths and field numbers must throw, never trap.
    func testRejectsHostileVarintsWithoutTrapping() {
        let codec = StarlinkProtobufCodec()

        // Field 1, wire type 2, followed by a length varint of UInt64.max:
        // narrowing that to Int trapped before it could be bounds-checked.
        let overflowingLength = Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        XCTAssertThrowsError(try codec.decodeStatus(fromResponseMessage: overflowingLength))

        // Length == Int.max is representable, but `offset + length` overflowed
        // before the bounds guard could reject it.
        let intMaxLength = Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertThrowsError(try codec.decodeStatus(fromResponseMessage: intMaxLength))

        // A field key whose number exceeds Int32.max.
        let hugeFieldNumber = Data([0xF8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00])
        XCTAssertThrowsError(try codec.decodeStatus(fromResponseMessage: hugeFieldNumber))
    }

    func testLengthDelimitedFieldsExposeSlicesWithoutCopyingPayload() throws {
        var writer = ProtobufWriter()
        writer.writeString(field: 1, "hello")

        var reader = ProtobufReader(data: writer.data)
        let field = try XCTUnwrap(reader.nextField())

        guard case let .lengthDelimited(payload) = field.value else {
            return XCTFail("expected length-delimited payload")
        }
        XCTAssertTrue(type(of: payload) == Data.SubSequence.self)
        XCTAssertEqual(String(decoding: payload, as: UTF8.self), "hello")
    }

    private func makeResponse(
        latency: Float?,
        dropRate: Float?,
        downlink: Float? = nil,
        uplink: Float? = nil,
        oldDishState: UInt64? = nil,
        deviceInfo: Data? = nil,
        deviceState: Data? = nil,
        obstructionStats: Data? = nil,
        alerts: Data? = nil,
        outage: Data? = nil
    ) -> Data {
        var dish = ProtobufWriter()
        if let deviceInfo {
            dish.writeLengthDelimited(field: 1, deviceInfo)
        }
        if let deviceState {
            dish.writeLengthDelimited(field: 2, deviceState)
        }
        if let dropRate {
            dish.writeFixed32(field: 1003, dropRate)
        }
        if let obstructionStats {
            dish.writeLengthDelimited(field: 1004, obstructionStats)
        }
        if let alerts {
            dish.writeLengthDelimited(field: 1005, alerts)
        }
        if let oldDishState {
            dish.writeVarint(field: 1006, oldDishState)
        }
        if let downlink {
            dish.writeFixed32(field: 1007, downlink)
        }
        if let uplink {
            dish.writeFixed32(field: 1008, uplink)
        }
        if let latency {
            dish.writeFixed32(field: 1009, latency)
        }
        if let outage {
            dish.writeLengthDelimited(field: 1014, outage)
        }

        var response = ProtobufWriter()
        response.writeLengthDelimited(field: 2004, dish.data)
        return response.data
    }

    private func makeDeviceInfo(hardwareVersion: String, softwareVersion: String, countryCode: String) -> Data {
        var writer = ProtobufWriter()
        writer.writeString(field: 2, hardwareVersion)
        writer.writeString(field: 3, softwareVersion)
        writer.writeString(field: 4, countryCode)
        return writer.data
    }

    private func makeDeviceState(uptime: UInt64) -> Data {
        var writer = ProtobufWriter()
        writer.writeVarint(field: 1, uptime)
        return writer.data
    }

    private func makeObstructionStats(fraction: Float, obstructedSeconds: Float, currentlyObstructed: Bool) -> Data {
        var writer = ProtobufWriter()
        writer.writeFixed32(field: 1, fraction)
        writer.writeBool(field: 5, currentlyObstructed)
        writer.writeFixed32(field: 9, obstructedSeconds)
        return writer.data
    }

    private func makeAlerts(_ fields: [Int]) -> Data {
        var writer = ProtobufWriter()
        for field in fields {
            writer.writeBool(field: field, true)
        }
        return writer.data
    }

    private func makeOutage(cause: UInt64) -> Data {
        var writer = ProtobufWriter()
        writer.writeVarint(field: 1, cause)
        return writer.data
    }
}
