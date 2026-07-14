import CloudKit
import Foundation
import PingScopeCore

public enum PingSampleRecordMapper {
    // These encodings intentionally match SQLiteHistoryStore: enum raw strings,
    // Int64 ports and booleans, Double milliseconds, enum raw strings, and JSON
    // text for structured metadata keep CloudKit and SQLite encodings stable.
    private static let maximumLatencyMilliseconds = 3_600_000.0
    private static let metadataEncoder = JSONEncoder()
    private static let metadataDecoder = JSONDecoder()

    public static func record(
        from result: PingResult,
        zoneID: CKRecordZone.ID = PingScopeCloudKitModel.zoneID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: PingScopeCloudKitModel.RecordType.pingSample,
            recordID: CKRecord.ID(recordName: result.id.uuidString, zoneID: zoneID)
        )
        let fields = PingScopeCloudKitModel.PingSampleField.self
        record[fields.hostID] = result.hostID.uuidString as CKRecordValue
        record[fields.address] = result.address as CKRecordValue
        record[fields.method] = result.method.rawValue as CKRecordValue
        if let port = result.port {
            record[fields.port] = Int64(port) as CKRecordValue
        }
        record[fields.timestamp] = result.timestamp as CKRecordValue
        if let latency = result.latency {
            record[fields.latencyMilliseconds] = latency.milliseconds as CKRecordValue
        }
        if let failureReason = result.failureReason {
            record[fields.failureReason] = failureReason.rawValue as CKRecordValue
        }
        if let note = result.metadata.note {
            record[fields.metadataNote] = note as CKRecordValue
        }
        if result.metadata.starlink != nil,
           let data = try? metadataEncoder.encode(result.metadata),
           let json = String(data: data, encoding: .utf8) {
            record[fields.metadataJSON] = json as CKRecordValue
        }
        if let networkInterface = result.networkInterface {
            record[fields.networkInterfaceTop] = networkInterface as CKRecordValue
        }
        if let networkName = result.networkName {
            record[fields.networkNameTop] = networkName as CKRecordValue
        }
        record[fields.isVPN] = Int64(result.isVPN ? 1 : 0) as CKRecordValue
        if let location = result.location {
            record[fields.latitude] = location.latitude as CKRecordValue
            record[fields.longitude] = location.longitude as CKRecordValue
            if let horizontalAccuracy = location.horizontalAccuracy {
                record[fields.horizontalAccuracy] = horizontalAccuracy as CKRecordValue
            }
            if let networkName = location.networkName {
                record[fields.networkName] = networkName as CKRecordValue
            }
            if let networkInterface = location.networkInterface {
                record[fields.networkInterface] = networkInterface as CKRecordValue
            }
        }
        return record
    }

    public static func pingResult(from record: CKRecord) -> PingResult? {
        guard record.recordType == PingScopeCloudKitModel.RecordType.pingSample,
              let id = UUID(uuidString: record.recordID.recordName) else {
            return nil
        }

        let fields = PingScopeCloudKitModel.PingSampleField.self
        guard let hostIDText = record[fields.hostID] as? String,
              let hostID = UUID(uuidString: hostIDText),
              let timestamp = record[fields.timestamp] as? Date else {
            return nil
        }

        let address = record[fields.address] as? String ?? ""
        let method = (record[fields.method] as? String).flatMap(PingMethod.init(rawValue:)) ?? .tcp
        let port = uint16(from: record[fields.port])
        let latency = latency(from: record[fields.latencyMilliseconds])
        let failureReason = (record[fields.failureReason] as? String).flatMap(FailureReason.init(rawValue:))
        let metadata = metadata(from: record)
        let location = location(from: record)

        return PingResult(
            id: id,
            hostID: hostID,
            address: address,
            method: method,
            port: port,
            timestamp: timestamp,
            latency: latency,
            failureReason: failureReason,
            metadata: metadata,
            location: location,
            networkInterface: record[fields.networkInterfaceTop] as? String,
            networkName: record[fields.networkNameTop] as? String,
            isVPN: (record[fields.isVPN] as? NSNumber)?.boolValue ?? false
        )
    }

    private static func uint16(from value: CKRecordValue?) -> UInt16? {
        guard let number = value as? NSNumber else { return nil }
        let rawValue = number.int64Value
        guard rawValue >= 0, rawValue <= Int64(UInt16.max) else { return nil }
        return UInt16(rawValue)
    }

    private static func latency(from value: CKRecordValue?) -> Duration? {
        guard let number = value as? NSNumber else { return nil }
        let milliseconds = number.doubleValue
        guard milliseconds.isFinite,
              milliseconds >= 0,
              milliseconds <= maximumLatencyMilliseconds else { return nil }
        return .milliseconds(milliseconds)
    }

    private static func metadata(from record: CKRecord) -> ProbeMetadata {
        let fields = PingScopeCloudKitModel.PingSampleField.self
        let note = record[fields.metadataNote] as? String
        if let json = record[fields.metadataJSON] as? String,
           let data = json.data(using: .utf8),
           let metadata = try? metadataDecoder.decode(ProbeMetadata.self, from: data) {
            return metadata
        }
        if let data = record[fields.metadataJSON] as? Data,
           let metadata = try? metadataDecoder.decode(ProbeMetadata.self, from: data) {
            return metadata
        }
        return ProbeMetadata(note: note)
    }

    private static func location(from record: CKRecord) -> SampleLocation? {
        let fields = PingScopeCloudKitModel.PingSampleField.self
        guard let latitude = (record[fields.latitude] as? NSNumber)?.doubleValue,
              let longitude = (record[fields.longitude] as? NSNumber)?.doubleValue else {
            return nil
        }
        let horizontalAccuracy = (record[fields.horizontalAccuracy] as? NSNumber)?.doubleValue
        return SampleLocation(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            networkName: record[fields.networkName] as? String,
            networkInterface: record[fields.networkInterface] as? String
        )
    }
}
