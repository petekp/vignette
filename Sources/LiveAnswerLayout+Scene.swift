import CoreGraphics

extension LiveAnswerLayout {
    /// What the layout keeps clear of, and where it may draw.
    struct Scene {
        /// The window the answer is about, less a margin: nothing is drawn outside it.
        var room: CGRect
        /// The person's marks, in global top-left points.
        var ink: [Mark]
        /// The window's text lines, in global top-left points.
        var text: [CGRect]
        /// The tags of the person's notes, in global top-left points.
        var notes: [CGRect] = []
        /// The visible screen the window is on. A popover is a window of its own, so it may hang past
        /// the window's edge, and AppKit keeps it on this; nil keeps it in `room`.
        var screen: CGRect? = nil
    }

    struct Sizes {
        /// A note's font size, in pt.
        var textSize: CGFloat
        /// The widest a note wraps at, in pt.
        var textWidth: CGFloat
        var style: TextStyle
    }
}

extension LiveAnswerLayout.Sizes {
    /// Live ink's sizes in `ui`.
    init(ui: UITweaks) {
        self.init(textSize: ui.liveInkTextSize, textWidth: ui.liveInkTextWidth, style: ui.textStyle)
    }
}
