import SwiftUI

/// The success check on a copied or sent card: a disc lit like polished metal, with a gradient from
/// its lit side to its far side, a bevelled rim, a fixed highlight, and a band of light that crosses
/// it once as it appears, blooming as it goes (`CheckGlare.metal`). Its look is the `check` settings,
/// and every length is a fraction of `diameter`, so it looks the same at every size. With no motion
/// the band is left out and the rest stays (docs/check-lab-2026-10-11.md).
struct MetalCheck: View {
    let diameter: CGFloat
    @ObservedObject private var settings = Settings.shared
    /// The Check Lab's hold on the glare; nil runs it once from when the check appears.
    @Environment(\.checkGlarePlace) private var heldPlace
    @Environment(\.displayScale) private var displayScale
    @State private var appeared = Date()
    @State private var crossed = false

    var body: some View {
        let ui = settings.motionUI
        metal(ui)
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                // A held place is a still, so the lab shows it with motion off too.
                if ui.checkGlare > 0, heldPlace != nil || (settings.motionScale > 0 && !crossed) {
                    TimelineView(.animation(paused: heldPlace != nil)) { context in
                        glare(ui, at: heldPlace ?? Self.place(at: context.date.timeIntervalSince(appeared), ui))
                    }
                }
            }
            .onAppear {
                appeared = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + ui.checkGlareDelay + ui.checkGlareDuration) { crossed = true }
            }
    }

    /// The glare's place `elapsed` seconds after the check appeared: 0 until the delay is over, 1 once
    /// it has crossed.
    private static func place(at elapsed: TimeInterval, _ ui: UITweaks) -> Double {
        min(1, max(0, (elapsed - ui.checkGlareDelay) / max(ui.checkGlareDuration, 0.01)))
    }

    private func metal(_ ui: UITweaks) -> some View {
        let d = diameter
        let base = SRGB(hex: ui.checkColor) ?? SRGB(hex: UITweaks().checkColor)!
        let lit = Self.color(base, toward: 1, by: ui.checkShine)
        let far = Self.color(base, toward: 0, by: ui.checkDepth)
        // Toward the light. The gradient runs the square's diagonal's length whatever its angle, so
        // turning the light keeps its contrast.
        let angle = ui.checkLightAngle * .pi / 180
        let toLight = CGVector(dx: sin(angle), dy: -cos(angle))
        let reach = 0.5 * 2.squareRoot()
        let from = UnitPoint(x: 0.5 + toLight.dx * reach, y: 0.5 + toLight.dy * reach)
        let to = UnitPoint(x: 0.5 - toLight.dx * reach, y: 0.5 - toLight.dy * reach)
        let highlight = ui.checkHighlightSize * d
        return ZStack {
            Circle().fill(LinearGradient(colors: [lit, Color(cgColor: base.cgColor), far], startPoint: from, endPoint: to))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.8 * ui.checkRim), .white.opacity(0), .black.opacity(0.3 * ui.checkRim)],
                                                 startPoint: from, endPoint: to),
                                  lineWidth: ui.checkRimWidth * d)
            Ellipse().fill(RadialGradient(colors: [.white.opacity(ui.checkHighlight), .white.opacity(0)],
                                          center: .center, startRadius: 0, endRadius: highlight / 2))
                .frame(width: highlight, height: highlight * 0.56)
                .rotationEffect(.degrees(ui.checkLightAngle))
                .offset(x: toLight.dx * 0.3 * d, y: toLight.dy * 0.3 * d)
            Image(systemName: "checkmark").font(.system(size: ui.checkGlyphSize * d, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(ui.checkGlyphShadow), radius: 0.027 * d, y: 0.033 * d)
        }
    }

    /// `base` taken `amount` of the way to the grey `level`.
    private static func color(_ base: SRGB, toward level: CGFloat, by amount: Double) -> Color {
        let t = CGFloat(amount)
        return Color(.sRGB, red: base.red + (level - base.red) * t, green: base.green + (level - base.green) * t,
                     blue: base.blue + (level - base.blue) * t)
    }

    /// The band at `place`, eased in and out, in a square wider than the disc by the bloom's reach on
    /// each side: outside the disc's clip, since the bloom spills past its edge.
    private func glare(_ ui: UITweaks, at place: Double) -> some View {
        let eased = place * place * (3 - 2 * place)
        let reach = ui.checkBloom > 0 ? ui.checkBloomRadius * diameter : 0
        let side = diameter + 2 * reach
        return Rectangle().fill(.white)
            .frame(width: side, height: side)
            .colorEffect(ShaderLibrary.checkGlare(.float(side), .float(diameter), .float(2 * eased - 1),
                                                  .float(ui.checkGlareWidth * diameter), .float(ui.checkGlareAngle * .pi / 180),
                                                  .float(ui.checkGlare), .float(ui.checkBloom), .float(reach),
                                                  .float(ui.checkBloomThreshold), .float(1 / displayScale)))
            .allowsHitTesting(false)
    }
}

extension EnvironmentValues {
    /// Where every `MetalCheck` below holds its glare, 0 to 1 across the disc, in the Check Lab.
    @Entry var checkGlarePlace: Double? = nil
}
