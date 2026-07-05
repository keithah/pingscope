import Foundation

public struct StarlinkProtobufCodec: Sendable {
    private static let getStatusField = 1004
    private static let dishGetStatusField = 2004

    public init() {}

    public func makeGetStatusRequestMessage() -> Data {
        var writer = ProtobufWriter()
        writer.writeLengthDelimited(field: Self.getStatusField, Data())
        return writer.data
    }

    public func makeGetStatusGRPCFrame() -> Data {
        makeGRPCFrame(message: makeGetStatusRequestMessage())
    }

    public func makeGRPCFrame(message: Data) -> Data {
        var frame = Data()
        frame.append(0)
        let length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: length) { bytes in
            frame.append(contentsOf: bytes)
        }
        frame.append(message)
        return frame
    }

    public func decodeStatus(fromGRPCFrame frame: Data) throws -> StarlinkStatus {
        try decodeStatus(fromResponseBytes: decodeGRPCMessage(from: frame))
    }

    public func decodeStatus(fromResponseMessage response: Data) throws -> StarlinkStatus {
        try decodeStatus(fromResponseBytes: response[...])
    }

    private func decodeStatus(fromResponseBytes response: Data.SubSequence) throws -> StarlinkStatus {
        var reader = ProtobufReader(data: response)
        var dishStatus: Data.SubSequence?

        while let field = try reader.nextField() {
            if field.number == Self.dishGetStatusField, case let .lengthDelimited(data) = field.value {
                dishStatus = data
            }
        }

        guard let dishStatus else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        return try decodeDishStatus(dishStatus)
    }

    private func decodeGRPCMessage(from frame: Data) throws -> Data.SubSequence {
        guard frame.count >= 5 else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        guard frame.byte(at: 0) == 0 else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        let length = (Int(frame.byte(at: 1)) << 24)
            | (Int(frame.byte(at: 2)) << 16)
            | (Int(frame.byte(at: 3)) << 8)
            | Int(frame.byte(at: 4))
        guard length >= 0, frame.count >= 5 + length else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        let payloadStart = frame.index(frame.startIndex, offsetBy: 5)
        let payloadEnd = frame.index(payloadStart, offsetBy: length)
        return frame[payloadStart..<payloadEnd]
    }

    private func decodeDishStatus(_ data: Data.SubSequence) throws -> StarlinkStatus {
        var reader = ProtobufReader(data: data)
        var telemetry = StarlinkTelemetry()
        var latencyMilliseconds: Double?
        var state: String?
        var outageCause: String?

        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, .lengthDelimited(let value)):
                let deviceInfo = try decodeDeviceInfo(value)
                telemetry.hardwareVersion = deviceInfo.hardwareVersion
                telemetry.softwareVersion = deviceInfo.softwareVersion
                telemetry.countryCode = deviceInfo.countryCode
            case (2, .lengthDelimited(let value)):
                telemetry.uptimeSeconds = try decodeDeviceState(value)
            case (1003, .fixed32(let value)):
                telemetry.popPingDropRate = Double(Float(bitPattern: value))
            case (1004, .lengthDelimited(let value)):
                let obstruction = try decodeObstructionStats(value)
                telemetry.fractionObstructed = obstruction.fractionObstructed
                telemetry.last24hObstructedSeconds = obstruction.obstructedSeconds
                if obstruction.currentlyObstructed {
                    telemetry.activeAlerts.append("obstructed")
                }
            case (1005, .lengthDelimited(let value)):
                telemetry.activeAlerts.append(contentsOf: try decodeAlerts(value))
            case (1006, .varint(let value)):
                state = oldDishStateName(value)
            case (1007, .fixed32(let value)):
                telemetry.downlinkThroughputBps = Double(Float(bitPattern: value))
            case (1008, .fixed32(let value)):
                telemetry.uplinkThroughputBps = Double(Float(bitPattern: value))
            case (1009, .fixed32(let value)):
                latencyMilliseconds = Double(Float(bitPattern: value))
            case (1014, .lengthDelimited(let value)):
                outageCause = try decodeOutageCause(value)
            default:
                break
            }
        }

        telemetry.activeAlerts = Array(Set(telemetry.activeAlerts)).sorted()
        telemetry.state = state ?? inferredState(latencyMilliseconds: latencyMilliseconds, dropRate: telemetry.popPingDropRate, outageCause: outageCause)
        return StarlinkStatus(popPingLatencyMilliseconds: latencyMilliseconds, telemetry: telemetry)
    }

    private func decodeDeviceInfo(_ data: Data.SubSequence) throws -> (hardwareVersion: String?, softwareVersion: String?, countryCode: String?) {
        var reader = ProtobufReader(data: data)
        var hardwareVersion: String?
        var softwareVersion: String?
        var countryCode: String?

        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (2, .lengthDelimited(let value)):
                hardwareVersion = String(bytes: value, encoding: .utf8)
            case (3, .lengthDelimited(let value)):
                softwareVersion = String(bytes: value, encoding: .utf8)
            case (4, .lengthDelimited(let value)):
                countryCode = String(bytes: value, encoding: .utf8)
            default:
                break
            }
        }
        return (hardwareVersion, softwareVersion, countryCode)
    }

    private func decodeDeviceState(_ data: Data.SubSequence) throws -> Double? {
        var reader = ProtobufReader(data: data)
        while let field = try reader.nextField() {
            if field.number == 1, case let .varint(value) = field.value {
                return Double(value)
            }
        }
        return nil
    }

    private func decodeObstructionStats(_ data: Data.SubSequence) throws -> (fractionObstructed: Double?, obstructedSeconds: Double?, currentlyObstructed: Bool) {
        var reader = ProtobufReader(data: data)
        var fractionObstructed: Double?
        var obstructedSeconds: Double?
        var currentlyObstructed = false

        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, .fixed32(let value)):
                fractionObstructed = Double(Float(bitPattern: value))
            case (5, .varint(let value)):
                currentlyObstructed = value != 0
            case (9, .fixed32(let value)):
                obstructedSeconds = Double(Float(bitPattern: value))
            case (1006, .fixed32(let value)):
                obstructedSeconds = Double(Float(bitPattern: value))
            default:
                break
            }
        }
        return (fractionObstructed, obstructedSeconds, currentlyObstructed)
    }

    private func decodeAlerts(_ data: Data.SubSequence) throws -> [String] {
        let names: [Int: String] = [
            1: "motors_stuck",
            2: "thermal_shutdown",
            3: "thermal_throttle",
            4: "unexpected_location",
            5: "mast_not_near_vertical",
            6: "slow_ethernet_speeds",
            7: "roaming",
            8: "install_pending",
            9: "is_heating",
            10: "power_supply_thermal_throttle",
            11: "is_power_save_idle",
            12: "moving_while_not_mobile",
            14: "dbf_telem_stale",
            15: "moving_too_fast_for_policy",
            16: "low_motor_current",
            17: "lower_signal_than_predicted",
            18: "slow_ethernet_speeds_100"
        ]
        var reader = ProtobufReader(data: data)
        var active: [String] = []
        while let field = try reader.nextField() {
            if case let .varint(value) = field.value, value != 0, let name = names[field.number] {
                active.append(name)
            }
        }
        return active
    }

    private func decodeOutageCause(_ data: Data.SubSequence) throws -> String? {
        var reader = ProtobufReader(data: data)
        while let field = try reader.nextField() {
            if field.number == 1, case let .varint(value) = field.value {
                return outageCauseName(value)
            }
        }
        return nil
    }

    private func oldDishStateName(_ value: UInt64) -> String? {
        switch value {
        case 1: "CONNECTED"
        case 2: "SEARCHING"
        case 3: "BOOTING"
        case 0: "UNKNOWN"
        default: nil
        }
    }

    private func outageCauseName(_ value: UInt64) -> String? {
        switch value {
        case 1: "BOOTING"
        case 2: "STOWED"
        case 3: "THERMAL_SHUTDOWN"
        case 4: "NO_SCHEDULE"
        case 5: "NO_SATS"
        case 6: "OBSTRUCTED"
        case 7: "NO_DOWNLINK"
        case 8: "NO_PINGS"
        case 9: "ACTUATOR_ACTIVITY"
        case 10: "CABLE_TEST"
        case 11: "SLEEPING"
        case 12: "MOVING_WHILE_NOT_ALLOWED"
        default: nil
        }
    }

    private func inferredState(latencyMilliseconds: Double?, dropRate: Double?, outageCause: String?) -> String? {
        if let outageCause, outageCause != "UNKNOWN" {
            return outageCause
        }
        guard let latencyMilliseconds, latencyMilliseconds >= 0 else {
            return nil
        }
        if let dropRate, dropRate >= 1 {
            return "NO_PINGS"
        }
        return "CONNECTED"
    }
}

struct ProtobufWriter {
    private(set) var data = Data()

    mutating func writeVarint(field: Int, _ value: UInt64) {
        writeKey(field: field, wireType: 0)
        writeVarint(value)
    }

    mutating func writeBool(field: Int, _ value: Bool) {
        writeVarint(field: field, value ? 1 : 0)
    }

    mutating func writeFixed32(field: Int, _ value: Float) {
        writeKey(field: field, wireType: 5)
        let bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: bits) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    mutating func writeString(field: Int, _ value: String) {
        writeLengthDelimited(field: field, Data(value.utf8))
    }

    mutating func writeLengthDelimited(field: Int, _ value: Data) {
        writeKey(field: field, wireType: 2)
        writeVarint(UInt64(value.count))
        data.append(value)
    }

    private mutating func writeKey(field: Int, wireType: UInt64) {
        writeVarint((UInt64(field) << 3) | wireType)
    }

    private mutating func writeVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7f) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}

struct ProtobufField {
    var number: Int
    var value: ProtobufValue
}

enum ProtobufValue {
    case varint(UInt64)
    case fixed32(UInt32)
    case fixed64(UInt64)
    case lengthDelimited(Data.SubSequence)
}

struct ProtobufReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func nextField() throws -> ProtobufField? {
        guard offset < data.count else {
            return nil
        }
        // These bytes arrive over plain TCP from a user-configured address, so a
        // malformed or hostile payload must throw, never trap. Validate every
        // varint before narrowing it to Int or using it in index arithmetic.
        let key = try readVarint()
        let rawNumber = key >> 3
        let wireType = Int(key & 0x7)
        guard rawNumber > 0, rawNumber <= UInt64(Int32.max) else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        let number = Int(rawNumber)

        switch wireType {
        case 0:
            return ProtobufField(number: number, value: .varint(try readVarint()))
        case 1:
            return ProtobufField(number: number, value: .fixed64(try readFixed64()))
        case 2:
            let rawLength = try readVarint()
            // Bounds-check against the remaining bytes before converting: a
            // length above Int.max traps in Int(_:), and `offset + length`
            // overflow-traps before a post-hoc guard could reject it.
            guard rawLength <= UInt64(data.count - offset) else {
                throw StarlinkStatusFetchError.invalidStatus
            }
            let length = Int(rawLength)
            let start = data.index(data.startIndex, offsetBy: offset)
            let end = data.index(start, offsetBy: length)
            let value = data[start..<end]
            offset += length
            return ProtobufField(number: number, value: .lengthDelimited(value))
        case 5:
            return ProtobufField(number: number, value: .fixed32(try readFixed32()))
        default:
            throw StarlinkStatusFetchError.invalidStatus
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 64 {
            guard offset < data.count else {
                throw StarlinkStatusFetchError.invalidStatus
            }
            let byte = data.byte(at: offset)
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw StarlinkStatusFetchError.invalidStatus
    }

    private mutating func readFixed32() throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        let value = UInt32(data.byte(at: offset))
            | (UInt32(data.byte(at: offset + 1)) << 8)
            | (UInt32(data.byte(at: offset + 2)) << 16)
            | (UInt32(data.byte(at: offset + 3)) << 24)
        offset += 4
        return value
    }

    private mutating func readFixed64() throws -> UInt64 {
        guard offset + 8 <= data.count else {
            throw StarlinkStatusFetchError.invalidStatus
        }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data.byte(at: offset + index)) << UInt64(index * 8)
        }
        offset += 8
        return value
    }
}

private extension Data {
    func byte(at offset: Int) -> UInt8 {
        self[index(startIndex, offsetBy: offset)]
    }
}
