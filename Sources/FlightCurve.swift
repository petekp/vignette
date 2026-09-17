import CoreGraphics

/// The shape of a flight: how far it bows to one side of the straight path, and how much the card
/// swells, at every point along the way. Both peak in the middle and are nothing at the ends, so a
/// card still leaves and lands exactly where the layout puts it.
///
/// The amounts come from the motion-scaled tweaks, so `motion: 0` and Reduce Motion give a straight
/// line. Pure geometry: no view and no settings, so the math stands on its own.
struct FlightCurve: Equatable {
    var arc: CGFloat        // how far the path bows, as a fraction of its length
    var arcMax: CGFloat     // the bow never exceeds this many points, however long the flight
    var depth: CGFloat      // how much larger the card is in the middle; 0.05 is five percent

    static let straight = FlightCurve(arc: 0, arcMax: 0, depth: 0)

    init(arc: CGFloat, arcMax: CGFloat, depth: CGFloat) {
        self.arc = arc
        self.arcMax = arcMax
        self.depth = depth
    }

    init(ui: UITweaks) {
        self.init(arc: ui.flightArc, arcMax: ui.flightArcMax, depth: ui.flightDepth)
    }

    /// Where a card is drawn relative to the straight path, and how much bigger it is there.
    struct Placement: Equatable {
        var offset: CGSize
        var scale: CGFloat
    }

    /// The placement for a card the straight path has carried to `point`. `from` and `to` are the
    /// ends of the path, in the same coordinates as `point`, with y down.
    func placement(at point: CGPoint, from: CGPoint, to: CGPoint) -> Placement {
        let flat = Placement(offset: .zero, scale: 1)
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return flat }
        // How far along the path the card is: 0 at `from`, 1 at `to`. A spring overshoots its
        // target, and past either end the card is simply on the line.
        let t = min(1, max(0, ((point.x - from.x) * dx + (point.y - from.y) * dy) / (length * length)))
        let peak = 4 * t * (1 - t)      // 0 at both ends, 1 in the middle
        guard peak > 0 else { return flat }
        // Perpendicular to the path: up from one that runs mostly sideways, left from one that runs
        // mostly up or down, so the bow swings into the screen instead of off its right edge. The
        // side belongs to the line and not to the direction of travel, so a flight that turns
        // around keeps bowing the same way instead of snapping across the path.
        var nx = -dy / length, ny = dx / length
        if abs(dx) >= abs(dy) ? ny > 0 : nx > 0 { nx = -nx; ny = -ny }
        let bow = min(length * arc, arcMax) * peak
        return Placement(offset: CGSize(width: nx * bow, height: ny * bow), scale: 1 + depth * peak)
    }
}
