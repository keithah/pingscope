import AppKit
import Darwin
import PingScopeCore
import SwiftUI

enum PingScopePrimaryWindowConfiguration {
    static let tabbingIdentifier = "com.hadm.PingScope.primary"

    @MainActor
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.tabbingIdentifier = tabbingIdentifier
        window.tabbingMode = .preferred
    }
}

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
            CommandGroup(after: .newItem) {
                Button("History") {
                    appDelegate.openHistory()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static weak var shared: AppDelegate?

    let model = PingScopeModel()
    let softwareUpdateController = SoftwareUpdateController()
    private lazy var overlayViewModel = OverlayPresentationViewModel(model: model)
    private lazy var statusPopoverViewModel = StatusPopoverPresentationViewModel(model: model)
    private var statusItem: NSStatusItem?
    private var statusItemView: MenuBarStatusView?
    private var popover: NSPopover?
    private var detachedPopoverWindow: NSWindow?
    private var overlayController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var historyWindowController: NSWindowController?
    private var lastExpandedOverlayFrame: NSRect?
    private var instanceLockFD: Int32 = -1
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        guard acquireSingleInstanceLock() else {
            NSApp.terminate(nil)
            return
        }
        DebugLog.write("launch flavor=\(BuildFlavor.current) sandboxed=\(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)")
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        model.start()
        model.onMenuStateChanged = { [weak self] state in
            self?.renderMenuState(state)
        }
        model.onPresentationChanged = { [weak self] in
            self?.refreshPresentationViewModels()
        }
        model.onOverlayGraphClicked = { [weak self] in
            self?.openPopoverFromOverlay()
        }
        if Self.launchesWindowed {
            DispatchQueue.main.async { [weak self] in
                self?.openWindowedStatusInterface()
            }
        }
        if model.overlayVisible {
            showOverlay()
        }
        installPowerObservers()
    }

    private static var launchesWindowed: Bool {
        CommandLine.arguments.contains("-windowed")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Await the runtime shutdown (history flush included) before letting the
        // process exit; a fire-and-forget stop loses the write buffer's pending
        // samples on every quit. The watchdog task bounds the wait so a wedged
        // flush cannot block quitting; a duplicate reply is ignored by AppKit.
        let model = model
        Task { @MainActor in
            await model.stopAndFlush()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        removePowerObservers()
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
            PingScopePrimaryWindowConfiguration.apply(to: window)
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func openHistory() {
        if historyWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "PingScope History"
            window.minSize = NSSize(width: 760, height: 580)
            PingScopePrimaryWindowConfiguration.apply(to: window)
            window.contentView = NSHostingView(rootView: HistoryWindowView(model: model))
            window.center()
            historyWindowController = NSWindowController(window: window)
        }
        historyWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showOverlay() {
        DebugLog.write("AppDelegate.showOverlay called overlayControllerNil=\(overlayController == nil)")
        if overlayController == nil {
            let view = OverlayView(viewModel: overlayViewModel, liveDisplay: model.liveDisplay)
            let window = OverlayWindow(contentRect: model.overlayFrame)
            window.contentView = OverlayContainerView(
                rootView: view,
                isCompact: { [weak self] in self?.overlayViewModel.presentation.compactMode ?? false },
                hostOptions: { [weak self] in self?.overlayHostOptions() ?? [] },
                onToggleCompact: { [weak self] in self?.toggleOverlayCompactMode() },
                onDetails: { [weak self] in self?.openPopoverFromOverlay() },
                onSettings: { [weak self] in self?.openSettings() },
                onClose: { [weak self] in self?.hideOverlay() },
                onSelectHost: { [weak self] id in
                    self?.overlayViewModel.selectHost(id)
                },
                onSelectAllHosts: { [weak self] in self?.overlayViewModel.selectAllHosts() },
                showsAllHosts: { [weak self] in self?.overlayViewModel.presentation.showsAllHosts ?? false },
                showsLegend: { [weak self] in self?.overlayViewModel.presentation.showsLegend ?? false },
                onToggleLegend: { [weak self] in
                    self?.overlayViewModel.toggleLegend()
                }
            )
            window.delegate = model
            overlayController = NSWindowController(window: window)
        }
        model.overlayVisible = true
        applyOverlayBehavior()
        constrainOverlayToVisibleScreen()
        overlayController?.showWindow(nil)
        DebugLog.write("overlay shown frame=\(String(describing: overlayController?.window?.frame))")
    }

    /// A borderless window is exempt from AppKit's automatic frame
    /// constraining, so a persisted overlay frame can be entirely off-screen
    /// after a display-configuration change (external monitor unplugged,
    /// clamshell, resolution change). The overlay then reads as enabled in
    /// Settings while nothing is visible anywhere. Clamp it back onto a
    /// screen before showing. The geometry lives in
    /// `clampedOverlayFrame(_:into:minVisible:)` so it is unit-testable.
    func constrainOverlayToVisibleScreen() {
        guard let window = overlayController?.window else { return }
        var screens = NSScreen.screens.map(\.visibleFrame)
        if let preferred = (window.screen ?? NSScreen.main)?.visibleFrame {
            screens.removeAll { $0 == preferred }
            screens.insert(preferred, at: 0)
        }
        guard let frame = clampedOverlayFrame(
            window.frame,
            into: screens,
            minVisible: CGSize(width: 60, height: 24)
        ) else { return }
        DebugLog.write("overlay frame off-screen; constrained to \(frame)")
        window.setFrame(frame, display: true)
        model.overlayFrame = frame
        UserDefaults.standard.overlayFrame = frame
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
            rootView: OverlayView(viewModel: overlayViewModel, liveDisplay: model.liveDisplay),
            isCompact: { [weak self] in self?.overlayViewModel.presentation.compactMode ?? false },
            hostOptions: { [weak self] in self?.overlayHostOptions() ?? [] },
            onToggleCompact: { [weak self] in self?.toggleOverlayCompactMode() },
            onDetails: { [weak self] in self?.openPopoverFromOverlay() },
            onSettings: { [weak self] in self?.openSettings() },
            onClose: { [weak self] in self?.hideOverlay() },
            onSelectHost: { [weak self] id in
                self?.overlayViewModel.selectHost(id)
            },
            onSelectAllHosts: { [weak self] in self?.overlayViewModel.selectAllHosts() },
            showsAllHosts: { [weak self] in self?.overlayViewModel.presentation.showsAllHosts ?? false },
            showsLegend: { [weak self] in self?.overlayViewModel.presentation.showsLegend ?? false },
            onToggleLegend: { [weak self] in
                self?.overlayViewModel.toggleLegend()
            }
        )
        applyOverlayBehavior()
    }

    private func overlayHostOptions() -> [(UUID, String, Bool)] {
        overlayViewModel.presentation.hostOptions.map { host in
            (host.id, host.name, host.isSelected)
        }
    }

    private func refreshPresentationViewModels() {
        if overlayController?.window?.isVisible == true {
            overlayViewModel.refresh()
        }
        if popover?.isShown == true || detachedPopoverWindow?.isVisible == true {
            statusPopoverViewModel.refresh()
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
        // The custom MenuBarStatusView draws the glyph, leaving the button with
        // no title/image and therefore no accessibility handle — which makes the
        // status item invisible to AX enumeration and un-pressable by automation
        // (e.g. the menubar-ux-tester harness). Give the button an explicit AX
        // label + identifier so it can be found and opened programmatically.
        button.setAccessibilityLabel("PingScope")
        button.setAccessibilityIdentifier("pingscope.statusItem")
        // Wire the button's accessibility action to the popover toggle. Real
        // mouse clicks are handled by MenuBarStatusView below; this makes the
        // item respond to an AXPress (how automation and assistive tech open
        // it) instead of routing solely through raw mouse events.
        button.target = self
        button.action = #selector(togglePopover)
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
        guard statusItemView?.content != content else { return }
        if statusItem?.length != CGFloat(content.itemWidth) {
            statusItem?.length = CGFloat(content.itemWidth)
            statusItemView?.frame.size.width = CGFloat(content.itemWidth)
        }
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

    /// Builds the shared menu-bar content view controller used by both the
    /// popover and the UI-test window, so both exercise identical UI.
    private func makeStatusContentController() -> NSViewController {
        let controller = NSHostingController(
            rootView: StatusPopoverView(
                viewModel: statusPopoverViewModel,
                liveDisplay: model.liveDisplay,
                onHistory: { [weak self] in
                    self?.openHistoryFromStatusContent()
                },
                onSettings: { [weak self] in
                    self?.openSettingsFromStatusContent()
                }
            )
            .environmentObject(softwareUpdateController)
        )
        controller.title = "PingScope"
        if #available(macOS 13.0, *) {
            controller.sizingOptions = []
        }
        controller.view.autoresizingMask = [.width, .height]
        return controller
    }

    private func openSettingsFromStatusContent() {
        popover?.performClose(nil)
        if detachedPopoverWindow?.isVisible == true {
            detachedPopoverWindow?.close()
        }
        openSettings()
    }

    private func openHistoryFromStatusContent() {
        popover?.performClose(nil)
        if detachedPopoverWindow?.isVisible == true {
            detachedPopoverWindow?.close()
        }
        openHistory()
    }

    private func showPopover(relativeTo anchorView: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = MenuBarPresentationMode.statusContentSize
        popover.contentViewController = makeStatusContentController()
        popover.delegate = self
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        self.popover = popover
        applyWindowOpacity()
        DispatchQueue.main.async { [weak self, weak popover] in
            guard self?.popover === popover else { return }
            self?.applyWindowOpacity()
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        MenuBarPresentationMode.shouldAllowUserDetachForMenuPopover()
    }

    func popoverDidDetach(_ popover: NSPopover) {
        DebugLog.write("menu popover detached to window")
    }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        let window = makeDetachedStatusWindow()
        detachedPopoverWindow = window
        return window
    }

    private func openWindowedStatusInterface() {
        popover?.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = detachedPopoverWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = makeDetachedStatusWindow()
        detachedPopoverWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeDetachedStatusWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MenuBarPresentationMode.statusContentSize),
            styleMask: MenuBarPresentationMode.detachedPopoverWindowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "PingScope"
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = makeStatusContentController()
        if let contentView = window.contentView {
            window.contentViewController?.view.frame = contentView.bounds
            window.contentViewController?.view.autoresizingMask = [.width, .height]
        }
        window.minSize = MenuBarPresentationMode.statusContentMinimumSize
        window.isReleasedWhenClosed = false
        return window
    }

    private func showContextMenu(from view: NSView) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Overlay", action: #selector(openOverlayFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "History...", action: #selector(openHistoryFromMenu), keyEquivalent: ""))
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

    @objc private func openHistoryFromMenu() {
        openHistory()
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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard let delegate = AppDelegate.shared, delegate.model.overlayVisible else { return }
                delegate.constrainOverlayToVisibleScreen()
            }
        }
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
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
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
            setAccessibilityHelp(content.accessibilityLabel)
            cachedLatencyText = Self.makeLatencyText(for: content)
            needsDisplay = true
        }
    }
    private var cachedLatencyText: NSAttributedString

    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        cachedLatencyText = Self.makeLatencyText(for: content)
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = content.accessibilityLabel
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("PingScope")
        setAccessibilityIdentifier("pingscope.statusItem")
        setAccessibilityHelp(content.accessibilityLabel)
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

        let textRect = NSRect(x: 0, y: CGFloat(content.textBaselineY), width: bounds.width, height: 12)
        cachedLatencyText.draw(with: textRect, options: [.usesLineFragmentOrigin])
    }

    private static func makeLatencyText(for content: MenuBarGlyphContent) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: content.latencyText,
            attributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(content.fontSize), weight: content.fontWeight.nsFontWeight),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    override func mouseDown(with event: NSEvent) {
        onPrimaryClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onPrimaryClick?()
        return true
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

private extension NSColor {
    convenience init(statusColor: StatusColor) {
        switch statusColor {
        case .gray: self.init(cgColor: NSColor.systemGray.cgColor)!
        case .green: self.init(calibratedRed: 0.38, green: 0.72, blue: 0.26, alpha: 1)
        case .yellow: self.init(cgColor: NSColor.systemYellow.cgColor)!
        case .red: self.init(cgColor: NSColor.systemRed.cgColor)!
        }
    }
}
