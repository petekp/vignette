import CoreGraphics
import Foundation

extension EditorCore {
    /// A nudge and a Shift nudge, in pt.
    static let nudge: CGFloat = 1
    static let longNudge: CGFloat = 10
    /// How far right and down a duplicate or a paste lands from its original, in pt.
    static let copyOffset: CGFloat = 10
    /// Marks whose tops are this close, in pt, are one row in Tab's reading order.
    static let rowTolerance: CGFloat = 16
    /// The smallest a text can be scaled to, in pt.
    static let smallestTextSize: CGFloat = 6
    /// Shift snaps an arrow's angle to steps of this many radians: 15°.
    static let snapAngle = CGFloat.pi / 12
    /// The pause after the last change before the drawing goes to the host.
    static let handOverDelay: TimeInterval = 0.3
    /// The room between a box's stroke and the note typed for it, in pt.
    static let noteGap: CGFloat = 8
    /// A freehand stroke keeps a point this many screen pt from the last one it kept.
    static let strokeSpacing: CGFloat = 2
    /// A freehand arrow's curve misses the smoothed stroke by at most this many screen pt.
    static let strokeTolerance: CGFloat = 1.5
    /// A stroke that strays no further than this many screen pt, or this share of the line between its
    /// ends, whichever is more, draws a straight arrow.
    static let straightStroke: CGFloat = 6
    static let straightShare: CGFloat = 0.04
}
