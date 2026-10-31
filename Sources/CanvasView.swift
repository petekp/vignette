import AppKit

/// Hosts the picture's and the overlay's layers, y down. It takes no events: the editor view does.
final class CanvasView: NSView {
    let host = CALayer()

    /// AppKit sets a layer-hosting view's root layer geometry from the view, overwriting a flag set on
    /// the layer, so the view itself must be flipped for its sublayers to run y down.
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = host
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
