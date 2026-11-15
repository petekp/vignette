import AppKit

/// The panel's content. The window server gives the panel only the presses on a flight's pixels,
/// so it takes every press it gets, with the drag and the release that follow, and none reaches
/// the flights' SwiftUI views.
final class PressCatcher: NSView {
    var onEvent: ((NSEvent) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onEvent?(event) }
    override func mouseDragged(with event: NSEvent) { onEvent?(event) }
    override func mouseUp(with event: NSEvent) { onEvent?(event) }
}
