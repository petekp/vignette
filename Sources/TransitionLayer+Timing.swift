import SwiftUI

/// How every flight moves down its path and comes to rest, from `ui.flightTiming`. A spring keeps a
/// flight's velocity when it is aimed somewhere else in mid-air. A curve reaches its target exactly
/// at the end of its duration, and a flight aimed again in mid-air changes speed in one frame.
@MainActor
enum FlightTiming: String, CaseIterable {
    /// Goes past its target and comes back by `Anim.flightBounce`, so it covers the target early.
    case spring
    /// Comes to rest without passing its target, so it covers the target only once it is nearly there.
    case springNoBounce
    case easeOut
    case linear

    init(_ ui: UITweaks) { self = Self(rawValue: ui.flightTiming) ?? Self(rawValue: UITweaks().flightTiming)! }

    private var bounce: Double? {
        switch self {
        case .spring: return Anim.flightBounce
        case .springNoBounce: return 0
        case .easeOut, .linear: return nil
        }
    }

    func animation(_ duration: Double) -> Animation {
        if let bounce { return Anim.spring(duration, bounce: bounce) }
        guard duration > 0 else { return .linear(duration: 0) }
        return self == .easeOut ? .easeOut(duration: duration) : .linear(duration: duration)
    }

    /// When a flight `distance` points long is within `within` points of its target, so whatever
    /// takes its place there lands on the same pixels. A flight that does not pass its target lands
    /// `landingAfterCover` after it covers it.
    func settles(_ duration: Double, distance: CGFloat, within: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        if self == .spring {
            return Anim.settle(duration, bounce: Anim.flightBounce, distance: distance, within: within)
        }
        return covers(duration, distance: distance, within: within) + Self.landingAfterCover
    }

    /// When the flight first covers its target on every side, so a window put there is hidden behind
    /// it. The bouncing spring covers it when it first passes it. The spring with no bounce covers it
    /// once it is within `within` points, moving slowly. A curve still moves fast at its end, so it
    /// covers once its last frame is on screen, with the flight standing still on the target.
    func covers(_ duration: Double, distance: CGFloat, within: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        switch self {
        case .spring:
            let settled = Anim.settle(duration, bounce: Anim.flightBounce, distance: distance, within: within)
            return min(settled, Anim.passesTarget(duration, bounce: Anim.flightBounce))
        case .springNoBounce:
            return Anim.settle(duration, bounce: 0, distance: distance, within: within)
        case .easeOut, .linear:
            return duration + Self.lastFrameShown
        }
    }

    /// How long after a flight covers its target the window or card that takes its place arrives:
    /// three refreshes at 60 Hz. The stack's panel is ordered in when the flight home covers its
    /// slot, and it has to be on screen before the card lands in it (docs/exit-panel-2026-11-01.md).
    private static let landingAfterCover = 0.05

    /// A flight's frames reach the screen after the moment they are computed for
    /// (docs/handover-2026-09-18.md), and a linear flight's last frame on a 1,200-point path still
    /// moves about 29 points at 120 Hz. Three refreshes at 60 Hz.
    private static let lastFrameShown = 0.05
}
