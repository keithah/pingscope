import AppKit

enum MenuBarPresentationMode {
    static let statusContentSize = NSSize(width: 400, height: 620)
    static let statusContentMinimumSize = NSSize(width: 360, height: 420)
    static let statusContentPadding: CGFloat = 16
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
