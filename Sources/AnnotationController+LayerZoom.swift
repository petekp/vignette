import AppKit

// MARK: Zoom steps played by Core Animation

/// With `ui.coreAnimationPlaysZoomSteps`, a zoom key's or a double-click's step is worked out ahead
/// (`ZoomKeyframes`) and handed to Core Animation: the frame, the clip, the shadow, the ring, the
/// title, the picture and the overlay each get the same keyframes, so the window server shows them in
/// step on its own clock. The views are laid out at the step's end when it begins. The tween still
/// ticks the zoom, which keeps the zoom's state current and the stack following the frame, so a hand
/// that takes over mid-step carries on from where the step is.
extension AnnotationController {
    /// Plays the step `zoomTween` has just started, or leaves it to the ticks when something on screen
    /// cannot follow layers: a text being typed, or a gesture in the editor.
    func playStepOnLayers() {
        let rate = Float(zoomScreen?.maximumFramesPerSecond ?? 60)
        guard rate > 0, let win = window, let frameLayer = frameView?.layer, let clipLayer = container?.layer,
              let flight = zoomTween.flight, editor.takesZoomStepsOnLayers,
              let step = ZoomKeyframes.make(from: zoom, flight: flight, interval: 1 / Double(rate)),
              let end = step.frames.last, let endPicture = step.pictures.last else {
            stopPlayingOnLayers()
            return
        }
        dropLayerStep()
        layerStep = step
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layOutFrame(end, picture: endPicture)
        let frames = step.frames.map { $0.offsetBy(dx: -win.frame.minX, dy: -win.frame.minY) }
        let sizes = frames.map(\.size)
        func play(_ layer: CALayer, _ keyPath: String, _ values: [Any]) {
            layer.add(step.animation(keyPath, values, on: layer, frameRate: rate), forKey: ZoomKeyframes.key(keyPath))
        }
        play(frameLayer, "position", frames.map { NSValue(point: Self.position(of: $0, anchor: frameLayer.anchorPoint)) })
        play(frameLayer, "bounds.size", sizes.map { NSValue(size: $0) })
        play(frameLayer, "shadowPath", sizes.map { Self.shadowPath(for: $0) })
        play(clipLayer, "position", sizes.map { NSValue(point: Self.position(of: CGRect(origin: .zero, size: $0), anchor: clipLayer.anchorPoint)) })
        play(clipLayer, "bounds.size", sizes.map { NSValue(size: $0) })
        if let ring { play(ring.outside, "path", sizes.map { ring.path(for: $0) }) }
        playTitle(step, frameRate: rate)
        editor.playZoomStep(step, frameRate: rate)
        CATransaction.commit()
    }

    /// Ends a step on layers where the ticks have the zoom now, so the views and the layers agree.
    func stopPlayingOnLayers() {
        guard let step = layerStep else { return }
        dropLayerStep()
        guard window != nil, step.frames.last != zoom.frame || step.pictures.last != zoom.picture else { return }
        moveFrame(to: zoom.frame, picture: zoom.picture)
    }

    /// Takes a step's animations off the layers and leaves the views where they are.
    func dropLayerStep() {
        guard layerStep != nil else { return }
        layerStep = nil
        for keyPath in ["position", "bounds.size", "shadowPath"] {
            frameView?.layer?.removeAnimation(forKey: ZoomKeyframes.key(keyPath))
            container?.layer?.removeAnimation(forKey: ZoomKeyframes.key(keyPath))
        }
        ring?.outside.removeAnimation(forKey: ZoomKeyframes.key("path"))
        stopTitle()
        editor.stopZoomStep()
    }

    /// Where a layer with `anchor` sits when its view's frame is `frame`.
    private static func position(of frame: CGRect, anchor: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + anchor.x * frame.width, y: frame.minY + anchor.y * frame.height)
    }
}
