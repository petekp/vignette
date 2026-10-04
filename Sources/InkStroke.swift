import CoreGraphics

/// What a stroke drawn with live ink becomes, in the points it was drawn in. A stroke that comes back
/// near its start is a loop, drawn as the ellipse round it, as the editor draws one. Any other stroke
/// is an arrow, made the way the editor's arrow tool makes one from a freehand drag. A press whose
/// path is shorter than the editor's shortest arrow is a tap, which erases the mark under it.
enum InkStroke: Equatable {
    case ellipse(CGRect)
    case arrow(Mark.Arrow)
    case tap(CGPoint)
    /// No points, or a path the editor makes no arrow of: it does nothing.
    case nothing

    /// A loop's path is at least this many points long, and its ends are no further apart than
    /// `loopGap` points or `loopGapShare` of its length, whichever is more.
    static let loopLength: CGFloat = 120
    static let loopGap: CGFloat = 40
    static let loopGapShare: CGFloat = 0.18

    /// `shortestArrow` is in the points the stroke is in: `UITweaks.shortestArrow` on a screen.
    init(_ points: [CGPoint], shortestArrow: CGFloat) {
        guard let start = points.first, let end = points.last else { self = .nothing; return }
        let length = zip(points, points.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        if length < shortestArrow {
            self = .tap(start)
            return
        }
        let gap = hypot(end.x - start.x, end.y - start.y)
        if length >= Self.loopLength, gap <= max(Self.loopGap, length * Self.loopGapShare) {
            self = .ellipse(Self.bounds(of: points))
            return
        }
        // The editor's tolerances are in screen points, which is what live ink draws in.
        let arrow = Mark.Arrow.freehand(along: points, spacing: EditorCore.strokeSpacing, tolerance: EditorCore.strokeTolerance,
                                        straightWithin: EditorCore.straightStroke, straightShare: EditorCore.straightShare)
        self = arrow.map(InkStroke.arrow) ?? .nothing
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
