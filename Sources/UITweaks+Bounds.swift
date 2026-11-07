import Foundation

extension UITweaks {
    /// One entry of `bounds`. A plain struct, not a tuple, so the array can be `Sendable`.
    /// `@unchecked`: `WritableKeyPath` isn't marked `Sendable` in the standard library, but key
    /// paths are immutable value descriptors and safe to share across threads.
    struct Bound: @unchecked Sendable {
        let name: String
        let path: WritableKeyPath<UITweaks, Double>
        let range: ClosedRange<Double>
        init(_ name: String, _ path: WritableKeyPath<UITweaks, Double>, _ range: ClosedRange<Double>) {
            self.name = name; self.path = path; self.range = range
        }
    }

    /// Bounds outside which a value crashes, divides by zero, or makes NaN. Not design limits. Each is
    /// defined with its tweak in `TweakCatalog`.
    static let bounds: [Bound] = TweakCatalog.sections.flatMap(\.tweaks).compactMap { spec in
        switch spec.control {
        case .number(let path, _, _, _, let safe): Bound(spec.key, path, safe)
        default: nil
        }
    }
}
