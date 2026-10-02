import AppKit
import PingScopeCore

/// Watches for mouse-downs delivered to other applications.
///
/// A transient popover only notices clicks that reach this app, or this app
/// resigning active. Opened from a menu bar item, neither is guaranteed, and the
/// popover then stays up when the user clicks elsewhere.
@MainActor
final class OutsideClickMonitor {
    typealias Install = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?

    private let install: Install
    private let remove: (Any) -> Void
    private var token: Any?

    init(
        install: @escaping Install = { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
        remove: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
    ) {
        self.install = install
        self.remove = remove
    }

    var isMonitoring: Bool { token != nil }

    func start(onClick: @escaping @MainActor () -> Void) {
        stop()
        token = install([.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated(onClick)
        }
    }

    func stop() {
        guard let token else { return }
        remove(token)
        self.token = nil
    }
}

/// Owns the menu bar popover: opening it focused, closing it when the user
/// clicks away, and giving focus back afterwards.
@MainActor
final class StatusPopoverController: NSObject, NSPopoverDelegate {
    /// The process-wide state the controller touches, replaceable in tests.
    @MainActor
    struct System {
        var frontmostApplication: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
        var activate: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
        var isActive: () -> Bool = { NSApp.isActive }
        var returnFocus: (NSRunningApplication) -> Void = { application in
            NSApp.yieldActivation(to: application)
            application.activate()
        }
        var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    }

    private let system: System
    private let outsideClickMonitor: OutsideClickMonitor
    private let makeContent: () -> NSViewController
    private let contentSize: (NSScreen?) -> NSSize

    /// Whether another PingScope window that can hold keyboard focus is up.
    var hasOtherVisibleWindow: () -> Bool = { false }
    var makeDetachedWindow: () -> NSWindow? = { nil }
    var onVisibilityChange: () -> Void = {}
    var animates = true

    private var popover: NSPopover?
    private var lastWillCloseUptime: TimeInterval?
    private var closedByOutsideClick = false
    private var applicationBeforePopover: NSRunningApplication?

    init(
        system: System = System(),
        outsideClickMonitor: OutsideClickMonitor = OutsideClickMonitor(),
        makeContent: @escaping () -> NSViewController,
        contentSize: @escaping (NSScreen?) -> NSSize
    ) {
        self.system = system
        self.outsideClickMonitor = outsideClickMonitor
        self.makeContent = makeContent
        self.contentSize = contentSize
    }

    var isShown: Bool { popover?.isShown == true }
    var window: NSWindow? { popover?.contentViewController?.view.window }

    /// A click on the status item.
    func toggle(relativeTo anchorView: NSView) {
        if let popover, popover.isShown {
            // A popover left behind on another Space still reports isShown;
            // closing it would look like a swallowed click, so bring it here.
            let isOnActiveSpace = window?.isOnActiveSpace ?? true
            DebugLog.write("status item click closes popover onActiveSpace=\(isOnActiveSpace)")
            popover.performClose(nil)
            if isOnActiveSpace { return }
        } else if MenuBarPresentationMode.shouldSuppressPopoverReopen(
            now: system.uptime(),
            lastWillClose: lastWillCloseUptime
        ) {
            DebugLog.write("status item click already dismissed the popover")
            return
        }

        DebugLog.write("status item click opens popover")
        show(relativeTo: anchorView)
    }

    func show(relativeTo anchorView: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = animates
        popover.contentSize = contentSize(anchorView.window?.screen)
        popover.contentViewController = makeContent()
        popover.delegate = self

        let frontmost = system.frontmostApplication()
        applicationBeforePopover = frontmost == .current ? nil : frontmost
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        self.popover = popover

        // A click on a menu bar item does not activate its app. Left inactive,
        // the transient popover never hears about clicks elsewhere and stays
        // up, and the first click inside lands in a window that is not key.
        system.activate()
        window?.makeKey()

        closedByOutsideClick = false
        outsideClickMonitor.start { [weak self, weak popover] in
            guard let self, let popover, self.popover === popover, popover.isShown else { return }
            DebugLog.write("outside click closes popover")
            closedByOutsideClick = true
            popover.performClose(nil)
        }
        onVisibilityChange()
    }

    func close() {
        popover?.performClose(nil)
    }

    /// Resizes the popover while it is up. Once detached, its window is the
    /// user's to size.
    func resize(using size: (NSScreen?) -> NSSize) {
        guard let popover, popover.isShown, !popover.isDetached else { return }
        popover.contentSize = size(window?.screen)
    }

    // MARK: NSPopoverDelegate

    func popoverWillClose(_ notification: Notification) {
        lastWillCloseUptime = system.uptime()
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChange()
        // A replaced popover finishes closing after its successor is showing.
        guard notification.object as? NSPopover === popover else { return }
        outsideClickMonitor.stop()
        let previous = applicationBeforePopover
        applicationBeforePopover = nil
        guard let previous, MenuBarPresentationMode.shouldReturnFocusAfterPopoverCloses(
            appIsActive: system.isActive(),
            hasOtherVisibleWindow: hasOtherVisibleWindow(),
            closedByOutsideClick: closedByOutsideClick
        ) else { return }
        system.returnFocus(previous)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        MenuBarPresentationMode.shouldAllowUserDetachForMenuPopover()
    }

    func popoverDidDetach(_ popover: NSPopover) {
        DebugLog.write("menu popover detached to window")
        onVisibilityChange()
    }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        makeDetachedWindow()
    }
}
