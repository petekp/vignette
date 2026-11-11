import AppKit
import SwiftUI

/// The AppKit overlay on a card's image. It draws the drawing's marks, `picture` being the shape of
/// the image under them. A click runs `onClick`; dragging past a few points starts a real drag of
/// `items`, asked for then, so cards can be dropped on chat apps, Finder, or a terminal. The press
/// becomes the drag (`onDrag`), so the card stays as the press left it while its drag image is out.
/// The marks are drawn here rather than in an AppKit view of their own because SwiftUI updates
/// every AppKit view in the stack on every frame of its animations: a second view per card would
/// add its update to every frame of a slide-in or a narrowing.
struct DragSource: NSViewRepresentable {
    let items: () -> [NSPasteboardWriting]
    let image: NSImage
    let onPress: (Bool) -> Void
    let onDrag: (DragSourceView.Phase) -> Void
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
        view.onDrag = onDrag
        view.onClick = onClick
        view.show(marks, picture: picture, corner: corner, restSize: restSize)
    }
}

@MainActor
final class DragSourceView: NSView, NSDraggingSource {
    enum Phase: Equatable {
        case began
        /// Whether the pointer is on the card when the drag ends.
        case ended(pointerOnCard: Bool)
    }

    var items: () -> [NSPasteboardWriting] = { [] }
    var image: NSImage?
    var onPress: (Bool) -> Void = { _ in }
    var onDrag: (Phase) -> Void = { _ in }
    var onClick: () -> Void = {}
    private var downPoint: NSPoint?
    private var dragging = false
    private var marksView: MarksView?
    /// The card's corner radius, which the drag image is clipped to.
    private var corner: CGFloat = 0
    /// The drag under way: its picture, and where the picture and the pointer were on screen when it began.
    private var drag: (picture: CGImage, frame: NSRect, pointer: NSPoint)?

    /// Draws `marks` over the card, clipped to its corners, or nothing for a screenshot with no drawing.
    func show(_ marks: MarkLayers?, picture: CGSize?, corner: CGFloat, restSize: CGSize?) {
        self.corner = corner
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
        let began = CACurrentMediaTime()
        let writers = items()
        guard !writers.isEmpty else { return onPress(false) }
        onDrag(.began)
        // One bitmap is both the drag image and the picture that pours at the drop, so the two match.
        let lifted = image.flatMap(lift)
        let dragged = writers.map { writer -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(lifted?.frame ?? bounds, contents: lifted.map { NSImage(cgImage: $0.picture, size: $0.frame.size) })
            return item
        }
        if let lifted, let window {
            drag = (lifted.picture, window.convertToScreen(convert(lifted.frame, to: nil)), NSEvent.mouseLocation)
        }
        beginDraggingSession(with: dragged, event: event, source: self)
        Log.write("[drag] began took=\(Int((CACurrentMediaTime() - began) * 1000))ms")
    }

    /// The card as the stack draws it, so the drag image takes its place without a step: its image
    /// filling it over the matte, its continuous corners, its shadow, the marks in the live style and
    /// its resting border, at the scale and on the pixels the card has on screen. What is drawn over a
    /// hovered card, the dim and the buttons, stays with the card, as it does when a flight carries
    /// the card off. Answers the picture and its frame in this view's coordinates, which reaches past
    /// the card far enough to hold the shadow.
    private func lift(_ picture: NSImage) -> (picture: CGImage, frame: NSRect)? {
        guard let window, bounds.width > 0, bounds.height > 0 else { return nil }
        let ui = Settings.shared.data.ui, size = bounds.size, backing = window.backingScaleFactor
        // In the window's points. `convert` includes the card's scale effect.
        let shown = convert(bounds, to: nil)
        let scale = shown.width / bounds.width
        let room = (ui.cardShadowRadius * 3 + abs(ui.cardShadowY) + ui.cardBorderWidth).rounded(.up)
        // Out to whole device pixels, so the picture's pixels lie on the card's.
        let reach = shown.insetBy(dx: -room * scale, dy: -room * scale)
        let minX = (reach.minX * backing).rounded(.down) / backing, minY = (reach.minY * backing).rounded(.down) / backing
        let frame = NSRect(x: minX, y: minY, width: (reach.maxX * backing).rounded(.up) / backing - minX,
                           height: (reach.maxY * backing).rounded(.up) / backing - minY)
        let marks = marks(over: picture).flatMap { marks in
            bitmap(size, scale: backing * scale) { _ in marks.draw(in: NSRect(origin: .zero, size: size)) }
        }
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        // CardView's views and modifiers, in its order. On screen the card casts one shadow from its
        // image and matte together; `ImageRenderer` would cast one from each, twice as dark.
        let card = Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: Config.matte))
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .black.opacity(ui.cardShadowOpacity), radius: ui.cardShadowRadius, y: ui.cardShadowY)
            .overlay {
                if let marks { Image(decorative: marks, scale: backing * scale).resizable().clipShape(shape) }
            }
            .overlay(ui.ring(cornerRadius: corner).stroke(.white.opacity(ui.cardBorderOpacity), lineWidth: ui.cardBorderWidth))
            .padding(room)
        let renderer = ImageRenderer(content: card)
        guard let lifted = bitmap(frame.size, scale: backing, draw: { context in
            context.translateBy(x: reach.minX - frame.minX, y: reach.minY - frame.minY)
            context.scaleBy(x: scale, y: scale)
            renderer.render(rasterizationScale: backing * scale) { _, draw in draw(context) }
        }) else { return nil }
        return (lifted, convert(frame, from: nil))
    }

    /// What `draw` draws on `size` points at `scale` pixels a point, in the colour space of the
    /// screen the card is on, as the card's window draws.
    private func bitmap(_ size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        guard size.width > 0, size.height > 0,
              let space = window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// The card's marks in the live style, over a picture of `picture`'s shape filling the card, or
    /// nil for a screenshot with no drawing.
    private func marks(over picture: NSImage) -> NSImage? {
        guard let drawing = marksView?.marks?.drawing, drawing.pixels.width > 0, drawing.pixels.height > 0,
              picture.size.width > 0, picture.size.height > 0 else { return nil }
        let ui = Settings.shared.data.ui
        return NSImage(size: bounds.size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let fill = max(rect.width / picture.size.width, rect.height / picture.size.height)
            let drawn = CGRect(x: (rect.width - picture.size.width * fill) / 2, y: (rect.height - picture.size.height * fill) / 2,
                               width: picture.size.width * fill, height: picture.size.height * fill)
            // The drawing's px, from the image's top-left with y down, onto the picture's rect.
            ctx.translateBy(x: drawn.minX, y: drawn.minY)
            ctx.scaleBy(x: drawn.width / CGFloat(drawing.pixels.width), y: drawn.height / CGFloat(drawing.pixels.height))
            drawing.draw(in: ctx, style: ui.textStyle, markStyle: ui.markStyle)
            return true
        }
    }

    override func mouseUp(with event: NSEvent) {
        onPress(false)
        if !dragging { onClick() }
        downPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        if let begun = drag { drag = (begun.picture, begun.frame, screenPoint) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    /// A drop that took the card pours the picture into the release point (`DropLanding`). A drop
    /// that failed or was cancelled leaves it to macOS, which slides the drag image home.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { drag = nil }
        let onCard = window.map { window in
            window.convertToScreen(convert(bounds, to: nil)).contains(screenPoint)
                && NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == window.windowNumber
        } ?? false
        onDrag(.ended(pointerOnCard: onCard))
        let point = "\(Int(screenPoint.x)),\(Int(screenPoint.y))"
        guard !operation.isEmpty else { return Log.write("[drag] ended at=\(point) not dropped; slides home") }
        guard let drag else { return Log.write("[drag] ended at=\(point) dropped; no picture to pour") }
        // The drag image keeps its offset from the pointer, so it ends where the pointer took it.
        let frame = drag.frame.offsetBy(dx: screenPoint.x - drag.pointer.x, dy: screenPoint.y - drag.pointer.y)
        let played = DropLanding.play(drag.picture, from: frame, into: screenPoint)
        Log.write("[drag] ended at=\(point) dropped from=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height)) "
                  + (played ? "poured" : "no motion"))
    }
}
