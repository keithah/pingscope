import AppKit
import PingScopeCore
import SwiftUI

final class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary]
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        hasShadow = true
        minSize = NSSize(width: 150, height: 54)
    }

    override var canBecomeKey: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown,
           let presenter = contentView as? OverlayContextMenuPresenting {
            presenter.presentOverlayContextMenu(with: event)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private protocol OverlayContextMenuPresenting: AnyObject {
    func presentOverlayContextMenu(with event: NSEvent)
}

final class OverlayContainerView: NSView {
    private let hostingView: NSHostingView<AnyView>
    private let isCompact: () -> Bool
    private let hostOptions: () -> [(UUID, String, Bool)]
    private let onToggleCompact: () -> Void
    private let onDetails: () -> Void
    private let onSettings: () -> Void
    private let onClose: () -> Void
    private let onSelectHost: (UUID) -> Void
    private let onSelectAllHosts: () -> Void
    private let showsAllHosts: () -> Bool
    private let showsLegend: () -> Bool
    private let onToggleLegend: () -> Void
    private let graphClickView: OverlayGraphClickView
    private var compactButton: NSButton?
    private var settingsButton: NSButton?
    private var closeButton: NSButton?

    init(
        rootView: some View,
        isCompact: @escaping () -> Bool,
        hostOptions: @escaping () -> [(UUID, String, Bool)],
        onToggleCompact: @escaping () -> Void,
        onDetails: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSelectHost: @escaping (UUID) -> Void,
        onSelectAllHosts: @escaping () -> Void,
        showsAllHosts: @escaping () -> Bool,
        showsLegend: @escaping () -> Bool,
        onToggleLegend: @escaping () -> Void
    ) {
        self.hostingView = NSHostingView(rootView: AnyView(rootView))
        self.isCompact = isCompact
        self.hostOptions = hostOptions
        self.onToggleCompact = onToggleCompact
        self.onDetails = onDetails
        self.onSettings = onSettings
        self.onClose = onClose
        self.onSelectHost = onSelectHost
        self.onSelectAllHosts = onSelectAllHosts
        self.showsAllHosts = showsAllHosts
        self.showsLegend = showsLegend
        self.onToggleLegend = onToggleLegend
        self.graphClickView = OverlayGraphClickView(onClick: onDetails)
        super.init(frame: .zero)

        wantsLayer = true
        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addSubview(graphClickView)
        graphClickView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            graphClickView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            graphClickView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            graphClickView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            graphClickView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: isCompact() ? 0.78 : 0.42)
        ])
        graphClickView.onRightClick = { [weak self] event in
            self?.presentOverlayContextMenu(with: event)
        }

        if !isCompact() {
            let compactButton = makeButton(
                symbolName: "arrow.up.left.and.arrow.down.right",
                tooltip: "Compact overlay",
                action: #selector(toggleCompact)
            )
            let settingsButton = makeButton(symbolName: "gearshape", tooltip: "Open settings", action: #selector(openSettings))
            let closeButton = makeButton(symbolName: "xmark", tooltip: "Close overlay", action: #selector(closeOverlay))
            self.compactButton = compactButton
            self.settingsButton = settingsButton
            self.closeButton = closeButton
            addSubview(compactButton)
            addSubview(settingsButton)
            addSubview(closeButton)

            NSLayoutConstraint.activate([
                closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                settingsButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                settingsButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -1),
                compactButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                compactButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -1)
            ])
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func rightMouseDown(with event: NSEvent) {
        DebugLog.write("overlay context menu requested")
        showContextMenu(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    private func showContextMenu(with event: NSEvent) {
        NSMenu.popUpContextMenu(contextMenu(), with: event, for: self)
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let compactTitle = isCompact() ? "Expanded Overlay" : "Compact Overlay"
        menu.addItem(NSMenuItem(title: compactTitle, action: #selector(toggleCompact), keyEquivalent: ""))
        let hosts = hostOptions()
        if hosts.count > 1 {
            let legendItem = NSMenuItem(title: showsLegend() ? "Hide Legend" : "Show Legend", action: #selector(toggleLegend), keyEquivalent: "")
            legendItem.target = self
            legendItem.isEnabled = showsAllHosts()
            menu.addItem(legendItem)

            let hostItem = NSMenuItem(title: "Host", action: nil, keyEquivalent: "")
            let hostMenu = NSMenu()
            let allItem = NSMenuItem(title: "All Hosts", action: #selector(selectAllHosts), keyEquivalent: "")
            allItem.target = self
            allItem.state = showsAllHosts() ? .on : .off
            hostMenu.addItem(allItem)
            hostMenu.addItem(.separator())
            for (index, host) in hosts.enumerated() {
                let item = NSMenuItem(title: host.1, action: #selector(selectHost(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = host.0
                item.state = host.2 ? .on : .off
                if showsAllHosts() {
                    item.attributedTitle = NSAttributedString(
                        string: host.1,
                        attributes: [.foregroundColor: NSColor.graphPaletteColor(index: index)]
                    )
                }
                hostMenu.addItem(item)
            }
            hostItem.submenu = hostMenu
            menu.addItem(hostItem)
        }
        menu.addItem(NSMenuItem(title: "Open Popover", action: #selector(openDetails), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close Overlay", action: #selector(closeOverlay), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func makeButton(symbolName: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 20)
        ])
        return button
    }

    @objc private func toggleCompact() {
        DebugLog.write("overlay context compact fired")
        onToggleCompact()
    }

    @objc private func openDetails() {
        DebugLog.write("overlay context details fired")
        onDetails()
    }

    @objc private func selectHost(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        DebugLog.write("overlay context host selected id=\(id.uuidString)")
        onSelectHost(id)
    }

    @objc private func selectAllHosts() {
        DebugLog.write("overlay context all hosts selected")
        onSelectAllHosts()
    }

    @objc private func toggleLegend() {
        DebugLog.write("overlay context legend toggled")
        onToggleLegend()
    }

    @objc private func openSettings() {
        DebugLog.write("overlay context settings fired")
        onSettings()
    }

    @objc private func closeOverlay() {
        DebugLog.write("overlay context close fired")
        onClose()
    }
}

extension OverlayContainerView: OverlayContextMenuPresenting {
    func presentOverlayContextMenu(with event: NSEvent) {
        DebugLog.write("overlay context menu requested")
        NSMenu.popUpContextMenu(contextMenu(), with: event, for: self)
    }
}

final class OverlayGraphClickView: NSView {
    private let onClick: () -> Void
    var onRightClick: ((NSEvent) -> Void)?
    private var mouseDownLocation: NSPoint?
    private var hasHandledMouseUp = false

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        hasHandledMouseUp = false
    }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !hasHandledMouseUp else { return }
        hasHandledMouseUp = true
        let start = mouseDownLocation ?? event.locationInWindow
        let end = event.locationInWindow
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance < 4 else { return }
        DebugLog.write("overlay graph click fired")
        onClick()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

private extension NSColor {
    static func graphPaletteColor(index: Int) -> NSColor {
        let palette: [NSColor] = [
            .systemBlue,
            .systemGreen,
            .systemOrange,
            .systemPurple,
            .systemPink,
            .systemCyan
        ]
        return palette[index % palette.count]
    }
}
