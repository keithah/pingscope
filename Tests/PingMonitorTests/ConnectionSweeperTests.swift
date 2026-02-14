import Foundation
import Network
import XCTest
@testable import PingMonitor

final class ConnectionSweeperTests: XCTestCase {
    private var sweeper: ConnectionSweeper!

    override func setUp() async throws {
        sweeper = ConnectionSweeper(sweepInterval: .milliseconds(100), maxAge: .milliseconds(200))
    }

    override func tearDown() async throws {
        await sweeper.stopSweeping()
        await sweeper.cancelAll()
        sweeper = nil
    }

    func testRegisterIncrementsCount() async {
        let connection = NWConnection(host: "8.8.8.8", port: 443, using: .tcp)

        _ = await sweeper.register(connection)
        let count = await sweeper.activeCount

        XCTAssertEqual(count, 1)
        connection.cancel()
    }

    func testUnregisterDecrementsCount() async {
        let connection = NWConnection(host: "8.8.8.8", port: 443, using: .tcp)

        let id = await sweeper.register(connection)
        await sweeper.unregister(id)
        let count = await sweeper.activeCount

        XCTAssertEqual(count, 0)
        connection.cancel()
    }

    func testSweepCancelsOldConnections() async {
        let connection = NWConnection(host: "8.8.8.8", port: 443, using: .tcp)

        _ = await sweeper.register(connection)
        try? await Task.sleep(for: .milliseconds(250))

        await sweeper.sweep()
        let count = await sweeper.activeCount

        XCTAssertEqual(count, 0)
    }

    func testSweepKeepsRecentConnections() async {
        let connection = NWConnection(host: "8.8.8.8", port: 443, using: .tcp)

        _ = await sweeper.register(connection)
        await sweeper.sweep()

        let count = await sweeper.activeCount
        XCTAssertEqual(count, 1)

        connection.cancel()
        await sweeper.cancelAll()
    }

    func testCancelAllRemovesEverything() async {
        let first = NWConnection(host: "8.8.8.8", port: 443, using: .tcp)
        let second = NWConnection(host: "1.1.1.1", port: 443, using: .tcp)

        _ = await sweeper.register(first)
        _ = await sweeper.register(second)

        await sweeper.cancelAll()
        let count = await sweeper.activeCount

        XCTAssertEqual(count, 0)
    }

    func testAutomaticSweepingRemovesAgedConnections() async {
        await sweeper.startSweeping()

        let connection = NWConnection(host: "8.8.8.8", port: 443, using: .tcp)
        _ = await sweeper.register(connection)

        try? await Task.sleep(for: .milliseconds(450))

        let count = await sweeper.activeCount
        XCTAssertEqual(count, 0)
    }
}
