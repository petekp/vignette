import SwiftUI

/// When the funnel's flight began on the media clock, set once the window has closed. The view
/// reads it every frame, so it needs no publishing.
@MainActor
final class FunnelClock {
    var begin: CFTimeInterval?
}

/// How a pour looks, apart from where it goes.
struct FunnelLook {
    /// 0 moves every row together, 1 is the full funnel.
    var strength: Double
    var smoothing: Double
    /// The radius the pour's corners grow to, in points on screen.
    var corner: Double
    var smear: Double
    var rim: Double
    var fade: Double
    /// The opacity of the shadow under the picture at the start, which goes as the rows leave.
    var shadow: Double

    /// The menu bar intro's, from the settings, so the Intro Lab's sliders show at once.
    @MainActor static func intro() -> FunnelLook {
        let ui = Settings.shared.data.ui
        // The window's shadow as measured on macOS 15: how much it darkens what is behind it at 2,
        // 10 and 22 pt beside the window (0.31, 0.20, 0.09) and just below it (0.54).
        return FunnelLook(strength: ui.introFunnel, smoothing: ui.introFunnelSmoothing, corner: ui.introFunnelCorner,
                          smear: ui.introFunnelSmear, rim: ui.introFunnelRim, fade: ui.introFunnelFade, shadow: 0.67)
    }
}

/// The picture pouring into a rect (docs/intro-funnel-2026-09-30.md): setup's window into the menu
/// bar icon, and a dropped card into the point it was dropped on (`DropLanding`). The bitmap stays
/// where it was, and `funnel` in IntroFunnel.metal bends it, row by row, into `icon`. The shadow is
/// drawn by the shader from the bent shape, and goes as the rows leave. The look is asked for on
/// every frame.
struct FunnelFlight: View {
    let image: CGImage
    /// The bitmap's place and the icon's, in the view's points with y down.
    let card: CGRect, icon: CGRect
    /// The picture's own corner radius in the view's points, which the pour's corners grow from.
    let cardRadius: CGFloat
    /// Points in this view per point on screen: 1 on screen, less in the Intro Lab's preview.
    var zoom: CGFloat = 1
    /// How far through the flight, 0 to 1, asked on every frame.
    let progress: @MainActor () -> Double
    var look: @MainActor () -> FunnelLook = FunnelLook.intro
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.animation) { _ in
            let t = progress()
            let look = look()
            let shadow = 1 - Self.ramp(t, 0.3, 0.7)
            GeometryReader { space in
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: card.width, height: card.height)
                    .offset(x: card.minX, y: card.minY)
                    .frame(width: space.size.width, height: space.size.height, alignment: .topLeading)
                    .layerEffect(ShaderLibrary.funnel(.float4(card.minX, card.minY, card.width, card.height),
                                                      .float4(icon.minX, icon.minY, icon.width, icon.height),
                                                      .float(t), .float(look.strength), .float(look.smoothing),
                                                      .float(look.corner * zoom), .float(cardRadius),
                                                      .float(look.smear), .float(look.rim), .float(look.fade),
                                                      .float3(look.shadow * shadow, 20 * zoom, 15 * zoom),
                                                      .float(1 / displayScale)),
                                 maxSampleOffset: space.size)
            }
        }
        .ignoresSafeArea()
    }

    private static func ramp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }
}
