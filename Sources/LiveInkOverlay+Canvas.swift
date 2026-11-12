import AppKit
import QuartzCore

extension LiveInkOverlay {
    /// The canvas: the pointer field, the marks and the stroke being drawn. Flipped, so its layers run
    /// from the screen's top-left corner, y down, as the marks' coordinates do.
    final class Canvas: NSView {
        var onStroke: (([CGPoint]) -> Void)?
        var onStrokeMoved: (([CGPoint]) -> Void)?
        var onHover: ((CGPoint) -> Void)?
        let field: PointerField
        /// The screen's top-left corner in global top-left points, the coordinates marks are in.
        private(set) var origin: CGPoint = .zero
        private let host = CALayer()
        /// The marks, in global points: moved by the screen's origin so each lands on this screen.
        let marksLayer: LiveMarksLayer
        /// The stroke being drawn, above the marks, moved as they are.
        private var pen: InkMarkLayer
        /// Builds the stroke being drawn as its points come.
        private var hand = InkHand.Pen(feel: InkHand.Feel())
        private var stroke: [CGPoint] = []
        private let scale: CGFloat

        var isTracking: Bool { !stroke.isEmpty }

        init(frame: CGRect, scale: CGFloat) {
            self.scale = scale
            field = PointerField(scale: scale)
            pen = InkMarkLayer(scale: scale)
            marksLayer = LiveMarksLayer(scale: scale)
            super.init(frame: frame)
            layer = host
            wantsLayer = true
            host.contentsScale = scale
            host.addSublayer(field.layer)
            for layer in [marksLayer, pen] {
                layer.anchorPoint = .zero
                host.addSublayer(layer)
            }
            // The panel never becomes key, so only an always-active area hears the pointer move.
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }

        func fit(origin: CGPoint) {
            self.origin = origin
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [marksLayer, pen] {
                layer.setAffineTransform(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            }
            field.layer.frame = bounds
            CATransaction.commit()
            marksLayer.placePopovers()
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        /// AppKit sets a layer-hosting view's root layer geometry from the view, so the view itself
        /// must be flipped for the marks to run y down.
        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        func showPen(_ points: [CGPoint], longest: CGFloat, markStyle: MarkStyle) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let feel = Settings.shared.data.ui.inkHandFeel
            if hand.feel != feel { hand = InkHand.Pen(feel: feel) }
            let stroke = hand.stroke(through: points)
            pen.isHidden = stroke.points.count < 2
            guard stroke.points.count > 1 else { return }
            pen.showPen(stroke, settled: hand.settled.points.count, longest: longest, markStyle: markStyle)
        }

        override func mouseMoved(with event: NSEvent) { take(.moved(location(of: event))) }
        override func mouseDown(with event: NSEvent) {
            if (window as? LiveInkOverlay)?.tapTakesPresses == true {
                Log.write("[live-ink] error a press reached the overlay while the tap is on")
            }
            take(.pressed(location(of: event)))
        }
        override func mouseDragged(with event: NSEvent) { take(.dragged(location(of: event))) }
        override func mouseUp(with event: NSEvent) { take(.released(location(of: event))) }

        func take(_ input: Input) {
            switch input {
            case .moved(let point):
                guard !isTracking else { return }
                onHover?(point)
            case .pressed(let point):
                stroke = [point]
                onStrokeMoved?(stroke)
            case .dragged(let point):
                guard isTracking else { return }
                stroke.append(point)
                onStrokeMoved?(stroke)
            case .released(let point):
                guard isTracking else { return }
                stroke.append(point)
                endStroke()
            }
        }

        func endStroke() {
            guard isTracking else { return }
            let finished = stroke
            cancelStroke()
            onStroke?(finished)
        }

        /// Fades out the stroke shown, which no mark takes over, under a fresh pen for the next.
        func fadePen() {
            guard !pen.isHidden else { return }
            let fading = pen
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pen = InkMarkLayer(scale: scale)
            pen.isHidden = true
            pen.setAffineTransform(fading.affineTransform())
            host.insertSublayer(pen, above: fading)
            CATransaction.commit()
            LiveMarksLayer.fadeOut(fading)
        }

        func cancelStroke() {
            guard isTracking else { return }
            stroke = []
            onStrokeMoved?([])
        }

        /// In global top-left points.
        private func location(of event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            return CGPoint(x: local.x + origin.x, y: local.y + origin.y)
        }
    }
}
