import AppKit

@MainActor
final class DisplayModeCoordinator: NSObject, NSWindowDelegate {
    private let displayPreferencesStore: DisplayPreferencesStore
    private var applicationResignObserver: Any?
    private var isInLiveResize: Bool = false

    private(set) var standardWindow: NSWindow?
    private(set) var floatingWindow: NSWindow?
    private var lastPresentedMode: DisplayMode = .full
    private var standardWindowMode: DisplayMode?
    private var floatingWindowMode: DisplayMode?

    init(
        displayPreferencesStore: DisplayPreferencesStore = DisplayPreferencesStore()
    ) {
        self.displayPreferencesStore = displayPreferencesStore
        super.init()

        applicationResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Dismiss like a popover, but never while resizing (grabbing the edge can
                // momentarily reshuffle focus/activation for borderless windows).
                if !self.isInLiveResize {
                    self.closeStandardWindow()
                }
            }
        }
    }

    deinit {
        if let applicationResignObserver {
            NotificationCenter.default.removeObserver(applicationResignObserver)
        }
    }

    func open(
        from button: NSStatusBarButton,
        mode: DisplayMode,
        isStayOnTopEnabled: Bool,
        contentViewController: NSViewController
    ) {
        if isStayOnTopEnabled {
            showFloatingWindow(from: button, mode: mode, contentViewController: contentViewController)
        } else {
            showStandardWindow(from: button, mode: mode, contentViewController: contentViewController)
        }
    }

    var isDisplayVisible: Bool {
        (standardWindow?.isVisible ?? false) || (floatingWindow?.isVisible ?? false)
    }

    func showStandardWindow(
        from button: NSStatusBarButton,
        mode: DisplayMode,
        contentViewController: NSViewController
    ) {
        if let window = floatingWindow {
            persistWindowFrame(window.frame, for: floatingWindowMode ?? lastPresentedMode)
            window.orderOut(nil)
        }

        let modeChanged = lastPresentedMode != mode
        if modeChanged, let window = standardWindow, window.isVisible {
            persistWindowFrame(window.frame, for: lastPresentedMode)
        }

        let preferredFrame = preferredFrame(for: mode, preservingSizeFrom: floatingWindow)
        let anchorRect = statusItemAnchorRect(for: button)
        let anchorCenter = anchorRect?.center
        let wantsAnchoredOpen = preferredFrame.origin.x == 0 && preferredFrame.origin.y == 0
        let referencePoint = wantsAnchoredOpen ? (anchorCenter ?? preferredFrame.center) : preferredFrame.center
        let visibleFrame = visibleFrame(containing: referencePoint, fallbackWindow: button.window)
        let minimumSize = minimumContentSize(for: mode)
        let resolvedFrame = Self.anchoredAndClampedFrame(
            anchorRect: wantsAnchoredOpen ? anchorRect : nil,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame,
            minimumSize: minimumSize
        )

        let window = standardWindow ?? makeStandardWindow(frame: resolvedFrame)
        lastPresentedMode = mode
        standardWindowMode = mode
        configureStandardWindow(window, for: mode)
        window.contentViewController = contentViewController
        // Some content/controller swaps can influence sizing; enforce the desired frame
        // after assigning content and again on the next runloop tick.
        window.setFrame(resolvedFrame, display: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.standardWindow === window else {
                return
            }
            window.setFrame(resolvedFrame, display: false)
        }

        standardWindow = window
    }

    func showFloatingWindow(
        from button: NSStatusBarButton,
        mode: DisplayMode,
        contentViewController: NSViewController
    ) {
        if let window = standardWindow {
            persistWindowFrame(window.frame, for: standardWindowMode ?? lastPresentedMode)
            window.orderOut(nil)
        }

        let modeChanged = lastPresentedMode != mode
        if modeChanged, let window = floatingWindow, window.isVisible {
            persistWindowFrame(window.frame, for: lastPresentedMode)
        }

        let preferredFrame = preferredFrame(for: mode, preservingSizeFrom: standardWindow)
        let anchorRect = statusItemAnchorRect(for: button)
        let wantsAnchoredOpen = preferredFrame.origin.x == 0 && preferredFrame.origin.y == 0
        let referencePoint = wantsAnchoredOpen ? (anchorRect?.center ?? preferredFrame.center) : preferredFrame.center
        let visibleFrame = visibleFrame(containing: referencePoint, fallbackWindow: button.window)
        let minimumSize = minimumContentSize(for: mode)
        let resolvedFrame = Self.anchoredAndClampedFrame(
            anchorRect: wantsAnchoredOpen ? anchorRect : nil,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame,
            minimumSize: minimumSize
        )

        let window = floatingWindow ?? makeFloatingWindow(frame: resolvedFrame)
        lastPresentedMode = mode
        floatingWindowMode = mode
        configureFloatingWindow(window, for: mode)
        window.contentViewController = contentViewController
        window.setFrame(resolvedFrame, display: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.floatingWindow === window else {
                return
            }
            window.setFrame(resolvedFrame, display: false)
        }

        floatingWindow = window
    }

    func closeStandardWindow() {
        guard let window = standardWindow else {
            return
        }

        // Only persist when this window is actually being dismissed from a visible state.
        // Otherwise, a hidden window with an old frame could overwrite the most recent
        // user-resized frame from the currently active shell.
        if window.isVisible {
            persistWindowFrame(window.frame, for: standardWindowMode ?? lastPresentedMode)
        }
        window.orderOut(nil)
    }

    func closeFloatingWindow() {
        guard let window = floatingWindow else {
            return
        }

        if window.isVisible {
            persistWindowFrame(window.frame, for: floatingWindowMode ?? lastPresentedMode)
        }
        window.orderOut(nil)
    }

    func closeAll() {
        closeStandardWindow()
        closeFloatingWindow()
    }

    func statusItemAnchorRect(for button: NSStatusBarButton) -> NSRect? {
        guard let buttonWindow = button.window else {
            return nil
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(buttonRectInWindow)
    }

    func makeFloatingWindow(frame: NSRect) -> NSWindow {
        let window = DisplayShellWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        window.delegate = self
        return window
    }

    func makeStandardWindow(frame: NSRect) -> NSWindow {
        let window = DisplayShellWindow(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.level = .normal
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        window.delegate = self
        return window
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isInLiveResize = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isInLiveResize = false
        persistFrameFromNotification(notification)
    }

    func windowDidResize(_ notification: Notification) {
        // Persist continuously so quick hide/reopen cycles keep the latest size.
        persistFrameFromNotification(notification)
    }

    func windowDidMove(_ notification: Notification) {
        persistFrameFromNotification(notification)
    }

    func windowWillClose(_ notification: Notification) {
        persistFrameFromNotification(notification)
    }

    static func anchoredAndClampedFrame(
        anchorRect: NSRect?,
        preferredFrame: NSRect,
        visibleFrame: NSRect,
        minimumSize: NSSize,
        verticalOffset: CGFloat = 8
    ) -> NSRect {
        var frame = preferredFrame

        frame.size.width = max(frame.size.width, minimumSize.width)
        frame.size.height = max(frame.size.height, minimumSize.height)

        if let anchorRect {
            frame.origin.x = anchorRect.midX - (frame.width / 2)
            frame.origin.y = anchorRect.minY - frame.height - verticalOffset
        }

        if frame.width > visibleFrame.width {
            frame.size.width = max(minimumSize.width, visibleFrame.width)
        }

        if frame.height > visibleFrame.height {
            frame.size.height = max(minimumSize.height, visibleFrame.height)
        }

        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - frame.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - frame.height

        if maxX < minX {
            frame.origin.x = minX
        } else {
            frame.origin.x = min(max(frame.origin.x, minX), maxX)
        }

        if maxY < minY {
            frame.origin.y = minY
        } else {
            frame.origin.y = min(max(frame.origin.y, minY), maxY)
        }

        return frame
    }

    private func frame(for mode: DisplayMode) -> NSRect {
        let modeState = displayPreferencesStore.modeState(for: mode)
        let frameData = modeState.frameData

        let defaultFrame = mode.defaultFrame
        let resolvedWidth = frameData.width > 0 ? frameData.width : defaultFrame.width
        let resolvedHeight = frameData.height > 0 ? frameData.height : defaultFrame.height
        return NSRect(
            x: frameData.x,
            y: frameData.y,
            width: resolvedWidth,
            height: resolvedHeight
        )
    }

    private func persistWindowFrame(_ frame: NSRect, for mode: DisplayMode) {
        displayPreferencesStore.updateModeState(for: mode) { state in
            state.frameData = DisplayFrameData(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        }
    }

    private func persistFrameFromNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === standardWindow {
            persistWindowFrame(window.frame, for: standardWindowMode ?? lastPresentedMode)
            return
        }

        if window === floatingWindow {
            persistWindowFrame(window.frame, for: floatingWindowMode ?? lastPresentedMode)
            return
        }
    }

    private func preferredFrame(for mode: DisplayMode, preservingSizeFrom outgoingWindow: NSWindow?) -> NSRect {
        var preferredFrame = frame(for: mode)

        guard let outgoingWindow,
              outgoingWindow.isVisible,
              lastPresentedMode == mode else {
            return preferredFrame
        }

        preferredFrame.size = outgoingWindow.frame.size
        return preferredFrame
    }

    private func visibleFrame(for anchorRect: NSRect?, fallbackWindow: NSWindow?) -> NSRect {
        if let anchorRect,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorRect.center) }) {
            return screen.visibleFrame
        }

        if let fallbackScreen = fallbackWindow?.screen {
            return fallbackScreen.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_280, height: 800)
    }

    private func visibleFrame(containing point: NSPoint, fallbackWindow: NSWindow?) -> NSRect {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen.visibleFrame
        }

        if let fallbackScreen = fallbackWindow?.screen {
            return fallbackScreen.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_280, height: 800)
    }

    private func configureStandardWindow(_ window: NSWindow, for mode: DisplayMode) {
        window.styleMask.insert(.resizable)
        window.styleMask.remove(.titled)
        window.collectionBehavior.insert(.fullScreenNone)

        window.contentMinSize = minimumContentSize(for: mode)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
    }

    private func configureFloatingWindow(_ window: NSWindow, for mode: DisplayMode) {
        window.styleMask.insert(.resizable)
        window.styleMask.remove(.titled)
        window.collectionBehavior.insert(.fullScreenNone)
        window.contentMinSize = minimumContentSize(for: mode)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)
    }

    private func minimumContentSize(for mode: DisplayMode) -> NSSize {
        switch mode {
        case .full:
            // User wants to freely resize smaller to find the right size.
            return NSSize(width: 220, height: 260)
        case .compact:
            // Keep compact resizable, but still readable at very narrow width.
            return NSSize(width: 150, height: 80)
        }
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

private final class DisplayShellWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
