import AppKit
import SwiftUI

extension TransitionLayer {
    /// An agent's title leaving the annotator with its image: the block as the annotator drew it,
    /// above the flight's picture, scaled with the flight's frame from `frameWidth`.
    struct Caption {
        var image: NSImage
        /// Its top-left corner from the frame's, in points, y down, at `frameWidth`.
        var offset: CGPoint
        var frameWidth: CGFloat
        var opacity: Double
    }
}

/// A flight's caption, pinned to its picture's top-left corner and scaled with its frame.
struct FlightCaption: View {
    let caption: TransitionLayer.Caption
    let frameWidth: CGFloat
    /// Apart from the fade's opacity, so showing it does not touch the fade.
    let shown: Bool

    var body: some View {
        Image(nsImage: caption.image)
            .offset(x: caption.offset.x, y: caption.offset.y)
            .scaleEffect(frameWidth / max(caption.frameWidth, 1), anchor: .topLeading)
            .opacity(caption.opacity)
            .opacity(shown ? 1 : 0)
    }
}
