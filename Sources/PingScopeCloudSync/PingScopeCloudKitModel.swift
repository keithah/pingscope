import CloudKit

public enum PingScopeCloudKitModel {
    public static let containerIdentifier = "iCloud.com.hadm.PingScope"
    public static let zoneName = "PingScopeHistory"
    public static let zoneID = CKRecordZone.ID(zoneName: zoneName)

    public enum RecordType {
        public static let pingSample = "PingSample"
        public static let monitoredHost = "MonitoredHost"
    }

    public enum PingSampleField {
        public static let hostID = "hostID"
        public static let address = "address"
        public static let method = "method"
        public static let port = "port"
        public static let timestamp = "timestamp"
        public static let latencyMilliseconds = "latencyMs"
        public static let failureReason = "failureReason"
        public static let metadataNote = "metadataNote"
        public static let metadataJSON = "metadataJSON"
        public static let latitude = "latitude"
        public static let longitude = "longitude"
        public static let horizontalAccuracy = "horizontalAccuracy"
        public static let networkName = "networkName"
        public static let networkInterface = "networkInterface"
        public static let networkNameTop = "networkNameTop"
        public static let networkInterfaceTop = "networkInterfaceTop"
        public static let isVPN = "isVPN"
    }

    public enum MonitoredHostField {
        public static let configJSON = "configJSON"
        public static let modifiedAt = "modifiedAt"
    }
}
