import SwiftUI

/// The success check on a copied or sent card: a coin of tinted polymer with a glowing check mark
/// inside it, ray marched and lit by a studio's reflections (`CheckCoin.metal`). It spins as it
/// appears, its face and rim flashing as they pass the studio's strip light, and settles face on
/// with a spring. The glow and the brightest reflections bloom. Its look is the `check` settings,
/// and every length is a fraction of `diameter`, so it looks the same at every size. With no motion
/// it does not spin (docs/check-lab-2026-10-11.md).
struct CheckCoin: View {
    let diameter: CGFloat
    @ObservedObject private var settings = Settings.shared
    /// The Check Lab's hold on the spin; nil runs it once from when the check appears.
    @Environment(\.checkSpinPlace) private var heldPlace
    @Environment(\.displayScale) private var displayScale
    @State private var appeared = Date()
    @State private var settled = false

    var body: some View {
        let ui = settings.motionUI
        let spin = CheckSpin(ui)
        // A held place is a still, so the lab shows it with motion off too.
        let spins = spin.turns > 0 && (heldPlace != nil || (settings.motionScale > 0 && !settled))
        Group {
            if spins {
                TimelineView(.animation(paused: heldPlace != nil)) { context in
                    let elapsed = heldPlace.map { $0 * spin.length } ?? context.date.timeIntervalSince(appeared)
                    coin(ui, turn: spin.turn(at: elapsed))
                }
            } else {
                coin(ui, turn: 0)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            appeared = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + spin.length) { settled = true }
        }
    }

    /// The coin at `turn` radians about its vertical axis, in a square wider than the disc by the
    /// bloom's reach on each side, since the bloom spills past the coin's edge.
    private func coin(_ ui: UITweaks, turn: Double) -> some View {
        let d = diameter
        let reach = ui.checkBloom > 0 ? ui.checkBloomRadius * d : 0
        let side = d + 2 * reach
        let stroke = Self.stroke(width: ui.checkMarkSize)
        let lightAngle = ui.checkLightAngle * .pi / 180, lightHeight = ui.checkLightHeight * .pi / 180
        let glintAngle = ui.checkGlintAngle * .pi / 180
        let shape: Shader.Argument = .float4(d / 2, ui.checkThickness * d / 2, ui.checkEdge * d, ui.checkDome * d)
        let mark: Shader.Argument = .float4(stroke[0], stroke[1], stroke[2], stroke[3])
        let markEnd: Shader.Argument = .float4(stroke[4], stroke[5], ui.checkMarkWeight * d / 2, ui.checkGlow)
        let light: Shader.Argument = .float4(sin(lightAngle) * cos(lightHeight), -cos(lightAngle) * cos(lightHeight),
                                             sin(lightHeight), ui.checkLight)
        let glint: Shader.Argument = .float4(sin(glintAngle), 0, cos(glintAngle), ui.checkGlint)
        let surface: Shader.Argument = .float4(ui.checkRoughness, ui.checkStudio, ui.checkClarity, ui.checkGlowSpread * d)
        let view: Shader.Argument = .float3(turn, 1 / displayScale, side)
        let shader = ShaderLibrary.checkCoin(shape, mark, markEnd, Self.rgb(ui.checkColor, \.checkColor),
                                             Self.rgb(ui.checkGlowColor, \.checkGlowColor), light, glint, surface, view)
        let shaded = Rectangle().fill(Color.white).frame(width: side, height: side).colorEffect(shader)
        // The bloom: the bright pass blurred and added over the coin.
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

    /// The mark's stroke, the short leg then the long one, as x and y fractions of the radius for a
    /// mark `width` of the diameter wide. The proportions are SF Symbols' heavy checkmark's.
    private static func stroke(width: Double) -> [Double] {
        [-0.5, 0.03, -0.15, 0.37, 0.5, -0.33].map { $0 * 2 * width }
    }

    private static func rgb(_ hex: String, _ fallback: KeyPath<UITweaks, String>) -> Shader.Argument {
        let c = SRGB(hex: hex) ?? SRGB(hex: UITweaks()[keyPath: fallback])!
        return .float3(c.red, c.green, c.blue)
    }
}

/// The coin's spin: `turns` whole turns, unwound by a spring after a delay, so it overshoots face on
/// by the spring's bounce and settles.
struct CheckSpin {
    let turns: Double
    let delay: TimeInterval
    let spring: Spring

    init(_ ui: UITweaks) {
        turns = ui.checkSpinTurns
        delay = ui.checkSpinDelay
        spring = Spring(duration: max(ui.checkSpinDuration, 0.01), bounce: ui.checkSpinBounce)
    }

    /// From the coin appearing until it is still.
    var length: TimeInterval { delay + spring.settlingDuration }

    func turn(at elapsed: TimeInterval) -> Double {
        let unwound = spring.value(target: 1.0, time: max(0, elapsed - delay))
        return -2 * .pi * turns * (1 - unwound)
    }
}

extension EnvironmentValues {
    /// Where every `CheckCoin` below holds its spin, 0 at its start to 1 once settled, in the Check Lab.
    @Entry var checkSpinPlace: Double? = nil
}
