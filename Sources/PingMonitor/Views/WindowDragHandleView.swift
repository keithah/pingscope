import AppKit
import SwiftUI

struct WindowDragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView(frame: .zero)
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        _ = context
    }
}

final class DragHandleNSView: NSView {
    var dragPerformer: ((NSWindow, NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        if let dragPerformer {
            dragPerformer(window, event)
        } else {
            window.performDrag(with: event)
        }
    }
}
