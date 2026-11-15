import AppKit

extension AppDelegate {
    /// A template disc `size` across with a hole `hole` across. The hole is half a point smaller
    /// than the dot it frames, so the two overlap and no background shows between them.
    static func ring(size: CGFloat, hole: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let inner = (size - hole) / 2 + 0.25
            NSBezierPath(ovalIn: rect.insetBy(dx: inner, dy: inner)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The icon with a clear circle filling `dot`, which is in the button's coordinates.
    /// The button draws the icon at its own size, centred.
    static func icon(_ icon: NSImage, clearedAround dot: NSRect, in button: NSStatusBarButton) -> NSImage {
        let size = icon.size
        let origin = NSPoint(x: (button.bounds.width - size.width) / 2, y: (button.bounds.height - size.height) / 2)
        var center = NSPoint(x: dot.midX - origin.x, y: dot.midY - origin.y)
        if button.isFlipped { center.y = size.height - center.y }
        let radius = dot.width / 2
        let image = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
