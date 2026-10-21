import AppKit
import SwiftUI

/// A real AppKit drag source for a file, so the drag pasteboard carries an honest file URL just like the Finder's.
struct DraggableFile: NSViewRepresentable {
    var url: URL
    var image: NSImage

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
        view.image = image
        view.needsDisplay = true
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL?
        var image: NSImage?
        private var mouseDownPoint: NSPoint?

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard let image else { return }
            let target = bounds.insetBy(dx: 4, dy: 4)
            let ratio = image.size.width / max(image.size.height, 1)
            var rect = target
            if ratio > target.width / target.height { rect.size.height = target.width / ratio } else { rect.size.width = target.height * ratio }
            rect.origin = NSPoint(x: bounds.midX - rect.width / 2, y: bounds.midY - rect.height / 2)
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 14
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.set()
            NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).addClip()
            image.draw(in: rect)
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) { mouseDownPoint = convert(event.locationInWindow, from: nil) }

        override func mouseDragged(with event: NSEvent) {
            guard let url, let start = mouseDownPoint else { return }
            let now = convert(event.locationInWindow, from: nil)
            guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
            mouseDownPoint = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let side: CGFloat = 96
            item.setDraggingFrame(NSRect(x: now.x - side / 2, y: now.y - side / 2, width: side, height: side), contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }
}
