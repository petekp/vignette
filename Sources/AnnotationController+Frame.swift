import AppKit

// MARK: The frame

extension AnnotationController {
    /// The one place the frame's rect is set: the frame view, the clip, the shadow's path, the
    /// editor inside it and the bar under it all take it from here, in the same tick, so nothing can
    /// be a frame behind. `frameOnScreen` reads the result back for anyone who needs the rect.
    /// `picture` is where the whole picture sits in the editor, in its coordinates, which run down
    /// from the top. `barTop` is where the bar's top edge goes (`AnnotatorZoom.barTop`).
    func moveFrame(to frame: NSRect, picture: CGRect, barTop: CGFloat) {
        guard let win = window, let frameView, let container else { return }
        frameView.frame = NSRect(x: frame.minX - win.frame.minX, y: frame.minY - win.frame.minY, width: frame.width, height: frame.height)
        container.frame = frameView.bounds
        let r = Settings.shared.data.ui.annotationCornerRadius
        frameView.layer?.shadowPath = CGPath(roundedRect: frameView.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        editor.fittedWidth = zoom.fitted.width
        editor.setSize(container.bounds.size, picture: picture)
        toolbar.follow(top: barTop, center: zoom.barCenter, fitted: zoom.fitted)
        placeTitle(frame: frame)
        onFrame?(frame)
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
        win.onCloseRequest = { [weak self] in self?.cancel(via: .window) }
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

    /// The thin white line round the frame that a card's border becomes in flight: the clip's own
    /// border, drawn over the image's edge pixels.
    func applyRing() {
        let ui = Settings.shared.data.ui
        container?.layer?.borderWidth = ui.cardBorderWidth
        container?.layer?.borderColor = NSColor.white.withAlphaComponent(ui.cardBorderOpacity).cgColor
    }
}
