import SwiftUI

/// Animation helper honoring the tweakable curves.
@MainActor
enum Anim {
    /// The bounce of a card's slide-in spring and of the `spring` flight timing (`FlightTiming`).
    static let flightBounce = 0.15

    static func swiftUI(_ curve: String, duration: Double) -> Animation {
        switch curve {
        case "easeOut": return .easeOut(duration: duration)
        case "easeInOut": return .easeInOut(duration: duration)
        case "linear": return .linear(duration: duration)
        default: return spring(duration, bounce: flightBounce)   // "spring"
        }
    }

    /// A SwiftUI spring that settles in about `duration`. Springs are the curve for every SwiftUI
    /// motion here: when one is interrupted by another on the same property, SwiftUI keeps the
    /// velocity, so a card that turns around or changes place mid-flight blends instead of jumping.
    static func spring(_ duration: Double, bounce: Double = 0) -> Animation {
        duration > 0 ? .spring(duration: duration, bounce: bounce) : .linear(duration: 0)
    }

    /// When the same spring first reaches its target. From there until it settles it is on the far
    /// side of it, coming back, so a rect animated by it contains the target on every side and
    /// covers anything drawn there. A spring that does not overshoot never reaches its target;
    /// this is then its whole settling time, and a caller that takes the earlier of this and
    /// `settle` gets no early cover, which is the right answer for one.
    static func passesTarget(_ duration: Double, bounce: Double = 0) -> Double {
        guard duration > 0 else { return 0 }
        let spring = Spring(duration: duration, bounce: bounce)
        let step = duration / 64
        var t = 0.0
        while t <= spring.settlingDuration {
            if spring.value(target: 1.0, time: t) >= 1 { return t }
            t += step
        }
        return spring.settlingDuration
    }

    /// When the animation `swiftUI(curve, duration:)` makes first covers `fraction` of its way.
    static func reaches(_ fraction: Double, curve: String, duration: Double) -> Double {
        switch curve {
        case "easeOut": return reaches(fraction, duration: duration) { UnitCurve.easeOut.value(at: $0) }
        case "easeInOut": return reaches(fraction, duration: duration) { UnitCurve.easeInOut.value(at: $0) }
        case "linear": return max(0, min(1, fraction)) * duration
        default: return reaches(fraction, spring: duration, bounce: flightBounce)
        }
    }

    /// When `spring(duration, bounce:)` first covers `fraction` of its way.
    static func reaches(_ fraction: Double, spring duration: Double, bounce: Double = 0) -> Double {
        let spring = Spring(duration: duration, bounce: bounce)
        return reaches(fraction, duration: duration) { spring.value(target: 1.0, time: $0 * duration) }
    }

    /// Searches `progress`, a function of the time as a fraction of `duration`, in 1/240 s steps.
    private static func reaches(_ fraction: Double, duration: Double, progress: (Double) -> Double) -> Double {
        guard duration > 0, fraction > 0 else { return 0 }
        let step = 1.0 / 240
        var t = 0.0
        while t < duration * 4, progress(t / duration) < fraction { t += step }
        return t
    }

    /// When the same spring is within `within` points of a target `distance` points away. Its tail
    /// runs well past its nominal duration: at 1.15 times it is still about 0.4% short, which is
    /// several points across a screen. Uses SwiftUI's own spring, so it matches what it animates.
    static func settle(_ duration: Double, bounce: Double = 0, distance: CGFloat, within: CGFloat) -> Double {
        guard duration > 0, distance > within else { return 0 }
        let spring = Spring(duration: duration, bounce: bounce)
        let tolerance = Double(within / distance)
        let step = duration / 32
        var t = spring.settlingDuration
        while t > step {
            if abs(1 - spring.value(target: 1.0, time: t - step)) > tolerance { return t }
            t -= step
        }
        return 0
    }
}
