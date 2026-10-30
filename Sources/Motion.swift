import Foundation

/// How much of every animation to play. One rule, so a script or a person can turn motion off.
enum Motion {
    static func scale(reduceMotion: Bool, multiplier: Double) -> Double {
        reduceMotion ? 0 : min(max(multiplier.isFinite ? multiplier : 1, 0), 1)
    }
}
