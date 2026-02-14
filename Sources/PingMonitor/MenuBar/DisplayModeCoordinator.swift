import AppKit

@MainActor
final class DisplayModeCoordinator: NSObject, NSWindowDelegate {
    private let popover: NSPopover
    private let displayPreferencesStore: DisplayPreferencesStore

    private(set) var standardWindow: NSWindow?
    private(set) var floatingWindow: NSWindow?
    private var lastPresentedMode: DisplayMode = .full

    init(
        popover: NSPopover? = nil,
        displayPreferencesStore: DisplayPreferencesStore = DisplayPreferencesStore()
    ) {
        self.popover = popover ?? NSPopover()
        self.displayPreferencesStore = displayPreferencesStore
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
        (standardWindow?.isVisible ?? false) || (floatingWindow?.isVisible ?? false) || popover.isShown
    }

    func showStandardWindow(
        from button: NSStatusBarButton,
        mode: DisplayMode,
        contentViewController: NSViewController
    ) {
        if let window = floatingWindow {
            persistWindowFrame(window.frame, for: lastPresentedMode)
            window.orderOut(nil)
        }

        if popover.isShown {
            popover.performClose(nil)
        }

        let modeChanged = lastPresentedMode != mode
        if modeChanged, let window = standardWindow, window.isVisible {
            persistWindowFrame(window.frame, for: lastPresentedMode)
        }

        let preferredFrame = frame(for: mode)
        let anchorRect = statusItemAnchorRect(for: button)
        let visibleFrame = visibleFrame(for: anchorRect, fallbackWindow: button.window)
        let resolvedFrame = Self.anchoredAndClampedFrame(
            anchorRect: anchorRect,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame
        )

        let window = standardWindow ?? makeStandardWindow(frame: resolvedFrame)
        lastPresentedMode = mode
        if modeChanged || !window.isVisible {
            window.setFrame(resolvedFrame, display: false)
        }
        window.contentViewController = contentViewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        standardWindow = window
    }

    func showFloatingWindow(
        from button: NSStatusBarButton,
        mode: DisplayMode,
        contentViewController: NSViewController
    ) {
        if let window = standardWindow {
            persistWindowFrame(window.frame, for: lastPresentedMode)
            window.orderOut(nil)
        }

        if popover.isShown {
            popover.performClose(nil)
        }

        let modeChanged = lastPresentedMode != mode
        if modeChanged, let window = floatingWindow, window.isVisible {
            persistWindowFrame(window.frame, for: lastPresentedMode)
        }

        let preferredFrame = frame(for: mode)
        let anchorRect = statusItemAnchorRect(for: button)
        let visibleFrame = visibleFrame(for: anchorRect, fallbackWindow: button.window)
        let resolvedFrame = Self.anchoredAndClampedFrame(
            anchorRect: anchorRect,
            preferredFrame: preferredFrame,
            visibleFrame: visibleFrame
        )

        let window = floatingWindow ?? makeFloatingWindow(frame: resolvedFrame)
        lastPresentedMode = mode
        window.setFrame(resolvedFrame, display: false)
        window.contentViewController = contentViewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        floatingWindow = window
    }

    func closeStandardWindow() {
        guard let window = standardWindow else {
            return
        }

        persistWindowFrame(window.frame, for: lastPresentedMode)
        window.orderOut(nil)
    }

    func closeFloatingWindow() {
        guard let window = floatingWindow else {
            return
        }

        persistWindowFrame(window.frame, for: lastPresentedMode)
        window.orderOut(nil)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func closeAll() {
        closePopover()
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
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.transient, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        return window
    }

    func makeStandardWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "PingMonitor"
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowDidEndLiveResize(_ notification: Notification) {
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
        verticalOffset: CGFloat = 8
    ) -> NSRect {
        var frame = preferredFrame

        if let anchorRect {
            frame.origin.x = anchorRect.midX - (frame.width / 2)
            frame.origin.y = anchorRect.minY - frame.height - verticalOffset
        }

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
        }

        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
        }

        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - frame.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - frame.height

        frame.origin.x = min(max(frame.origin.x, minX), maxX)
        frame.origin.y = min(max(frame.origin.y, minY), maxY)

        return frame
    }

    private func frame(for mode: DisplayMode) -> NSRect {
        let modeState = displayPreferencesStore.modeState(for: mode)
        let frameData = modeState.frameData
        return NSRect(
            x: frameData.x,
            y: frameData.y,
            width: frameData.width,
            height: frameData.height
        )
    }

    private func persistWindowFrame(_ frame: NSRect, for mode: DisplayMode) {
        displayPreferencesStore.updateModeState(for: mode) { state in
            state.frameData = DisplayFrameData(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.width,
                height: frame.height
            )
        }
    }

    private func persistFrameFromNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        guard window === standardWindow || window === floatingWindow else {
            return
        }

        persistWindowFrame(window.frame, for: lastPresentedMode)
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
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
