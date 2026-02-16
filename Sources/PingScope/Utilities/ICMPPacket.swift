import Foundation

/// ICMP header structure for echo request/reply packets.
/// Source: macOS icmp(4) man page, RFC 792
struct ICMPHeader {
    var type: UInt8
    var code: UInt8
    var checksum: UInt16
    var identifier: UInt16
    var sequenceNumber: UInt16

    static let echoRequest: UInt8 = 8
    static let echoReply: UInt8 = 0

    /// Size of ICMP header in bytes
    static let size: Int = 8
}

/// Calculate internet checksum per RFC 1071.
/// Used for ICMP header checksum calculation.
/// Source: Apple SimplePing, RFC 1071
func icmpChecksum(data: Data) -> UInt16 {
    var sum: UInt32 = 0
    var index = 0

    while index < data.count - 1 {
        let word = UInt32(data[index]) << 8 | UInt32(data[index + 1])
        sum += word
        index += 2
    }

    if index < data.count {
        sum += UInt32(data[index]) << 8
    }

    while sum >> 16 != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16)
    }

    return ~UInt16(sum)
}

extension ICMPHeader {
    /// Create an echo request header with the given identifier and sequence.
    /// Checksum is initially zero and must be computed after serialization.
    static func echoRequestHeader(identifier: UInt16, sequenceNumber: UInt16) -> ICMPHeader {
        ICMPHeader(
            type: echoRequest,
            code: 0,
            checksum: 0,
            identifier: identifier,
            sequenceNumber: sequenceNumber
        )
    }

    /// Serialize header to Data for transmission.
    /// All multi-byte fields use network byte order (big-endian).
    func toData() -> Data {
        var data = Data(count: ICMPHeader.size)
        data[0] = type
        data[1] = code
        data[2] = UInt8(checksum >> 8)
        data[3] = UInt8(checksum & 0xFF)
        data[4] = UInt8(identifier >> 8)
        data[5] = UInt8(identifier & 0xFF)
        data[6] = UInt8(sequenceNumber >> 8)
        data[7] = UInt8(sequenceNumber & 0xFF)
        return data
    }

    /// Parse header from received Data.
    /// Returns nil if data is too short.
    static func from(data: Data) -> ICMPHeader? {
        guard data.count >= ICMPHeader.size else { return nil }
        return ICMPHeader(
            type: data[0],
            code: data[1],
            checksum: UInt16(data[2]) << 8 | UInt16(data[3]),
            identifier: UInt16(data[4]) << 8 | UInt16(data[5]),
            sequenceNumber: UInt16(data[6]) << 8 | UInt16(data[7])
        )
    }
}
