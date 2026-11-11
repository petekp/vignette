import AppKit

// MARK: The frame

extension AnnotationController {
    /// Lays the frame out at `frame` and tells the stack, which narrows as the frame grows towards it.
    func moveFrame(to frame: NSRect, picture: CGRect) {
        layOutFrame(frame, picture: picture)
        onFrame?(frame)
    }

    /// The one place the frame's rect is set: the frame view, the clip, the shadow's path, the ring
    /// and the editor inside it all take it from here, in the same tick, so nothing can be a frame
    /// behind. `frameOnScreen` reads the result back for anyone who needs the rect. `picture` is where
    /// the whole picture sits in the editor, in its coordinates, which run down from the top.
    func layOutFrame(_ frame: NSRect, picture: CGRect) {
        guard let win = window, let frameView, let container else { return }
        frameView.frame = NSRect(x: frame.minX - win.frame.minX, y: frame.minY - win.frame.minY, width: frame.width, height: frame.height)
        container.frame = frameView.bounds
        frameView.layer?.shadowPath = Self.shadowPath(for: frameView.bounds.size)
        ring?.place(size: frameView.bounds.size)
        editor.setSize(container.bounds.size, picture: picture)
        placeTitle(frame: frame)
    }

    /// The frame view's shadow, cast by a frame of `size`.
    static func shadowPath(for size: CGSize) -> CGPath {
        let r = Settings.shared.data.ui.annotationCornerRadius
        return CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// The visible frame in screen coordinates.
    var frameOnScreen: NSRect? {
        guard let win = window, let frameView else { return nil }
        return win.convertToScreen(frameView.frame)
    }

    func makeWindow() -> AnnotationWindow {
        let win = AnnotationWindow(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false   // the frame view carries the shadow; the window itself is invisible
        win.level = AnnotationWindow.level
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.animationBehavior = .none
        win.onCloseRequest = { [weak self] in self?.cancel() }
        let root = NSView()
        root.wantsLayer = true
        let frameView = NSView()
        frameView.wantsLayer = true
        // The same shadow the flight carries into this frame, so the handover shows nothing.
        // AppKit's y points up, so a shadow below the frame is a negative offset.
        let look = TransitionLayer.Look.annotator(Settings.shared.data.ui)
        frameView.layer?.shadowColor = NSColor.black.cgColor
        frameView.layer?.shadowOpacity = Float(look.shadowOpacity)
        frameView.layer?.shadowRadius = look.shadowRadius
        frameView.layer?.shadowOffset = CGSize(width: 0, height: -look.shadowY)
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        // The window server gives a press to the window whose pixel under it is not clear, so this
        // opaque frame takes every press on it, over a screenshot's transparent pixels too, and the
        // clear rest of the window passes presses to the app behind, where `OutsideClick` sees them.
        // That holds only while `ignoresMouseEvents` is never set: once set either way, the window
        // takes or passes every press, whatever its pixels.
        container.layer?.backgroundColor = Config.matte.cgColor
        // Sized by hand, with its picture, in `moveFrame`: a size set without the picture would lay
        // the editor out at a size its picture does not fill.
        editor.autoresizingMask = []
        container.addSubview(editor)
        frameView.addSubview(container)
        root.addSubview(frameView)
        root.addSubview(titleView)
        win.contentView = root
        self.frameView = frameView
        self.container = container
        if let clip = container.layer, let frameLayer = frameView.layer { ring = FrameRing(clip: clip, in: frameLayer) }
        window = win
        return win
    }

    /// The window's corner and ring match a card's, so the flight from the stack ends on a shape that looks the same.
    func applyCornerRadius() {
        let ui = Settings.shared.data.ui
        container?.layer?.cornerRadius = ui.annotationCornerRadius
        container?.layer?.cornerCurve = .continuous
        applyRing()
    }

    func applyRing() {
        ring?.apply(Settings.shared.data.ui, scale: zoomScreen?.backingScaleFactor ?? 2)
        if let size = frameView?.bounds.size { ring?.place(size: size) }
    }
}
