import AppKit
import Darwin
import PingScopeCore
import SwiftUI

@main
struct PingScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(model: appDelegate.model)
                .environmentObject(appDelegate.softwareUpdateController)
                .frame(width: 700, height: 680)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let model = PingScopeModel()
    let softwareUpdateController = SoftwareUpdateController()
    private var statusItem: NSStatusItem?
    private var statusItemView: MenuBarStatusView?
    private var popover: NSPopover?
    private var overlayController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var lastExpandedOverlayFrame: NSRect?
    private var instanceLockFD: Int32 = -1
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        guard acquireSingleInstanceLock() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        model.start()
        model.onMenuStateChanged = { [weak self] state in
            self?.renderMenuState(state)
        }
        model.onOverlayGraphClicked = { [weak self] in
            self?.openPopoverFromOverlay()
        }
        if model.overlayVisible {
            showOverlay()
        }
        installPowerObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removePowerObservers()
        model.stop()
        releaseSingleInstanceLock()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func openSettings() {
        DebugLog.write("AppDelegate.openSettings called")
        if settingsWindowController == nil {
            let view = SettingsRootView(model: model)
                .environmentObject(softwareUpdateController)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "PingScope Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showOverlay() {
        DebugLog.write("AppDelegate.showOverlay called overlayControllerNil=\(overlayController == nil)")
        if overlayController == nil {
            let view = OverlayView(model: model)
            let window = OverlayWindow(contentRect: model.overlayFrame)
            window.contentView = OverlayContainerView(
                rootView: view,
                isCompact: { [weak self] in self?.model.overlayCompactMode ?? false },
                hostOptions: { [weak self] in self?.overlayHostOptions() ?? [] },
                onToggleCompact: { [weak self] in self?.toggleOverlayCompactMode() },
                onDetails: { [weak self] in self?.openPopoverFromOverlay() },
                onSettings: { [weak self] in self?.openSettings() },
                onClose: { [weak self] in self?.hideOverlay() },
                onSelectHost: { [weak self] id in
                    self?.model.overlayShowsAllHosts = false
                    self?.model.selectHost(id)
                },
                onSelectAllHosts: { [weak self] in self?.model.overlayShowsAllHosts = true },
                showsAllHosts: { [weak self] in self?.model.overlayShowsAllHosts ?? false },
                showsLegend: { [weak self] in self?.model.overlayShowsLegend ?? false },
                onToggleLegend: { [weak self] in
                    guard let self else { return }
                    self.model.overlayShowsLegend.toggle()
                }
            )
            window.delegate = model
            overlayController = NSWindowController(window: window)
        }
        model.overlayVisible = true
        applyOverlayBehavior()
        overlayController?.showWindow(nil)
        DebugLog.write("overlay shown frame=\(String(describing: overlayController?.window?.frame))")
    }

    func hideOverlay() {
        DebugLog.write("AppDelegate.hideOverlay called")
        model.overlayVisible = false
        overlayController?.close()
    }

    func resetOverlayFrame() {
        let frame = NSRect(x: 80, y: 620, width: 240, height: 96)
        model.overlayFrame = frame
        overlayController?.window?.setFrame(frame, display: true)
    }

    func applyOverlayBehavior() {
        guard let window = overlayController?.window else { return }
        window.alphaValue = CGFloat(model.overlayOpacity)
        if model.overlayAlwaysOnTop {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.orderFrontRegardless()
        } else {
            window.level = .normal
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.orderBack(nil)
        }
        DebugLog.write("overlay behavior applied opacity=\(model.overlayOpacity) alwaysOnTop=\(model.overlayAlwaysOnTop) level=\(window.level.rawValue)")
    }

    func applyWindowOpacity() {
        let alpha = CGFloat(model.overlayOpacity)
        overlayController?.window?.alphaValue = alpha
        popover?.contentViewController?.view.window?.alphaValue = alpha
        DebugLog.write("window opacity applied value=\(model.overlayOpacity)")
    }

    func openPopoverFromOverlay() {
        DebugLog.write("AppDelegate.openPopoverFromOverlay called")
        guard let anchorView = overlayController?.window?.contentView else {
            showPopoverFromStatusItem()
            return
        }
        showPopover(relativeTo: anchorView)
    }

    func toggleOverlayCompactMode() {
        setOverlayCompactMode(!model.overlayCompactMode)
    }

    func setOverlayCompactMode(_ isCompact: Bool) {
        guard model.overlayCompactMode != isCompact else {
            refreshOverlayContent()
            return
        }
        model.overlayCompactMode = isCompact
        applyOverlayCompactLayout(isCompact)
    }

    func applyOverlayCompactLayout(_ isCompact: Bool) {
        resizeOverlayForCompactMode(isCompact)
        refreshOverlayContent()
    }

    private func resizeOverlayForCompactMode(_ isCompact: Bool) {
        guard let window = overlayController?.window else { return }
        let current = window.frame
        let newSize: NSSize
        if isCompact {
            lastExpandedOverlayFrame = current
            newSize = NSSize(
                width: max(150, current.width * 0.5),
                height: max(54, current.height * 0.5)
            )
        } else if let expanded = lastExpandedOverlayFrame {
            newSize = expanded.size
        } else {
            newSize = NSSize(
                width: max(240, current.width * 2),
                height: max(96, current.height * 2)
            )
        }

        let newOrigin = NSPoint(
            x: current.maxX - newSize.width,
            y: current.maxY - newSize.height
        )
        let frame = NSRect(origin: newOrigin, size: newSize)
        window.setFrame(frame, display: true, animate: false)
        model.overlayFrame = frame
    }

    private func refreshOverlayContent() {
        overlayController?.window?.contentView = OverlayContainerView(
            rootView: OverlayView(model: model),
            isCompact: { [weak self] in self?.model.overlayCompactMode ?? false },
            hostOptions: { [weak self] in self?.overlayHostOptions() ?? [] },
            onToggleCompact: { [weak self] in self?.toggleOverlayCompactMode() },
            onDetails: { [weak self] in self?.openPopoverFromOverlay() },
            onSettings: { [weak self] in self?.openSettings() },
            onClose: { [weak self] in self?.hideOverlay() },
            onSelectHost: { [weak self] id in
                self?.model.overlayShowsAllHosts = false
                self?.model.selectHost(id)
            },
            onSelectAllHosts: { [weak self] in self?.model.overlayShowsAllHosts = true },
            showsAllHosts: { [weak self] in self?.model.overlayShowsAllHosts ?? false },
            showsLegend: { [weak self] in self?.model.overlayShowsLegend ?? false },
            onToggleLegend: { [weak self] in
                guard let self else { return }
                self.model.overlayShowsLegend.toggle()
            }
        )
        applyOverlayBehavior()
    }

    private func overlayHostOptions() -> [(UUID, String, Bool)] {
        let primaryID = model.primaryHost?.id
        return model.snapshot.hosts.map { host in
            (host.id, host.displayName, !model.overlayShowsAllHosts && host.id == primaryID)
        }
    }

    private func installStatusItem() {
        let defaultContent = model.menuBarGlyphContent
        let item = NSStatusBar.system.statusItem(withLength: CGFloat(defaultContent.itemWidth))
        guard let button = item.button else {
            statusItem = item
            return
        }
        button.title = ""
        button.image = nil
        button.toolTip = "PingScope"
        let view = MenuBarStatusView(frame: NSRect(x: 0, y: 0, width: defaultContent.itemWidth, height: NSStatusBar.system.thickness))
        view.autoresizingMask = [.width, .height]
        view.onPrimaryClick = { [weak self] in
            self?.togglePopover()
        }
        view.onSecondaryClick = { [weak self, weak view] in
            guard let view else { return }
            self?.showContextMenu(from: view)
        }
        button.addSubview(view)
        statusItemView = view
        statusItem = item
        renderMenuState(model.menuBarState)
    }

    private func renderMenuState(_ state: MenuBarState) {
        let content = model.menuBarGlyphContent
        statusItem?.length = CGFloat(content.itemWidth)
        statusItemView?.frame.size.width = CGFloat(content.itemWidth)
        statusItemView?.content = content
    }

    @objc private func togglePopover() {
        guard let anchorView = statusItemView else { return }

        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(from: anchorView)
            return
        }

        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }

        showPopoverFromStatusItem()
    }

    private func showPopoverFromStatusItem() {
        guard let anchorView = statusItemView else { return }
        showPopover(relativeTo: anchorView)
    }

    private func showPopover(relativeTo anchorView: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 430, height: 540)
        popover.contentViewController = NSHostingController(
            rootView: StatusPopoverView(
                model: model,
                onSettings: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.openSettings()
                }
            )
                .environmentObject(softwareUpdateController)
        )
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        self.popover = popover
        applyWindowOpacity()
        DispatchQueue.main.async { [weak self, weak popover] in
            guard self?.popover === popover else { return }
            self?.applyWindowOpacity()
        }
    }

    private func showContextMenu(from view: NSView) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(openOverlayFromMenu), keyEquivalent: ""))
        #if !APPSTORE
            if softwareUpdateController.isAvailable {
                menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
            }
        #endif
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PingScope", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY), in: view)
    }

    @objc private func openOverlayFromMenu() {
        showOverlay()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    #if !APPSTORE
        @objc private func checkForUpdatesFromMenu() {
            softwareUpdateController.checkForUpdates()
        }
    #endif

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func acquireSingleInstanceLock() -> Bool {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("com.pingscope.fresh.lock")
        instanceLockFD = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard instanceLockFD >= 0 else { return true }
        return flock(instanceLockFD, LOCK_EX | LOCK_NB) == 0
    }

    private func releaseSingleInstanceLock() {
        guard instanceLockFD >= 0 else { return }
        flock(instanceLockFD, LOCK_UN)
        close(instanceLockFD)
        instanceLockFD = -1
    }

    private func installPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let model = model
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [model] in
                model.resumeMeasurementsAfterSystemChange()
            }
        }
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [model] in
                model.pauseMeasurementsForSleep()
            }
        }
    }

    private func removePowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if let wakeObserver {
            center.removeObserver(wakeObserver)
        }
        if let sleepObserver {
            center.removeObserver(sleepObserver)
        }
    }

}

final class MenuBarStatusView: NSView {
    var content = MenuBarGlyphContent(
        latencyText: "--ms",
        dotDiameter: 8,
        itemWidth: 34,
        fontSize: 9.5,
        fontWeight: .regular,
        textBaselineY: 0,
        color: .gray,
        accessibilityLabel: "PingScope has no data"
    ) {
        didSet {
            toolTip = content.accessibilityLabel
            setAccessibilityLabel(content.accessibilityLabel)
            needsDisplay = true
        }
    }

    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = content.accessibilityLabel
        setAccessibilityRole(.button)
        setAccessibilityLabel(content.accessibilityLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let dotDiameter = CGFloat(content.dotDiameter)
        let dotRect = NSRect(
            x: bounds.midX - dotDiameter / 2,
            y: bounds.maxY - dotDiameter - 2,
            width: dotDiameter,
            height: dotDiameter
        )
        NSColor(statusColor: content.color).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(content.fontSize), weight: content.fontWeight.nsFontWeight),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: 0, y: CGFloat(content.textBaselineY), width: bounds.width, height: 12)
        content.latencyText.draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        onPrimaryClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }
}

private extension MenuBarFontWeight {
    var nsFontWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        }
    }
}

final class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary]
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        hasShadow = true
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

        if !isCompact() {
            let compactButton = makeButton(
                symbolName: "arrow.up.left.and.arrow.down.right",
                tooltip: "Compact graph mode",
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
        let compactTitle = isCompact() ? "Exit Compact Graph" : "Compact Graph"
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
        nextResponder?.rightMouseDown(with: event)
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

    convenience init(statusColor: StatusColor) {
        switch statusColor {
        case .gray: self.init(cgColor: NSColor.systemGray.cgColor)!
        case .green: self.init(calibratedRed: 0.38, green: 0.72, blue: 0.26, alpha: 1)
        case .yellow: self.init(cgColor: NSColor.systemYellow.cgColor)!
        case .red: self.init(cgColor: NSColor.systemRed.cgColor)!
        }
    }
}
