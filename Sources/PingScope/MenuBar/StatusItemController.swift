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
    private let titleFormatter: StatusItemTitleFormatter
    private let onTogglePopover: () -> Void
    private let onRequestContextMenu: (NSStatusBarButton) -> Void
    private var cancellables: Set<AnyCancellable> = []

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(
        viewModel: MenuBarViewModel,
        clickRouter: StatusItemClickRouter = StatusItemClickRouter(),
        titleFormatter: StatusItemTitleFormatter = StatusItemTitleFormatter(),
        onTogglePopover: @escaping () -> Void,
        onRequestContextMenu: @escaping (NSStatusBarButton) -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.clickRouter = clickRouter
        self.titleFormatter = titleFormatter
        self.onTogglePopover = onTogglePopover
        self.onRequestContextMenu = onRequestContextMenu
        super.init()

        configureButton()
        updateAppearance(with: viewModel.menuBarState, isCompactModeEnabled: viewModel.isCompactModeEnabled)

        viewModel.$menuBarState.combineLatest(viewModel.$isCompactModeEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, isCompactModeEnabled in
                self?.updateAppearance(with: state, isCompactModeEnabled: isCompactModeEnabled)
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
        button.imagePosition = .imageAbove
        button.alignment = .center
    }

    private func updateAppearance(with state: MenuBarState, isCompactModeEnabled: Bool) {
        guard let button = statusItem.button else {
            return
        }

        button.attributedTitle = styledTitle(
            text: titleFormatter.titleText(for: state.displayText, isCompactModeEnabled: isCompactModeEnabled)
        )
        button.image = statusSymbolImage(for: state.status)
        button.contentTintColor = nil
    }

    private func statusSymbolImage(for status: MenuBarStatus) -> NSImage? {
        let diameter: CGFloat = 8
        // Offset dot to right to center over "m" and part of 2nd numeral
        let imageWidth: CGFloat = 26
        let xOffset: CGFloat = 13
        let imageHeight: CGFloat = diameter + 4 // Extra padding at top to lower the dot
        let image = NSImage(size: NSSize(width: imageWidth, height: imageHeight))
        image.lockFocus()
        statusColor(for: status).setFill()
        NSBezierPath(ovalIn: NSRect(x: xOffset, y: 0, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func styledTitle(text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
                .baselineOffset: -5
            ]
        )
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

struct StatusItemTitleFormatter {
    func titleText(for displayText: String, isCompactModeEnabled: Bool) -> String {
        // Always format as "26ms" (no space)
        return displayText.replacingOccurrences(of: " ms", with: "ms")
    }
}
