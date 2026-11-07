import QuartzCore

/// A zoom step worked out ahead, for Core Animation to play (`ui.coreAnimationPlaysZoomSteps`):
/// where the frame and the picture are at each refresh of the display, from the spring the zoom's
/// tween is on, run through the zoom's own ticks. The layers then show what the ticks would have
/// placed, on the window server's clock rather than the main thread's.
struct ZoomKeyframes: Equatable {
    /// When the first keyframe is on screen, in `CACurrentMediaTime`'s time: the spring's last tick.
    var start: CFTimeInterval
    /// Seconds between keyframes: one refresh of the display.
    var interval: Double
    /// The frame on screen at each keyframe, as `AnnotatorZoom.Effect.place` gives it.
    var frames: [CGRect]
    /// The picture at each keyframe, in the coordinates of that keyframe's frame, down from its top.
    var pictures: [CGRect]

    /// Each keyframe is shown for one interval, the last one included.
    var duration: Double { interval * Double(frames.count) }

    /// The step from where `flight` is to its target. `zoom` is copied, so the zoom on screen is not
    /// moved. Nil when the step has nothing to play.
    static func make(from zoom: AnnotatorZoom, flight: Tween.Flight, interval: Double) -> ZoomKeyframes? {
        guard interval > 0 else { return nil }
        var ahead = zoom
        var frames: [CGRect] = [], pictures: [CGRect] = []
        for level in flight.samples(every: interval) {
            guard case .place(let frame, let picture)? = ahead.reduce(.tick(level)) else { return nil }
            frames.append(frame)
            pictures.append(picture)
        }
        guard frames.count > 1 else { return nil }
        return ZoomKeyframes(start: flight.at, interval: interval, frames: frames, pictures: pictures)
    }

    /// An animation of `keyPath` through `values`, one per keyframe, each held for its interval.
    /// Held rather than blended: every frame and picture the zoom places is on the screen's device
    /// pixels, and a value part way between two of them is not.
    func animation(_ keyPath: String, _ values: [Any], on layer: CALayer, frameRate: Float) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.calculationMode = .discrete
        animation.keyTimes = (0...values.count).map { NSNumber(value: Double($0) / Double(values.count)) }
        animation.beginTime = layer.convertTime(start, from: nil)
        animation.duration = duration
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate / 2, maximum: frameRate, preferred: frameRate)
        return animation
    }

    /// The key every animation of a step is added under, so the next step or a hand replaces it.
    static func key(_ keyPath: String) -> String { "zoomStep.\(keyPath)" }
}
