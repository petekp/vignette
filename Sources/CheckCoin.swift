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
        let reach = ui.checkBloom > 0 ? ui.checkBloomRadius * diameter : 0
        let side = diameter + 2 * reach
        let shaded = Rectangle().fill(Color.white).frame(width: side, height: side)
            .colorEffect(Self.coinShader(ui, diameter: diameter, side: side, turn: turn, pixel: 1 / displayScale))
        // The bloom: the bright pass blurred and added over the coin.
        return shaded
            .overlay {
                if reach > 0 {
                    shaded.colorEffect(Self.brightShader(ui))
                        .blur(radius: reach / 2)
                        .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
    }

    private static func coinShader(_ ui: UITweaks, diameter d: CGFloat, side: CGFloat, turn: Double, pixel: CGFloat) -> Shader {
        let stroke = stroke(width: ui.checkMarkSize)
        let lightAngle = ui.checkLightAngle * .pi / 180, lightHeight = ui.checkLightHeight * .pi / 180
        let glintAngle = ui.checkGlintAngle * .pi / 180
        let shape: Shader.Argument = .float4(d / 2, ui.checkThickness * d / 2, ui.checkEdge * d, ui.checkDome * d)
        let mark: Shader.Argument = .float4(stroke[0], stroke[1], stroke[2], stroke[3])
        let markEnd: Shader.Argument = .float4(stroke[4], stroke[5], ui.checkMarkWeight * d / 2, ui.checkGlow)
        let light: Shader.Argument = .float4(sin(lightAngle) * cos(lightHeight), -cos(lightAngle) * cos(lightHeight),
                                             sin(lightHeight), ui.checkLight)
        let glint: Shader.Argument = .float4(sin(glintAngle), 0, cos(glintAngle), ui.checkGlint)
        let surface: Shader.Argument = .float4(ui.checkRoughness, ui.checkStudio, ui.checkClarity, ui.checkGlowSpread * d)
        let view: Shader.Argument = .float3(turn, pixel, side)
        return ShaderLibrary.checkCoin(shape, mark, markEnd, rgb(ui.checkColor, \.checkColor),
                                       rgb(ui.checkGlowColor, \.checkGlowColor), light, glint, surface, view)
    }

    private static func brightShader(_ ui: UITweaks) -> Shader {
        ShaderLibrary.checkBright(.float(ui.checkBloom), .float(ui.checkBloomThreshold))
    }

    /// Compiles both shaders off the main thread. SwiftUI otherwise compiles them in the frame that
    /// first draws a check: 27 to 34 ms on an M-series Mac and a third of a second in a VM, so the
    /// first check after a launch stalled its card's animation. macOS 14 has no way to ask for this.
    static func compileShaders() {
        guard #available(macOS 15, *) else { return }
        let ui = Settings.shared.data.ui
        let coin = coinShader(ui, diameter: 22, side: 22, turn: 0, pixel: 0.5), bright = brightShader(ui)
        Task.detached(priority: .utility) {
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                try await coin.compile(as: .colorEffect)
                try await bright.compile(as: .colorEffect)
                Log.write("[check] shaders compiled \((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)ms")
            } catch {
                Log.write("[check] error shader compile: \(error)")
            }
        }
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
