import AppKit
import SwiftUI

/// The AppKit overlay on a card's image. It draws the drawing's marks, `picture` being the shape of
/// the image under them. A click runs `onClick`; dragging past a few points starts a real file drag so
/// cards can be dropped on chat apps, Finder, or a terminal. The marks are here rather than in an
/// overlay of their own because SwiftUI updates every AppKit view in the stack on every frame of its
/// animations, so a second one a card is paid for on every frame of a slide-in or a narrowing.
struct DragSource: NSViewRepresentable {
    let urls: () -> [URL]
    let image: NSImage
    let onPress: (Bool) -> Void
    let onClick: () -> Void
    var marks: MarkLayers? = nil
    var picture: CGSize? = nil
    var corner: CGFloat = 0

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ view: DragSourceView, context: Context) {
        view.urls = urls
        view.image = image
        view.onPress = onPress
        view.onClick = onClick
        view.show(marks, picture: picture, corner: corner)
    }
}

@MainActor
final class DragSourceView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var image: NSImage?
    var onPress: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    private var downPoint: NSPoint?
    private var dragging = false
    private var marksView: MarksView?

    /// Draws `marks` over the card, clipped to its corners, or nothing for a screenshot with no drawing.
    func show(_ marks: MarkLayers?, picture: CGSize?, corner: CGFloat) {
        guard let marks else {
            marksView?.removeFromSuperview()
            marksView = nil
            return
        }
        let view = marksView ?? MarksView(frame: bounds)
        if marksView == nil {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            marksView = view
        }
        view.marks = marks
        view.picture = picture
        view.corner = corner
    }

    /// The stack panel is not key while the annotator is; a click on a card must still count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragging = false
        onPress(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !dragging else { return }
        guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 5 else { return }
        dragging = true
        onPress(false)
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
        onPress(false)
        if !dragging { onClick() }
        downPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
