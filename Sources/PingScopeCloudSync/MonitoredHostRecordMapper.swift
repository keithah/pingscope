import CloudKit
import Foundation
import PingScopeCore

public struct MonitoredHostRecord: Equatable, Sendable {
    public let config: HostConfig
    public let modifiedAt: Date

    public init(config: HostConfig, modifiedAt: Date) {
        self.config = config
        self.modifiedAt = modifiedAt
    }
}

public enum MonitoredHostRecordMapper {
    public static func record(
        from config: HostConfig,
        modifiedAt: Date,
        zoneID: CKRecordZone.ID = PingScopeCloudKitModel.zoneID
    ) throws -> CKRecord {
        let record = CKRecord(
            recordType: PingScopeCloudKitModel.RecordType.monitoredHost,
            recordID: CKRecord.ID(recordName: config.id.uuidString, zoneID: zoneID)
        )
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        record[PingScopeCloudKitModel.MonitoredHostField.configJSON] = try encoder.encode(config) as CKRecordValue
        record[PingScopeCloudKitModel.MonitoredHostField.modifiedAt] = modifiedAt as CKRecordValue
        return record
    }

    public static func monitoredHost(from record: CKRecord) -> MonitoredHostRecord? {
        guard record.recordType == PingScopeCloudKitModel.RecordType.monitoredHost,
              let id = UUID(uuidString: record.recordID.recordName),
              let data = record[PingScopeCloudKitModel.MonitoredHostField.configJSON] as? Data,
              let modifiedAt = record[PingScopeCloudKitModel.MonitoredHostField.modifiedAt] as? Date,
              let config = try? hostDecoder().decode(HostConfig.self, from: data),
              config.id == id else {
            return nil
        }
        return MonitoredHostRecord(config: config, modifiedAt: modifiedAt)
    }

    private static func hostDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
