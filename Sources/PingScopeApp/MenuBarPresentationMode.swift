import AppKit

enum MenuBarPresentationMode {
    static let statusContentSize = NSSize(width: 400, height: 620)
    static let statusContentMinimumSize = NSSize(width: 360, height: 420)
    static let statusContentPadding: CGFloat = 16
    static let statusGraphMinimumHeight: CGFloat = 150
    static let statusControlHitSize: CGFloat = 40
    static let statusCompactControlHitSize: CGFloat = 30
    /// One row of the All Hosts summary card, divider included.
    static let statusHostRowHeight: CGFloat = 46
    /// All Hosts rows `statusContentSize` holds before they start squeezing the
    /// graph and sample rows down to their minimums.
    static let statusHostRowsFittingDefaultHeight = 3
    /// Screen height left clear of the status content for the popover arrow or
    /// the detached window's title bar.
    static let statusContentScreenMargin: CGFloat = 40
    /// A click on the status item while the transient popover is open both
    /// dismisses the popover (as an outside click) and reaches the toggle.
    static let popoverReopenSuppressionInterval: TimeInterval = 0.25

    static let detachedPopoverWindowStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable
    ]

    /// Opening size for the status content: the default, grown so every All
    /// Hosts row fits without scrolling, as far as the screen allows.
    static func statusContentSize(hostRowCount: Int, availableHeight: CGFloat) -> NSSize {
        let extraRows = max(0, hostRowCount - statusHostRowsFittingDefaultHeight)
        let preferredHeight = statusContentSize.height + CGFloat(extraRows) * statusHostRowHeight
        return NSSize(
            width: statusContentSize.width,
            height: max(statusContentMinimumSize.height, min(preferredHeight, availableHeight))
        )
    }

    static func shouldSuppressPopoverReopen(now: TimeInterval, lastWillClose: TimeInterval?) -> Bool {
        guard let lastWillClose else { return false }
        return now - lastWillClose < popoverReopenSuppressionInterval
    }

    /// Opening the popover takes focus from the app the user was in. Hand it
    /// back when they put the popover away themselves and nothing else of ours
    /// is up. After an outside click the system has already moved focus to
    /// whatever was clicked, and reactivating the old app would fight that.
    static func shouldReturnFocusAfterPopoverCloses(
        appIsActive: Bool,
        hasOtherVisibleWindow: Bool,
        closedByOutsideClick: Bool
    ) -> Bool {
        appIsActive && !hasOtherVisibleWindow && !closedByOutsideClick
    }

    /// Control-click is the left button, so it arrives through the status
    /// button's action rather than the right-click gesture.
    static func isControlClick(type: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        type == .leftMouseDown && modifierFlags.contains(.control)
    }

    static func shouldAllowUserDetachForMenuPopover() -> Bool {
        true
    }
}
