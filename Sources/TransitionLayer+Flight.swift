import AppKit

extension TransitionLayer {
    struct Flight: Identifiable {
        let id: UUID
        var image: NSImage
        /// The drawing's marks over the image, or nil when it has none.
        var marks: MarkLayers?
        var frame: CGRect      // top-left origin, in the layer's own coordinates
        var look: Look
        /// The shape the picture is drawn in, width over height, filling the frame: the image's own,
        /// or no wider than the frame where the look fills its width. Animated with the frame.
        var aspect: CGFloat
        var opacity: Double = 1
        var caption: Caption?
        /// Leaving the annotator, which still draws the title: the flight shows its caption from
        /// `annotatorStoppedDrawing`.
        var leavingAnnotator = false
        /// The path this flight is on, and the one it was on before it was aimed again.
        var path = Path()
        var previousPath = Path()
        /// 0 the moment a flight is aimed down a new path, 1 once it has settled there. In between
        /// the bow comes from both paths, so a retarget bends instead of stepping sideways.
        var blend: CGFloat = 1
        var generation = 0
        /// Runs when `end(id:)` or `endAll()` removes this flight before it arrived, so whatever it
        /// was covering can take over. Aiming the flight again replaces it; arriving clears it. The
        /// annotator's outbound flight and each of `converge`'s pieces set it.
        var dropped: (() -> Void)?
    }
}
