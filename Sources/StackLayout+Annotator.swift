import AppKit

// MARK: The annotator's frame

extension StackLayout {
    /// The strip of the screen the stack keeps for itself at its narrowest, and the gap beside it.
    /// The annotator's frame never enters it, so the stack always has somewhere to be.
    var reservedWidth: CGFloat { margin + maxCardWidth * minWidthScale + ui.stackGap }

    /// The rect the annotator's frame fits and grows within while the recent stack is showing:
    /// the visible frame, less the stack's reserved strip on the right.
    func annotatorRoom(visibleFrame v: NSRect) -> NSRect {
        NSRect(x: v.minX, y: v.minY, width: max(1, v.width - reservedWidth), height: v.height)
    }

    /// How wide the stack may be drawn with the annotator's frame where it is: the largest width
    /// at which the column's left edge still clears the frame's right edge by the gap. 1 when the
    /// frame is far enough away, and never below the minimum, which is the width the room the
    /// frame grows within was reserved for.
    func widthScale(clearing frame: NSRect, visibleFrame v: NSRect) -> CGFloat {
        let free = v.maxX - margin - ui.stackGap - frame.maxX
        return min(1, max(minWidthScale, free / max(maxCardWidth, 1)))
    }

    /// Where an agent's title above `frame` wraps. Its text starts `indent` in from the frame's left
    /// edge and wraps at the frame's right edge, or `minimum` wide when that is narrower, so a narrow
    /// image's title is not cramped and hangs past the frame's right edge. Never past `room`'s right
    /// edge, where the stack's strip begins.
    static func titleWrapWidth(frame: NSRect, room: NSRect, minimum: CGFloat, indent: CGFloat) -> CGFloat {
        max(1, min(max(frame.width - indent, minimum), room.maxX - frame.minX - indent))
    }

    /// Where the annotator goes: the image's exact aspect, centered in the rect it is given, with
    /// room below for the toolbar and above for what `above` says it needs when it wraps at a given
    /// width, an agent's title (`titleWrapWidth`). Small crops scale up until the toolbar fits.
    func annotationFrame(for image: NSSize, visibleFrame: NSRect, below: CGFloat = 0,
                         above: (_ wrap: CGFloat) -> CGFloat = { _ in 0 }) -> NSRect {
        // The room above takes height, so the frame can come out narrower, and a narrower title
        // wraps onto more lines. Each fit keeps room for the lines at the width before it, until
        // the lines stop growing.
        var reserved: CGFloat = 0
        var frame = annotationFrame(for: image, visibleFrame: visibleFrame, below: below, above: reserved)
        for _ in 0..<Self.titleFits {
            let needed = above(Self.titleWrapWidth(frame: frame, room: visibleFrame, minimum: ui.agentTitleMinWidth,
                                                   indent: ui.annotationCornerRadius))
            guard needed > reserved else { break }
            reserved = needed
            frame = annotationFrame(for: image, visibleFrame: visibleFrame, below: below, above: reserved)
        }
        return frame
    }

    private static let titleFits = 4

    private func annotationFrame(for image: NSSize, visibleFrame: NSRect, below: CGFloat, above: CGFloat) -> NSRect {
        var v = visibleFrame.insetBy(dx: ui.annotationScreenInset, dy: ui.annotationScreenInset)
        v.origin.y += below
        v.size.height -= below + above
        // The frame goes on whole points, so the room it fits in is on whole points too.
        let left = v.minX.rounded(.up), bottom = v.minY.rounded(.up)
        v = NSRect(x: left, y: bottom, width: v.maxX.rounded(.down) - left, height: v.maxY.rounded(.down) - bottom)
        let w0 = max(image.width, 1), h0 = max(image.height, 1)
        let fit = min(v.width / w0, v.height / h0)
        let floor = max(1, ui.annotationMinWidth / w0, ui.annotationMinHeight / h0)
        let scale = min(fit, floor)
        let w = w0 * scale
        // On whole points, so the frame is on every display's pixel grid, with the image's shape: the
        // editor draws the picture across the frame's width, so the height follows the rounded width
        // and the picture's bottom edge is under half a point from the frame's. Where the height fills
        // the room, a width rounded up past it is rounded down instead.
        var width = w.rounded()
        if (width * h0 / w0).rounded() > v.height { width = w.rounded(.down) }
        let size = NSSize(width: width, height: (width * h0 / w0).rounded())
        return NSRect(x: (v.midX - size.width / 2).rounded(), y: (v.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }
}
