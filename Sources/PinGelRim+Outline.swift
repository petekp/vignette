import CoreGraphics

/// The popover's outline as a closed line of points, moved in by half the rim's width.
extension PinGelRim {
    /// `path`, one closed outline, as points: each curve cut into `steps` straight pieces, each point
    /// through `convert`, and points closer than half a point to the one before left out. Nil for a
    /// path of more than one outline.
    static func points(of path: CGPath, steps: Int = 6, _ convert: (CGPoint) -> CGPoint) -> [CGPoint]? {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var outlines = 0
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                outlines += 1
                current = element.points[0]
                points.append(current)
            case .addLineToPoint:
                current = element.points[0]
                points.append(current)
            case .addQuadCurveToPoint:
                let control = element.points[0], end = element.points[1]
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps), u = 1 - t
                    points.append(CGPoint(x: u * u * current.x + 2 * u * t * control.x + t * t * end.x,
                                          y: u * u * current.y + 2 * u * t * control.y + t * t * end.y))
                }
                current = end
            case .addCurveToPoint:
                let one = element.points[0], two = element.points[1], end = element.points[2]
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    points.append(CGPoint(x: a * current.x + b * one.x + c * two.x + d * end.x,
                                          y: a * current.y + b * one.y + c * two.y + d * end.y))
                }
                current = end
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        guard outlines == 1 else { return nil }
        var kept: [CGPoint] = []
        for point in points.map(convert) where kept.last.map({ hypot(point.x - $0.x, point.y - $0.y) >= 0.5 }) ?? true {
            kept.append(point)
        }
        if let first = kept.first, let last = kept.last, kept.count > 1, hypot(first.x - last.x, first.y - last.y) < 0.5 { kept.removeLast() }
        return kept.count >= 3 ? kept : nil
    }

    /// `line`, a closed outline, with each point moved `distance` toward the inside, along the mean of
    /// its two sides' inward normals and further at a sharp corner, as far as `farthest` times `distance`.
    static func inset(_ line: [CGPoint], by distance: CGFloat, farthest: CGFloat = 3) -> [CGPoint]? {
        let count = line.count
        guard count >= 3 else { return nil }
        var twiceArea: CGFloat = 0
        for index in 0..<count {
            let a = line[index], b = line[(index + 1) % count]
            twiceArea += a.x * b.y - b.x * a.y
        }
        guard twiceArea != 0 else { return nil }
        // Positive area puts the inside on the left of each side, as (-dy, dx) from its direction.
        let way: CGFloat = twiceArea > 0 ? 1 : -1
        func inward(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            let dx = b.x - a.x, dy = b.y - a.y, length = max(hypot(dx, dy), 1e-6)
            return CGVector(dx: -dy / length * way, dy: dx / length * way)
        }
        return line.indices.map { index in
            let before = line[(index + count - 1) % count], here = line[index], after = line[(index + 1) % count]
            let one = inward(before, here), two = inward(here, after)
            var mean = CGVector(dx: one.dx + two.dx, dy: one.dy + two.dy)
            let length = hypot(mean.dx, mean.dy)
            mean = length > 1e-6 ? CGVector(dx: mean.dx / length, dy: mean.dy / length) : one
            let reach = distance / max(mean.dx * one.dx + mean.dy * one.dy, 1 / farthest)
            return CGPoint(x: here.x + mean.dx * reach, y: here.y + mean.dy * reach)
        }
    }
}
