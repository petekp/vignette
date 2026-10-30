import Foundation
import CoreGraphics

/// The pointer's events a hand sends as it draws along a line, each with its time from when the pen
/// landed: closer together where the line turns, as a hand slows there, and where it lands and lifts.
/// The ink's width follows their spacing, as it does for the person's own strokes.
struct HandStroke: Equatable {
    let times: [TimeInterval]
    let points: [CGPoint]

    var duration: TimeInterval { times.last ?? 0 }

    /// A hand taking `duration` to draw the curve through `controls`, sending `rate` events a second.
    init(through controls: [CGPoint], duration: TimeInterval, rate: Double = 120) {
        let path = ArrowBody.Curve(through: controls)
        let curve = path.samples
        guard curve.count > 1, duration > 0 else {
            times = curve.map { _ in 0 }
            points = curve
            return
        }
        // The time to each point of the curve, at a speed that drops where it turns and at its ends.
        let lengths = path.lengths
        let total = max(lengths.last ?? 0, .ulpOfOne)
        var reached: [Double] = [0]
        for index in 1..<curve.count {
            let along = lengths[index] / total
            let ends = min(InkHand.ease(along / 0.12), InkHand.ease((1 - along) / 0.12))
            let speed = (0.35 + 0.65 * (1 - Self.turn(at: index, in: curve))) * (0.3 + 0.7 * ends)
            reached.append(reached[index - 1] + Double(lengths[index] - lengths[index - 1]) / Double(speed))
        }
        let scale = duration / max(reached.last ?? 1, .ulpOfOne)
        var times: [TimeInterval] = []
        var points: [CGPoint] = []
        var at = 1
        for event in 0...Int((duration * rate).rounded(.up)) {
            let time = min(Double(event) / rate, duration)
            while at < curve.count - 1, reached[at] * scale < time { at += 1 }
            let before = reached[at - 1] * scale, after = reached[at] * scale
            let t = after > before ? min(max(CGFloat((time - before) / (after - before)), 0), 1) : 1
            let a = curve[at - 1], b = curve[at]
            times.append(time)
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        self.times = times
        self.points = points
    }

    /// The events sent by `elapsed` seconds after the pen landed.
    func events(by elapsed: TimeInterval) -> [CGPoint] {
        let count = times.firstIndex { $0 > elapsed } ?? times.count
        return Array(points.prefix(count))
    }

    /// Where the hand is `elapsed` seconds after the pen landed, between the events either side.
    func position(at elapsed: TimeInterval) -> CGPoint? {
        guard let first = points.first else { return nil }
        guard let after = times.firstIndex(where: { $0 > elapsed }) else { return points.last }
        guard after > 0 else { return first }
        let t = CGFloat((elapsed - times[after - 1]) / (times[after] - times[after - 1]))
        let a = points[after - 1], b = points[after]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// How sharply the curve turns at `index`, from 0 for straight to 1 for a right angle or more.
    private static func turn(at index: Int, in curve: [CGPoint]) -> CGFloat {
        let reach = 2
        let a = curve[max(index - reach, 0)], b = curve[index], c = curve[min(index + reach, curve.count - 1)]
        let one = CGVector(dx: b.x - a.x, dy: b.y - a.y), two = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let lengths = hypot(one.dx, one.dy) * hypot(two.dx, two.dy)
        guard lengths > 0 else { return 0 }
        let cosine = (one.dx * two.dx + one.dy * two.dy) / lengths
        return min(acos(min(max(cosine, -1), 1)) / (.pi / 2), 1)
    }
}
