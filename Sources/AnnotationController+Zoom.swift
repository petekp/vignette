import AppKit

// MARK: Zoom

extension AnnotationController {
    func place(_ win: NSWindow, frame: NSRect) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        zoomScreen = screen
        zoom.pixelScale = screen.backingScaleFactor
        if win.frame != screen.visibleFrame { win.setFrame(screen.visibleFrame, display: false) }
        moveFrame(to: frame, picture: zoom.picture, barTop: zoom.barTop)
    }

    /// Hands `input` to the zoom and does what it answers. A spring that lands at once, at motion 0,
    /// ticks and arrives inside `animate`, after the zoom has answered.
    func run(_ input: AnnotatorZoom.Input) {
        switch zoom.reduce(input) {
        case .spring(let level, let seconds)?:
            // The title sits over another part of the screen once a step has moved the frame.
            zoomTween.animate(to: level, duration: motionScaled(seconds)) { [weak self] in
                self?.run(.arrived)
                self?.measureTitleInk()
            }
        case .place(let frame, let picture, let barTop)?:
            guard window != nil else { return }
            moveFrame(to: frame, picture: picture, barTop: barTop)
        case .movePicture(let picture)?:
            editor.pictureRect = picture
        case nil:
            break
        }
    }

    /// The editor's zoom keys and its double-click on empty space.
    func zoomRequested(_ request: EditorCore.ZoomRequest) {
        switch request {
        case .zoomIn: run(.zoomIn)
        case .zoomOut: run(.zoomOut)
        case .fit: run(.fit)
        case .smart(let point):
            run(.smart(at: cursorFraction(editor.convert(editor.viewPoint(forImagePoint: point), to: nil))))
        }
    }

    /// A pinch, a scroll or a two-finger double tap over the editor. Cmd or ctrl on a scroll zooms,
    /// as the pinch does; a plain scroll moves the part of a magnified picture in view. A trackpad's
    /// scroll is a gesture, and lifting the fingers lets go of a pull below the fit; momentum after
    /// the lift is ignored, as a pinch's end is, so the zoom stops where the hand did. A mouse wheel
    /// has no phases, and each notch is a step.
    func zoomGesture(_ event: NSEvent) {
        switch event.type {
        case .magnify:
            if event.phase == .ended || event.phase == .cancelled { run(.lift); return }
            run(.pinch(by: event.magnification, at: cursorFraction(event.locationInWindow)))
        case .smartMagnify:
            run(.smart(at: cursorFraction(event.locationInWindow)))
        case .scrollWheel:
            let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Self.wheelLinePoints
            if event.modifierFlags.intersection([.command, .control]).isEmpty {
                run(.pan(by: CGVector(dx: event.scrollingDeltaX * line, dy: event.scrollingDeltaY * line)))
                return
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { run(.lift); return }
            guard event.momentumPhase.isEmpty else { return }
            run(.wheel(points: event.scrollingDeltaY * line, at: cursorFraction(event.locationInWindow),
                       fingers: !event.phase.isEmpty))
        default:
            break
        }
    }

    /// Zoom's springs are in code rather than in the tweaks, but the motion scale still shortens
    /// them, so `ui.motion: 0` and Reduce Motion land a zoom step at once.
    func motionScaled(_ seconds: Double) -> Double { seconds * Settings.shared.motionScale }

    static func edgePull(_ ui: UITweaks) -> AnnotatorZoom.EdgePull {
        AnnotatorZoom.EdgePull(band: ui.zoomEdgeBandPoints, pull: ui.zoomEdgePull)
    }

    /// A line of a mouse wheel's notch in points, for wheels that report lines rather than points.
    static let wheelLinePoints: CGFloat = 10

    /// A point in the window's coordinates as a fraction of the visible frame, x from the left and
    /// y from the top.
    func cursorFraction(_ locationInWindow: NSPoint) -> CGPoint? {
        guard let frameView, frameView.bounds.width > 0, frameView.bounds.height > 0 else { return nil }
        let p = frameView.convert(locationInWindow, from: nil)
        return Zoom.clamped(CGPoint(x: p.x / frameView.bounds.width, y: 1 - p.y / frameView.bounds.height))
    }
}
