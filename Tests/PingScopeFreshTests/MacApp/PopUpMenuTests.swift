@testable import PingScope
import AppKit
import PingScopeCore
import SwiftUI
import XCTest

@MainActor
final class PopUpMenuTests: XCTestCase {
    private func titles(_ menu: NSMenu?) -> [String] {
        menu?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? []
    }

    private func choose(_ title: String, in menu: NSMenu?, file: StaticString = #filePath, line: UInt = #line) {
        guard let menu, let index = menu.items.firstIndex(where: { $0.title == title }) else {
            XCTFail("no item titled \(title)", file: file, line: line)
            return
        }
        menu.performActionForItem(at: index)
    }

    func testSettingsMenuForAllHostsEndsWithQuit() {
        let menu = StatusPopoverMenus.settings(displayMode: .signal, intervalHost: nil, actions: .init())

        XCTAssertEqual(titles(menu), ["Display style", "-", "Open History", "Open Settings", "-", "Quit PingScope"])
    }

    func testSettingsMenuForOneHostOffersItsPingInterval() {
        let host = HostConfig(displayName: "Edge", address: "192.0.2.1", interval: .seconds(5))
        let menu = StatusPopoverMenus.settings(displayMode: .signal, intervalHost: host, actions: .init())
        let interval = menu.item(withTitle: "Ping interval")?.submenu

        XCTAssertEqual(
            titles(menu),
            ["Display style", "-", "Ping interval", "-", "Open History", "Open Settings", "-", "Quit PingScope"]
        )
        XCTAssertEqual(titles(interval), ["1s", "2s", "5s", "10s", "30s"])
        XCTAssertEqual(interval?.items.filter { $0.state == .on }.map(\.title), ["5s"])
    }

    func testDisplayStyleSubmenuChecksTheCurrentMode() {
        let menu = StatusPopoverMenus.settings(displayMode: .ring, intervalHost: nil, actions: .init())
        let styles = menu.item(withTitle: "Display style")?.submenu

        XCTAssertEqual(titles(styles), PingScopeDisplayMode.allCases.map(\.displayName))
        XCTAssertEqual(styles?.items.filter { $0.state == .on }.map(\.title), [PingScopeDisplayMode.ring.displayName])
    }

    func testEverySettingsItemIsEnabledAndRunsItsAction() {
        let host = HostConfig(displayName: "Edge", address: "192.0.2.1")
        var log: [String] = []
        let menu = StatusPopoverMenus.settings(displayMode: .signal, intervalHost: host, actions: .init(
            setDisplayMode: { log.append("mode \($0.rawValue)") },
            setPingInterval: { log.append("interval \($0) \($1 == host.id)") },
            openHistory: { log.append("history") },
            openSettings: { log.append("settings") },
            quit: { log.append("quit") }
        ))

        choose(PingScopeDisplayMode.ring.displayName, in: menu.item(withTitle: "Display style")?.submenu)
        choose("10s", in: menu.item(withTitle: "Ping interval")?.submenu)
        choose("Open History", in: menu)
        choose("Open Settings", in: menu)
        choose("Quit PingScope", in: menu)

        XCTAssertEqual(log, ["mode ring", "interval 10000 true", "history", "settings", "quit"])
    }

    func testHostsMenuListsAllHostsThenEachHost() {
        let first = UUID(), second = UUID()
        var log: [String] = []
        let menu = StatusPopoverMenus.hosts(
            [(id: first, name: "Gateway"), (id: second, name: "DNS")],
            selectAllHosts: { log.append("all") },
            selectHost: { log.append($0 == second ? "second" : "other") }
        )

        XCTAssertEqual(titles(menu), ["All Hosts", "-", "Gateway", "DNS"])
        choose("All Hosts", in: menu)
        choose("DNS", in: menu)
        XCTAssertEqual(log, ["all", "second"])
    }

    func testHostsMenuOmitsAllHostsForASingleHost() {
        let menu = StatusPopoverMenus.hosts([(id: UUID(), name: "Gateway")], selectAllHosts: {}, selectHost: { _ in })

        XCTAssertEqual(titles(menu), ["Gateway"])
    }

    // MARK: Click behaviour

    private final class Spy {
        var built = 0
        var presented = 0
    }

    private final class Ticker: ObservableObject {
        @Published var tick = 0
    }

    private struct Harness: View {
        @ObservedObject var ticker: Ticker
        let spy: Spy

        var body: some View {
            VStack {
                Text("tick \(ticker.tick)")
                PopUpMenuButton {
                    spy.built += 1
                    return NSMenu()
                } present: { _, _ in
                    spy.presented += 1
                } label: {
                    Color.red.frame(width: 60, height: 60)
                }
            }
            .frame(width: 100, height: 100)
        }
    }

    private func makeWindow(ticker: Ticker, spy: Spy) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(ticker: ticker, spy: spy))
        // Mouse events are only routed to views of a window that is on screen.
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return window
    }

    private func send(_ type: NSEvent.EventType, to window: NSWindow) {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 50, y: 35),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ) else {
            XCTFail("could not synthesize \(type)")
            return
        }
        window.sendEvent(event)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    func testMenuOpensOnMouseUpSoTheSameClickCannotDismissIt() {
        let spy = Spy()
        let window = makeWindow(ticker: Ticker(), spy: spy)
        defer { window.close() }

        send(.leftMouseDown, to: window)
        XCTAssertEqual(spy.presented, 0, "opening on mouse down leaves a mouse-up that can close the menu again")

        send(.leftMouseUp, to: window)
        XCTAssertEqual(spy.presented, 1)
    }

    func testMenuIsBuiltPerClickAndNeverByARerender() {
        let spy = Spy()
        let ticker = Ticker()
        let window = makeWindow(ticker: ticker, spy: spy)
        defer { window.close() }

        for _ in 0..<10 {
            ticker.tick += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(spy.built, 0, "probe results re-render the view; that must not rebuild the menu")

        send(.leftMouseDown, to: window)
        send(.leftMouseUp, to: window)
        for _ in 0..<10 {
            ticker.tick += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(spy.built, 1)
    }
}
