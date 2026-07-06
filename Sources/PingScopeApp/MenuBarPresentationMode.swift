import AppKit

enum MenuBarPresentationMode {
    static let statusContentSize = NSSize(width: 430, height: 540)
    static let statusContentMinimumSize = NSSize(width: 360, height: 420)
    static let statusGraphMinimumHeight: CGFloat = 150
    static let statusControlHitSize: CGFloat = 40
    static let statusCompactControlHitSize: CGFloat = 30

    static let detachedPopoverWindowStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable
    ]

    static func shouldAllowUserDetachForMenuPopover() -> Bool {
        true
    }
}
