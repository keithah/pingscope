import AppKit
import PingScopeCore
import SwiftUI

/// A button that pops up an AppKit menu built at click time.
///
/// SwiftUI's `Menu` opens on mouse down and keeps its `NSMenu` in sync with the
/// view. In the status content that goes wrong twice over: the mouse-up of the
/// same click could dismiss the menu again, so it only stayed up while the
/// button was held, and every probe result rebuilt the open menu under the
/// pointer. Here the menu opens from the button's action, after the mouse is
/// already up, and nothing touches it once it is showing.
struct PopUpMenuButton<Label: View>: View {
    let makeMenu: @MainActor () -> NSMenu
    var present: @MainActor (NSMenu, NSView) -> Void = PopUpMenuPresenter.popUpBelow
    @ViewBuilder let label: () -> Label
    @State private var anchor = PopUpMenuAnchor()

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            present(makeMenu(), view)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .background(PopUpMenuAnchorView(anchor: anchor))
    }
}

enum PopUpMenuPresenter {
    /// Deferred a turn so the button finishes its own click handling before the
    /// menu's tracking loop takes over the run loop.
    @MainActor
    static func popUpBelow(_ menu: NSMenu, _ view: NSView) {
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4), in: view)
        }
    }
}

private final class PopUpMenuAnchor {
    weak var view: NSView?
}

private struct PopUpMenuAnchorView: NSViewRepresentable {
    let anchor: PopUpMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, isOn: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = isOn ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

@MainActor
enum StatusPopoverMenus {
    struct SettingsActions {
        var setDisplayMode: (PingScopeDisplayMode) -> Void = { _ in }
        var setPingInterval: (Int, UUID) -> Void = { _, _ in }
        var openHistory: () -> Void = {}
        var openSettings: () -> Void = {}
        var quit: () -> Void = {}
    }

    /// `intervalHost` is the focused host, or nil while All Hosts is showing
    /// (the interval picker beside the range control covers that case).
    static func settings(
        displayMode: PingScopeDisplayMode,
        intervalHost: HostConfig?,
        actions: SettingsActions
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("Display style", items: PingScopeDisplayMode.allCases.map { mode in
            ClosureMenuItem(mode.displayName, isOn: mode == displayMode) { actions.setDisplayMode(mode) }
        }))
        menu.addItem(.separator())
        if let intervalHost {
            let selected = PingIntervalPresentation.selection(for: intervalHost.interval)
            menu.addItem(submenu("Ping interval", items: PingIntervalPresentation.options(including: selected).map { option in
                ClosureMenuItem(option.label, isOn: option.milliseconds == selected) {
                    actions.setPingInterval(option.milliseconds, intervalHost.id)
                }
            }))
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("Open History", handler: actions.openHistory))
        menu.addItem(ClosureMenuItem("Open Settings", handler: actions.openSettings))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit PingScope", handler: actions.quit))
        return menu
    }

    static func hosts(
        _ hosts: [(id: UUID, name: String)],
        selectAllHosts: @escaping () -> Void,
        selectHost: @escaping (UUID) -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        if hosts.count > 1 {
            menu.addItem(ClosureMenuItem("All Hosts", handler: selectAllHosts))
            menu.addItem(.separator())
        }
        for host in hosts {
            menu.addItem(ClosureMenuItem(host.name) { selectHost(host.id) })
        }
        return menu
    }

    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }
}
