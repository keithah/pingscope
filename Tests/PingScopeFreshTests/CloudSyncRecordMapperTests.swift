import CloudKit
import XCTest
import PingScopeCore
@testable import PingScopeCloudSync

final class CloudSyncRecordMapperTests: XCTestCase {
    func testCloudKitModelConstantsAreStable() {
        XCTAssertEqual(PingScopeCloudKitModel.containerIdentifier, "iCloud.com.hadm.PingScope")
        XCTAssertEqual(PingScopeCloudKitModel.zoneName, "PingScopeHistory")
        XCTAssertEqual(PingScopeCloudKitModel.RecordType.pingSample, "PingSample")
        XCTAssertEqual(PingScopeCloudKitModel.RecordType.monitoredHost, "MonitoredHost")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.hostID, "hostID")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.address, "address")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.method, "method")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.port, "port")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.timestamp, "timestamp")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.latencyMilliseconds, "latencyMs")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.failureReason, "failureReason")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.metadataNote, "metadataNote")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.metadataJSON, "metadataJSON")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.latitude, "latitude")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.longitude, "longitude")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.horizontalAccuracy, "horizontalAccuracy")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.networkName, "networkName")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.networkInterface, "networkInterface")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.networkNameTop, "networkNameTop")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.networkInterfaceTop, "networkInterfaceTop")
        XCTAssertEqual(PingScopeCloudKitModel.PingSampleField.isVPN, "isVPN")
        XCTAssertEqual(PingScopeCloudKitModel.MonitoredHostField.configJSON, "configJSON")
        XCTAssertEqual(PingScopeCloudKitModel.MonitoredHostField.modifiedAt, "modifiedAt")
    }

    func testPingSampleRoundTripsLocatedSampleLosslessly() throws {
        let sample = PingResult(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            hostID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            address: "dish.example",
            method: .starlink,
            port: 9_200,
            timestamp: Date(timeIntervalSince1970: 1_750_000_000.125),
            latency: .milliseconds(42.75),
            failureReason: nil,
            metadata: ProbeMetadata(
                note: "connected",
                starlink: StarlinkTelemetry(
                    state: "CONNECTED",
                    popPingDropRate: 0.125,
                    activeAlerts: ["thermal"]
                )
            ),
            location: SampleLocation(
                latitude: 37.7749,
                longitude: -122.4194,
                horizontalAccuracy: 8.5,
                networkName: "Office Wi-Fi",
                networkInterface: "wifi"
            ),
            networkInterface: "wifi",
            networkName: "Office Wi-Fi",
            isVPN: true
        )

        let record = PingSampleRecordMapper.record(from: sample)
        let decoded = try XCTUnwrap(PingSampleRecordMapper.pingResult(from: record))

        XCTAssertEqual(record.recordID.recordName, sample.id.uuidString)
        XCTAssertEqual(record.recordID.zoneID, PingScopeCloudKitModel.zoneID)
        XCTAssertEqual(decoded, sample)
    }

    func testPingSampleRoundTripsUnlocatedSample() throws {
        let sample = PingResult(
            id: UUID(),
            hostID: UUID(),
            address: "1.1.1.1",
            method: .icmp,
            port: nil,
            timestamp: Date(timeIntervalSince1970: 2_000),
            latency: .milliseconds(7),
            failureReason: nil,
            location: nil,
            networkInterface: "cellular",
            networkName: "Cellular · 5G",
            isVPN: true
        )

        let decoded = try XCTUnwrap(PingSampleRecordMapper.pingResult(
            from: PingSampleRecordMapper.record(from: sample)
        ))

        XCTAssertEqual(decoded, sample)
        XCTAssertNil(decoded.location)
        XCTAssertEqual(decoded.networkInterface, "cellular")
        XCTAssertEqual(decoded.networkName, "Cellular · 5G")
        XCTAssertTrue(decoded.isVPN)
    }

    func testPingSampleRoundTripsFailure() throws {
        let sample = PingResult(
            id: UUID(),
            hostID: UUID(),
            address: "example.com",
            method: .https,
            port: 443,
            timestamp: Date(timeIntervalSince1970: 3_000),
            latency: nil,
            failureReason: .timeout,
            metadata: ProbeMetadata(note: "late")
        )

        let decoded = try XCTUnwrap(PingSampleRecordMapper.pingResult(
            from: PingSampleRecordMapper.record(from: sample)
        ))

        XCTAssertEqual(decoded, sample)
    }

    func testPingSampleRoundTripsAllOptionalNilValues() throws {
        let sample = PingResult(
            id: UUID(),
            hostID: UUID(),
            address: "",
            method: .tcp,
            port: nil,
            timestamp: Date(timeIntervalSince1970: 4_000),
            latency: nil,
            failureReason: nil,
            metadata: ProbeMetadata(),
            location: nil
        )

        let decoded = try XCTUnwrap(PingSampleRecordMapper.pingResult(
            from: PingSampleRecordMapper.record(from: sample)
        ))

        XCTAssertEqual(decoded, sample)
    }

    func testPingSampleDecodeKeepsRowWhenCoordinatesAreInvalid() throws {
        let sample = PingResult(
            id: UUID(),
            hostID: UUID(),
            address: "example.com",
            method: .tcp,
            port: 443,
            timestamp: Date(timeIntervalSince1970: 5_000),
            latency: .milliseconds(15),
            failureReason: nil
        )
        let record = PingSampleRecordMapper.record(from: sample)
        record[PingScopeCloudKitModel.PingSampleField.latitude] = 91 as CKRecordValue
        record[PingScopeCloudKitModel.PingSampleField.longitude] = -122 as CKRecordValue
        record[PingScopeCloudKitModel.PingSampleField.horizontalAccuracy] = -1 as CKRecordValue

        let decoded = try XCTUnwrap(PingSampleRecordMapper.pingResult(from: record))

        XCTAssertEqual(decoded.id, sample.id)
        XCTAssertEqual(decoded.hostID, sample.hostID)
        XCTAssertEqual(decoded.latency, sample.latency)
        XCTAssertNil(decoded.location)
    }

    func testPingSampleDecodeUsesDefaultsForPartialRecord() throws {
        let id = UUID()
        let hostID = UUID()
        let timestamp = Date(timeIntervalSince1970: 6_000)
        let record = CKRecord(
            recordType: PingScopeCloudKitModel.RecordType.pingSample,
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: PingScopeCloudKitModel.zoneID)
        )
        record[PingScopeCloudKitModel.PingSampleField.hostID] = hostID.uuidString as CKRecordValue
        record[PingScopeCloudKitModel.PingSampleField.timestamp] = timestamp as CKRecordValue

        let decoded = try XCTUnwrap(PingSampleRecordMapper.pingResult(from: record))

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.hostID, hostID)
        XCTAssertEqual(decoded.timestamp, timestamp)
        XCTAssertEqual(decoded.address, "")
        XCTAssertEqual(decoded.method, .tcp)
        XCTAssertNil(decoded.port)
        XCTAssertNil(decoded.latency)
        XCTAssertNil(decoded.failureReason)
        XCTAssertEqual(decoded.metadata, ProbeMetadata())
        XCTAssertNil(decoded.location)
        XCTAssertNil(decoded.networkInterface)
        XCTAssertNil(decoded.networkName)
        XCTAssertFalse(decoded.isVPN)
    }

    func testPingSampleDecodeRejectsMissingRequiredFields() {
        let id = UUID()
        let record = CKRecord(
            recordType: PingScopeCloudKitModel.RecordType.pingSample,
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: PingScopeCloudKitModel.zoneID)
        )
        record[PingScopeCloudKitModel.PingSampleField.timestamp] = Date() as CKRecordValue
        XCTAssertNil(PingSampleRecordMapper.pingResult(from: record))

        record[PingScopeCloudKitModel.PingSampleField.hostID] = UUID().uuidString as CKRecordValue
        record[PingScopeCloudKitModel.PingSampleField.timestamp] = nil
        XCTAssertNil(PingSampleRecordMapper.pingResult(from: record))
    }

    func testMonitoredHostRoundTripsConfigAndModifiedDate() throws {
        let host = HostConfig(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            displayName: "ISP edge",
            address: "192.0.2.1",
            tier: .ispEdge,
            method: .udp,
            port: 53,
            interval: .milliseconds(750),
            timeout: .milliseconds(1_250),
            thresholds: LatencyThresholds(degradedMilliseconds: 83.5, downAfterFailures: 4),
            isEnabled: false,
            notifications: .enabled
        )
        let modifiedAt = Date(timeIntervalSince1970: 1_750_123_456.5)

        let record = try MonitoredHostRecordMapper.record(from: host, modifiedAt: modifiedAt)
        let decoded = try XCTUnwrap(MonitoredHostRecordMapper.monitoredHost(from: record))

        XCTAssertEqual(record.recordID.recordName, host.id.uuidString)
        XCTAssertEqual(record.recordID.zoneID, PingScopeCloudKitModel.zoneID)
        XCTAssertEqual(decoded.config, host)
        XCTAssertEqual(decoded.modifiedAt, modifiedAt)
    }

    func testMonitoredHostDecodeRejectsMalformedRecords() throws {
        let id = UUID()
        let record = CKRecord(
            recordType: PingScopeCloudKitModel.RecordType.monitoredHost,
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: PingScopeCloudKitModel.zoneID)
        )
        record[PingScopeCloudKitModel.MonitoredHostField.configJSON] = Data("not json".utf8) as CKRecordValue
        record[PingScopeCloudKitModel.MonitoredHostField.modifiedAt] = Date() as CKRecordValue
        XCTAssertNil(MonitoredHostRecordMapper.monitoredHost(from: record))

        record[PingScopeCloudKitModel.MonitoredHostField.configJSON] = try JSONEncoder().encode(
            HostConfig(id: UUID(), displayName: "Wrong ID", address: "example.com")
        ) as CKRecordValue
        XCTAssertNil(MonitoredHostRecordMapper.monitoredHost(from: record))
    }

    func testMonitoredHostMapperIsNaNSafe() throws {
        let host = HostConfig(
            displayName: "Legacy thresholds",
            address: "example.com",
            thresholds: LatencyThresholds(degradedMilliseconds: .nan, downAfterFailures: 3)
        )

        let record = try MonitoredHostRecordMapper.record(from: host, modifiedAt: .now)
        let decoded = try XCTUnwrap(MonitoredHostRecordMapper.monitoredHost(from: record))
        XCTAssertTrue(decoded.config.thresholds.degradedMilliseconds.isNaN)
        XCTAssertEqual(decoded.config.thresholds.downAfterFailures, 3)
    }
}
