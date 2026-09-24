import AppKit
import SwiftUI

/// The AppKit overlay on a card's image. It draws the drawing's marks, `picture` being the shape of
/// the image under them. A click runs `onClick`; dragging past a few points starts a real drag of
/// `items`, asked for then, so cards can be dropped on chat apps, Finder, or a terminal. The marks
/// are drawn here rather than in an AppKit view of their own because SwiftUI updates every AppKit
/// view in the stack on every frame of its animations: a second view per card would add its update
/// to every frame of a slide-in or a narrowing.
struct DragSource: NSViewRepresentable {
    let items: () -> [NSPasteboardWriting]
    let image: NSImage
    let onPress: (Bool) -> Void
    let onClick: () -> Void
    var marks: MarkLayers? = nil
    var picture: CGSize? = nil
    var corner: CGFloat = 0
    /// The card's size at rest, which the marks are drawn at however narrow the stack is.
    var restSize: CGSize? = nil

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ view: DragSourceView, context: Context) {
        view.items = items
        view.image = image
        view.onPress = onPress
        view.onClick = onClick
        view.show(marks, picture: picture, corner: corner, restSize: restSize)
    }
}

@MainActor
final class DragSourceView: NSView, NSDraggingSource {
    var items: () -> [NSPasteboardWriting] = { [] }
    var image: NSImage?
    var onPress: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    private var downPoint: NSPoint?
    private var dragging = false
    private var marksView: MarksView?

    /// Draws `marks` over the card, clipped to its corners, or nothing for a screenshot with no drawing.
    func show(_ marks: MarkLayers?, picture: CGSize?, corner: CGFloat, restSize: CGSize?) {
        guard let marks else {
            marksView?.removeFromSuperview()
            marksView = nil
            return
        }
        let view = marksView ?? MarksView(frame: bounds)
        if marksView == nil {
            view.autoresizingMask = [.width, .height]
            view.flattened = true
            addSubview(view)
            marksView = view
        }
        view.marks = marks
        view.picture = picture
        view.corner = corner
        view.restSize = restSize
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
        let writers = items()
        guard !writers.isEmpty else { return }
        let picture = image.map(dragImage)
        let dragged = writers.map { writer -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(bounds, contents: picture)
            return item
        }
        beginDraggingSession(with: dragged, event: event, source: self)
    }

    /// The card as it is drawn: its image filling it, over the matte, clipped to its corners, and the
    /// marks over it in the live style.
    private func dragImage(_ picture: NSImage) -> NSImage {
        let drawing = marksView?.marks?.drawing, corner = marksView?.corner ?? 0, ui = Settings.shared.data.ui
        return NSImage(size: bounds.size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext, picture.size.width > 0, picture.size.height > 0 else { return false }
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).addClip()
            Config.matte.setFill()
            rect.fill()
            let fill = max(rect.width / picture.size.width, rect.height / picture.size.height)
            let drawn = CGRect(x: (rect.width - picture.size.width * fill) / 2, y: (rect.height - picture.size.height * fill) / 2,
                               width: picture.size.width * fill, height: picture.size.height * fill)
            picture.draw(in: drawn, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if let drawing, drawing.pixels.width > 0, drawing.pixels.height > 0 {
                // The drawing's px, from the image's top-left with y down, onto the picture's rect.
                ctx.translateBy(x: drawn.minX, y: drawn.minY)
                ctx.scaleBy(x: drawn.width / CGFloat(drawing.pixels.width), y: drawn.height / CGFloat(drawing.pixels.height))
                drawing.draw(in: ctx, style: ui.textStyle, arrowhead: ui.arrowhead)
            }
            return true
        }
    }

    override func mouseUp(with event: NSEvent) {
        onPress(false)
        if !dragging { onClick() }
        downPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
