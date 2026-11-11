import AppKit

// MARK: Zoom steps played by Core Animation

extension EditorView {
    /// Whether all the editor shows is on layers a zoom step can be played on. A text being typed, or
    /// one lingering over its bitmap, is a text view, and a gesture's marks follow the pointer, so
    /// either keeps the step on the ticks.
    var takesZoomStepsOnLayers: Bool {
        core.typing == nil && core.gesture == nil && typingField == nil && lingering == nil
    }

    /// Plays `step` on the picture's layer and the overlay's. The view is at the step's end already
    /// (`setSize(_:picture:)`). It is as tall as the last keyframe's frame and sits on the frame's
    /// bottom edge, while each keyframe's picture is placed from the top of its own frame, so each is
    /// moved down by the difference in height.
    func playZoomStep(_ step: ZoomKeyframes, frameRate: Float) {
        let width = CGFloat(core.drawing.pixels.width)
        guard width > 0, let height = step.frames.last?.height else { return }
        let transforms = zip(step.pictures, step.frames).map { picture, frame in
            CGAffineTransform(a: picture.width / width, b: 0, c: 0, d: picture.width / width,
                              tx: picture.minX, ty: picture.minY + height - frame.height)
        }
        let layer = picture.layer
        let values = transforms.map { NSValue(caTransform3D: CATransform3DMakeAffineTransform($0)) }
        layer.add(step.animation("transform", values, on: layer, frameRate: frameRate), forKey: ZoomKeyframes.key("transform"))
        overlay.play(step, transforms: transforms, frameRate: frameRate)
    }

    func stopZoomStep() {
        picture.layer.removeAnimation(forKey: ZoomKeyframes.key("transform"))
        overlay.stopPlaying()
    }
}
