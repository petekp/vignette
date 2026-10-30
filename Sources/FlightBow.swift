import SwiftUI

/// Bows the straight path the flight's frame is taking, and swells the card around its middle.
/// Its animatable data is that frame's centre and the blend between the flight's paths, so both
/// the position along the path and a change of path move with the frame's own animation: a flight
/// aimed somewhere else in mid-air bends across to the new bow instead of stepping sideways.
struct Bow: GeometryEffect {
    var center: CGPoint
    var path: TransitionLayer.Path
    var previous: TransitionLayer.Path
    var blend: CGFloat

    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGFloat> {
        get { AnimatablePair(CGPoint.AnimatableData(center.x, center.y), blend) }
        set {
            center = CGPoint(x: newValue.first.first, y: newValue.first.second)
            blend = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let placed = FlightCurve.blend(previous.curve.placement(at: center, from: previous.from, to: previous.to),
                                       path.curve.placement(at: center, from: path.from, to: path.to),
                                       blend)
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        return ProjectionTransform(CGAffineTransform.identity
            .translatedBy(x: placed.offset.width, y: placed.offset.height)
            .translatedBy(x: mid.x, y: mid.y)
            .scaledBy(x: placed.scale, y: placed.scale)
            .translatedBy(x: -mid.x, y: -mid.y))
    }
}
