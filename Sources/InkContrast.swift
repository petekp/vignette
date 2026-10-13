import CoreGraphics

/// Which of live ink's two colours stands out from what is behind it: the one with the higher
/// contrast ratio (WCAG 2) against the content's luminance. The gel's strokes and the pointer's lamp
/// both choose this way (docs/live-ink-lamp-and-stroke-colour-2026-10-12.md).
struct InkContrast: Equatable {
    /// The relative luminance of the ice and of the deep blue, 0 to 1.
    let ice: Double
    let deep: Double

    init(ice: CGColor, deep: CGColor) {
        self.ice = Self.luminance(of: ice)
        self.deep = Self.luminance(of: deep)
    }

    init(_ ui: UITweaks) {
        self.init(ice: SRGB(hex: ui.inkGelLight)?.cgColor ?? InkGel.defaultIce, deep: SRGB(hex: ui.inkGelDeep)?.cgColor ?? InkGel.defaultDeep)
    }

    /// Whether the deep blue stands out more than the ice from a cell of the backdrop, whose value is
    /// its brightness as the maps keep it: sRGB encoded, 0 to 1.
    func deepWins(behind cell: CGFloat) -> Bool {
        let behind = Self.linear(Double(cell))
        return Self.ratio(deep, behind) > Self.ratio(ice, behind)
    }

    /// A stroke's colour from the share of its length over content where the deep blue wins: 0 the
    /// ice, 1 the deep blue, and `mixed` for a stroke with a real share of both.
    static func state(deepShare: CGFloat, mixed: CGFloat) -> CGFloat {
        func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
            let t = min(max((x - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
        return deepShare <= 0.5 ? mixed * smoothstep(0.05, 0.2, deepShare)
                                : mixed + (1 - mixed) * smoothstep(0.8, 0.95, deepShare)
    }

    private static func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    private static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    private static func luminance(of colour: CGColor) -> Double {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = colour.converted(to: space, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else { return 0 }
        return 0.2126 * linear(Double(c[0])) + 0.7152 * linear(Double(c[1])) + 0.0722 * linear(Double(c[2]))
    }
}
