import CoreGraphics

extension AnnotatorZoom {
    enum Input: Equatable {
        case prepare(fitted: CGRect, room: CGRect, bar: ZoomBar)   // an image opens in `fitted`, with `bar` under it; the frame grows within `room`
        case landed                                    // the flight put the image down
        case lifted                                    // the flight's image is gone: only the window draws the image
        case refit(fitted: CGRect, room: CGRect, bar: ZoomBar)     // the room changed under the open image, which fits in `fitted` now
        case refitTick(CGFloat)                        // the re-fit's spring now, from 0 at the change to 1
        case zoomIn, zoomOut, fit                      // Cmd+Plus, Cmd+Minus, Cmd+0
        case smart(at: CGPoint?)                       // a two-finger double tap, or a double-click on empty space
        case pinch(by: CGFloat, at: CGPoint?)          // a pinch's magnification
        case wheel(points: CGFloat, at: CGPoint?, fingers: Bool)   // a scroll with Cmd or Ctrl held
        case lift                                      // the fingers left the trackpad
        case pan(by: CGVector)                         // a plain scroll, in points
        case reveal(CGRect, image: CGSize)             // the caret, in image px
        case tick(CGFloat)                             // the spring's level now
        case arrived                                   // the spring reached its target
        case close                                     // the card is about to fly home
    }

    enum Effect: Equatable {
        /// Carry the level to `to` on a spring of this many seconds, before the motion scale.
        case spring(to: CGFloat, seconds: Double)
        /// A tick: the frame on screen, the picture in the editor's coordinates, which run down from
        /// the top of the frame, and the top edge of the bar under the frame. All three are set in
        /// one turn of the run loop.
        case place(frame: CGRect, picture: CGRect, barTop: CGFloat)
        /// A pan: the picture moves and the frame stays.
        case movePicture(CGRect)
        /// The room changed: carry the frame, the picture and the bar from where they are drawn to
        /// where the new room puts them, on a spring from 0 to 1 of this many seconds, before the
        /// motion scale. Each of its ticks comes back as `.refitTick`.
        case refit(seconds: Double)
    }

    /// What a `.place` draws: the frame on screen, the picture in the editor's coordinates, and the
    /// middle of the bar's top edge.
    struct Placement: Equatable {
        var frame: CGRect
        var picture: CGRect
        var barTop: CGFloat
        var barCenter: CGFloat

        /// `t` of the way from this placement to `end`. Every edge moves in a straight line, so a
        /// picture that covers both frames covers each one on the way, and one of the image's shape
        /// keeps it. On a pixel grid the frame's edges are rounded inward, so it stays covered.
        func blended(to end: Placement, by t: CGFloat, pixelScale: CGFloat?) -> Placement {
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            func mix(_ a: CGRect, _ b: CGRect) -> CGRect {
                CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY), width: mix(a.width, b.width), height: mix(a.height, b.height))
            }
            let exact = mix(frame, end.frame)
            let shown = pixelScale.map { Zoom.aligned(exact, to: $0, within: exact) } ?? exact
            // The picture runs down from the frame's top-left corner, which the rounding moved.
            let picture = mix(self.picture, end.picture)
                .offsetBy(dx: exact.minX - shown.minX, dy: shown.maxY - exact.maxY)
            return Placement(frame: shown, picture: picture, barTop: mix(barTop, end.barTop),
                             barCenter: mix(barCenter, end.barCenter))
        }
    }

    /// Where an image fits and the room it may grow within, as `prepare` and `refit` give them.
    struct Fit: Equatable {
        var fitted: CGRect
        var room: CGRect
        var bar: ZoomBar
    }

    enum Phase: Equatable {
        case closed, flying, landed, closing
    }

    /// How far from each edge of the picture a zoom holds that edge, in points, and the part of that
    /// band where it holds it exactly (`Zoom.pulledToEdges`).
    struct EdgePull: Equatable {
        var band: CGFloat
        var pull: CGFloat
    }
}

extension AnnotatorZoom.Phase: CustomStringConvertible {
    var description: String {
        switch self {
        case .closed: return "closed"
        case .flying: return "flying"
        case .landed: return "landed"
        case .closing: return "closing"
        }
    }
}
