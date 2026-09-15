import AppKit
import SwiftUI

/// Invisible overlay on a card's image. A click runs `onClick`; dragging past a few points starts a
/// real file drag so cards can be dropped on chat apps, Finder, or a terminal.
struct DragSource: NSViewRepresentable {
    let urls: () -> [URL]
    let image: NSImage
    let onClick: () -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
        view.image = image
        view.onClick = onClick
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var image: NSImage?
    var onClick: () -> Void = {}
    private var downPoint: NSPoint?
    private var dragging = false

    /// The stack panel is not key while the annotator is; a click on a card must still count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !dragging else { return }
        guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 5 else { return }
        dragging = true
        let files = urls()
        guard !files.isEmpty else { return }
        let items = files.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: image)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging { onClick() }
        downPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
