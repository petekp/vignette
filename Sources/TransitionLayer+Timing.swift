import SwiftUI

/// How every flight moves down its path and comes to rest, from `ui.flightTiming`. A spring keeps a
/// flight's velocity when it is aimed somewhere else in mid-air. A curve lands exactly at the end of
/// its duration, and a flight aimed again in mid-air changes speed in one frame.
@MainActor
enum FlightTiming: String, CaseIterable {
    /// Goes past its target and comes back by `Anim.flightBounce`, so it covers the target early.
    case spring
    /// Comes to rest without passing its target, so it covers the target only once it has arrived.
    case springNoBounce
    case easeOut
    case linear

    init(_ ui: UITweaks) { self = Self(rawValue: ui.flightTiming) ?? .spring }

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
    /// takes its place there lands on the same pixels.
    func settles(_ duration: Double, distance: CGFloat, within: CGFloat) -> Double {
        if let bounce { return Anim.settle(duration, bounce: bounce, distance: distance, within: within) }
        return duration > 0 ? duration + Self.lastFrameShown : 0
    }

    /// When the flight first covers its target on every side, so a window put there is hidden behind it.
    func covers(_ duration: Double, distance: CGFloat, within: CGFloat) -> Double {
        let settled = settles(duration, distance: distance, within: within)
        guard let bounce else { return settled }
        return min(settled, Anim.passesTarget(duration, bounce: bounce))
    }

    /// A flight's frames reach the screen after the moment they are computed for: the spring's last
    /// frame was drawn further from its target than its clock said (docs/handover-2026-09-18.md). A
    /// curve's last frames still move several points each, so the window or card that takes a curve's
    /// place waits this long past its end, three frames at 60 Hz.
    private static let lastFrameShown = 0.05
}
