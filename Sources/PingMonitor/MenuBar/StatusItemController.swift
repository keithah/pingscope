import AppKit
import Combine
import Foundation

enum StatusItemClickRoute: Equatable {
    case togglePopover
    case openContextMenu
}

struct StatusItemClickRouter {
    func route(event: NSEvent?) -> StatusItemClickRoute? {
        route(eventType: event?.type, modifierFlags: event?.modifierFlags ?? [])
    }

    func route(eventType: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags) -> StatusItemClickRoute? {
        switch eventType {
        case .leftMouseUp:
            if modifierFlags.contains(.control) || modifierFlags.contains(.command) {
                return .openContextMenu
            }
            return .togglePopover
        case .rightMouseUp:
            return .openContextMenu
        default:
            return nil
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let clickRouter: StatusItemClickRouter
    private let onTogglePopover: () -> Void
    private let onRequestContextMenu: (NSStatusBarButton) -> Void
    private var cancellables: Set<AnyCancellable> = []

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(
        viewModel: MenuBarViewModel,
        clickRouter: StatusItemClickRouter = StatusItemClickRouter(),
        onTogglePopover: @escaping () -> Void,
        onRequestContextMenu: @escaping (NSStatusBarButton) -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.clickRouter = clickRouter
        self.onTogglePopover = onTogglePopover
        self.onRequestContextMenu = onRequestContextMenu
        super.init()

        configureButton()
        updateAppearance(with: viewModel.menuBarState)

        viewModel.$menuBarState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateAppearance(with: state)
            }
            .store(in: &cancellables)
    }

    func routeClick(event: NSEvent?) -> StatusItemClickRoute? {
        clickRouter.route(event: event)
    }

    @objc
    private func handleStatusItemButtonAction(_ sender: NSStatusBarButton) {
        guard let route = routeClick(event: NSApp.currentEvent) else {
            return
        }

        switch route {
        case .togglePopover:
            onTogglePopover()
        case .openContextMenu:
            onRequestContextMenu(sender)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemButtonAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    private func updateAppearance(with state: MenuBarState) {
        guard let button = statusItem.button else {
            return
        }

        button.title = state.displayText
        button.image = statusSymbolImage(for: state.status)
        button.contentTintColor = statusColor(for: state.status)
    }

    private func statusSymbolImage(for status: MenuBarStatus) -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "PingMonitor status"
        ) else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 9, height: 9)
        return image.withSymbolConfiguration(.init(pointSize: 9, weight: .regular))
    }

    private func statusColor(for status: MenuBarStatus) -> NSColor {
        switch status {
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        case .gray:
            return .systemGray
        }
    }
}
