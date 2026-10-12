import SwiftUI

/// The success check on a copied or sent card: a domed metal disc with a raised check mark, lit by
/// reflecting a studio, with a strip light that sweeps across it once as it appears and a bloom on
/// what is brightest (`CheckMetal.metal`). Its look is the `check` settings, and every length is a
/// fraction of `diameter`, so it looks the same at every size. With no motion the strip light is
/// left out and the rest stays (docs/check-lab-2026-10-11.md).
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
        // A held place is a still, so the lab shows it with motion off too.
        let sweeps = ui.checkGlare > 0 && (heldPlace != nil || (settings.motionScale > 0 && !crossed))
        Group {
            if sweeps {
                TimelineView(.animation(paused: heldPlace != nil)) { context in
                    lit(ui, glareAt: heldPlace ?? Self.place(at: context.date.timeIntervalSince(appeared), ui))
                }
            } else {
                lit(ui, glareAt: nil)
            }
        }
        .frame(width: diameter, height: diameter)
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

    /// The mark in white, lit as metal by the shader, in a square wider than the disc by the bloom's
    /// reach on each side, since the bloom spills past the disc's edge. `glareAt` is the strip
    /// light's place from 0 to 1, or nil for none.
    private func lit(_ ui: UITweaks, glareAt place: Double?) -> some View {
        let d = diameter
        let reach = ui.checkBloom > 0 ? ui.checkBloomRadius * d : 0
        let side = d + 2 * reach
        let markHeight = ui.checkMarkHeight * d
        let lightAngle = ui.checkLightAngle * .pi / 180, lightHeight = ui.checkLightHeight * .pi / 180
        let toLight = (x: sin(lightAngle) * cos(lightHeight), y: -cos(lightAngle) * cos(lightHeight), z: sin(lightHeight))
        // The mark's shadow falls away from the light, longer as the light gets lower.
        let shadowReach = markHeight / max(tan(lightHeight), 0.2)
        // The strip crosses the reflections of the disc's face, which turn by up to twice the dome's
        // steepest slope, and its own width either side.
        let span = sin(2 * atan(2 * ui.checkDome)) + 1.5 * ui.checkGlareWidth + 0.1
        let eased = place.map { $0 * $0 * (3 - 2 * $0) }
        let sampled = shadowReach + 1
        let disc: Shader.Argument = .float4(side / 2, side / 2, d / 2, 1 / displayScale)
        let form: Shader.Argument = .float4(ui.checkDome, ui.checkRim, markHeight, ui.checkMarkBevel * d)
        let light: Shader.Argument = .float4(toLight.x, toLight.y, toLight.z, ui.checkLight)
        let surface: Shader.Argument = .float4(ui.checkRoughness, ui.checkStudio, ui.checkMarkShadow, shadowReach)
        let glare: Shader.Argument = .float4(eased == nil ? 0 : ui.checkGlare, ui.checkGlareWidth,
                                             ui.checkGlareAngle * .pi / 180, ((eased ?? 0) * 2 - 1) * span)
        let metal = ShaderLibrary.checkMetal(disc, Self.rgb(ui.checkColor, \.checkColor), Self.rgb(ui.checkMarkColor, \.checkMarkColor),
                                             form, light, surface, glare)
        let shaded = Self.mark(size: ui.checkMarkSize * d, bevel: ui.checkMarkBevel * d, side: side)
            .layerEffect(metal, maxSampleOffset: CGSize(width: sampled, height: sampled))
        // The bloom: the bright pass blurred and added over the check.
        return shaded
            .overlay {
                if reach > 0 {
                    shaded.colorEffect(ShaderLibrary.checkBright(.float(ui.checkBloom), .float(ui.checkBloomThreshold)))
                        .blur(radius: reach / 2)
                        .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
    }

    /// The mark in white on a square of `side`, blurred over its bevel, which the shader reads as its
    /// height. A layer effect runs only where its view draws, so the square is filled with a
    /// near-clear white, below every threshold the shader has, which gives it the whole disc and the
    /// bloom's reach.
    private static func mark(size: CGFloat, bevel: CGFloat, side: CGFloat) -> some View {
        let square = Rectangle().fill(Color.white.opacity(1.0 / 255))
        let mark = Image(systemName: "checkmark").font(.system(size: size, weight: .heavy)).foregroundStyle(Color.white)
            .blur(radius: bevel)
        return ZStack { square; mark }.frame(width: side, height: side)
    }

    private static func rgb(_ hex: String, _ fallback: KeyPath<UITweaks, String>) -> Shader.Argument {
        let c = SRGB(hex: hex) ?? SRGB(hex: UITweaks()[keyPath: fallback])!
        return .float3(c.red, c.green, c.blue)
    }
}

extension EnvironmentValues {
    /// Where every `MetalCheck` below holds its glare, 0 to 1 across the disc, in the Check Lab.
    @Entry var checkGlarePlace: Double? = nil
}
